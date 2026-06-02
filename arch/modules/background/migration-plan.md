# Background 迁移计划

> 状态：已实现到 Phase 6 compatible switch，并已追加 CharacterState / ConversationState sources、SkillReference source、Stage context filter、LibMan offline draft runtime 和 idle reflect draft worker。统一 `[Background]` block、Exa ToolBroker、LibMan apply UI、自动 synthesis 写入和 duplicate/conflict review 尚未实现。

## Phase 0：文档和边界

目标：

- 明确角色不是 agent。
- 明确 BackgroundWorker 无发言权。
- 明确 LibMan 是素材构建 agent，不参与 RP 输出。
- 明确 Phase 0 的历史基线曾是 Memory/WorldBook 直接注入；当前 Phase 6 后已切到 `BackgroundPacket` 兼容注入。

产物：

- `arch/modules/background/*`
- `arch/modules/memory/*` 增加 BackgroundSource 关联说明。
- `arch/modules/world-book.md` 增加向量化和 Background 目标说明。
- `arch/modules/exa.md` 增加 LibMan 使用边界。

## Phase 1：Memory recall ordering 验收（已完成）

目标：

- 复用 2026-05-14 已关闭的 `PromptAssembler.trim(memories:)` importance 重排修复。
- 让 Memory recall order 保持 semantic relevance。
- importance 只做 tie-breaker。
- 让 `MemoryRecallResult` / trace 成为 source tool 可包装的稳定输出。

验证：

- 已有 Phase A 回归测试证明高 importance 低 relevance 不会在 `PromptAssembler` 裁剪阶段挤掉高 relevance 记忆。
- 当前 Background 接入后继续要求 `MemoryBackgroundSource` candidate order 保持 semantic relevance。

当前状态：

- 已完成；当前 Chat 主链路通过 `MemoryRecallTool -> MemoryBackgroundSource -> BackgroundWorker -> BackgroundPacket -> PromptAssembler(... backgroundPacket:)` 注入兼容 `[Memories]`。`MemoryManager.retrieveMemories(...)` 仍保留为 direct compatibility path。

## Phase 2：世界书向量化（已完成）

目标：

- 新增 `world_book_entry_embedding`。
- WorldBookSource 同时支持 keyword 和 semantic candidates。
- entry 创建/更新/删除时维护 embedding 或 rebuild 标记。
- 让 `WorldBookRecallResult` / trace 成为 source tool 可包装的稳定输出。

验证：

- disabled entries 不返回。
- keyword-only / semantic-only / hybrid 排序稳定。
- 当前角色绑定世界书范围隔离。

当前状态：

- 已完成 Phase A/B/C/D；当前 Chat 主链路通过 `WorldBookRecallTool -> WorldBookBackgroundSource -> BackgroundWorker -> BackgroundPacket -> PromptAssembler(... backgroundPacket:)` 注入兼容 `[World Book Entries]`。`WorldBookSource.recallEntries(...)` 仍是 source adapter 输入和旧兼容路径。

## Phase 3：AgentCore foundation（已完成）

目标：

- 稳定 `Core/AgentCore` 基座 contract：identity、capability/policy、task/result、diagnostics、executor、tool/side-effect boundary。
- 保持零运行时 consumer，不接入 Chat / Prompt / Memory / WorldBook。

验证：

- AgentCore focused tests 覆盖 descriptor、policy profile、deterministic executor 和 diagnostics。
- policy 明确 BackgroundWorker 默认不联网、不写 DB、不生成 assistant message。

当前状态：

- 2026-05-17 AgentCore foundation 已完成；当时 full suite 303 tests / 58 suites passed。Background Source Tools Phase 4A-4D 后当前全局 full-suite 基线为 319 tests / 61 suites passed。

## Phase 4：Memory / WorldBook source tool 暴露

目标：

- 新增内部 read-only source tool contract。
- `MemoryRecallTool` 只包装 `MemoryManager.recallMemories(...)`，输出 `MemoryRecallResult` / trace。
- `WorldBookRecallTool` 只包装 `WorldBookSource.recallEntries(...)`，输出 `WorldBookRecallResult` / trace。
- Phase 4 当时不引入 BackgroundWorker、不切 Chat prompt、不改 `[Memories]` / `[World Book Entries]` 兼容输出；Phase 5/6 已在后续完成 worker / packet / compatible switch。
- 不复制 Memory rank fusion 或 WorldBook keyword+semantic fusion。

验证：

- tool 输出保持 Memory / WorldBook 当前 result 顺序。
- diagnostics / trace metadata 可被 BackgroundSource adapter 消费。
- tool 为 read-only：不写 DB、不联网、不生成 assistant message、不触发 WorldBook indexing side effect。

当前状态：

- 2026-05-17 Phase 4A-4D 已落地，见 `harness/2026.05.17/background-source-tools/index.md`。
- `OpenChat/Core/Background/BackgroundSourceTool.swift` 已定义 source tool / request / candidate 基础 contract，并进入 Xcode target。
- `OpenChat/Core/Memory/MemoryRecallTool.swift` 已实现 read-only wrapper，符合 `BackgroundSourceTool`，只调用 `MemoryManager.recallMemories(...)`。
- `OpenChat/Core/WorldBook/WorldBookRecallTool.swift` 已实现 read-only wrapper，符合 `BackgroundSourceTool`，只调用 `WorldBookSource.recallEntries(...)`。
- `MemoryBackgroundSource.swift` / `WorldBookBackgroundSource.swift` 已进入 Xcode target；`BackgroundSourceTests` 覆盖 candidate 顺序、source prefix、metadata、character/worldBook request 边界和不按 token budget 裁剪。
- Baseline + Phase 4 closeout focused tests 验证了 Memory / WorldBook / Prompt / Chat / AgentCore 前置 contract、recall tool pass-through 和 adapter mapping；Phase 5/6 的 worker / packet / prompt switch 由后续 focused tests 单独证明。

## Phase 5：Background DTO + deterministic worker

目标：

- 新增 `Core/Background` DTO。
- 不引入 LLM worker。
- 通过 Phase 4 source tool / adapter 把现有 memory/worldbook retrieval 结果包成 `BackgroundCandidate`。
- `BackgroundWorker` 作为 AgentCore 受限 consumer，用确定性策略输出 `BackgroundPacket`。

验证：

- 给定 candidates，输出顺序稳定。
- budget 裁剪稳定。
- diagnostics 记录 omitted reason。
- AgentCore policy 明确 BackgroundWorker 不联网、不写 DB、不生成 assistant message。

当前状态：

- 已完成。`BackgroundPolicy.swift`、`BackgroundPacket.swift`、`BackgroundDiagnostics.swift`、`BackgroundWorker.swift` 已进入 target。
- `BackgroundWorkerTests` / `BackgroundPacketTests` / `BackgroundDiagnosticsTests` 覆盖 default policy、DTO identity、deterministic selection、duplicate/budget/per-source omission、policy denial 和 diagnostics。
- Phase 5 没有让 worker 读写 DB、联网、调用 LLM、触发 worldBook rebuild 或生成 assistant message。

## Phase 6：PromptAssembler 切换到 BackgroundPacket

目标：

- PromptAssembler 主链路不再分别接收 worldBookEntries + memories 作为直接注入来源。
- Chat 链路调用 `BackgroundManager.prepare(...)`。
- `BackgroundAssembler` 生成兼容 prompt block。

兼容：

- 可先保持原 `[World Book Entries]` 和 `[Memories]` 文本格式，但来源从 packet 来。
- 再逐步统一为 `[Background]`。

当前状态：

- 已完成 compatible switch。`BackgroundManager.swift` 组合 source adapters 与 worker，`BackgroundAssembler.swift` 把 packet entries 分组为 worldBook / memory prompt items。
- `PromptAssembler.swift` 新增 packet-aware preview/assemble overload，仍保留旧 direct overload；当前输出保持 `[World Book Entries]` 在前、`[Memories]` 在后。
- `ChatViewModel+Support.swift` 主链路调用 `BackgroundManager.prepare(...)`，并由 packet-aware PromptAssembler 生成 request body。
- bounded worldBook rebuild 仍保留在 ChatViewModel pre-source stage；`BackgroundWorker` 与 `WorldBookBackgroundSource` 不触发 rebuild。
- worldBook source failure 的兼容 keyword fallback 在 manager 中生成 `.worldBook` fallback candidates，避免切换后静默丢失世界书背景。
- `ChatViewModelPromptAssemblyTests` 覆盖 request body 使用 packet selected entries、current input 不重复、semantic-only worldBook entry 仍进入兼容 block、semantic failure keyword fallback 仍生效。

## Phase 6.5：Skill references source（已完成）

目标：

- 为角色 skill bundle 提供第一版本地只读工具实现，不进入公网 web search。
- 从当前角色绑定 bundle 的 `content/references/**/*.md` 做轻量关键词检索。
- 输出 `.skillReference` candidates，经 `BackgroundWorker` 统一排序 / 限流 / diagnostics 后作为 `[Skill Reference]` 背景材料进入 prompt。
- 继续保持普通角色回复不是 AgentCore runtime；该 source 是应用预检索工具，不是模型可自由调用的 Chat Completions / Responses tool loop。

验证：

- 有绑定 bundle 时可搜索 references markdown，保留 relativePath、matchedTerms、score、trace metadata。
- 无绑定 bundle 或空查询时返回空结果，不抛错。
- `BackgroundAssembler` 能把 `.skillReference` entry 注入当前轮背景 block。

当前状态：

- `OpenChat/Core/SkillBundles/SkillReferenceSearchTool.swift`、`SkillReferenceBackgroundSource` 已进入 target。
- `OpenChat/App/DependencyContainer.swift` 已将 `SkillReferenceBackgroundSource` 加入生产 `BackgroundManager`。
- `OpenChatTests/Core/SkillBundleTests/SkillReferenceSearchToolTests.swift` 和 `PromptAssemblerTests` 覆盖 tool、source candidate mapping 和 prompt block。

## Phase 7：LibMan

目标：

- 新增素材构建入口。
- 当前第一版使用 LLM + 用户提供 source materials 生成 `LibrarianDraft`，不联网。
- 目标架构再接 Exa structured output。
- 用户确认后写入角色卡/世界书的 apply UI 仍是后续范围。
- 写入世界书后触发 embedding rebuild。

验证：

- 无确认不写 DB。
- draft 带 citations。
- 当前 offline draft parser 拒绝无 citations 输出。
- 后续 Exa 失败不影响主聊天。

当前状态：

- 已完成 offline draft runtime：`LibrarianDraftTask` / `LibrarianDraftExecutor` 通过 `LLMAgentExecutor` 生成用户可见草稿，policy 为 read-only、需要 confirmation，不写数据库。
- 已有 `LibrarianDraftTaskTests` 覆盖 cited draft、API request shape、无 DB write 和无 citation reject。
- 未实现：Exa ToolBroker / web search、UI preview/apply flow、confirmed write 和 world book embedding rebuild enqueue。

## Phase 8：低频 synthesis

目标：

- 可选引入低频 reflect / observation synthesis draft。
- 产物必须带 `based_on` ids。
- 默认不进入每轮聊天，不静默写库。

验证：

- synthesis 不覆盖原始记忆。
- 无 source ids 的 synthesis 不允许保存为长期事实。

当前状态：

- 已完成 draft-only idle worker：`MemoryReflectBackgroundWorker.prepareIdleDraft(...)` 从 recent high-value memories 生成 `MemoryReflectObservation` draft，并受 minimum memories / interval / running guard 限制。
- `ChatViewModel.triggerMemoryExtraction()` 后会尝试低频 draft 准备，但当前不会自动 apply / write memory。
- `MemoryReflectBackgroundWorkerTests` 覆盖 draft produced without DB write 和 insufficient memories skip。
- 未实现：duplicate/conflict review UI、自动合并 / 删除 / 覆盖策略、后台任务持久队列。
