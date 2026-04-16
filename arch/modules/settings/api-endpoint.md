# API 端点管理

> 父文档：[settings/index.md](index.md)

## 1. 功能描述

- API 端点的增删改查
- 自动拉取模型端点可用的模型 提供列表选项，若拉取失败则提示，并要求用户自己填入模型名称
- 设置默认端点
- 选择 API 模式（Chat Completions / Responses API）
- 选择 API 模式（Chat Completions / Responses API）
- 测试连接可用性

## 2. 视图设计

### 2.1 端点列表（SettingsView 中的 Section）

```
Section: API 端点
  ┌─ 本地 Llama ────────── ✓ 默认 ──┐
  │  http://localhost:8080/v1         │
  └───────────────────────────────────┘
  ┌─ OpenAI ──────────────────────┐
  │  https://api.openai.com/v1     │
  └───────────────────────────────┘
  [+ 添加端点]
```

### 2.2 APIEndpointEditorView

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
│  Section: 模型                            │
│  ────────────────────────────────────   │
│  [加载中...] ○   (拉取模型列表时)       │
│  或                                      │
│  模型: [Picker: llama-3-8b ▼]           │
│        [手动输入模型名称]                │
│  或                                      │
│  模型名称: [_______________]  [重试]    │
│  ⚠️ 拉取失败：连接被拒绝                    │
│  ────────────────────────────────────   │
│                                         │
│  最大上下文 Token:                       │
│  [4096_____]                            │
│  Section: API 模式                       │
│  ────────────────────────────────────   │
│  API 模式: [Picker: Chat Completions ▼] │
│  ℹ️ Responses 模式下 frequency_penalty、 │
│     presence_penalty、stop 参数将被忽略  │
│                                         │
│                                         │
│  Section: API 模式                       │
│  ────────────────────────────────────   │
│  API 模式: [Picker: Chat Completions ▼] │
│  ℹ️ Responses 模式下 frequency_penalty、 │
│     presence_penalty、stop 参数将被忽略  │
│                                         │
│  设为默认: [开关]                       │
│                                         │
│  [🔗 测试连接]                          │
│  ✅ 连接成功！模型响应正常。             │
└─────────────────────────────────────────┘
```

> **实现证据**: `APIEndpointEditorView.swift` — 模型选择区域支持三种状态：加载中、Picker 选择、手动输入回退

## 3. APIEndpointEditorViewModel

```swift
@Observable
final class APIEndpointEditorVi
    var apiMode: APIMode = .chatCompletionsewModel {
    // 表单字段
    var name: String = ""
    var baseURL: String = ""
    var apiKey: String = ""
    var modelName: String = ""
    var maxContextTokens: Int = 4096
    var isDefault: Bool = false
    var apiMode: APIMode = .chatCompletions

    // 测试状态
    private(set) var testResult: TestResult? = nil
    enum TestResult {
        case testing
        case success(String)
        case failure(String)
    }

    // 模型列表拉取状态
    private(set) var availableModels: [String] = []
    private(set) var isFetchingModels: Bool = false
    private(set) var modelFetchError: String? = nil
    var isCustomModelInput: Bool = false

    let editingEndpoint: APIEndpointRecord?

    var isValid: Bool  // name + baseURL + modelName 非空，baseURL 为合法 URL

    func save() async throws -> APIEndpointRecord
    func testConnection() async
    func scheduleFetchModels()       // 0.5s debounce 后触发 fetchAvailableModels
    func fetchAvailableModels() async // GET {baseURL}/models
}
```

> **实现证据**: `APIEndpointEditorViewModel.swift`

## 4. 模型列表拉取

编辑器打开时自动向 `{baseURL}/models` 发送 GET 请求拉取可用模型：

- `baseURL` 或 `apiKey` 变化时 debounce 0.5s 后重新拉取
- 成功：显示 Picker 下拉选择，底部提供“手动输入模型名称”链接
- 失败：回退到 TextField 手动输入 + 错误提示 + 重试按钮
- 加载中：显示 ProgressView

```swift
// APIClient 新增方法
func fetchM请求（根据所选 API 模式自动发往 Chat Completions 或 Responses 端点）：

```swift
func testConnection() async {
    testResult = .testing
    do {
        let config = APIEndpointConfig(
            baseURL: URL(string: baseURL)!,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            modelName: modelName,
            maxContextTokens: maxContextTokens,
            apiMode: apiMode
func testConnection() async {
    testResult = .testing
    do {
        let config = APIEndpointConfig(
            baseURL: URL(string: baseURL)!,
            apiKey: apiKey.isEmpty ? nil : apiKey,
            modelName: modelName,
            maxContextTokens: maxContextTokens,
            apiMode: apiMode
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

## 6. 安全考虑

- API Key 存储在 SQLite 数据库的 `api_endpoint.apiKey` 字段
- iOS App Sandbox 提供文件级保护
- 未来可考虑迁移到 Keychain（当前版本暂不实现，因为本地模型场景下 API Key 通常为空或无需保密）

## 实现证据（2026-04-16）

- `APIEndpointEditorView.swift` — API Mode Picker（Chat Completions / Responses），Responses 模式下显示参数忽略提示
- `APIEndpointEditorViewModel.swift` — `apiMode: APIMode` 属性，save 时持久化到 `APIEndpointRecord.apiMode`
- `APIEndpointRecord.swift` — `apiMode: String` 字段 + `apiModeValue: APIMode` 计算属性
- 数据库迁移 `v5_addApiMode` — 为 `api_endpoint` 表追加 `apiMode` 列（默认 `chatCompletions`）
