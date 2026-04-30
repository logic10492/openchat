# 上下文策略全局默认配置

> 父文档：[settings/index.md](index.md)

## 1. 功能描述

- 设置默认上下文管理策略（截断 / 压缩）
- 在单个对话中配置压缩模式（标准 / 高智能）
- 配置压缩用 API 端点

## 2. 视图设计

```
Section: 上下文管理
  默认策略: [对话剔除 ▸]
  对话压缩模式: [标准 ▸]
  压缩用端点: [与聊天端点相同 ▸]
```

## 3. 存储方式

| Key | 类型 | 默认值 |
|---|---|---|
| `default_context_strategy` | String | "truncation" |
| `compression_endpoint_id` | String? | nil |

`compression_endpoint_id` 为 `nil` 时表示使用当前聊天端点进行压缩。

## 4. 会话级压缩模式

当前实现把压缩模式存储在 `conversation.compressionMode`，由 `ChatSettingsSheet` 在对话设置中展示；全局设置页暂不保存默认压缩模式。

| 值 | 阈值语义 |
|---|---|
| `standard` | 自动压缩阈值为 `endpoint.maxContextTokens × 0.40` |
| `highIntelligence` | effective compact window 为 `endpoint.maxContextTokens × 0.25`，自动压缩阈值为该 effective window 的 90% |
