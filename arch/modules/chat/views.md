# 聊天视图设计

## 1. ChatView（主界面）

```
┌─────────────────────────────────────────┐
│ [←]       艾拉                  [⚙️] │  ← 导航栏：液态玻璃角色胶囊 + 设置
│          银月森林                      │  ← 胶囊副标题：仅角色卡绑定世界书时显示
│─────────────────────────────────────────│
│                                         │
│        ┌────────────────────────────┐   │
│        │ 你好，请问你是谁？         │   │  ← 用户消息：右侧扁平气泡
│        └────────────────────────────┘   │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │ 我是艾拉，银月森林的守护者。     │   │  ← AI 消息：左侧扁平气泡
│  │ 有什么我能帮助你的吗？           │   │
│  └──────────────────────────────────┘   │
│                                         │
│        ┌────────────────────────────┐   │
│        │ 这里是哪里？               │   │  ← 长按气泡：复制 / 编辑
│        └────────────────────────────┘   │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │ 这里是银月森林的入口...          │   │  ← 可重新生成：动作栏 / 长按菜单
│  │ 前方就是精灵族的领地了。█        │   │  ← 流式输出光标
│  └──────────────────────────────────┘   │
│                                         │
│─────────────────────────────────────────│
│ [输入消息...]                    [■停止]│  ← 生成中显示停止按钮
│ [输入消息...]                    [➤发送]│  ← 空闲时显示发送按钮
└─────────────────────────────────────────┘
```

顶部胶囊规则：
- 非 Stage 会话显示当前角色卡名；如果角色卡绑定世界书，第二行用次要文字显示世界书名；未绑定世界书时不显示副标题。
- 点击非 Stage 胶囊在胶囊下方弹出 SwiftUI popover，而不是展开胶囊本体；胶囊本体不显示 chevron 或其他展开暗示。
- popover 上半部分是“可选世界书”：包含“无世界书”和所有世界书；选择世界书只更新下半部分筛选，不立即保存会话。
- popover 下半部分是“世界书可选角色”：展示当前世界书下的角色；“无世界书”筛选下展示未绑定世界书的角色。选择角色后更新 `selectedCharacterCardID` 并复用 `ChatViewModel.saveConversationSettings()` 保存到当前会话。
- Stage 会话本轮只做简单兼容：胶囊显示 `Stage` 与当前 active/present participants 摘要，点击进入设置，不通过胶囊切换会话级角色卡。

实现证据：`ChatView.swift` 只保留页面级 lifecycle、sheet 和 shell 布局；toolbar、timeline、composer 分别由 `ChatNavigationToolbar.swift`、`ChatTimelineHostView.swift`、`ChatInputBarHostView.swift` 承担，避免流式消息刷新时把导航胶囊和输入栏一起卷入 `ChatView` 的主体重算。`ChatView.swift` 的 shell `ZStack` 最底层挂载 `ChatConversationBackground(isGenerating: viewModel.isGenerating, isEnabled: isVibeBackgroundEnabled, isTimelineScrolling: isTimelineScrolling)`；`ChatConversationBackground.swift` 再组合 `VibeBackgroundView` 与页面背景色，使 vibe background 位于消息 viewport 和 Liquid Glass chrome 之后，不进入 composer 内部。`VibeBackgroundView.swift` 只是 SwiftUI bridge shell，真正动画与绘制在 `VibeBackgroundUIKitRepresentable.swift` / `VibeBackgroundUIKitView.swift` 中完成，并由 `CADisplayLink` 驱动 `VibeBackgroundDriver` 的连续 motion state；当前渲染层使用 ProMotion 友好的 `preferredFrameRateRange` 范围提示，但按 phase 把调度上限限制到 idle/completing 24fps、waiting 30fps、streaming 60fps，并用 `targetTimestamp` 推进动画时间，避免 CPU bitmap renderer 在 120Hz 设备上被过高频率唤醒。用户滚动 timeline 时，`ChatTimelineViewController` 会通过 `onScrollingChanged` 暂停 `VibeBackgroundUIKitView` 的 display link，非程序化滚动结束后再恢复；程序化跳底和 prepend offset restoration 会短暂 suppress 这条滚动报告，避免 streaming follow-scroll 被误判成用户手滑。`ChatSettingsSheet.swift` 在 `Appearance` section 提供 `Vibe Background (Beta)` 开关，开关通过 `UserDefaults` 的 `chat_vibe_background_enabled` key 控制整层背景是否启用。principal toolbar 使用 `ChatHeaderCapsule` 渲染角色胶囊。`ChatChromeViews.swift` 的 `ChatChromeAppearance` 按 `ColorScheme` 固定顶部胶囊的 glass tint、文字、描边和阴影：iOS 26+ 仍使用原生 `glassEffect(.regular.tint(...).interactive(), in: Capsule())` 保留 Liquid Glass 采样和质感，但浅色模式始终使用浅色 tint，深色模式始终使用深色 tint，不再随滚动内容亮暗发生黑白切换；iOS 17-25 使用同一套浅/深色静态 fallback fill。非 Stage 分支通过 `Button + popover` 展示 `CharacterPickerPopover`，由 `availableWorldBooks` 与 `availableCharacterCards` 组成世界书筛选和角色列表，并在角色选择时调用 `selectCharacterCard(_:)`；Stage 分支仅作为设置入口。消息滚动、日期分隔、分组和流式跟随由 `ChatMessageTimelineView.swift` 承担，避免 `ChatView.swift` 再次膨胀为聊天行为大杂烩。顶部/底部控件下方的边缘视觉保持 2026-05-27 用户截图和 `e1c17f6` 的视觉契约，但按系统版本拆分实现：iOS 26+ 由 UIKit timeline 的 `UICollectionView.topEdgeEffect` / `bottomEdgeEffect` 使用 native `.soft`，避免 SwiftUI full-viewport mask 进入长列表滚动热路径；iOS 17-25 仍由 `ChatView.swift` 外层 `ChatEdgeEffectViewport` 提供 top/bottom fade mask 和 `.ultraThinMaterial` fallback。`ChatEdgeEffects.swift` 同时保留 `chatInputBar` safe-area bridge；边缘效果只影响消息 viewport，不进入 `InputBarView`。

## 2. MessageBubbleView

**布局规则**：
- user 消息：右对齐，主题色背景
- assistant 消息：左对齐，次要色背景，不展示头像或头像占位
- system 消息：居中，淡灰色，小字体（通常不展示给用户，除非是压缩摘要）
- 主消息列约束最大宽度，避免 iPad / 横屏下长文本铺满全屏；用户消息比助手消息更窄，保持对话阅读节奏。
- 同一发送者 / 同一 speaker / 同一天 / 5 分钟内的连续消息按 Telegram 式分组，组内压缩垂直间距，只在组尾显示时间脚。
- 时间脚内嵌在分组尾部气泡内；短消息气泡按内容自然收缩，不因时间脚或头像轨道被撑宽。
- Stage 或多角色消息可在分组首条显示 speaker 名；普通 user/assistant 身份主要由左右对齐和顶部胶囊承担；消息行内不展示头像。
- 气泡保持扁平色块，不使用液态玻璃材质；液态玻璃只用于顶部胶囊。

**内容渲染**：
- 使用 Markdown 渲染（粗体、斜体、代码块、列表等）
- 流式输出时逐步追加文本，末尾显示闪烁光标
- 展示层会把连续 3 个以上换行压缩为最多 1 个空行，避免角色输出留下大段空白；原始 message content 不改写

**思考内容展示**：
- 第一级：默认折叠，只显示 `Character Thinking` 行和生成中状态，不直接暴露思考正文。
- 第二级：点开展开后显示固定高度滚动预览。若思考内容过长，预览保留尾部上下文，前置内容用省略号表达，避免长思考链挤占主回复。预览文本启用系统文本选择，用户可通过系统复制菜单复制可见内容。
- 实现证据：`MessageBubbleView.swift` 调用 `ReasoningDisclosureView` 渲染 `MessageRecord.reasoningContent`；`ReasoningDisclosureView.swift` 负责折叠状态、固定高度预览、尾部截断和系统文本选择。

**长按菜单**：

| 消息类型 | 菜单项 |
|---|---|
| user | 编辑、复制 |
| assistant | 底部动作栏与长按菜单：复制、重新生成、删除 |
| system (压缩) | 查看原始内容 |

实现证据：`ChatMessageTimelineView.swift` 现在是 SwiftUI shell，实际长列表热路径下沉到 `UIKitTimeline/ChatTimelineUIKitRepresentable.swift` 与 `ChatTimelineViewController.swift`。该 UIKit core 使用 `UICollectionView`、稳定 item id、可复用 cell、文本/高度缓存、prepend offset preservation、50ms 流式跟随滚动合并，以及 `hasEarlierMessages` / `isLoadingEarlierMessages` 触发的向上分页加载。`hasEarlierMessages` 用 `pageSize + 1` sentinel row 判定，刚好等于窗口大小时不会误显示还有历史。`ChatTimelineDataSource.swift` 独立负责 diffable datasource、snapshot 和 cell 注册；当 stable item id 顺序不变时，流式尾条和内容-only 变化走 `reconfigureItems` 快路径，只让已变更 cell 重新配置，不重建完整插删事务，并在 apply 完成后 invalidate layout，确保 streaming row 增高时重新测量。`ChatTimelineViewController` 在 snapshot apply completion 后执行非 prepend 跳底/流式跟随，避免对尚未提交到 data source 的新 item 滚动；prepend 路径只按 content height delta 恢复用户阅读位置；当 iPad `NavigationSplitView` 侧栏显示/隐藏导致 collection bounds 改变时，会重新 invalidate layout 并在原本贴底时保持贴底。滚动状态通过 `onScrollingChanged` 回传给 SwiftUI shell：真实拖拽、鼠标/触控板滚动和 DEBUG autoscroll 都会暂停 vibe background display link，idle 检测约 50ms 节流，避免手滑期间每个 scroll event 创建新的恢复任务。`ChatTimelineItemBuilder` 只在确实存在更早消息或正在加载时生成 `load-earlier` item，避免无更多历史时顶部留下隐藏 cell 空行。`ChatTimelineLayout.swift` 独立负责 collection layout 和 viewport-relative bubble metrics；`ChatMessageCell.swift` 用 UIKit `UILabel` 渲染正文，按角色使用确定的宽度/对齐约束：user 右对齐、assistant 左对齐、system 居中，并始终以实际 cell/detail 宽度计算气泡，不再用整块 `UIScreen` 宽度参与 iPad split/sidebar 布局。`ChatTimelineTextCache` 以 messageID、content revision、role、font/style 为 key，避免长流式正文反复做整串 hash；`ChatTimelineHeightCache` 以 messageID、content/reasoning revision 和宽度缓存高度。`ChatTimelineItemBuilder` 用 `MessageDisplayItem.createdAt` 插入日期分隔，用 role/speaker/day/5 分钟窗口计算分组，并把 memory extraction、retrieval trace、UI 性能 marker 都建成稳定 timeline item。`ChatTimelineViewController.swift` 还提供 DEBUG-only `--ui-testing-chat-performance-autoscroll` probe，用 `CADisplayLink` 连续滚动并打印 frame interval、CPU、RSS 与 loaded timeline item 数；10K fixture 下模拟器 probe 显示 `loaded_timeline_items=122`。`IPadChatTimelineLayoutUITests.swift` 覆盖未选中起步、从 iPad 侧栏点开已有会话后 user/assistant 文本仍落在 timeline bounds 内，并保留 `ipad-sidebar-chat-timeline-layout` 截图附件用于视觉复查。气泡仍为 flat bubble，不使用 Liquid Glass；长按菜单由 cell 的 `UIContextMenuInteraction` 提供复制、编辑、重新生成、删除。旧 SwiftUI `MessageBubbleView.swift` / `MarkdownTextView` 仍保留为气泡视觉和 Markdown 分块策略的源实现参考，但超长会话的滚动容器不再是 `ScrollView + LazyVStack`。

迁移依据：2026-05-27 复查 Telegram-iOS master 原始源码：`submodules/TelegramUI/Sources/ChatHistoryListNode.swift` 定义 `historyMessageCount = 44`，并用 anchored `ChatHistoryLocationInput` 请求历史窗口；`submodules/Display/Source/ListView.swift` 维护 `items` / `itemNodes`、`displayedItemRange`、可见范围回调和 delete/insert/update transaction，transaction 接收 `stationaryItemRange` 与 scroll target；`submodules/TelegramUI/Sources/PreparedChatHistoryViewTransition.swift` 先对 `ChatHistoryEntry` 做 stable merge，输出 delete/insert/update transaction，并在 reload / hole reload / position restoration 时保持静止范围或指定 scroll anchor。OpenChat 没有 vendoring Telegram 代码，只迁移这些结构原则：窗口化 history、稳定 diff、cell 复用、可见范围驱动加载、滚动位置恢复和流式更新合并。

边缘效果依据：2026-05-27 继续复查 Telegram-iOS master `ffd82647`。普通列表页面如 `submodules/TelegramUI/Sources/ContactSelectionControllerNode.swift` 使用 `EdgeEffectView`，以 top 80pt、bottom 88pt 的非交互 overlay 调用 `update(content:blur:alpha:rect:edge:edgeSize:)`；聊天页 `submodules/TelegramUI/Sources/ChatControllerNode.swift` 则持有 `topBackgroundEdgeEffectNode` / `bottomBackgroundEdgeEffectNode`，通过 `backgroundNode.makeEdgeEffectNode()` 创建，并在顶部用 `WallpaperEdgeEffectEdge(edge: .top, size: 80.0)` + `blur: true`，底部用 `WallpaperEdgeEffectEdge(edge: .bottom, size: min(60.0, blurFrame.height))` + `blur: false`。`submodules/WallpaperBackgroundNode/Sources/WallpaperEdgeEffectNodeImpl.swift` 说明具体分层：克隆/采样 background content 与 gradient node，套 `EdgeEffectView.generateEdgeGradient(...)` mask，并在 blur 打开时加 `VariableBlurView(maxBlurRadius: 1.0)`。OpenChat 当前没有 Telegram 的 wallpaper node/VariableBlur 私有滤镜栈，也没有 Telegram input panel background node 的完整背景协作，因此实现为 UIKit-local edge overlay：不复制源码、不 vendor 私有组件，但保留“背景同源边缘 overlay + 非线性 gradient mask + 顶部 blur / 底部输入区过渡”的结构，而不是 SwiftUI 全局 material mask。

## 3. InputBarView

```swift
struct InputBarView: View {
    @Binding var text: String
    @Binding var isPrefillModeEnabled: Bool
    @Binding var inputRole: StageInputRole
    @Binding var responderIds: [String]
    var prefillNextRole: PrefillInputRole
    var stageParticipants: [StageParticipantRecord]
    var showsDirectorTools: Bool
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onCustomizeResponders: () -> Void
}
```

- 底部 composer 不再铺整宽 `.regularMaterial` 横条；底栏容器中只放透明 dock、独立圆角输入 capsule、左侧工具按钮和右侧发送按钮，键盘弹出时避免出现额外灰色横栏。
- 多行文本输入框使用 SwiftUI `TextEditor` + 隐藏测量文本自适应高度，最大 6 行，保留 `chat.inputText` accessibility identifier。
- 发送按钮：圆形 `arrow.up`，`text` 非空时启用
- 停止按钮：生成中显示圆形 `stop.fill`，点击取消当前流式请求
- 键盘 Return 不发送（允许换行），需点击按钮发送
- 非 Stage 会话显示左侧 `Input Mode` 菜单，可在普通发送和预填充手写对话之间切换。预填充模式保持开启直到用户手动切回；开启后输入框上方显示本次发送会保存成用户输入还是角色回复。若当前历史最后一条是 `user`，本次输入保存为当前角色的 `assistant` 回复；否则保存为 `user` 输入。该模式始终只写本地历史，不触发 API 请求。
- Stage 会话显示轻量 `ellipsis.circle` 工具按钮；展开后由 `DirectorResponderPanel.swift` 管理 responder 选择和上下排序。
- `DirectorResponderPanel.swift` 同时提供 `StageInputRole` 的 segmented picker：`Participant` 会把输入作为用户消息并触发当前 responder 队列；`Director` 会把输入保存为 hidden stage instruction，不进入消息列表。

实现证据：`ChatView.swift` 通过 `chatInputBar` 挂载 `InputBarView`：iOS 26+ 使用 `safeAreaBar(edge: .bottom, spacing: 0)`，让系统 scroll edge effect 纳入 custom bar 的 safe area 计算；iOS 17-25 fallback 到 `safeAreaInset(edge: .bottom, spacing: 0)`。`InputBarView.swift` 使用透明外层、`TextEditor`、`InputTextHeightPreferenceKey` 和独立圆角输入 capsule 实现 Telegram 式底部 composer；输入 capsule、输入模式按钮与发送/停止圆形按钮复用 `ChatChromeAppearance`，在 iOS 26+ 用固定浅/深模式 tint 的 `glassEffect(.regular.tint(...).interactive(), in:)` 保留 glass 采样但锁定主视觉色阶，避免跟随背景取色突变；iOS 17-25 使用同一套浅/深色 fallback fill。非 Stage 分支通过 `Menu` 暴露 `chat.inputModeMenu`，预填充开启时显示 `chat.prefillModeHint` 并读取 `ChatViewModel.prefillNextRole` 这个窄状态切换 placeholder；该状态只在消息尾角色真正变化时同步，不让 composer 在每个流式正文 batch 中观察整条 `messages` 数组。Stage 工具入口保持 `ellipsis.circle`，两者不同时显示。`DirectorResponderPanel.swift` 持有输入模式切换、director instruction 提示、responder 行、选择、上下移动和 accessibility identifiers。`UITestingSupport.swift` 的 `--ui-testing` 种子提供 Mara/Io 双角色 Stage 和 mock 流式回复，`--ui-testing-chat-edge-effects` 额外填充长消息用于顶部/底部边缘截图验证，`--ui-testing-chat-prefill` 选择独立非 Stage 会话用于预填充 UI 自动化；`StageUITests.swift` 验证 director 输入不显示为消息、participant 输入生成 Mara/Io 多轮回复，`PrefillModeUITests.swift` 验证非 Stage 输入栏菜单、预填充提示、assistant/user 交替气泡和模式保持开启。

## 4. ChatSettingsSheet

在聊天界面点击设置图标弹出的 Sheet。会话标题编辑也在该面板中完成，避免主导航栏堆叠多个操作按钮：

```
┌─────────────────────────────────────────┐
│ 会话设置                         [完成]  │
│─────────────────────────────────────────│
│ Section: 会话                            │
│   标题: [银月森林的入口]                 │
│   API 端点: [使用默认 ▸]                │
│   模型: [使用默认 ▸]                    │
│   角色卡: [艾拉 ▸]                      │
│   上下文策略: [剔除/压缩]               │
│   场景覆盖: [可选文本输入]              │
│   慢速剧情推进: [开关]                  │
│                                         │
│ Section: Stage                          │
│   导演模式 / 参与者管理                  │
│                                         │
│ Section: 模型                            │
│   本会话自定义模型参数: [开关]           │
│   关闭时展示继承的全局默认值摘要         │
│   打开后展开 Temperature / Top P /      │
│   Max Tokens / Thinking 设置             │
└─────────────────────────────────────────┘
```

模型参数继承规则：
- `conversation.modelParameters == nil` 时，`ChatViewModel.currentParameters` 从 `UserDefaults.openChatDefaultModelParameters()` 读取全局默认。
- 旧版本曾在保存会话设置时把当时的默认模型参数写入 `conversation.modelParameters`；`ChatViewModel` 会把这类 legacy 默认 JSON 视为“继承全局”，避免老会话被固定在旧默认值上。
- 只有打开 `Customize for This Chat` 时，保存设置才会把当前控件值编码到 `conversation.modelParameters`。
- 关闭本会话自定义会清空 `conversation.modelParameters`，后续生成继续继承全局默认。
- 实现证据：`ChatSettingsSheet.swift` 的 Model section 使用 `usesCustomModelParameters` 控制摘要/控件展开；`ChatViewModel.swift` 的 `currentParameters` 在会话覆盖和全局默认之间切换，并兼容 legacy 默认参数 JSON；`ChatViewModelPromptAssemblyTests.swift` 覆盖全局继承、legacy 默认参数继承、开启自定义时预填当前全局默认，以及保存时不写入覆盖的回归。

历史布局草图：

```
│ Section: 角色与世界（非 Stage 会话）     │
│   角色卡: [艾拉 ▸]          [更换/移除] │
│   世界: 中土世界（通过角色卡关联）       │
│   场景覆盖: [可选文本输入]              │
│                                         │
│ Section: 上下文管理                      │
│   策略: (●) 剔除  ( ) 压缩             │
│                                         │
│ Section: 模型参数                        │
│   Temperature: [====●=====] 0.80        │
│   Top P:       [========●=] 0.95        │
│   Max Tokens:  [====●=====] 2048        │
│                                         │
│ Section: API 端点                        │
│   当前: [本地 Llama ▸]                  │
└─────────────────────────────────────────┘
```
