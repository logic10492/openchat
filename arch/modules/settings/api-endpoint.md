# API 端点管理

> 父文档：[settings/index.md](index.md)

## 1. 功能描述

- API 端点的增删改查（端点 = URL + API Key 组合）
- 端点下模型列表管理：自动拉取 + 手动添加
- 每个模型独立配置 maxContextTokens 和 API 模式
- 拉取失败或列表为空时自动插入 "default" 占位模型
- 设置默认端点和默认模型
- 对话中动态选择模型
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
│  Base URL:                              │
│  [http://localhost:8080/v1___]          │
│  API Key (可选):                        │
│  [sk-.........................]         │
│  设为默认: [开关]                       │
│  [🔗 测试连接]                          │
│  ✅ 连接成功！模型响应正常。             │
│                                         │
│  Section: 可用模型                      │
│  ┌ llama-3-8b                默认 手动 ┐ │
│  │ 32768 tokens · Responses          │ │
│  └ 长按: 编辑模型 / 设为默认 / 删除     │
│  [+ 添加模型]                 [刷新]    │
└─────────────────────────────────────────┘
```

> **实现证据**: `APIEndpointEditorView.swift` — 端点字段、连接测试、可用模型列表、长按菜单（编辑模型 / 设为默认 / 删除）、添加模型 sheet、编辑模型 sheet。

## 3. APIEndpointEditorViewModel

```swift
@Observable
@MainActor
final class APIEndpointEditorViewModel {
    var name = ""
    var baseURL = ""
    var apiKey = ""
    var isDefault = false
    private(set) var testResult: TestResult?

    // 模型列表拉取状态
    var models: [EndpointModelRecord] = []
    var fetchedAPIModels: [ModelObject] = []
    private(set) var isFetchingModels = false
    private(set) var modelFetchError: String?

    // 添加模型 sheet
    var isShowingAddModel = false
    var newModelId = ""
    var newModelMaxContext = AppConstants.defaultMaxContextTokens
    var newModelApiMode: APIMode = .chatCompletions

    // 编辑模型 sheet
    var isShowingEditModel = false
    var editingModel: EndpointModelRecord?
    var editModelMaxContext = AppConstants.defaultMaxContextTokens
    var editModelApiMode: APIMode = .chatCompletions

    let editingEndpoint: APIEndpointRecord?

    var isValid: Bool  // name 非空，baseURL 可解析为 URL
    var isAddModelValid: Bool

    func save() async throws -> APIEndpointRecord
    func testConnection() async
    func loadModels() async
    func scheduleFetchModels()       // 0.5s debounce 后触发 fetchAndMergeModels
    func fetchAndMergeModels() async // GET {baseURL}/models 并写入 endpoint_model
    func addManualModel() async
    func deleteModel(_ id: String) async
    func setDefaultModel(_ id: String) async
    func beginEditingModel(_ model: EndpointModelRecord)
    func saveEditedModel() async
}
```

> **实现证据**: `APIEndpointEditorViewModel.swift`

## 4. 模型列表拉取

编辑器打开时自动向 `{baseURL}/models` 发送 GET 请求拉取可用模型：

- `baseURL` 或 `apiKey` 变化时 debounce 0.5s 后重新拉取。
- 成功：`APIClient.fetchModels(baseURL:apiKey:)` 解码 `ModelObject`，再由 `DatabaseManager.upsertFetchedModels(endpointId:models:)` 合并到 `endpoint_model`。
- `context_length` 或 vLLM 风格 `max_model_len` 会写入 `maxContextTokens`。
- 已标记 `isManual == true` 的模型视为本地维护记录；后续拉取同名模型时不会覆盖用户手动设置的 `maxContextTokens` / `apiMode`。
- 失败或列表为空：已保存端点会确保至少有一个 `"default"` 占位模型。
- 加载中：列表区域显示 `ProgressView`。

## 5. 模型添加与编辑

- 添加模型：用户填写模型名称、最大上下文 Token、API 模式；保存为 `EndpointModelRecord(isManual: true)`。
- 编辑模型：通过已有模型行的长按菜单进入；模型名称只读，允许修改最大上下文 Token 与 API 模式。
- 编辑保存后将该模型标记为 `isManual: true`，表示用户已进行本地覆盖，避免不可靠的模型拉取再次覆盖上下文窗口。
- 删除模型后如果端点没有任何模型，自动插入 `"default"` 占位模型。

> **实现证据（2026-04-29）**:
> - `APIEndpointEditorView.swift` — `.contextMenu` 新增 `Edit Model`，并提供 `editModelSheet`。
> - `APIEndpointEditorViewModel.swift` — `beginEditingModel(_:)` 预填编辑状态，`saveEditedModel()` 更新 `maxContextTokens` / `apiMode` 并设置 `isManual = true`。
> - `EndpointModelTests.swift` — 覆盖编辑保存与 `upsertFetchedModels` 不覆盖本地手动上下文。

## 6. 连接测试

连接测试使用当前默认模型（没有默认模型时使用首个模型或 `"default"` 占位），构造 `APIEndpointConfig` 后发送最小 `maxTokens: 1` 请求。请求会根据模型记录中的 `apiMode` 自动分发到 Chat Completions 或 Responses。

## 7. 安全考虑

- API Key 存储在 SQLite 数据库的 `api_endpoint.apiKey` 字段
- iOS App Sandbox 提供文件级保护
- 未来可考虑迁移到 Keychain（当前版本暂不实现，因为本地模型场景下 API Key 通常为空或无需保密）

## 实现证据（2026-04-29）

- `APIEndpointEditorView.swift` — 端点基本信息 + 可用模型列表 Section（刷新/手动添加/编辑模型/设为默认/滑动删除）
- `APIEndpointEditorViewModel.swift` — 端点字段（name, baseURL, apiKey, isDefault）+ 模型列表管理（fetchAndMergeModels, addManualModel, beginEditingModel, saveEditedModel, deleteModel, setDefaultModel）
- `APIEndpointRecord.swift` — 仅含 name/baseURL/apiKey/isDefault（已移除 modelName/maxContextTokens/apiMode）
- `EndpointModelRecord.swift` — 端点模型记录（modelId, maxContextTokens, apiMode, isDefault, isManual）
- `DatabaseManager+EndpointModels.swift` — 模型 CRUD + upsertFetchedModels（保留 isManual 本地覆盖）+ ensureDefaultModel
- 数据库迁移 `v8_endpoint_model_decoupling` — 创建 endpoint_model 表，迁移数据，conversation 新增 modelName 列
- `ChatSettingsSheet.swift` — 对话设置中新增 Model Picker（端点切换时刷新模型列表）
- `ChatViewModel.swift` — selectedModelName 状态 + loadModelsForEndpoint + 保存 conversation.modelName
- 全量 136 个 Swift Testing 测试通过（2026-04-29）：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17'`
