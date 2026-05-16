# LibMan / 图书管理员

> 状态：目标架构规划，尚未实现。AgentCore foundation source 已存在；LibMan runtime / Exa tool broker 尚未实现。
> 依赖规划：`arch/modules/exa.md` 中的 Exa web search 能力。

LibMan 是素材构建 agent，不是聊天 agent。它帮助用户查资料、整理引用、生成角色卡和世界书草稿，但不参与主 RP 回复。

实现上，LibMan 应复用 `AgentCore`：显式启用 `llm`、`webSearch`、`userVisibleDraft` capability；数据库写入仍必须由用户确认流程触发，不由 LibMan 静默执行。

2026-05-17 closeout：`OpenChat/Core/AgentCore/AgentPolicy.swift` 已提供 `AgentPolicy.librarianDraftDefault()`，允许 `llm` / `webSearch` / `userVisibleDraft`，tool policy 限定 `exa`，并要求 draft apply / persistent write confirmation。AgentCore focused tests 12 tests / 4 suites passed，full suite 303 tests / 58 suites passed。该实现只证明 AgentCore policy profile 已可用，不代表 LibMan、Exa broker 或写入流程已实现。

## 1. 职责

LibMan 可以：

- 使用 Exa 搜索公开网页。
- 根据用户目标整理角色卡草稿。
- 根据资料生成世界书条目草稿。
- 给出 source citations 和 grounding。
- 标记不确定、冲突或来源不足的内容。
- 把结果交给用户审阅确认。

LibMan 不可以：

- 直接进入主聊天生成链路。
- 静默写入角色卡或世界书。
- 无引用地声称来自某个作品或资料源。
- 替用户决定角色设定的最终版本。
- 每轮 RP 对话都联网搜索。
- 绕过 AgentCore policy 临时扩大 tool / DB 权限。

## 2. 与 Exa 的关系

`arch/modules/exa.md` 记录 Exa `/search` 能力，适合 LibMan 的素材构建任务：

- `deep` / `deep-lite`：构建角色设定、世界背景、作品资料整理。
- `outputSchema`：直接产出结构化 draft。
- `highlights`：控制 token 成本。
- `output.grounding`：保留字段级 citations。

LibMan 不应把 Exa 原始结果直接塞进 prompt；它应产出可审阅 draft。

## 3. 输出 contract

```swift
struct LibrarianDraft: Sendable {
    let characterPatch: CharacterCardPatch?
    let worldBookEntries: [WorldBookEntryDraft]
    let citations: [SourceCitation]
    let warnings: [String]
}

struct CharacterCardPatch: Sendable {
    let name: String?
    let personality: String?
    let appearance: String?
    let physique: String?
    let speechStyle: String?
    let backstory: String?
    let scenario: String?
    let exampleDialogs: [ChatMessage]
    let tags: [String]
    let creatorNotes: String?
}

struct WorldBookEntryDraft: Sendable {
    let title: String
    let keywords: [String]
    let content: String
    let priority: Int
    let citations: [SourceCitation]
}
```

## 4. 用户确认流程

```text
User request
  -> LibMan search plan
  -> Exa search
  -> structured draft + citations
  -> user preview
  -> user edits/accepts
  -> write CharacterCardRecord / WorldBookEntryRecord
  -> enqueue world book embedding rebuild
```

确认前，所有输出都是 draft。

## 5. UI 入口建议

- CharacterCard editor：`用图书管理员补全角色`
- WorldBook editor：`用图书管理员生成条目`
- Import flow：`从网页资料整理世界书`

UI 应明确展示：

- 使用了哪些来源。
- 哪些字段来自资料，哪些是模型补写。
- 哪些内容需要用户确认。

## 6. 安全与版权边界

- 避免长篇复制来源文本。
- 世界书条目应是摘要化、重写后的设定笔记。
- 引用只保留 URL/title/highlight 级别证据。
- 对同人/版权作品，应偏向“用户私用资料整理”，不要生成可发布的伪官方文档。

## 7. 与 BackgroundWorker 的边界

| 项目 | LibMan | BackgroundWorker |
|---|---|---|
| 是否可联网 | 可以，通过 Exa | 不可以 |
| 是否参与每轮聊天 | 不参与 | 参与，但只整理背景 |
| 是否输出用户可见文本 | 输出草稿 | 默认不输出，只返回 packet |
| 是否写数据库 | 用户确认后写 | 不写 |
| 是否能生成新设定 | 可生成草稿 | 不生成新事实 |
| AgentCore capability | `llm` / `webSearch` / `userVisibleDraft`，确认后才进入写入流程 | 第一阶段仅 `deterministic` |
