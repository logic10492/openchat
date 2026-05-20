# AntiEntropy

> 更新时间：2026-05-20
> 目的：把源码传播风险、架构文档、测试证据和当前实现现实放在同一处，作为后续修复和验收的反熵入口。

## 本次结论入口

| 部分 | 文件 | 结论摘要 |
|---|---|---|
| propagation-audit | [propagation-audit.md](propagation-audit.md) | 当前静态图无 Swift import 级循环阻断；Chat 当前输入重复注入、Prompt 四层顺序、migration 源码约束已完成修复写回，剩余主要风险集中在分层边界漂移。 |
| Triangle-Consistency | [triangle-consistency.md](triangle-consistency.md) | `src-test` 最新 full scheme 通过：Swift Testing 397 tests / 72 suites，Stage UI XCTest 1 test，`** TEST SUCCEEDED **`。 |
| problem | [problem.md](problem.md) | 记录记忆系统风险与修复状态：提取 cutoff、触发调度、recall ordering、fallback tiers、recall trace、retain v2 provenance 和 dedupe 已关闭；提取 UI 与 retrieval trace debug UI 已部分关闭。 |
| layering-repair-plan | [layering-repair-plan.md](layering-repair-plan.md) | 记录 Feature/App/Shared/Core 分层漂移的独立修复顺序、验证标准与文档回写要求。 |
| memory-vector-reliability | [propagation-audit.md](propagation-audit.md#2026-04-30-memory-vector-reliability-incremental-audit) | Memory embedding/vector/retrieval 可靠性修复已完成增量传播审计；详细证据见 `harness/2026.04.30/memory-vector-reliability/index.md`。 |
| checkpoint-compression | [propagation-audit.md](propagation-audit.md#2026-04-30-checkpoint-compression-incremental-audit) | Codex 风格持久化 compression checkpoint 已完成增量传播审计；详细证据见 `harness/2026.04.30/checkpoint-compression/index.md`。 |
| prompt-four-layer-assembly | [propagation-audit.md](propagation-audit.md#2026-04-30-prompt-four-layer-assembly-incremental-audit) | Prompt 四层拼装已完成增量传播审计；详细证据见 `harness/2026.04.30/prompt-four-layer-assembly/index.md`。 |

## 审计基线

- 审计时间：2026-04-27
- 工作区状态：审计开始前已有未提交改动：
  - `OpenChat/Core/Networking/APIRequest.swift`
  - `OpenChatTests/Core/NetworkingTests/APIClientTests.swift`
  - `OpenChatTests/Core/NetworkingTests/ResponsesAPITests.swift`
  - `OpenChatTests/Core/NetworkingTests/ThinkingFeatureTests.swift`
  - `arch/modules/api-client.md`
  - `.vscode/`
- 本次 AntiEntropy 文档已记录 2026-04-27 修复写回；剩余分层漂移不在本轮源码修复中混入。

## 已执行验证

```bash
xcodebuild -list -project OpenChat.xcodeproj
xcrun simctl list devices available
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

最新 full scheme 结果：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` 在 iOS 26.5 `iPhone 17 Pro` 上成功，Swift Testing `397 tests in 72 suites passed`，随后 `OpenChatUITests/StageUITests` 1 个 XCTest 通过，结尾为 `** TEST SUCCEEDED **`。当前基线已覆盖 API-client、Prompt 四层顺序、Memory embedding/vector/retrieval/extraction-cutoff/recall-trace/fallback-tier/retain-v2-provenance/reflect-contract/idle draft worker、Responses request-shape、checkpoint compression、compression mode、WorldBook Vectorization Phase A/B/C/D、AgentCore foundation、Background source tools / worker / prompt switch / Stage filter、Director contract、LLM Director、multi-speaker parser 和 Stage UI automation baseline tests。
