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

## Phase 1：Background DTO 和 deterministic worker

目标：

- 新增 `Core/Background` DTO。
- 不引入 LLM worker。
- 把现有 memory/worldbook retrieval 结果包成 `BackgroundCandidate`。
- `BackgroundWorker` 用确定性策略输出 `BackgroundPacket`。

验证：

- 给定 candidates，输出顺序稳定。
- budget 裁剪稳定。
- diagnostics 记录 omitted reason。

## Phase 2：Memory recall ordering 验收与 Background 接入

目标：

- 复用 2026-05-14 已关闭的 `PromptAssembler.trim(memories:)` importance 重排修复。
- 让 MemorySource 的 candidate order 保持 semantic relevance。
- importance 只做 tie-breaker。

验证：

- 已有 Phase A 回归测试证明高 importance 低 relevance 不会在 `PromptAssembler` 裁剪阶段挤掉高 relevance 记忆。
- Background 接入时继续要求 MemorySource candidate order 保持 semantic relevance。

## Phase 3：世界书向量化

目标：

- 新增 `world_book_entry_embedding`。
- WorldBookSource 同时支持 keyword 和 semantic candidates。
- entry 创建/更新/删除时维护 embedding 或 rebuild 标记。

验证：

- disabled entries 不返回。
- keyword-only / semantic-only / hybrid 排序稳定。
- 当前角色绑定世界书范围隔离。

## Phase 4：PromptAssembler 切换到 BackgroundPacket

目标：

- PromptAssembler 不再分别接收 worldBookEntries + memories 作为直接注入来源。
- Chat 链路调用 `BackgroundManager.prepare(...)`。
- `BackgroundAssembler` 生成 `[Background]` block。

兼容：

- 可先保持原 `[World Book Entries]` 和 `[Memories]` 文本格式，但来源从 packet 来。
- 再逐步统一为 `[Background]`。

## Phase 5：LibMan

目标：

- 新增素材构建入口。
- 使用 Exa structured output 生成 `LibrarianDraft`。
- 用户确认后写入角色卡/世界书。
- 写入世界书后触发 embedding rebuild。

验证：

- 无确认不写 DB。
- draft 带 citations。
- Exa 失败不影响主聊天。

## Phase 6：低频 synthesis

目标：

- 可选引入低频 reflect / observation synthesis。
- 产物必须带 `based_on` ids。
- 默认不进入每轮聊天。

验证：

- synthesis 不覆盖原始记忆。
- 无 source ids 的 synthesis 不允许保存为长期事实。
