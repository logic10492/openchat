# 聊天模块设计

> 所属层：`Features/Chat/`
> 依赖：Core/Networking（APIClient）, Core/PromptEngine, Core/ContextManager, Core/Database, Features/CharacterCard, Features/WorldBook

## 1. 功能范围

- 消息列表展示（支持 Markdown 渲染）
- 流式输出实时显示
- 发送消息 / 停止生成
- 重新生成最后一条 AI 回复
- 编辑已发送的用户消息（编辑后重新生成）
- 当前会话设置（上下文策略；非 Stage 会话支持角色卡/世界书切换，Stage 会话通过 Stage participants 管理角色）
- 会话信息展示（顶部角色胶囊；token 使用情况保留在消息统计区域，不在导航栏常驻显示）
- 每条 AI 回复下方显示详细统计（输入/输出 token 数、TPS、上下文窗口剩余百分比），可在全局设置中关闭详细模式，关闭后仅在窗口余量 < 20% 时显示上下文窗口剩余百分比
- 记忆提取完成时在对话中显示临时提示（"已提取 N 条记忆"，3 秒后自动消失）

> Stage 规划：Chat 当前是单会话/单主角色实现。多角色共同参与、导演 agent 和用户导演输入属于目标 Stage 系统，详见 `../stage/index.md`。

## 2. 子文档

| 文档 | 内容 |
|---|---|
| [views.md](views.md) | ChatView、消息气泡、输入栏、设置 Sheet 的视图设计与实现证据 |
| [view-model.md](view-model.md) | `ChatViewModel` 状态、发送/重新生成/编辑/预填充语义、记忆提取和 Background 主链路 |
| [streaming.md](streaming.md) | `MessageDisplayItem`、流式分块渲染、Markdown 延迟刷新、滚动跟随、Token 使用展示 |
| [vibe-background.md](vibe-background.md) | 状态驱动的聊天动态背景概念草案，预留内容 watcher 与 Liquid Glass chrome 视觉关系 |
| [performance-report-2026-05-26.md](performance-report-2026-05-26.md) | 长会话 + 氛围背景的滑动/生成性能审计、优化证据和 before/after 指标 |
| [evidence.md](evidence.md) | 当前实现证据、已完成功能和自动化测试覆盖 |

## 3. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `ChatView.swift` | 聊天页面 shell：绑定 `ChatViewModel`、设置/编辑 sheet、输入栏和消息 timeline 组合 |
| `ChatNavigationToolbar.swift` | 导航栏角色胶囊、Stage 胶囊和设置按钮，隔离 toolbar 对 `ChatViewModel` 的观察范围 |
| `ChatTimelineHostView.swift` | 将 `ChatViewModel` 的消息/统计/诊断状态映射到 `ChatMessageTimelineView`，隔离流式消息刷新 |
| `ChatInputBarHostView.swift` | 将输入文本、Stage responder 和生成状态绑定到 `InputBarView`，隔离 composer 刷新 |
| `ChatMessageTimelineView.swift` | UIKit `UICollectionView` 消息轨道 SwiftUI bridge：日期分隔、同发送者短间隔分组、流式自动跟随/用户拖动暂停、记忆提取提示和诊断 trace 插入 |
| `ChatChromeViews.swift` | 聊天 chrome 组件：背景、日期分隔、顶部角色胶囊、角色/世界书 popover、编辑消息 sheet |
| `ChatEdgeEffects.swift` | `chatInputBar` safe-area bridge 与 iOS 17-25 消息 viewport fade/material fallback；iOS 26+ 边缘 soft effect 由 UIKit timeline 的 native scroll edge effect 承担，视觉权威为 2026-05-27 用户截图和 `e1c17f6` |
| `MessageBubbleView.swift` | 单条消息行和气泡，支持 Markdown、长按菜单、分组尾部时间、流式光标和统计展示 |
| `MessageBubbleChrome.swift` | 系统消息胶囊、时间脚等气泡辅助 chrome |
| `ReasoningDisclosureView.swift` | AI 思考内容展示：折叠摘要、固定高度滚动预览、长文本尾部截断与系统复制 |
| `InputBarView.swift` | 底部 composer（文本框 + 发送/停止按钮 + Stage 工具入口） |
| `DirectorResponderPanel.swift` | Stage responder 选择与排序面板 |
| `ChatSettingsSheet.swift` | 当前会话设置面板 |
| `ChatViewModel.swift` | 核心 ViewModel，管理消息状态、调度 API 请求 |
| `ChatViewModel+Support.swift` | 生成/流式/记忆提取的实现细节 |
| `MessageDisplayItem.swift` | 消息展示用 DTO（含可选 StreamingStats） |
| `StreamingRenderBuffer.swift` | 合并高频 SSE delta，降低长流式回复期间的 UI invalidation 频率 |
| `StreamingStats.swift` | 流式输出统计数据（输入/输出 token、TPS、上下文余量） |
| `StatsBarView.swift` | 统计数据展示组件（详细/精简两种模式） |

## 4. 与其他模块的交互

| 交互对象 | 交互方式 |
|---|---|
| `Core/Networking` | APIClient.streamMessage() 发送流式请求 |
| `Core/PromptEngine` | PromptAssembler.assemble() 拼装 prompt |
| `Core/ContextManager` | ContextManager.prepareHistory() 预处理历史 |
| `Core/Database` | 读写 MessageRecord, ConversationRecord |
| `Features/CharacterCard` | 显示角色卡信息，跳转角色卡详情 |
| `Features/WorldBook` | ChatSettingsSheet 中选择/切换世界书 |
| `Features/Conversation` | ConversationListView 点击进入 ChatView |
| `Features/Settings` | 全局默认参数作为 fallback |

## 5. 设计决策

1. **流式优先**：默认使用流式请求，给用户即时反馈。仅在端点不支持 SSE 时回退到非流式
2. **乐观 UI**：发送消息后立即显示用户气泡和 AI 占位，不等待 API 确认
3. **部分保存**：用户取消生成时保留已生成的内容，而非丢弃
4. **编辑即重新生成**：编辑消息后删除后续消息并重新生成，保持对话逻辑一致性
5. **Token 透明**：显示详细的 token 使用报告，帮助用户理解上下文分配情况
