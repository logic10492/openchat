# ChatViewModel 设计

## 1. 状态

```swift
@Observable
final class ChatViewModel {
    // 依赖
    private let db: DatabaseManager
    private let apiClient: APIClient
    private let contextManager: ContextManager
    private let memoryManager: MemoryManager

    // 会话状态
    let conversation: ConversationRecord
    private(set) var messages: [MessageDisplayItem] = []
    private(set) var isGenerating: Bool = false
    private(set) var tokenUsage: TokenUsageReport? = nil

    // 输入状态
    var inputText: String = ""
    var isPrefillModeEnabled: Bool = false

    // 错误状态
    private(set) var error: APIError? = nil

    // 流式任务引用（用于取消）
    private var streamTask: Task<Void, Never>? = nil
}
```

## 2. 核心方法

```swift
extension ChatViewModel {

    /// 初始加载：从 DB 读取会话消息
    func loadMessages() async

    /// 发送消息：保存用户消息 → 拼装 prompt → 流式请求 → 保存 AI 回复
    func sendMessage() async

    /// 停止生成：取消当前流式任务
    func stopGenerating()

    /// 重新生成：删除最后一条 AI 回复 → 重新发送
    func regenerateLastResponse() async

    /// 编辑消息：更新指定消息内容 → 删除该消息之后的所有消息 → 重新生成
    func editMessage(_ messageId: String, newContent: String) async

    /// 删除消息
    func deleteMessage(_ messageId: String) async
}
```

## 3. 编辑与预填充语义

编辑语义：只允许编辑 user 消息，且生成中不接受编辑。编辑早期 user turn 时，`ChatViewModel.editMessage(...)` 会保存新的 user 内容、删除该消息 sortOrder 之后的所有 message，并删除覆盖该位置的 compression checkpoint，然后用新内容重新生成 assistant 回复。这等价于 KV cache 前缀变更后的分支截断：旧 assistant 回复和后续 user turn 不再进入新的 prompt history。

实现证据：`ChatViewModel.swift` 的 `editMessage(_:newContent:)` 先校验 `target.role == "user"`，随后调用 `deleteCompressionCheckpoints(conversationId:sourceEndAtOrAfter:)` 与 `deleteMessages(conversationId:afterSortOrder:)`，再用 `replaceTimelineMessage(with:)` 和 `removeTimelineMessages(afterSortOrder:)` 局部更新当前可见 timeline window，最后以 `persistUserMessage: false` 调用 `generateResponse(...)`。`deleteMessage(...)` 删除 DB row 后只通过 `removeTimelineMessage(id:)` 移除 visible item，不再调用 `loadMessages()` 回填 120 条窗口。`ChatViewModelPromptAssemblyTests.test_editUserMessage_truncatesTailAndRegeneratesFromEditedPrefix` 覆盖 `a -> A -> b -> B -> c -> C` 编辑 `a` 后只保留 `edited a -> new response`，并验证新请求不包含旧分支内容；`test_deleteMessage_removesVisibleTimelineItemWithoutReloadingWindow` 和 `test_editMessage_truncatesVisibleTimelineTailWithoutReloadingWindow` 覆盖 150 条 DB 历史、120 条可见 window 下删除/编辑 visible row 时不会通过 full reload 把 sortOrder 29 等更早消息补进 timeline。

预填充语义：`isPrefillModeEnabled == true` 且当前会话不是 Stage 时，`sendMessage()` 不走标题生成、prompt 拼装或网络流式请求，而是通过 `savePrefilledMessage(...)` 直接保存一条本地 `MessageRecord`。下一条 role 由当前消息历史尾部决定：若最后一条是 `user`，本次保存为 `assistant` 并写入当前角色 `speakerName`；否则本次保存为 `user` 且不写 speaker metadata。保存后清空输入，但保留预填充模式开启，于是用户可进入 `user -> assistant -> user -> assistant` 的手写循环。关闭预填充后的下一次普通发送，会让这些消息由 `ContextManager.prepareHistory(...)` 按普通历史处理。实现证据：`ChatViewModelPromptAssemblyTests.test_prefillMode_afterUserInputAlternatesAssistantAndUserWithoutNetworkRequest` 覆盖已有 user 尾消息时从 assistant 开始并继续交替；`ChatViewModelPromptAssemblyTests.test_prefillMode_withoutPriorUserInputStartsWithUserMessage` 覆盖无 user 尾消息时从 user 开始；`ChatViewModelPromptAssemblyTests.test_prefilledExchange_isIncludedInNextGenerationHistory` 覆盖手写 user/assistant 交换会进入下一次普通生成的 API request history。

## 4. 发送消息完整流程

```
sendMessage():
    1. guard !inputText.isEmpty, !isGenerating
    2. 如果 isPrefillModeEnabled 且非 Stage：
       如果最后一条消息是 user，保存 assistant MessageRecord；否则保存 user MessageRecord
       清空 inputText，保持预填充模式开启，返回
    3. isGenerating = true
    4. 创建 userMessage (MessageRecord) 并保存到 DB
    5. 将 userMessage 追加到 messages 列表
    6. 清空 inputText

    7. // 加载上下文
       characterCard = 从 DB 加载 conversation.characterCardId
       worldBook = 从 DB 通过 characterCard.worldBookId 加载世界书
       worldBookEntries = 从 DB 加载世界书的已启用条目
       endpoint = 从 DB 加载 conversation.apiEndpointId

    7.5 // 前置记忆提取
       若达到 pending message 阈值，ChatViewModel 在本轮生成前同步等待
       memoryManager.extractMemories(from: conversation)，让新记忆可被 Background source 召回。

    7. 从 DB 读取当前会话消息后，构造 promptHistoryMessages：
       - 乐观保存的当前 user message 保留在 DB/UI 中；
       - prompt history 中排除本轮 current input record；
       - 重新生成/编辑时排除与 currentInput 对应的最后一条 user record。

    8. 对当前 worldBook 做 bounded rebuild：
       WorldBookEmbeddingIndexer.rebuildMissingOrStale(worldBookId:limit: 8)
       失败只记录 warning，不阻断生成；该 side effect 仍归 ChatViewModel。

    9. BackgroundManager.prepare(request, policy):
       - MemoryBackgroundSource 包装 MemoryRecallTool / MemoryManager.recallMemories(...)
       - WorldBookBackgroundSource 包装 WorldBookRecallTool / WorldBookSource.recallEntries(...)
       - BackgroundWorker deterministic selection 输出 BackgroundPacket
       - worldBook source failure 时保留 keyword fallback candidates

    10. PromptAssembler.preview(... backgroundPacket:) 使用 packet selected entries
        计算 Stable Identity、Current-Turn Context、Current Turn 与 fixedTokens。

    11. ContextManager.prepareHistory(messages:promptHistoryMessages, ...)
       只处理过滤后的历史，再由 PromptAssembler.assemble(... backgroundPacket:)
       输出 `stableIdentityMessages + processedHistory + currentTurnContextMessages + currentTurnMessage`。
       tokenUsage = result.tokenUsage

    12. // 创建空的 assistantMessage 占位
        assistantMessage = MessageRecord(role: "assistant", content: "")
        保存到 DB
        追加到 messages 列表

    13. // 流式请求
        streamTask = Task {
            do {
                let stream = apiClient.streamMessage(
                    messages: result.messages,
                    endpoint: endpointConfig,
                    parameters: modelParams)

                for try await delta in stream {
                    assistantMessage.content += delta.content
                    更新 messages 中对应项的显示内容（触发 UI 刷新）

                    if delta.finishReason != nil {
                        break
                    }
                }

                // 完成：更新 token 计数并保存
                assistantMessage.tokenCount = TokenCounter.count(assistantMessage.content)
                更新 DB 中的 assistantMessage

            } catch is CancellationError {
                // 用户取消：保存已生成的部分内容
                更新 DB 中的 assistantMessage（保留已有内容）

            } catch {
                self.error = error as? APIError
                // 删除空的 assistantMessage
                从 DB 和 messages 列表中移除
            }

            isGenerating = false
            streamTask = nil
        }
```

## 5. 重新生成流程

```
regenerateLastResponse():
    1. guard let lastAssistant = messages.last(where: { $0.role == "assistant" })
    2. 从 DB 和 messages 中删除 lastAssistant
    3. 将 inputText 设为空（不需要新的用户输入）
    4. 执行与 sendMessage() 步骤 6-11 相同的流程
       （但使用已有的最后一条 user 消息作为 currentInput）
```

## 6. 编辑消息流程

```
editMessage(messageId, newContent):
    1. 找到 messageId 在 messages 中的位置 idx
    2. 更新该消息的 content 为 newContent，保存 DB
    3. 删除 idx 之后的所有消息（DB + messages 列表）
    4. 执行重新生成流程
```

## 7. 记忆提取触发

当前源码在用户消息持久化后，从 DB 读取 `conversation.lastExtractedSortOrder` 与消息列表，计算 `sortOrder > cutoff` 的待提取消息数；当待提取消息数达到 `ChatViewModel.minimumPendingMessagesForExtraction == 4` 时，在**当前 `generateResponse` 中同步等待**记忆提取完成（在检索记忆之前）：

```swift
// Pre-response extraction in generateResponse:
if try await shouldExtractMemories(for: conversation),
   characterCard?.id != nil {
    extractionPhase = .extracting
    let result = try await memoryManager.extractMemories(from: conversation)
    extractionPhase = result.isEmpty ? .skipped : .completed(...)
}
// Then BackgroundManager.prepare(...) can recall newly extracted memories.
```

- **触发时机**：发送链路内的前置同步提取（位于用户消息持久化之后、记忆检索之前）；`ChatView.onDisappear` 保留 fire-and-forget 调用
- **UI 反馈**：通过 `extractionPhase` 状态驱动 `MemoryExtractionIndicator` 内联指示器，显示"正在提取 / 已提取 N 条 / 提取失败"
- **cutoff 边界**：使用 `conversation.lastExtractedSortOrder`（基于 message sortOrder）替代旧的 `latestMemoryDate`（基于 memory_entry.createdAt），避免并发写入导致消息被跳过
- **错误反馈**：提取失败记录日志并在 UI 显示错误指示器，不阻塞后续生成

## 8. Background 主链路切换

2026-05-17 Phase 6 后，Chat 主链路不再直接把 `MemoryManager.retrieveMemories(...)` 和 `WorldBookSource.recallEntries(...)` 的数组交给 PromptAssembler。当前源码事实：

- `OpenChat/App/DependencyContainer.swift` 装配 `BackgroundManager`，其 sources 为 `MemoryBackgroundSource(tool: MemoryRecallTool(memoryManager: ...))` 与 `WorldBookBackgroundSource(tool: WorldBookRecallTool(source: ...))`。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` 在 `generateResponse(...)` 中构造 `BackgroundRequest`，调用 `backgroundManager.prepare(...)`，再调用 packet-aware `PromptAssembler.preview(... backgroundPacket:)` / `assemble(... backgroundPacket:)`。
- bounded `WorldBookEmbeddingIndexer.rebuildMissingOrStale(worldBookId:limit:)` 仍由 ChatViewModel 在 manager prepare 前执行；`BackgroundWorker` 与 source adapter 不触发 rebuild。
- `BackgroundManager` 对单 source failure 做降级；worldBook source failure 使用旧 keyword fallback 生成 `.worldBook` candidates。
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift` 覆盖 request body 使用 packet selected entries、current input 不重复、semantic-only world book entry 进入 `[World Book Entries]`、semantic failure keyword fallback 保持可用。
