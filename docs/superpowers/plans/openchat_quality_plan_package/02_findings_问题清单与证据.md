# 02. 问题清单与源码证据

> 说明：以下证据采用 `文件:行号`。行号基于本次解压后的源码快照。

## F-01：API Key 明文存储，安全风险高

**证据**

- `OpenChat/Core/Database/Migrations.swift:221-227`：`api_endpoint` 表创建 `apiKey` TEXT 字段。
- `OpenChat/Core/Database/Records/APIEndpointRecord.swift:7-10`：`APIEndpointRecord` 直接持有 `apiKey: String?`。
- `OpenChat/Features/Settings/Views/APIEndpointEditorView.swift:15-20`：API Key 使用普通 `TextField`。
- `arch/modules/settings/api-endpoint.md` 文档中也将 API Key 存 SQLite 作为当前行为。

**影响**

本地数据库被备份、导出、崩溃采样、越权读取或误分享时，API Key 会泄漏。普通 TextField 也会增加肩窥和自动填充/输入历史风险。

**建议**

迁移到 Keychain；数据库只保存 key reference 或 endpoint id。UI 使用 `SecureField`，并增加“已保存 key / 替换 key / 清除 key”状态。

---

## F-02：保存失败被吞掉，用户可能误以为保存成功

**证据**

- `OpenChat/Features/Settings/Views/APIEndpointEditorView.swift:52-56`：`_ = try? await viewModel.save(); dismiss()`。
- `OpenChat/Features/CharacterCard/Views/CharacterCardEditorView.swift:48-51`：同类保存后 dismiss 模式。
- `OpenChat/Features/WorldBook/Views/WorldBookEditorView.swift:112-115`、`:130`、`:138-153`：保存和导入过程中多处吞错。
- `OpenChat/Features/Settings/ViewModels/APIEndpointEditorViewModel.swift:217-222`、`:232-244`、`:247-254`、`:277-283`：新增/删除/默认模型/编辑模型时存在静默 catch。

**影响**

数据未保存、导入不完整或模型操作失败时，用户无法及时知道。对 RP 应用来说，角色卡、世界书、API endpoint 都属于高价值配置，静默失败会直接破坏信任。

**建议**

所有保存入口改成：保存中禁用按钮 → 成功后 dismiss → 失败时保留页面并展示错误。ViewModel 暴露 `errorMessage` 或注入 `ErrorPresenter`。

---

## F-03：启动时 live 容器失败会静默切到 preview/in-memory，可能掩盖数据库问题

**证据**

- `OpenChat/OpenChatApp.swift:8-10`：`let container = (try? DependencyContainer.live()) ?? DependencyContainer.preview()`。
- `OpenChat/App/DependencyContainer.swift:36-43`：preview 优先 in-memory，失败再 live，最后 `fatalError`。

**影响**

如果真实数据库打开失败，应用可能进入 preview/in-memory 状态，用户看起来“数据没了”。这是严重的数据信任问题。

**建议**

live 初始化失败时展示启动错误页，提供重试、导出诊断、迁移修复选项。Preview 容器只应在 SwiftUI Preview/测试中使用。

---

## F-04：流式生成取消/失败后部分回复状态不一致

**证据**

- `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift:197-199`：`stopGenerating()` 仅 cancel task。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:145-219`：stream task 中 catch 后 `removeAssistantPlaceholder`，只移除空内容。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:169-183`：只有正常完成时才保存 assistant message。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:237-239`：非空部分内容不会被移除，也不会落库。

**影响**

用户停止生成后，界面可能保留一段 assistant 回复，但刷新后消失；或失败后部分内容不入库。长 RP 对话中这会造成叙事断裂。

**建议**

取消时给出明确策略：默认保留部分回复并标记 `finishReason = cancelled`，或者确认后丢弃。无论策略如何，UI 与数据库必须一致。

---

## F-05：stream task 继承 MainActor，长流式处理可能影响 UI 响应

**证据**

- `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift:5-7`：`ChatViewModel` 是 `@MainActor @Observable`。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:145`：在 MainActor 类型方法中创建 `Task { [weak self] ... }`。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:150-167`：流式循环里更新消息、处理 usage/reasoning。

**影响**

高频 delta、长 reasoning 或 JSON 解码可能把过多工作放在 UI actor。风险不是“必然卡死”，而是扩展后容易出现 UI 抖动。

**建议**

把 streaming orchestration 下沉到 service/actor，在后台处理网络和解析，只把最小 UI delta 通过 `MainActor.run` 合批提交。

---

## F-06：`memory_embedding` 虚拟表无外键，清空数据时可能留下孤儿向量

**证据**

- `OpenChat/Core/Database/Migrations.swift:83-88`：`CREATE VIRTUAL TABLE memory_embedding USING vec0(entry_id TEXT PRIMARY KEY, embedding float[384])`，没有外键。
- `OpenChat/Core/Database/DatabaseManager.swift:42-52`：`eraseAllData` 删除 message/conversation/worldbook/character/endpoints，但没有显式清空 `memory_embedding`。

**影响**

sqlite-vec 虚拟表不会因为 `memory_entry` 删除自动级联。长期使用后可能积累无效向量，影响检索、存储空间和隐私清理完整性。

**建议**

`eraseAllData`、角色卡删除、记忆删除都应通过统一 Memory 删除服务或显式执行向量删除。清空全量数据时优先 `DELETE FROM memory_embedding`。

---

## F-07：默认 endpoint/model 缺少数据库唯一约束

**证据**

- `OpenChat/Core/Database/DatabaseManager+Endpoints.swift` 中保存默认 endpoint 时靠事务更新其他记录。
- `OpenChat/Core/Database/DatabaseManager+EndpointModels.swift` 中保存默认 model 时靠事务更新同 endpoint 其他模型。
- `OpenChat/Core/Database/Migrations.swift` 当前未见 partial unique index 约束。

**影响**

运行时逻辑通常有效，但迁移、并发、多窗口、手工恢复数据库时可能出现多个 default。后续读取“默认项”会不确定。

**建议**

追加 migration：`CREATE UNIQUE INDEX ... WHERE isDefault = 1`。endpoint model 可对 `(endpointId)` 加 partial unique。

---

## F-08：message sortOrder 用 max+1，缺并发兜底

**证据**

- `OpenChat/Core/Database/DatabaseManager+Conversations.swift` 中 `nextSortOrder` 读取 max sortOrder 再 +1。
- `OpenChat/Core/Database/Migrations.swift:301-306` 只有普通 index，未见 `(conversationId, sortOrder)` unique index。

**影响**

单窗口正常，但多窗口、并发重试、后台任务同时写入时可能产生重复 sortOrder。

**建议**

追加唯一索引，并把“取下一个 sortOrder + insert message”放进同一个写事务。

---

## F-09：JSON TEXT 字段解码失败被隐式吞掉

**证据**

- `OpenChat/Core/Database/Records/CharacterCardRecord.swift`：`decodedExampleDialogs`、`decodedTags` 解码失败时回退。
- `OpenChat/Core/Database/Records/WorldBookEntryRecord.swift`：`decodedKeywords` 解码失败回退。
- `OpenChat/Core/Database/Records/RecordCoders.swift`：`try?` encode/decode。

**影响**

坏数据不会暴露，可能导致角色示例、标签、关键词突然为空，用户难以定位原因。

**建议**

保存前强校验，读取时返回 typed error 或记录修复事件；提供 migration/repair 工具修复旧数据。

---

## F-10：全量导入导出未完成

**证据**

- `OpenChat/Features/Settings/ViewModels/SettingsViewModel.swift:83-90`：`exportAllData` / `importData` 直接抛 “not wired yet”。
- `OpenChat/Features/Settings/Views/DataManagementView.swift` 文案显示功能仍待 pipeline 完成。

**影响**

用户的角色卡、世界书、对话和记忆无法可靠备份。对本地 AI/RP 应用，这是产品信任核心。

**建议**

设计版本化 JSON snapshot，支持导出、导入预览、冲突处理、校验、dry-run 和回滚。

---

## F-11：Prompt 预算可被 oversized block 突破

**证据**

- `OpenChat/Core/PromptEngine/PromptAssembler.swift:257-293`：`trim` 对 entries/messages/memories 都允许 `result.isEmpty` 时纳入第一项，即使超过预算。

**影响**

如果角色卡示例、世界书条目或记忆单项极长，仍可能突破上下文预算，造成请求失败或挤压历史。

**建议**

增加 block 内截断/摘要：先按优先级选中，再对单项内容进行 hard cap；必要时标注 `[truncated]`。

---

## F-12：Prompt 注入边界不足

**证据**

- `OpenChat/Core/PromptEngine/PromptAssembler.swift:219-225`：默认 system prompt 直接拼接角色名。
- 世界书、记忆、示例对话作为 labeled system block 注入，但未见“数据块不是指令”的安全边界说明。

**影响**

用户导入的世界书/记忆内容可以包含“忽略之前所有指令”等文本。虽然这是本地 RP 应用，很多内容来自用户自己，但对导入分享卡/世界书尤其有风险。

**建议**

为所有外部/用户可编辑数据块加边界：明确其是设定资料，不可覆盖系统角色、安全规则、输出格式和开发者指令。

---

## F-13：工程自动化缺口

**证据**

- 未发现 `.github/workflows`。
- 未发现 SwiftLint/SwiftFormat 配置。
- `.github/instructions` 只有协作指令，不是 CI。

**影响**

Codex/多人协作时，架构约束、格式、测试容易逐步漂移。

**建议**

添加 CI：生成 xcodeproj、build、unit tests、资源缺失 mock tests、源码边界扫描。添加格式化/lint 规则。

---

## F-14：嵌入模型资源缺失时测试策略需要明确

**证据**

- `.gitmodules:1-3`：`OpenChat/Resources/Models` 指向私有/局域网 Gitea submodule。
- `OpenChatTests/Core/MemoryTests/EmbeddingServiceTests.swift` 依赖 bundle tokenizer/model。

**影响**

压缩包或 CI 没有模型权重时，Embedding 测试可能失败，阻断普通核心测试。

**建议**

把 Embedding 测试分成：mock embedding 单元测试、真实模型集成测试。真实模型测试仅在资源存在或 CI secret/submodule 可用时启用。
