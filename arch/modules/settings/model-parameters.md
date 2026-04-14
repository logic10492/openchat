# 模型参数全局默认值

> 父文档：[settings/index.md](index.md)

## 1. 功能描述

- 调节模型参数的全局默认值
- 恢复默认值
- 会话级参数可覆盖全局参数

## 2. 视图设计

```
Section: 模型参数默认值
  Temperature: [====●=====] 0.80
  Top P:       [========●=] 0.95
  Max Tokens:  [未设置]
  Frequency P: [●=========] 0.00
  Presence P:  [●=========] 0.00
  [恢复默认值]
```

## 3. 存储方式

全局默认参数使用 **UserDefaults** 存储（轻量，无需入库）：

| Key | 类型 | 默认值 |
|---|---|---|
| `default_temperature` | Double | 0.8 |
| `default_top_p` | Double | 0.95 |
| `default_max_tokens` | Int? | nil |
| `default_frequency_penalty` | Double | 0.0 |
| `default_presence_penalty` | Double | 0.0 |

## 4. 参数优先级

会话级参数覆盖存储在 `conversation.modelParameters` JSON 字段中。

PromptEngine 使用时的优先级：**会话参数 > 全局参数**。
