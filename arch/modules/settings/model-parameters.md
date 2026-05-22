# 模型参数全局默认值

> 父文档：[settings/index.md](index.md)

## 1. 功能描述

- 调节模型参数的全局默认值
- 恢复默认值
- 会话默认继承全局参数；用户显式打开本会话自定义后，会话级参数才覆盖全局参数

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

会话级参数覆盖存储在 `conversation.modelParameters` JSON 字段中；`nil` 表示继承全局默认。旧版本保存设置时可能写入一份默认参数 JSON，当前 `ChatViewModel` 会把这类 legacy 默认值视为继承全局默认，避免老会话继续固定旧默认。

PromptEngine 使用时的优先级：**会话参数 > 全局参数**。

实现证据：
- `UserDefaults+ModelParameters.swift` 负责从 `default_temperature` / `default_top_p` / `default_max_tokens` 等 key 解析全局默认。
- `ChatViewModel.currentParameters` 在 `usesCustomModelParameters == false` 时返回全局默认，在 `true` 时返回会话控件值。
- `ChatViewModel.saveConversationSettings()` 仅在本会话自定义打开时写入 `conversation.modelParameters`，否则保存为 `nil`。
- `ChatViewModelPromptAssemblyTests.swift` 覆盖全局默认继承、legacy 默认参数继承、打开本会话自定义时预填当前全局默认，以及保存继承状态不写入覆盖。
