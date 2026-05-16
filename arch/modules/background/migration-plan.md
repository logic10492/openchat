# Background 迁移计划

> 状态：目标架构规划，尚未实现。

## Phase 0：文档和边界

目标：

- 明确角色不是 agent。
- 明确 BackgroundWorker 无发言权。
- 明确 LibMan 是素材构建 agent，不参与 RP 输出。
- 明确当前实现仍是 Memory/WorldBook 直接注入。

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
- 让 `MemoryRecallResult` / trace 成为后续 source tool 可包装的稳定输出。

验证：

- 已有 Phase A 回归测试证明高 importance 低 relevance 不会在 `PromptAssembler` 裁剪阶段挤掉高 relevance 记忆。
- 后续 Background 接入时继续要求 MemorySource candidate order 保持 semantic relevance。

当前状态：

- 已完成；当前 Chat 兼容链路仍由 `MemoryManager.retrieveMemories(...)` 返回 entries 并注入 `[Memories]`。

## Phase 2：世界书向量化（已完成）

目标：

- 新增 `world_book_entry_embedding`。
- WorldBookSource 同时支持 keyword 和 semantic candidates。
- entry 创建/更新/删除时维护 embedding 或 rebuild 标记。
- 让 `WorldBookRecallResult` / trace 成为后续 source tool 可包装的稳定输出。

验证：

- disabled entries 不返回。
- keyword-only / semantic-only / hybrid 排序稳定。
- 当前角色绑定世界书范围隔离。

当前状态：

- 已完成 Phase A/B/C/D；当前 Chat 兼容链路仍由 `WorldBookSource.recallEntries(...)` 预选 entries 并注入 `[World Book Entries]`。

## Phase 3：AgentCore foundation（已完成）

目标：

- 稳定 `Core/AgentCore` 基座 contract：identity、capability/policy、task/result、diagnostics、executor、tool/side-effect boundary。
- 保持零运行时 consumer，不接入 Chat / Prompt / Memory / WorldBook。

验证：

- AgentCore focused tests 覆盖 descriptor、policy profile、deterministic executor 和 diagnostics。
- policy 明确 BackgroundWorker 默认不联网、不写 DB、不生成 assistant message。

当前状态：

- 2026-05-17 已完成；full suite 303 tests / 58 suites passed。

## Phase 4：Memory / WorldBook source tool 暴露

目标：

- 新增内部 read-only source tool contract。
- `MemoryRecallTool` 只包装 `MemoryManager.recallMemories(...)`，输出 `MemoryRecallResult` / trace。
- `WorldBookRecallTool` 只包装 `WorldBookSource.recallEntries(...)`，输出 `WorldBookRecallResult` / trace。
- 不引入 BackgroundWorker，不切 Chat prompt，不改 `[Memories]` / `[World Book Entries]` 兼容输出。
- 不复制 Memory rank fusion 或 WorldBook keyword+semantic fusion。

验证：

- tool 输出保持 Memory / WorldBook 当前 result 顺序。
- diagnostics / trace metadata 可被后续 BackgroundSource adapter 消费。
- tool 为 read-only：不写 DB、不联网、不生成 assistant message、不触发 WorldBook indexing side effect。

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

## Phase 6：PromptAssembler 切换到 BackgroundPacket

目标：

- PromptAssembler 不再分别接收 worldBookEntries + memories 作为直接注入来源。
- Chat 链路调用 `BackgroundManager.prepare(...)`。
- `BackgroundAssembler` 生成 `[Background]` block。

兼容：

- 可先保持原 `[World Book Entries]` 和 `[Memories]` 文本格式，但来源从 packet 来。
- 再逐步统一为 `[Background]`。

## Phase 7：LibMan

目标：

- 新增素材构建入口。
- 使用 Exa structured output 生成 `LibrarianDraft`。
- 用户确认后写入角色卡/世界书。
- 写入世界书后触发 embedding rebuild。

验证：

- 无确认不写 DB。
- draft 带 citations。
- Exa 失败不影响主聊天。

## Phase 8：低频 synthesis

目标：

- 可选引入低频 reflect / observation synthesis。
- 产物必须带 `based_on` ids。
- 默认不进入每轮聊天。

验证：

- synthesis 不覆盖原始记忆。
- 无 source ids 的 synthesis 不允许保存为长期事实。
