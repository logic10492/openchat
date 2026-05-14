# OpenChat 代码库质量评估与改进计划（单文件版）

本文件是计划包的压缩摘要。详细任务拆分请看 `openchat_quality_plan_package.zip`。

# 00. 总览：质量结论与优先级

## 一句话结论

OpenChat 不是“玩具项目”。它已经具备较清晰的四层目录、GRDB 迁移体系、OpenAI 兼容网络层、SSE 流式解析、Prompt 四层组装、上下文压缩 checkpoint、角色记忆/向量检索、以及数量可观的核心测试。整体质量属于 **中上水平、可以继续迭代**。

但它距离可放心长期使用/发布还有明显差距。最需要优先处理的不是模型能力，而是：**API Key 安全存储、错误处理可靠性、流式生成取消与部分结果落库、数据库一致性、分层漂移、导入导出未完成、CI/资源测试策略、Prompt 注入边界**。

## 审查范围与证据口径

- 解压目录：`/mnt/data/openchat_repo/openchat`。
- 生产 Swift 文件：106 个，约 9,189 行。
- 测试 Swift 文件：31 个，约 5,067 行。
- Swift Testing `@Test` 静态计数：197 个。
- 本环境没有 Xcode/iOS Simulator，无法实际运行 `xcodebuild`；因此“构建通过/测试通过”只可引用仓库文档记录，不作为本次复验结论。
- 嵌入模型权重缺失按用户说明视为正常，不记为代码缺陷。

## 评分卡

| 维度 | 评分 | 评价 |
|---|---:|---|
| 架构清晰度 | 8.0/10 | 目录、文档、模块意图清楚；已有反熵文档记录分层问题。 |
| 代码组织 | 7.5/10 | 文件大小总体可控，Core/Feature 分离较好；少数 ViewModel 和 View 过重。 |
| 核心业务实现 | 7.5/10 | Chat、Prompt、Context、Memory、Networking 主链路完整。 |
| 测试基础 | 7.0/10 | 核心测试数量可观；UI、Feature 保存流、导入导出、架构边界测试不足。 |
| 安全与隐私 | 4.0/10 | API Key 明文 SQLite；缺 Keychain、隐私清单、文件保护和错误脱敏。 |
| 错误处理/可观测性 | 5.5/10 | 部分错误会展示；但大量 `try?`、空 `catch`、启动 fallback 掩盖问题。 |
| 产品完成度 | 5.5/10 | 核心可用，但导入导出、头像、示例对话编辑、完整数据备份未完成。 |
| 可维护性 | 7.0/10 | 文档和迁移纪律较好；需要自动化边界测试与格式/ lint 工具。 |
| CI/工程流程 | 4.5/10 | 未见 CI workflow、SwiftLint/SwiftFormat 配置；资源依赖测试需拆分。 |
| AI/RP 特化能力 | 7.0/10 | 角色卡、世界书、记忆、时间感知已成型；Prompt 防注入和 lorebook 细节不足。 |

## 最优先处理的 10 个事项

1. **API Key 从 SQLite 明文迁到 Keychain**，UI 改为 `SecureField`，数据库只保留 Keychain 引用或 endpoint id。
2. **移除保存链路中的 `try?` 和空 `catch`**，失败时不应直接 dismiss，应展示错误并保留编辑状态。
3. **修复流式生成生命周期**：取消时明确“保留部分回复/丢弃部分回复”；落库策略要一致；使用 `defer` 清理状态。
4. **`eraseAllData` 显式清理 `memory_embedding` 虚拟表**，避免 sqlite-vec 向量孤儿数据。
5. **资源依赖测试分层**：模型权重缺失时，Embedding 相关测试应 skip 或使用 mock，不影响普通 CI。
6. **执行已有分层修复计划**：Core 不读 App 常量，Feature 不持有 AppState，Shared 不调用 Core。
7. **追加数据库唯一性约束/一致性迁移**：默认 endpoint/model、message sortOrder 等用 DB 约束兜底。
8. **完成全量导入导出**：当前 Settings 里导入导出直接抛“未接线”，需要产品化闭环。
9. **网络层增加超时、重试、错误截断/脱敏**，并增强 Responses API 事件兼容。
10. **Prompt 数据块加边界和防注入指令**，尤其是世界书、记忆、角色卡用户可编辑字段。

## 推荐推进顺序

| 阶段 | 目标 | 预期产物 |
|---|---|---|
| Sprint 0 | 建立可复现基线 | 本地/CI 构建脚本、资源缺失 mock/skip、已知限制文档。 |
| Sprint 1 | P0 可靠性与安全热修 | Keychain、错误展示、取消生成、向量清理、测试 gating。 |
| Sprint 2 | 架构边界修复 | 分层源码扫描测试、App shell 迁移、AppState 解耦、Core 常量迁移。 |
| Sprint 3 | 数据闭环与一致性 | 导入导出、唯一索引迁移、数据校验/修复、备份恢复测试。 |
| Sprint 4 | AI/RP 体验增强 | Prompt 防注入、世界书解析升级、记忆游标、Token 预算校准。 |
| Sprint 5 | 产品化 | UI 测试、性能监控、隐私清单、崩溃/日志策略、可发布检查。 |


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


# 03. 改进路线图

## 优先级定义

| 优先级 | 含义 |
|---|---|
| P0 | 影响数据安全、用户信任、主链路正确性；应立即修复。 |
| P1 | 影响长期可维护性和产品闭环；应在下一个主版本前修复。 |
| P2 | 增强体验、鲁棒性和 AI/RP 质量；可排入稳定迭代。 |
| P3 | 高级能力和精细化优化；在基础稳定后推进。 |

## P0：立即修复

1. API Key Keychain 化。
2. 保存/导入/模型操作错误不再吞掉。
3. 流式生成取消/失败后的 UI 与 DB 状态一致。
4. `eraseAllData` 显式清理 `memory_embedding`。
5. Embedding 资源缺失时测试不阻断普通 CI。
6. live 容器启动失败不再静默切 preview/in-memory。

## P1：核心工程化

1. 执行分层漂移修复。
2. 增加源码边界测试。
3. 数据库唯一索引与一致性迁移。
4. 完成全量导入导出。
5. 记忆提取游标改为 message sortOrder/state table。
6. 网络超时、重试、错误截断/脱敏。
7. 添加 CI workflow 和格式/lint 基线。

## P2：AI/RP 体验增强

1. Prompt 数据块边界与防注入。
2. Token 预算校准和 per-model 安全余量。
3. 世界书解析升级：front matter、YAML/JSON、priority clamp、错误预览。
4. 角色卡示例对话编辑器。
5. 头像选择与资源管理。
6. 记忆管理 UI：查看、禁用、删除、纠错。

## P3：高级 RP 能力

1. 分支对话/消息树。
2. lorebook 高级触发：regex、depth、constant、probability、recursive。
3. 回复风格 profile：文风、篇幅、NSFW/安全边界、第一/第三人称等。
4. 角色关系状态机：好感、情绪、长期目标。
5. 多模型策略：本地模型草稿 + 云端模型润色/压缩。

## 分阶段计划

### Sprint 0：建立可复现基线（1–2 天）

**目标**：先确保任何改动都可以被稳定验证。

**任务**

- 明确模型权重缺失时的测试策略：mock/skip/集成测试标签。
- 添加 `scripts/test.sh` 或 Makefile，统一运行 project generation、build、tests。
- 添加 `KNOWN_LIMITATIONS.md`：记录模型权重、导入导出未接线、Keychain 未完成等已知状态。
- 检查 `ruby scripts/generate_xcodeproj.rb` 后工程文件是否稳定。

**验收**

- 无模型权重时，普通单元测试可运行。
- 有模型权重时，可额外运行真实 embedding 集成测试。
- 构建/测试命令文档化。

### Sprint 1：可靠性与安全热修（3–5 天）

**目标**：先修最容易损害用户信任的问题。

**任务**

- API Key 迁移到 Keychain。
- APIEndpoint 编辑 UI 改 `SecureField`。
- 所有保存按钮去掉 `try?`，失败时展示错误。
- stream cancel 策略落地：保留部分回复并落库，或确认后丢弃。
- `eraseAllData` 与删除角色/记忆时清理 vector rows。
- live 容器失败显示错误页，不切 preview。

**验收**

- 数据库导出不含 API Key 明文。
- 保存失败不会关闭编辑页。
- 取消生成后刷新应用，聊天内容与用户看到的一致。
- 清空数据后 memory_entry 和 memory_embedding 都为空。

### Sprint 2：架构边界修复（5–7 天）

**目标**：把文档中的分层规则变成源码事实。

**任务**

- Core 使用的默认值迁移到 Core/Shared config 或通过 DI 注入。
- ChatViewModel 不再持有 AppState，改注入闭包/协议。
- `Features/Support/SidebarView.swift` 移入 App shell。
- WorldBook 不直接构造 CharacterCard UI，改 route/coordinator。
- `String+Token.swift` 移出 Shared 或删除。
- 添加源码扫描测试。

**验收**

- 边界测试通过。
- `arch/AntiEntropy/layering-repair-plan.md` 状态更新为 closed 或记录受控例外。

### Sprint 3：数据闭环与一致性（5–8 天）

**目标**：让用户数据可备份、可恢复、可迁移。

**任务**

- 追加 v13 migration：默认项 unique index、message sortOrder unique index、记忆提取 state table。
- 实现版本化导出 snapshot。
- 实现导入 dry-run：校验、冲突预览、资源缺失提示。
- JSON TEXT 字段保存前校验，读取失败记录错误。
- 添加导入导出 round-trip tests。

**验收**

- 导出 → 删除数据 → 导入后，角色卡/世界书/endpoint metadata/对话/消息/记忆一致。
- 冲突导入可选择跳过、覆盖或生成新 ID。
- 坏 JSON 输入不会静默变空。

### Sprint 4：AI/RP 质量增强（5–8 天）

**目标**：提升长期 RP 的稳定、沉浸和可控性。

**任务**

- Prompt 数据块边界和防注入指令。
- 预算内单项截断/摘要。
- per-model token budget safety margin。
- 世界书导入解析升级。
- 记忆质量 UI：禁用/删除/纠错/手动添加。
- 记忆提取游标用 message sortOrder。

**验收**

- Prompt 单元测试覆盖四层顺序、防注入边界、oversized block 截断。
- 世界书导入失败有错误列表，而不是部分静默失败。
- 记忆提取不会在“无新记忆”时重复处理同一段消息。

### Sprint 5：产品化与发布准备（持续）

**目标**：从“开发可用”升级为“长期可维护”。

**任务**

- 添加隐私清单 `.xcprivacy`。
- 数据库文件保护属性。
- UI 测试/snapshot tests。
- 日志脱敏与诊断导出。
- 性能基准：大世界书、长对话、大量记忆。
- App Store/分发前检查。

**验收**

- 敏感信息不会进入日志/错误弹窗/导出包。
- 大型 RP 数据集下 prompt 组装和检索性能可接受。
