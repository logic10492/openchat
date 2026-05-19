# 07. New Thread Handoff

## 新 thread 入口

你要执行的是 OpenChat 顶层路线 Phase 6：Director / 导演模式 foundation。

工作目录：

```text
/Volumes/SN550-Work/workspace/openchat
```

计划包：

```text
docs/superpowers/plans/2026-05-19-director-mode-foundation/
```

## 第一件事

运行：

```bash
git status --short --branch
```

然后读取：

- `AGENTS.md`
- 本计划包 `README.md` 到 `07_new_thread_handoff.md`
- `PLANING.md`
- `arch/modules/stage/index.md`
- `arch/modules/stage/director.md`
- `arch/modules/stage/prompt-flow.md`
- `arch/modules/stage/migration-plan.md`
- `OpenChat/Core/AgentCore/AgentDescriptor.swift`
- `OpenChat/Core/AgentCore/AgentPolicy.swift`
- `OpenChatTests/Core/AgentCoreTests/AgentPolicyTests.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`

## 执行边界

如果用户只要求 Phase 6 Director：

- 只实现 Director contract types、mode policy boundary 和 contract tests。
- 不新增 DB migration。
- 不改 Chat UI。
- 不改 InputBar UI。
- 不改 production PromptAssembler request shape。
- 不接 DirectorPlan 到当前 Chat 主链路。
- 不实现多角色输出。

如果用户要求继续 Phase 7/8/9/10：

- Phase 7 才处理 Stage participant / speaker / visibility DTO。
- Phase 8 才处理 Stage 基础落地和最小 UI 入口。
- Phase 9 才处理用户导演输入 UI 和持久化路径。
- Phase 10 才处理多角色 Stage 输出和 speaker metadata。

## 当前重要事实

- `AgentKind.director` 已存在。
- `AgentPolicy.directorDefault(allowsLLM:)` 已存在，但只是 policy profile。
- Director runtime / executor 尚未实现。
- Stage DB/UI 尚未实现。
- 当前 Chat 仍是单主角色生产链路。
- Background Phase 5/6 已完成 packet-compatible prompt switch，但这不是 Stage / Director runtime。
- 用户导演输入“不作为普通角色台词保存”在 Phase 6 是 contract / test boundary，不是 UI 已落地。

## 失败时怎么处理

- 如果 tests 暴露 baseline failure，记录到 harness，不要削弱测试。
- 如果需要 DB migration、Chat UI、Stage UI、Prompt production shape、multi-speaker parser、LibMan、Exa、network tool 或 database write，停止并请求用户确认。
- 如果新增 Swift 文件未进入 Xcode target，按项目规则运行 `ruby scripts/generate_xcodeproj.rb`，并检查签名配置没有漂移。

## 完成定义

- 执行者能从本文件直接恢复上下文。
- Phase 6 的顺序、边界、测试、写回面足够明确。
- 没有把 Stage / Director runtime 误写成已实现。

## Closeout 写回

实施完成后至少更新：

- `arch/modules/stage/director.md`
- `arch/modules/stage/prompt-flow.md`
- `arch/modules/stage/migration-plan.md`
- `PLANING.md`
- `arch/AntiEntropy/propagation-audit.md`
- `arch/AntiEntropy/triangle-consistency.md`
- `harness/<date>/director-mode-foundation/index.md`
- `harness/<date>/director-mode-foundation/evidence.txt`
