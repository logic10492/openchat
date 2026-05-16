# OpenChat AgentCore 基座开发计划包

> 生成日期：2026-05-17
> 范围：按 `arch/modules/agent-core.md` 落地 `Core/AgentCore` 基础 contract，并在实现前完成传播审计，确定第一阶段允许修改的代码块。
> 状态：已执行完成；AgentCore foundation source / focused tests / Xcode project membership / closeout tests 均已验证。

## 范围边界

本计划包只处理 AgentCore 基座，不切换主聊天链路：

- 新增 `OpenChat/Core/AgentCore/` foundation types。
- 新增 `OpenChatTests/Core/AgentCoreTests/` focused tests。
- 建立后台 agent / worker 共享的 identity、capability / policy、task / result、diagnostics、executor、tool / side-effect boundary。
- 明确 BackgroundWorker、Director、LibMan 三类首批 consumer 的 policy profile 和传播边界。
- 保持角色回复仍由主聊天模型自然流式输出，不引入 `PersonaRender` runtime、角色 tool call、强制 JSON / tagged schema 或 streaming parser。

不纳入本计划包：

- 不实现 `Core/Background`、`BackgroundWorker`、`BackgroundPacket`。
- 不把 Memory / WorldBook 包装成 `BackgroundSource`。
- 不修改 `ChatViewModel.generateResponse(...)` 主链路。
- 不修改 `PromptAssembler` 的 `[Memories]` / `[World Book Entries]` 兼容输出。
- 不实现 Director / LibMan / Exa tool broker。
- 不新增数据库 migration。

## 源码基线结论

2026-05-17 执行结果：

- `OpenChat/Core/AgentCore/` 已出现 AgentCore foundation Swift 文件，覆盖 identity、capability / policy、task / result、diagnostics、deterministic executor、tool / side-effect boundary 和 typed error。
- `OpenChatTests/Core/AgentCoreTests/` 已出现 descriptor、policy、deterministic executor、diagnostics focused tests。
- `ruby scripts/generate_xcodeproj.rb` 已把新增 AgentCore source/test 加入 Xcode target；`OpenChat.xcodeproj/xcshareddata/xcschemes/OpenChat.xcscheme` 的 target UUID 随 generator 更新，签名配置仍来自脚本。
- AgentCore focused tests：12 tests / 4 suites passed。
- 主链路 regression focused tests：50 tests / 4 suites passed。
- Full suite：303 tests / 58 suites passed。
- BackgroundWorker、Director、LibMan、Exa tool broker、`Core/Background`、Chat / Prompt runtime switch 仍未实现。

当前主聊天路径仍是：

```text
ChatViewModel.generateResponse
  -> MemoryManager.retrieveMemories / WorldBookSource.recallEntries
  -> PromptAssembler.preview / assemble
  -> ContextManager.prepareHistory
  -> APIClient.streamMessage
```

AgentCore 第一阶段不应接入这条路径。第一阶段应该是零运行时 consumer 的 Core contract + tests；下一计划包应先做 Memory / WorldBook read-only source tool 暴露与传播审计。只有 source tool / adapter 边界稳定后，才进入 `Core/Background` DTO / BackgroundWorker，并允许继续传播到 `DependencyContainer`、`ChatViewModel+Support`、`PromptAssembler`、Memory / WorldBook source adapters。

## 阅读顺序

1. `00_propagation_audit.md`：实现前传播审计，列出允许修改和禁止修改的代码块。
2. `01_target_architecture.md`：AgentCore 目标 contract 和 consumer policy profile。
3. `02_dag_and_file_ownership.md`：阶段 DAG、并行边界和文件归属。
4. `03_phase_a_contract_types.md`：identity / capability / policy / task / result 类型落地计划。
5. `04_phase_b_executor_diagnostics.md`：deterministic executor、diagnostics、typed error 和 tests。
6. `05_phase_c_consumer_readiness.md`：BackgroundWorker / Director / LibMan 后续接入前置条件。
7. `06_testing_acceptance.md`：focused tests、full suite、文档写回和完成定义。

## 推荐执行顺序

```text
S0 propagation audit + baseline read
  -> A AgentCore contract types
  -> B deterministic executor + diagnostics
  -> C consumer readiness docs / arch sync
  -> Lead closeout: project generation check + focused tests + full suite if source changed
```

## 基线命令

OpenChat 是 Xcode project，不是 Swift Package：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests'
```

如果 simulator 名称不可用，先运行：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

AgentCore 源码实施后，新增 Swift 文件需要进入 Xcode project。若 project 未自动包含新文件，应运行：

```bash
ruby scripts/generate_xcodeproj.rb
```

该脚本会重建 `OpenChat.xcodeproj`，签名配置必须保持来自脚本中的既有值，不手工改签名。
