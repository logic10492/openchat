# 设置模块设计

> 所属层：`Features/Settings/`
> 依赖：Core/Database（APIEndpointRecord）, Core/Networking

## 1. 功能范围

- API 端点管理（CRUD、测试连接、设置默认）
- 模型参数全局默认值调节
- 上下文策略全局默认配置
- 数据管理（导出、导入、清除）
- 应用外观设置

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `SettingsView.swift` | 设置主界面（Section 列表） |
| `APIEndpointEditorView.swift` | 单个 API 端点的添加/编辑界面 |
| `ModelParametersView.swift` | 模型参数全局默认值调节界面 |
| `DataManagementView.swift` | 数据导出/导入/清除界面 |
| `SettingsViewModel.swift` | 设置数据管理 |
| `APIEndpointEditorViewModel.swift` | 端点编辑表单状态管理 |

## 3. 视图设计

### 3.1 SettingsView

```
┌─────────────────────────────────────────┐
│ 设置                                    │
│─────────────────────────────────────────│
│ Section: API 端点                        │
│   ┌─ 本地 Llama ────────── ✓ 默认 ──┐  │
│   │  http://localhost:8080/v1         │  │
│   └───────────────────────────────────┘  │
│   ┌─ OpenAI ──────────────────────┐     │
│   │  https://api.openai.com/v1     │     │
│   └───────────────────────────────┘     │
│   [+ 添加端点]                          │
│                                         │
│ Section: 模型参数默认值                  │
│   Temperature: [====●=====] 0.80        │
│   Top P:       [========●=] 0.95        │
│   Max Tokens:  [未设置]                 │
│   Frequency P: [●=========] 0.00       │
│   Presence P:  [●=========] 0.00       │
│   [恢复默认值]                          │
│                                         │
│ Section: 上下文管理                      │
│   默认策略: [对话剔除 ▸]                │
│   压缩用端点: [与聊天端点相同 ▸]        │
│                                         │
│ Section: 数据管理                        │
│   [导出所有数据]                        │
│   [导入数据]                            │
│   [清除所有数据]  ← 红色，二次确认      │
│                                         │
│ Section: 关于                            │
│   版本: 1.0.0 (Build 1)                │
└─────────────────────────────────────────┘
```

### 3.2 APIEndpointEditorView

```
┌─────────────────────────────────────────┐
│ [取消]    添加 API 端点        [保存]   │
│─────────────────────────────────────────│
│  名称: [本地 Llama___________]          │
│                                         │
│  Base URL:                              │
│  [http://localhost:8080/v1___]          │
│                                         │
│  API Key (可选):                        │
│  [sk-.........................]  [👁]   │
│                                         │
│  模型名称:                              │
│  [llama-3-8b________________]           │
│                                         │
│  最大上下文 Token:                       │
│  [4096_____]                            │
│                                         │
│  设为默认: [开关]                       │
│                                         │
│  [🔗 测试连接]                          │
│  ✅ 连接成功！模型响应正常。             │
└─────────────────────────────────────────┘
```

## 4. ViewModel 设计

### 4.1 SettingsViewModel

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

### 4.2 APIEndpointEditorViewModel

```swift
@Observable
final class APIEndpointEditorViewModel {
    // 表单字段
    var name: String = ""
    var baseURL: String = ""
    var apiKey: String = ""
    var modelName: String = ""
    var maxContextTokens: Int = 4096
    var isDefault: Bool = false

    // 测试状态
    private(set) var testResult: TestResult? = nil
    enum TestResult {
        case testing
        case success(String)     // 成功信息
        case failure(String)     // 错误信息
    }

    let editingEndpoint: APIEndpointRecord?  // nil = 创建模式

    // 校验
    var isValid: Bool  // name + baseURL + modelName 非空，baseURL 为合法 URL

    func save() async throws -> APIEndpointRecord
    func testConnection() async
}
```

### 4.3 连接测试

测试连接时发送一个简单的 Chat Completion 请求：

```swift
func testConnection() async {
    testResult = .testing
    do {
        let config = APIEndpointConfig(
            baseURL: URL(string: baseURL)!,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            modelName: modelName,
            maxContextTokens: maxContextTokens
        )
        let response = try await apiClient.sendMessage(
            messages: [ChatMessage(role: "user", content: "Hi")],
            endpoint: config,
            parameters: ModelParameters(maxTokens: 1)   // 最小 token 节省开销
        )
        testResult = .success("连接成功！模型 \(modelName) 响应正常。")
    } catch {
        testResult = .failure("连接失败：\(error.localizedDescription)")
    }
}
```

## 5. 全局参数存储

全局默认参数使用 **UserDefaults** 存储（轻量，无需入库）：

| Key | 类型 | 默认值 |
|---|---|---|
| `default_temperature` | Double | 0.8 |
| `default_top_p` | Double | 0.95 |
| `default_max_tokens` | Int? | nil |
| `default_frequency_penalty` | Double | 0.0 |
| `default_presence_penalty` | Double | 0.0 |
| `default_context_strategy` | String | "truncation" |
| `compression_endpoint_id` | String? | nil |

会话级参数覆盖存储在 `conversation.modelParameters` JSON 字段中。PromptEngine 使用时的优先级：会话参数 > 全局参数。

## 6. 数据导出/导入

### 6.1 导出格式

导出为单个 JSON 文件：

```json
{
  "formatVersion": 1,
  "exportedAt": "2026-04-14T12:00:00Z",
  "data": {
    "endpoints": [...],
    "characterCards": [...],
    "worldBooks": [...],
    "worldBookEntries": [...],
    "conversations": [...],
    "messages": [...],
    "settings": {
      "defaultTemperature": 0.8,
      ...
    }
  }
}
```

### 6.2 导出流程

1. 导出全部数据库表内容
2. 导出 UserDefaults 中的设置
3. 序列化为 JSON
4. 通过 `ShareSheet` 或保存到文件

### 6.3 导入流程

1. 用户选择 JSON 文件
2. 解析并验证格式版本
3. 提示用户：覆盖现有数据 / 合并（跳过已存在 ID 的记录）
4. 批量写入数据库
5. 更新 UserDefaults

### 6.4 清除数据

1. 二次确认弹窗："确定要清除所有数据吗？此操作不可恢复。"
2. 清空所有数据库表
3. 重置 UserDefaults 到默认值
4. 不删除 API 端点配置（用户可能还需要）

## 7. 安全考虑

### 7.1 API Key 存储

- API Key 存储在 SQLite 数据库的 `api_endpoint.apiKey` 字段
- iOS App Sandbox 提供文件级保护
- 未来可考虑迁移到 Keychain（当前版本暂不实现，因为本地模型场景下 API Key 通常为空或无需保密）

### 7.2 导出安全

- 导出文件包含 API Key 明文 → 在导出确认弹窗中提醒用户
- 导出文件使用 `.openchat` 扩展名便于识别

## 8. 与其他模块的交互

| 交互对象 | 交互方式 |
|---|---|
| `Features/Chat` | ChatSettingsSheet 引用全局默认参数作为初始值 |
| `Core/Networking` | 测试连接时使用 APIClient |
| `Core/Database` | 管理 APIEndpointRecord CRUD |
| `Core/ContextManager` | 提供默认上下文策略 + 压缩端点配置 |
