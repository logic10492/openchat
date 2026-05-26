# 聊天流式输出与统计

## 1. MessageDisplayItem

```swift
struct MessageDisplayItem: Identifiable {
    let id: String
    let role: String
    var content: String           // 可变：流式输出时逐步更新
    var contentBlocks: [TextContentBlock] // 渲染分块，降低超长流式输出的单次更新范围
    var contentRenderRevision: Int        // 流式内容修订号，驱动滚动跟随与 diff
    let isCompressed: Bool
    let originalContent: String?  // 压缩消息的原始内容
    let createdAt: Date

    init(from record: MessageRecord)
}
```

## 2. 流式输出的 UI 更新策略

### 2.1 分块流式渲染

流式 SSE 事件仍然逐 chunk 进入 UI，保证用户看到实时输出；但 assistant 正文不再作为单个大文本整体重算：

- `ChatViewModel+Support` 使用 `StreamingRenderBuffer` 在普通生成和 Stage 多角色生成两条路径合并高频 delta；默认约 50ms 或累计 520 字符刷新一次，结束时强制 flush，降低超长回复期间 `messages[index]` 修改和 SwiftUI diff 频率
- `MessageDisplayItem.appendContentDelta(...)` 同步维护完整 `content` 与 `contentBlocks`
- `TextContentBlock` 优先按自然换行切块，超长无换行文本按固定上限兜底切块
- `MessageBubbleView` 传入 `contentBlocks`，由 `MarkdownTextView` 分块渲染，避免每个 SSE chunk 都让整条长回复重新参与 Markdown / Text 构建
- `MessageBubbleView` 对值语义输入使用 `.equatable()`，旧消息在流式尾条更新时跳过无变化的子树重算
- `contentRenderRevision` 只表达流式文本修订，不把完整 content 放入 Hashable diff 热路径

### 2.2 Markdown 延迟刷新与缓存

RP 文本默认以 plain Text 先显示；Markdown 渲染作为延迟增强，不阻塞逐 chunk 输出：

- `MarkdownRenderPolicy.refreshDelay(forCharacterCount:)` 按全文长度返回 30 / 50 / 75 / 100ms 的延迟，文本越长越 lazy
- 每个 `TextContentBlock` 独立执行 Markdown parse
- `MarkdownRenderCache` 缓存已解析或失败的 block，避免相同块重复解析
- 当前实现使用 `.inlineOnlyPreservingWhitespace`，保持原有 inline Markdown 行为

### 2.3 自动滚动

- 消息列表使用 `ScrollViewReader`
- 新用户消息到达和生成开始时滚动到底部
- 流式内容更新时仅在 `isGenerating && shouldFollowStreaming == true` 时跟随到底部，并通过 50ms 合并任务降低逐 chunk `scrollTo` 触发频率
- 用户上滑后暂停跟随；拖动/按住期间不恢复
- 手势结束且 0.5s 内没有新的触摸事件后，仅当本轮仍在生成时恢复跟随并立即滚回底部
- 生成结束会取消待恢复的跟随任务，不再触发最终跳底；用户可自由拖动历史消息

### 2.4 流式光标

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
