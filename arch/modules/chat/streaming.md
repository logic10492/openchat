# 聊天流式输出与统计

## 1. MessageDisplayItem

```swift
struct MessageDisplayItem: Identifiable {
    let id: String
    let role: String
    var content: String           // 可变：流式输出时逐步更新
    var contentBlocks: [TextContentBlock] // 渲染分块，降低超长流式输出的单次更新范围
    var contentRenderRevision: Int        // 流式内容修订号，驱动滚动跟随与 diff
    var renderedMarkdown: AttributedString? // 流式尾条的后台预解析 Markdown
    var reasoningRenderRevision: Int      // 思考内容修订号，避免长 reasoning 进入 diff 热路径
    let isCompressed: Bool
    let originalContent: String?  // 压缩消息的原始内容
    let createdAt: Date

    init(from record: MessageRecord)
}
```

## 2. 流式输出的 UI 更新策略

### 2.1 分块流式渲染

流式 SSE 事件仍然逐 chunk 接收，保证用户看到实时输出；但 chunk 拼接、显示分块和 Markdown 预解析不再由主线程逐 token 承担：

- `ChatViewModel+Support` 在普通生成和 Stage 多角色生成两条路径使用 `StreamingResponseAccumulator` actor 接收 `StreamDelta`；actor 在后台维护完整 content、reasoning、usage、pending delta、`contentBlocks` 和 `renderedMarkdown`
- actor 默认约 50ms 或累计 520 字符产出一次 `StreamingRenderSnapshot`；结束和错误路径都会强制 flush，降低超长回复期间 `messages[index]` 修改和 timeline diff 频率，同时保证失败前已收到但尚未到刷新阈值的 partial delta 不丢失
- 主线程只应用已节流的 `StreamingRenderSnapshot` 到当前 assistant `MessageDisplayItem`，最终持久化和 stats 从 `StreamingFinalSnapshot` 读取，不再从 UI `messages` 反查最终字符串
- `MessageDisplayItem.applyStreamingSnapshot(...)` 一次性替换完整 `content`、`contentBlocks`、`renderedMarkdown`、reasoning 和 revision
- `MessageDisplayItem` 的 equality/hash 使用 revision 而不是完整 content / reasoning 字符串，避免长字符串在每次流式刷新时做大比较
- `TextContentBlock` 优先按自然换行切块，超长无换行文本按固定上限兜底切块
- UIKit timeline 的 `ChatMessageCell` 和 `ChatTimelineHeightMeasurer` 优先使用 `MessageDisplayItem.renderedMarkdown` 生成 `NSAttributedString` 与高度测量；如果没有预渲染结果才回退到主线程 Markdown parse
- `contentRenderRevision` / `reasoningRenderRevision` 只表达流式修订，不把完整 content 或 reasoning content 放入 Hashable diff 热路径

### 2.2 Markdown 延迟刷新与缓存

RP 文本默认以 plain Text 先显示；Markdown 渲染作为延迟增强，不阻塞逐 chunk 输出：

- `MarkdownRenderPolicy.refreshDelay(forCharacterCount:)` 按全文长度返回 30 / 50 / 75 / 100ms 的延迟，文本越长越 lazy
- 每个 `TextContentBlock` 独立执行 Markdown parse
- `MarkdownRenderCache` 缓存已解析或失败的 block，避免相同块重复解析
- 当前实现使用 `.inlineOnlyPreservingWhitespace`，保持原有 inline Markdown 行为

### 2.3 自动滚动

- 消息列表使用 UIKit `UICollectionView` core，SwiftUI 只负责桥接；iOS 26+ 上下 soft edge 由 `UICollectionView` 的 native `topEdgeEffect` / `bottomEdgeEffect` 承担，避免 SwiftUI full-viewport mask 进入滚动热路径；iOS 17-25 继续由 `ChatEdgeEffectViewport` 提供 fade/material fallback。视觉权威为 2026-05-27 用户截图和 `e1c17f6`
- 新用户消息到达和生成开始时滚动到底部
- 流式正文或 reasoning 更新时仅在 `isGenerating && shouldFollowStreaming == true` 时跟随到底部，并通过 50ms 合并任务降低逐 chunk `scrollToItem` 触发频率
- 用户上滑后暂停跟随；拖动/按住期间不恢复
- 手势结束且 0.5s 内没有新的触摸事件后，仅当本轮仍在生成时恢复跟随并立即滚回底部
- 生成结束会取消待恢复的跟随任务，不再触发最终跳底；用户可自由拖动历史消息

### 2.4 长历史窗口化

超长会话不能把完整历史直接交给 UI timeline。当前策略：

- `ChatViewModel.loadMessages()` 初始只读取最近 120 条消息。
- `loadEarlierMessagesIfNeeded()` 在 timeline 顶部附近触发，每页读取 80 条更早消息。
- `hasEarlierMessages` 用 sentinel row 判定：初始读取 `120 + 1` 条但只展示最近 120 条；向上分页读取 `80 + 1` 条但只 prepend 80 条。这样刚好等于窗口大小时不会误显示还有历史。
- `DatabaseManager.fetchRecentMessages(conversationId:limit:)` 和 `fetchMessages(conversationId:beforeSortOrder:limit:)` 都先按 `sortOrder DESC` 限制窗口，再反转为升序返回，保证 UI 不需要全量排序。
- 删除 visible message 时，`ChatViewModel.deleteMessage(...)` 删除 DB row 后只从当前 `messages` window 移除对应 id；不会调用 `loadMessages()` 重新读取 120 条并把更早消息补进窗口。
- 编辑 visible user message 时，`ChatViewModel.editMessage(...)` 保存 edited row、删除其后的 DB tail 后，只替换当前 row 并移除当前 window 中 `sortOrder` 更大的项，再触发重新生成；不会让整条 timeline 做 full reload。
- Prompt/context 组装不读取 `viewModel.messages` 这个 UI window；`generateResponse(...)` 仍从 DB 读取完整会话历史，再交给 `ContextManager.prepareHistory(...)` 按策略截断或压缩。`ChatViewModelPromptAssemblyTests.test_promptHistoryUsesDatabaseBeyondVisibleTimelineWindow` 覆盖 150 条 DB 历史、120 条可见 timeline window 时，API request 仍包含窗口外的早期历史。
- prepend 更早消息后，`ChatTimelineViewController` 记录旧 content height 和 content offset，再按高度 delta 恢复当前位置，避免用户阅读位置跳动。
- 非 prepend 的跳底/流式跟随在 diffable snapshot apply completion 后执行，避免 collection view 在新 item 尚未提交到 data source 时滚动到不存在的 indexPath。
- fixture 支持 `--ui-testing-chat-performance-count` 生成 1,000 / 3,000 / 10,000 条历史，用来确认 UI 热路径与总历史长度解耦。

### 2.5 流式光标

- 生成中的 AI 消息末尾显示闪烁的 `█` 光标
- 生成完成后光标消失

## 3. Token 使用情况展示

点击导航栏的 📊 图标弹出 Popover：

```
┌──────────────────────────┐
│ Token 使用情况            │
│──────────────────────────│
│ 总预算: 1638 / 4096      │
│ ████████░░░░░░░░ 40%     │
│──────────────────────────│
│ System Prompt:    120    │
│ 角色描述:          85    │
│ 场景:              42    │
│ 世界书 (3条):     230    │
│ 示例对话:         180    │
│ 历史 (12条):      850    │
│ 当前输入:          31    │
│──────────────────────────│
│ 已用: 1538  剩余: 100    │
└──────────────────────────┘
```
