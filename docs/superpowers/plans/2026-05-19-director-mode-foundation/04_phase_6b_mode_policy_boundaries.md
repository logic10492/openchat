# 04. Phase 6B - Mode / Policy Boundaries

## 目标

锁定 `silent`、`agent`、`userControlled` 三种 Director mode 的行为 contract，并复用 AgentCore policy 边界。

## silent

语义：

- 不主动运行 Director agent。
- 不生成主动 stage instruction。
- 不改变 speaker plan。
- 可以保留用户显式导演指令，但不主动解释场景。

测试：

- silent plan 可以为空。
- silent mode 不要求 LLM capability。
- silent mode 不要求 network / DB write。

## agent

语义：

- Director 可以是 deterministic。
- 可选 LLM-assisted，但必须使用 `AgentPolicy.directorDefault(allowsLLM: true)` 或等价策略。
- 输出只能是 `DirectorPlan`。
- 不替角色写台词。
- 不把 diagnostics 写入聊天消息。

Policy 红线：

- 不允许 `.webSearch`。
- 不允许 `.databaseWrite`。
- 不允许 network tools。
- 不允许 persistent write。
- 不允许把 draft 暴露成 assistant reply。

当前已有证据：

- `AgentPolicy.directorDefault(allowsLLM:)` 已禁止 web / database write。
- `AgentPolicyTests.test_directorDefault_canOptionallyAllowLLM_butNeverWebOrDatabaseWrite` 已覆盖基础边界。

Phase 6 可追加测试：

- LLM director 允许 `.llm` 但仍 `toolUsePolicy.allowNetwork == false`。
- deterministic director 不含 `.llm`。
- director policy `confirmationPolicy.requiredForPersistentWrite == true`。

## userControlled

语义：

- 用户本轮输入被解释为 stage instruction。
- 默认不作为普通 user-to-character message。
- 是否让角色听见指令必须是显式选项。
- Phase 6 不实现输入栏 UI；只建立 contract。

测试：

- `StageInputRole.director` 可编码。
- director instruction 默认 visibility 不是 visible-to-character。
- 从 director input 生成的 instruction 不产生 `ChatMessage(role: "user")`。

如果没有 helper 可以测试最后一条，则在 Phase 6 closeout 中标记为 contract-only，等 Phase 9 UI/persistence 落地时补端到端测试。

## 与 AgentCore 的关系

Director 可以复用：

- `AgentKind.director`
- `AgentPolicy.directorDefault(allowsLLM:)`
- `AgentDiagnostics`
- future `AgentExecutor`

但 Phase 6 不要求实现 Director executor。Director runtime 可在后续小阶段落地；那时必须验证 policy denial、schema repair 和 timeout behavior。

## 完成定义

- 三种 mode 的 contract 有测试或明确 documented boundary。
- `agent` mode policy 不比当前 `directorDefault` 更宽。
- `userControlled` 不被当作普通角色台词。
- 没有 web / network / DB write 能力扩张。
