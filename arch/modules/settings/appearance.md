# 应用外观设置

> 父文档：[settings/index.md](index.md)

## 状态：Design System 基线已落地

OpenChat 当前已建立共享设计系统基线，用于收敛 spacing、radius、surface、typography、button、list、card 等基础样式。该阶段不是全量视觉重构，而是为后续页面精修提供稳定 token 和可复用 modifier。

### 已实现的视觉基线

- **设计 token**：`OpenChatDesignSystem` 定义在 `OpenChat/Shared/Extensions/View+Modifiers.swift`，包含 `Spacing`、`Radius`、`IconSize`、`Typography`、`Surface`、`Shadow`、`ControlSize`。
- **共享 modifier**：同文件提供 `openChatCardStyle()`、`openChatGlassInputStyle()`、`openChatSidebarRow(isSelected:)`、`openChatListRowStyle()`、`openChatPrimaryButtonStyle()`、`openChatBadgeStyle()` 等入口。
- **核心调用点**：`ChatView`、`InputBarView`、`MessageBubbleView`、`SidebarView`、`WelcomeView`、`EmptyStateView` 已迁移到共享 token。
- **列表调用点**：`CharacterCardListView`、`CharacterCardDetailView`、`WorldBookListView`、`SettingsView` 已开始复用统一的 row typography、spacing、badge 和 accent wash。

### 设计约束

- 页面级背景优先使用 `OpenChatDesignSystem.Surface.pageBackground`，不要在 View 内直接散落 `Color(.systemGroupedBackground)`。
- 常用间距使用 `OpenChatDesignSystem.Spacing`，保留 4/8/12/16/24/32 的节奏。
- 圆角使用 `OpenChatDesignSystem.Radius`；输入栏、空状态等大 surface 使用 `input`，列表与按钮使用 `sm` / `md`。
- 新增按钮、badge、list row、card surface 时优先添加或复用 Shared modifier，避免单个 View 自行定义一套样式。
- 当前允许局部保留系统 `Form` / `List` 默认样式；后续页面精修时逐步迁移，不一次性改动所有业务页面。

### 实现证据

- `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'generic/platform=iOS Simulator'` 于 2026-05-22 通过。
- 本阶段没有修改 `PRODUCT_BUNDLE_IDENTIFIER`、`DEVELOPMENT_TEAM`、`CODE_SIGN_STYLE` 或 `scripts/generate_xcodeproj.rb`。

### 后续预期配置范围（待开发面板）

未来的外观设置面板预计将提供：
- 沉浸式主题策略调节（跟随系统 / 浅色 / 深色）
- 界面字体与排版适配（支持更大的 Dynamic Type 阶级调整）
- 自定义主题高亮色（Accent Color）的材质渗透度调节
