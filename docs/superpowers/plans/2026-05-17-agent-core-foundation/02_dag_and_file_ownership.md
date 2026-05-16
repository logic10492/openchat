# 02. DAG 与文件归属

## 阶段 DAG

```text
S0 propagation audit
  -> A1 identity / capability / policy types
  -> A2 task / context / result types
  -> B1 diagnostics / schema / tool usage types
  -> B2 deterministic executor + typed errors
  -> B3 focused AgentCore tests
  -> C1 consumer readiness docs
  -> Lead closeout
```

可并行窗口：

- A1 和 A2 可以连续由同一实现者完成，避免 policy / task 类型震荡。
- B1 可在 A1 后开始；B2 需要 A2 和 B1。
- B3 应跟随 B2，不提前写只测结构体初始化的弱测试。
- C1 可与 B3 并行写文档，但不能把未实现的 BackgroundWorker 写成已完成。

不在本 DAG 内：

- `Core/Background`、`BackgroundWorker`、`BackgroundPacket`。
- `MemoryBackgroundSource` / `WorldBookBackgroundSource`。
- `PromptAssembler` 切到 `BackgroundPacket`。
- Director / LibMan runtime。

## 文件归属

| 阶段 | 主要文件 | 测试文件 | 文档写回 |
|---|---|---|---|
| S0 | docs only | 无 | `00_propagation_audit.md` |
| A1 | `OpenChat/Core/AgentCore/AgentDescriptor.swift`, `AgentCapability.swift`, `AgentPolicy.swift`, `ToolUsePolicy.swift`, `SideEffectPolicy.swift` | `AgentDescriptorTests.swift`, `AgentPolicyTests.swift` | `arch/modules/agent-core.md` |
| A2 | `AgentTask.swift`, `AgentExecutionContext.swift`, `AgentExecutionResult.swift` | `AgentExecutionContextTests.swift` 或合并进 executor tests | `arch/modules/agent-core.md` |
| B1 | `AgentDiagnostics.swift`, `SchemaValidation.swift` | `AgentDiagnosticsTests.swift` | `arch/modules/agent-core.md` |
| B2 | `AgentExecutor.swift`, `DeterministicAgentExecutor.swift`, `AgentError.swift` | `DeterministicAgentExecutorTests.swift` | `arch/modules/background/background-worker.md` |
| C1 | docs only | 无 | `PLANING.md`, Background / Stage docs |
| Lead | `OpenChat.xcodeproj/project.pbxproj` only if generated | focused / full suite | harness evidence if implementation proceeds |

## Project generation rule

新增 Swift 文件后，如果 `xcodebuild` 不能发现测试或编译目标，应运行：

```bash
ruby scripts/generate_xcodeproj.rb
```

约束：

- 不手工修改 `PRODUCT_BUNDLE_IDENTIFIER`、`DEVELOPMENT_TEAM`、`CODE_SIGN_STYLE`。
- `project.pbxproj` 的变更必须来自 generator。
- 如果 generator 产生无关签名漂移，停止并单独审计，不继续叠加业务修改。

## 后续 Background 文件归属预告

AgentCore 完成后，下一个计划包应先新增 Memory / WorldBook read-only source tool 或等价 adapter-readiness 文件，例如：

```text
OpenChat/Core/Memory/
  MemoryRecallTool.swift

OpenChat/Core/WorldBook/
  WorldBookRecallTool.swift
```

该计划包只包装现有 `MemoryManager.recallMemories(...)` / `WorldBookSource.recallEntries(...)` result，不复制排序/融合逻辑，不切 Chat prompt。

完成 source tool 暴露后，后续 Background 计划包才允许新增：

```text
OpenChat/Core/Background/
  BackgroundRequest.swift
  BackgroundCandidate.swift
  BackgroundPacket.swift
  BackgroundSource.swift
  BackgroundWorker.swift
  BackgroundDiagnostics.swift
  BackgroundManager.swift
  BackgroundAssembler.swift
```

并传播到：

```text
OpenChat/App/DependencyContainer.swift
OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift
OpenChat/Core/PromptEngine/PromptAssembler.swift
OpenChat/Core/Memory/...
OpenChat/Core/WorldBook/...
```

这些文件不属于当前 AgentCore 第一阶段修改范围；其中 Chat / Prompt runtime switch 更不属于 source tool 暴露计划包。
