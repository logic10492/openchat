# 设置模块设计

> 所属层：`Features/Settings/`
> 依赖：Core/Database（APIEndpointRecord）, Core/Networking

## 1. 功能范围

| 功能 | 设计文档 | 状态 |
|---|---|---|
| API 端点管理（CRUD、测试连接、设置默认） | [api-endpoint.md](api-endpoint.md) | 设计完成 |
| 模型参数全局默认值调节 | [model-parameters.md](model-parameters.md) | 设计完成 |
| 上下文策略全局默认配置 | [context-strategy.md](context-strategy.md) | 设计完成 |
| 数据管理（导出、导入、清除） | [data-management.md](data-management.md) | 设计完成 |
| 应用外观设置 | [appearance.md](appearance.md) | 待设计 |

> 新增功能时，在此表中追加行并创建对应 `.md` 文件即可。

## 2. 文件清单与职责

| 文件 | 职责 | 关联文档 |
|---|---|---|
| `SettingsView.swift` | 设置主界面（Section 列表） | 本文件 §3 |
| `APIEndpointEditorView.swift` | 单个 API 端点的添加/编辑界面 | [api-endpoint.md](api-endpoint.md) |
| `ModelParametersView.swift` | 模型参数全局默认值调节界面 | [model-parameters.md](model-parameters.md) |
| `DataManagementView.swift` | 数据导出/导入/清除界面 | [data-management.md](data-management.md) |
| `SettingsViewModel.swift` | 设置数据管理 | 本文件 §4 |
| `APIEndpointEditorViewModel.swift` | 端点编辑表单状态管理 | [api-endpoint.md](api-endpoint.md) |

## 3. SettingsView 主界面布局

```
┌─────────────────────────────────────────┐
│ 设置                                    │
│─────────────────────────────────────────│
│ Section: API 端点                        │
│   → 详见 api-endpoint.md                │
│                                         │
│ Section: 模型参数默认值                  │
│   → 详见 model-parameters.md            │
│                                         │
│ Section: 上下文管理                      │
│   → 详见 context-strategy.md            │
│                                         │
│ Section: 数据管理                        │
│   → 详见 data-management.md             │
│                                         │
│ Section: 关于                            │
│   版本: 1.0.0 (Build 1)                │
└─────────────────────────────────────────┘
```

## 4. SettingsViewModel

```swift
@Observable
final class SettingsViewModel {
    // API 端点
    private(set) var endpoints: [APIEndpointRecord] = []

    // 全局模型参数默认值（存储在 UserDefaults）
    var defaultTemperature: Double = 0.8
    var defaultTopP: Double = 0.95
    var defaultMaxTokens: Int? = nil
    var defaultFrequencyPenalty: Double = 0.0
    var defaultPresencePenalty: Double = 0.0

    // 全局上下文策略
    var defaultContextStrategy: ContextStrategy = .truncation
    var compressionEndpointId: String? = nil  // nil = 使用聊天端点

    func loadEndpoints() async
    func deleteEndpoint(_ id: String) async throws
    func setDefaultEndpoint(_ id: String) async throws
    func resetModelParameters()

    // 数据管理
    func exportAllData() async throws -> URL      // 返回导出文件路径
    func importData(from url: URL) async throws
    func clearAllData() async throws
}
```

## 5. 与其他模块的交互

| 交互对象 | 交互方式 |
|---|---|
| `Features/Chat` | ChatSettingsSheet 引用全局默认参数作为初始值 |
| `Core/Networking` | 测试连接时使用 APIClient |
| `Core/Database` | 管理 APIEndpointRecord CRUD |
| `Core/ContextManager` | 提供默认上下文策略 + 压缩端点配置 |
