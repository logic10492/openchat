# 上下文策略全局默认配置

> 父文档：[settings/index.md](index.md)

## 1. 功能描述

- 设置默认上下文管理策略（截断 / 压缩）
- 配置压缩用 API 端点

## 2. 视图设计

```
Section: 上下文管理
  默认策略: [对话剔除 ▸]
  压缩用端点: [与聊天端点相同 ▸]
```

## 3. 存储方式

| Key | 类型 | 默认值 |
|---|---|---|
| `default_context_strategy` | String | "truncation" |
| `compression_endpoint_id` | String? | nil |

`compression_endpoint_id` 为 `nil` 时表示使用当前聊天端点进行压缩。
