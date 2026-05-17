# OpenChat Planning

> 更新时间：2026-05-17
> 状态：规划入口 + 当前执行状态。本文记录目标架构、已完成计划包和下一步落地顺序；未标记完成的阶段不代表当前源码已实现。

## 1. 当前重点

OpenChat 下一阶段的重点有两条主线：

1. 把角色扮演所需的背景上下文从“各模块分别注入 prompt”升级为“统一 Background 调度”。
2. 把单角色 Chat 扩展为支持多角色共同参与的 Stage。

当前执行顺序已经调整：

```text
Memory Hindsight-lite repair
  -> WorldBook vectorization
  -> AgentCore foundation contract
  -> Memory / WorldBook read-only source tools
  -> BackgroundSource adapters / Core Background DTO
  -> deterministic BackgroundWorker
  -> Prompt switches to BackgroundPacket
  -> LibMan
  -> low-frequency reflect
  -> Director
  -> multi-character scene
  -> Stage
  -> UI automation baseline
```

2026-05-17 状态：

- Memory Hindsight-lite A/B/C/D 与 Lead closeout 已完成并通过 full suite。
- WorldBook vectorization A/B/C/D 与 closeout 已完成并通过 full suite。WorldBook 已具备 embedding、semantic recall、trace、候选管理和 CRUD/import/delete/rebuild 维护能力。
- AgentCore foundation 已完成：`OpenChat/Core/AgentCore/` 与 `OpenChatTests/Core/AgentCoreTests/` 已进入 Xcode target；AgentCore focused 12 tests / 4 suites、主链路 focused 50 tests / 4 suites、full suite 303 tests / 58 suites 均通过。
- 当前工作区已落地 Memory / WorldBook read-only source tools、BackgroundSource adapters、`Core/Background` DTO、deterministic `BackgroundWorker`、`BackgroundManager`、`BackgroundPacket` 与 Chat/Prompt 到 packet-aware 路径的兼容切换。
- 当前工作区验证结果：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` 通过 330 tests / 65 suites；`xcodebuild build` 通过；模拟器安装与 `fukujusou.openchat.com` 启动 smoke 通过。
- 当前缺口：项目尚无独立 `OpenChatUITests` target；现有 E2E 只到 build/install/launch smoke，尚未自动点击用户路径。
- 当前下一步建议先进入 LibMan / reflect / Director / 多角色同场 / Stage，Stage 基线落地后再建立 UI 自动化 baseline。
- LibMan、Stage、Director、多角色同场仍是后续阶段。

```text
WorldBook + Memory + Character State + Conversation State
  -> source tools / source adapters
  -> BackgroundSource candidates
  -> BackgroundWorker / 后台员工
  -> BackgroundPacket
  -> BackgroundAssembler
  -> Main Chat Model
```

核心边界：

- 对话角色不是 agent，而是 persona。
- 角色回复第一阶段保持自然流式文本；动作感由模型自然输出和 UI 轻量适配处理，不给普通角色回复开放 tool call，也不把角色纳入 AgentCore runtime。
- 动作/台词拆分、标签化输出、JSON/schema 输出和 streaming parser 先挂起；当前重点继续做 AgentCore，不在本阶段处理角色输出适配。
- AgentCore 是后台 agent/worker 的共享运行时基座，暴露 identity、capability/policy、task/result、diagnostics、executor、tool/side-effect boundary。
- Memory / WorldBook 的 tool 暴露指内部 read-only source tool，不是普通角色 tool call，也不是用户可见工具栏。
- BackgroundWorker / 后台员工无权直接输出，只能返回要注入的 background 条目。
- LibMan / 图书管理员可以用 Exa 搜索构建素材，但不参与实时 RP 输出。
- Stage 可以有导演 agent，但导演也不替角色发言。
- Prompt 文本最终由确定性 assembler 生成，不能让后台 worker 自由发言。

## 2. 角色不是 Agent

原则：

> 对话角色不是 agent，而是由角色卡、关系状态、长期记忆、世界背景和当前会话状态共同渲染出的 persona。

角色不 agent 化的原因：

- 角色的核心价值是稳定扮演，不是自主完成任务。
- 主聊天模型已经负责角色回复，再包装 `CharacterAgent` 不会自然增加能力。
- agent 化会引入工具权、目标、任务队列和自治行为，容易破坏 RP 沉浸感。
- “血肉感”应来自可维护状态，而不是角色拥有后台权限。

参考文档：

- `arch/modules/background/role-boundary.md`

## 3. BackgroundWorker / 后台员工

职责：

- 汇总 Memory / WorldBook / Character / ConversationState 候选。
- 选择、排序、去重、冲突标记和预算裁剪。
- 返回 `BackgroundPacket`。
- 记录 diagnostics，供调试或详细统计使用。
- 作为 `AgentCore` 的受限 consumer，第一阶段只启用 deterministic capability。

禁止：

- 生成 assistant 回复。
- 改写用户输入。
- 静默修改角色卡、世界书或记忆。
- 直接拼接最终 prompt 文本。
- 调用 Exa 或其他 web search。

接入前置条件：

- `MemoryRecallTool` / `WorldBookRecallTool` 或等价内部 source tool contract 先完成，并保持 read-only。
- Memory tool 只包装 `MemoryManager.recallMemories(...)` / `MemoryRecallResult`，不复制 Memory 层排序、fallback 或 trace 逻辑。
- WorldBook tool 只包装 `WorldBookSource.recallEntries(...)` / `WorldBookRecallResult`；索引维护仍由既有 lifecycle / rebuild 入口负责，不让 BackgroundWorker 通过 tool 触发写库 side effect。
- BackgroundWorker 后续只消费 `BackgroundCandidate`，不能绕过 tool/source boundary 直接重排 Memory 或 WorldBook 的内部候选。

参考文档：

- `arch/modules/agent-core.md`
- `arch/modules/background/index.md`
- `arch/modules/background/architecture.md`
- `arch/modules/background/background-worker.md`
- `arch/modules/background/sources.md`
- `docs/superpowers/plans/2026-05-17-agent-core-foundation/README.md`

## 4. Memory 与 WorldBook source tool / BackgroundSource

目标：

- `MemoryRecallTool` 负责把现有 Memory recall result 暴露给后台调度层。
- `WorldBookRecallTool` 负责把现有 WorldBook recall result 暴露给后台调度层。
- `MemoryBackgroundSource` 负责长期记忆候选。
- `WorldBookBackgroundSource` 负责世界书候选。
- BackgroundSource adapter 读取 tool result，输出 `BackgroundCandidate`，再由 BackgroundWorker 统一调度。
- Memory 和 WorldBook 不再分别拥有最终 prompt 注入权。

当前状态：

- 当前 Memory 已完成 Hindsight-lite 修复：`MemoryManager` 能输出 `MemoryRecallResult` / `MemoryRecallTrace`，fallback 改为 semantic / keyword / recent high-value 分层，retain v2 已有 provenance / dedupe metadata。
- `MemoryRecallTool` 与 `MemoryBackgroundSource` 已在当前工作区消费 Memory recall result，并把 selected memory candidates 交给 Background worker / packet 路径。
- 当前 WorldBook 已完成 keyword + semantic 融合召回：`WorldBookSource` 输出 recall result / trace，Chat 主链路会先执行 bounded rebuild，再把 selected entries 传给 `PromptAssembler`。
- `WorldBookRecallTool` 与 `WorldBookBackgroundSource` 已在当前工作区消费 WorldBook recall result，并把 selected world-book candidates 交给 Background worker / packet 路径。
- `ChatViewModel` 当前主链路为 bounded world-book rebuild -> `BackgroundManager.prepare(...)` -> `PromptAssembler.preview(... backgroundPacket:)` -> `ContextManager.prepareHistory(...)` -> `PromptAssembler.assemble(... backgroundPacket:)`。
- 旧 direct overload 保留为兼容 / rollback path；最终 prompt 文本仍保持 `[World Book Entries]` 与 `[Memories]` block 名称，来源改为 `BackgroundPacket` selected entries。
- CharacterState / ConversationState source 尚未实现，仍是后续阶段。

参考文档：

- `arch/modules/memory/index.md`
- `arch/modules/memory/hindsight-lite.md`
- `arch/modules/world-book.md`
- `arch/modules/background/sources.md`

## 5. 世界书向量化（已完成）

> 当前状态：已完成，是 BackgroundWorker 的已完成前置工作。

已完成目标：

- 为 `world_book_entry` 建立 embedding 索引。
- 让世界书支持 keyword + semantic 双路召回。
- 让 BackgroundWorker 能公平比较世界书候选和记忆候选。
- 让 WorldBook 像 Memory 一样由专门 Core 层管理：embedding、索引重建、召回结果、trace、禁用过滤和 CRUD/import/delete 同步维护。

已落地 schema：

```text
world_book_entry_embedding
  entry_id TEXT PRIMARY KEY
  embedding float[384]

world_book_entry_embedding_meta
  entryId TEXT PRIMARY KEY
  contentHash TEXT
  embeddedAt DATETIME
  embeddingModel TEXT
```

参考文档：

- `arch/modules/background/world-book-vectorization.md`
- `arch/modules/world-book.md`
- `docs/superpowers/plans/2026-05-16-world-book-vectorization/README.md`
- `harness/2026.05.16/world-book-vectorization/index.md`

本阶段先建立 WorldBook 的向量检索能力和可测试管理边界。当前工作区后续 Background 计划包已开始消费这些能力，但仍保留 `[World Book Entries]` 兼容 block 名称。

## 6. LibMan / 图书管理员

LibMan 是素材构建 agent，不是聊天 agent。

职责：

- 使用 Exa 搜索公开资料。
- 帮用户生成角色卡草稿。
- 帮用户生成世界书条目草稿。
- 保留 citations / grounding。
- 交给用户审阅确认后再写数据库。

边界：

- LibMan 可以联网；BackgroundWorker 不联网。
- LibMan 输出 draft；主聊天模型输出角色回复。
- LibMan 不参与实时 RP prompt。
- Exa 搜索失败不影响主聊天。
- 未经用户确认，LibMan 不静默写入角色卡或世界书。

参考文档：

- `arch/modules/background/lib-man.md`
- `arch/modules/exa.md`

## 7. Stage / 多角色舞台

Stage 是 Chat 的目标扩展形态。

目标：

- 一个 Stage 可以绑定多个角色卡。
- 多个角色可以在同一场景中共同参与。
- Stage 拥有 Director / 导演。
- 导演有三种工作模式：
  - `silent` / 闭嘴：导演不主动介入。
  - `agent` / agent 模式：导演后台调度场景、节奏、发言顺序和冲突提示。
  - `userControlled` / 用户接管模式：用户以导演身份直接发出舞台指令。
- 不论当前模式如何，用户都可以临时以导演角色说话。

边界：

- 角色仍不是 agent。
- 导演不替角色写最终台词。
- 导演输出是 `DirectorPlan` / stage instructions，不是 assistant message。
- 用户导演输入不应被保存为角色听到的普通台词，除非用户显式要求。

参考文档：

- `arch/modules/stage/index.md`
- `arch/modules/stage/director.md`
- `arch/modules/stage/multi-character.md`
- `arch/modules/stage/prompt-flow.md`
- `arch/modules/stage/migration-plan.md`

## 8. Hindsight-lite 关系

Hindsight-lite 不应替代 Background，而应成为 Background 的一部分：

- retain：Memory 继续负责长期记忆抽取与持久化；source range / provenance / dedupe metadata 已在 Hindsight-lite Phase C 落地。
- recall：Memory 已能输出有序 `MemoryRecallResult` / `MemoryRecallTrace`；进入 Background 前仍保持旧兼容 API 供 Chat 使用。
- reflect：Phase D 已落地最小 `MemoryReflectRequest` / `MemoryReflectObservation` contract；reflect LLM executor、UI 入口和 `memory_entry_link` 持久化仍是后续独立计划。

已完成顺序：

1. 修复 Memory recall ordering，避免 `importance` 覆盖语义相关性。
2. 增加 `MemoryRecallTrace`，记录 distance、fallback reason、selected ids 和 omitted ids。
3. 将 recent fallback 改为 keyword + recent high-value 分层 fallback。
4. 增加 source range / provenance / dedupe metadata。
5. 验收当前 Responses API 下 `[Memories]` folding 后的 request shape。
6. 建立低频 reflect 的最小 DTO contract。

仍未做：

- 将 Memory 输出包装成 `BackgroundCandidate`。
- 实现 reflect LLM executor / UI 入口 / `memory_entry_link` migration。

参考文档：

- `arch/modules/memory/hindsight-lite.md`
- `arch/AntiEntropy/problem.md`
- `docs/superpowers/plans/2026-05-14-memory-hindsight-lite-repair/README.md`

## 9. 建议落地顺序

### Phase 0：规划固化（已完成）

- 保持 `arch/modules/background/*` 为目标架构文档。
- 明确 Background / LibMan / Stage 内容尚未实现。
- 后续修改源码前先更新对应计划或 issue。

### Phase 1：Memory Hindsight-lite repair（已完成）

- Phase A：Memory prompt trim 保持 retrieval order，不再被 `importance` 重排覆盖。
- Phase B：新增 `MemoryRecallResult` / `MemoryRecallTrace`，fallback 改为 semantic / keyword / recent high-value tiers。
- Phase C：追加 `memory_entry_provenance`，升级 extraction prompt v2，补 source boundary、dedupe、atomic provenance 写入。
- Phase D：新增 reflect 最小 contract，验收 Responses API `[Memories]` request shape。
- Lead closeout：focused tests 与 full suite 已通过；full suite 记录为 251 tests / 46 suites passed。

### Phase 2：世界书向量化（已完成）

- 已追加 `world_book_entry_embedding` 与 `world_book_entry_embedding_meta`。
- 已建立 `Core/WorldBook` 管理层：`WorldBookVectorStore`、`WorldBookEmbeddingIndexer`、`WorldBookRecallModels`、`WorldBookSource`。
- `WorldBookSource` 已支持 keyword + semantic 融合召回，并输出 recall result / trace。
- CRUD / import / delete / eraseAllData 已维护 vector/meta；Data Management 已提供手动 rebuild。
- 仍保持当前 prompt 输出兼容：semantic 结果继续进入 `[World Book Entries]`，尚未提前切 BackgroundWorker。
- Closeout full suite：291 tests / 54 suites passed。

### Phase 3：AgentCore foundation + source tool exposure + Background worker（当前大阶段）

#### Phase 3a：AgentCore foundation contract（已完成）

- 已落地 `Core/AgentCore` 基座 contract：identity、capability/policy、task/result、diagnostics、executor、tool/side-effect boundary。
- 已落地 focused tests：descriptor、policy profile、deterministic executor、diagnostics。
- Closeout：AgentCore focused 12 tests / 4 suites passed；主链路 regression focused 50 tests / 4 suites passed；full suite 303 tests / 58 suites passed。
- 不接入 Chat / Prompt / Memory / WorldBook / Database / Networking / UI runtime。

#### Phase 3b：Memory / WorldBook read-only source tool 暴露（当前工作区已完成）

- 为 Memory 暴露内部 source tool contract，包装 `MemoryManager.recallMemories(...)` 与 `MemoryRecallResult` / trace。
- 为 WorldBook 暴露内部 source tool contract，包装 `WorldBookSource.recallEntries(...)` 与 `WorldBookRecallResult` / trace。
- tool 输出必须结构化、read-only、可诊断；不拼 prompt、不写 DB、不调用网络、不生成 assistant message。
- 该 tool 暴露只服务后续 BackgroundSource / 后台 worker，不给普通角色回复开放 tool call。
- 已补 focused tests 覆盖 source tool / adapter 的候选映射、顺序、metadata 与 read-only 边界。

#### Phase 3c：Background DTO + deterministic worker（当前工作区已完成）

- 新增 `Core/Background` DTO。
- 用确定性规则实现 BackgroundWorker。
- 通过 Phase 3b 的 source tool / adapter 包装已完成的 Memory recall result 与完成向量化后的 WorldBook candidates。
- 不让 BackgroundWorker 直接拼最终 prompt 或调用网络。
- 已落 Core 层闭环与 tests；`BackgroundWorker` 输出 `BackgroundPacket`，diagnostics 不进入 prompt 文本。
- 不处理角色回复动作/台词结构化，也不引入普通角色 tool call；标签化输出相对 JSON 更适合未来流式文本，但需要单独设计 streaming adapter 后再决定。

### Phase 4：Prompt 切换到 BackgroundPacket（当前工作区已完成）

- Chat 链路调用 `BackgroundManager.prepare(...)`。
- `PromptAssembler` 消费 Background packet/block。
- `[World Book Entries]` + `[Memories]` 兼容 block 的直接来源已切到 `BackgroundPacket` selected entries。
- 验证：focused Background / Prompt / Chat tests 已覆盖 packet-aware 路径；当前 full suite 330 tests / 65 suites passed。

### Phase 5：LibMan

- 接入 Exa search。
- 产出 `LibrarianDraft`。
- 用户确认后写入 CharacterCard / WorldBook。
- 写入世界书后触发 embedding rebuild。

### Phase 6：低频 reflect / observation synthesis

- 只在手动整理或后台低频任务中运行。
- 产物必须带 `basedOn` source ids。
- 不直接替代原始记忆。

### Phase 7：Director / 导演模式

- 建立 `DirectorPlan` / director policy / stage instruction 的最小 contract。
- 导演可以调度场景、节奏、发言顺序和冲突提示，但不替角色写最终台词。
- 支持 `silent`、`agent`、`userControlled` 三种导演模式的 contract 与测试边界。
- 用户导演输入不应被保存为角色听到的普通台词，除非用户显式要求。

### Phase 8：多角色同场基础

- 定义 Stage participant / speaker / visibility / stage action 等基础 DTO。
- Stage 可绑定多个角色卡，并保留每个角色的身份、世界书、关系和可见性边界。
- 第一阶段只选择本轮主 speaker，不做多角色连续输出。
- 多角色同场必须在 Stage UI/数据结构正式落地前先完成 contract 与测试边界。

### Phase 9：Stage 基础落地

- 新增 Stage / participant / director DTO。
- 接入 Stage 数据模型和最小 UI 入口。
- 建立导演模式和用户导演输入的测试边界。

### Phase 10：用户导演输入

- 输入栏支持“作为用户说话 / 作为导演说话”。
- 导演输入进入 stage instruction。
- 任意导演模式下用户都能临时接管。

### Phase 11：多角色 Stage 输出

- Stage 绑定多个角色。
- Director/default policy 选择本轮主 speaker。
- 第一阶段只输出一个角色回复，后续再扩展多角色连续输出。

### Phase 12：UI 自动化 baseline

目标：

- 增加独立 `OpenChatUITests` target，用 XCUITest 覆盖真实用户路径。
- 保持 `OpenChatTests` 负责逻辑 / 数据库 / Prompt / 网络解析；`OpenChatUITests` 只验证 UI 接线、导航和关键工作流是否可走通。
- 所有 UI 测试必须不依赖真实网络、不依赖用户真实数据、不写生产数据库。

实施要点：

- 修改 `scripts/generate_xcodeproj.rb`，由脚本生成 `OpenChatUITests` target，避免手改 Xcode 工程后被重新生成覆盖。
- 为关键 View 增加稳定 `accessibilityIdentifier`，例如 sidebar 新建会话、chat input、send button、settings/add endpoint、endpoint editor fields、character/world-book 创建入口。
- 在 App 启动路径增加 `--ui-testing` / `--mock-api` 等启动参数，UI 测试模式下使用临时数据库、`InMemoryAPIKeyStore` 和可预测 seed data。
- 增加 mock API seam，让 UI 测试中的发送消息流程返回固定 assistant response，不访问真实 OpenAI-compatible endpoint。
- 第一批只覆盖最短关键路径：启动 -> 新建会话 -> 发送消息 -> mock assistant response 可见；设置页新增 endpoint；角色卡 / 世界书创建后可在 Chat 设置中选择。
- Stage 基线落地后，补充 Stage 创建、导演模式切换、多角色 participant 选择等 UI smoke。
- 第二批再覆盖破坏性操作与错误路径：重命名 / 删除会话、保存失败可见、endpoint 连接失败提示、memory extraction indicator 不阻塞发送。

验收命令：

```bash
xcodebuild test \
  -project OpenChat.xcodeproj \
  -scheme OpenChat \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:OpenChatUITests
```

完成标准：

- `OpenChatUITests` target 由生成脚本稳定生成。
- UI test 不访问真实网络，测试数据可重复。
- 至少 3 条 smoke 级用户路径稳定通过。
- full suite 仍通过，且 build/install/launch smoke 不回退。

## 10. 当前已知未完成

- `OpenChatUITests` target 尚未实现；UI/E2E 自动化仍只有 build/install/launch smoke。
- UI testing mode、mock API seam、seed data、稳定 accessibility identifiers 尚未实现。
- CharacterState / ConversationState source 尚未实现。
- LibMan 尚未实现。
- Stage 系统尚未实现。
- Director agent / 导演模式尚未实现。
- 多角色同场参与尚未实现。
- reflect LLM executor / UI 入口 / `memory_entry_link` 持久化尚未实现。
- Background diagnostics 已有 DTO / tests，尚未进入用户可见调试界面。
- 本地化资源仍有缺口，需要补齐 `Localizable.xcstrings` 中缺失的 UI 文案 key。
- 多个 Swift 文件超过 300 行规范，后续可按风险逐步拆分。
- 角色动作/台词拆分、标签化输出、JSON/schema 输出和 streaming parser 尚未设计；当前只保留自然流式文本 + UI 轻量适配。
