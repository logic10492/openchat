# 应用外观设置

> 父文档：[settings/index.md](index.md)

## 状态：Liquid Glass 视觉重构完成

OpenChat 现已全面采用 Apple HIG 前沿的 **Liquid Glass (液态玻璃)** 视觉风格，致力于带来极具质感和深度的用户体验。

### 视觉架构与特性

- **全局材质系统**：全面废弃了硬编码的 `systemGray` 背景，所有背景及输入部件均基于原生的 `.regularMaterial` 和 `.ultraThinMaterial`，并辅以极低不透明度的 0.5pt 白色内发光（`.blendMode(.overlay)`），强化玻璃厚度感。
- **空间景深与交互反馈**：移除了传统单层死板阴影，采用基于 `Elevation 1、2、3` 级别的分层背光投影，配合 120Hz 的流畅滚动及 Haptics（`UIImpactFeedbackGenerator`）碰撞震动，赋予界面生命力。
- **独立悬浮体验**：输入框 (`InputBarView`) 等核心组件被重设为不贴底的悬浮磨砂胶囊形态，并配合 SafeAreaInsets 确保下层内容可通过材质透出纯净的色彩。消息气泡 (`MessageBubbleView`) 在保证 Vibrancy 文字对比度的同时不滥用渐变色，维持极简质感。
- **网格规范**：全局强制使用 8pt 倍数间距间距系统（8/16/24/32）。

### 后续预期配置范围（待开发面板）

未来的的外观设置面板预计将提供：
- 沉浸式主题策略调节（跟随系统 / 浅色 / 深色）
- 界面字体与排版适配（支持更大的 Dynamic Type 阶级调整）
- 自定义主题高亮色（Accent Color）的材质渗透度调节
