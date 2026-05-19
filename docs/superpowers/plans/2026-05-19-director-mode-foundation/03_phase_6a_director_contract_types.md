# 03. Phase 6A - Director Contract Types

## 目标

落地 Director 模式的最小 DTO contract，为后续 Stage / Prompt / UI 做边界准备。

本阶段不实现 Director executor，不接 Chat 主链路，不写 DB。

## 建议 source

优先新增 Core 层目录，具体命名在实施前再按 source-tree 审计确认：

```text
OpenChat/Core/Stage/DirectorMode.swift
OpenChat/Core/Stage/StageInstruction.swift
OpenChat/Core/Stage/DirectorPlan.swift
OpenChat/Core/Stage/DirectorDiagnostics.swift
```

如果项目决定用 `Core/Director/`，必须在计划执行前同步更新 file ownership，避免 Core 目录漂移。

## Contract 要求

### DirectorMode

- `silent`
- `agent`
- `userControlled`

要求：

- raw values 稳定。
- `Codable` / `Sendable` / `CaseIterable`。
- 不用 localized display string 作为 raw value。

### StageInputRole

- `participant`
- `director`

要求：

- 只是输入语义，不等于 message role。
- `director` 不应被映射为 `MessageRecord.role == "user"` 的普通角色台词。

### StageInstruction

建议字段：

- stable `id`
- source：user / director agent / system default
- content
- visibility：hiddenFromCharacters / visibleToParticipants / debugOnly
- createdAt

要求：

- 空 content 不合法。
- visibility 默认不让角色听见用户导演指令，除非显式选择。
- 不携带 DB write command。

### SpeakerTurn

建议字段：

- participantId 或 characterCardId optional hint
- intent：respondToUser / react / advanceScene / remainSilent
- maxTokens optional

要求：

- Phase 6 只是 hint，不实现多角色输出。
- 没有 participant storage 时，不要求 resolved participant id。

### DirectorPlan

建议字段：

- mode
- stageInstructions
- speakerPlan
- diagnostics

要求：

- 空 plan 合法，尤其 silent mode。
- 不含 assistant text。
- 不含 API request messages。
- 不含 persistence operation。

## 测试要求

新增 focused tests：

```text
OpenChatTests/Core/StageTests/DirectorContractTests.swift
```

覆盖：

- mode raw values。
- Codable round trip。
- empty silent plan 合法。
- non-empty instruction 需要 content。
- director input role 不等于 chat message role。
- DirectorPlan 不暴露 assistant text 字段。

## 完成定义

- Contract types 编译通过并进入 Xcode target。
- Focused tests 覆盖 DTO shape。
- 没有 DB migration。
- 没有 Chat / Prompt / UI 改动。
- docs 更新为“Director contract 已落地；runtime 未落地”。
