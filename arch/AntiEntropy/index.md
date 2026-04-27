# AntiEntropy

> 更新时间：2026-04-27
> 目的：把源码传播风险、架构文档、测试证据和当前实现现实放在同一处，作为后续修复和验收的反熵入口。

## 本次结论入口

| 部分 | 文件 | 结论摘要 |
|---|---|---|
| propagation-audit | [propagation-audit.md](propagation-audit.md) | 当前静态图无 Swift import 级循环阻断；Chat 当前输入重复注入、Prompt 时间/顺序、migration 源码约束已完成修复写回，剩余主要风险集中在分层边界漂移。 |
| Triangle-Consistency | [triangle-consistency.md](triangle-consistency.md) | `src-test` 当前审计工作区通过 133 tests；Prompt 时间格式、记忆/世界书顺序、数据库迁移约束、测试数量与覆盖范围已回写，Feature 分层漂移留待单独修复计划。 |
| layering-repair-plan | [layering-repair-plan.md](layering-repair-plan.md) | 记录 Feature/App/Shared/Core 分层漂移的独立修复顺序、验证标准与文档回写要求。 |

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
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17'
```

结果：`xcodebuild test` 成功，当前审计工作区 Swift Testing `133 tests in 28 suites passed`，结尾为 `** TEST SUCCEEDED **`。该计数包含审计开始前已有未提交 networking 测试改动。
