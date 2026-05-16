# 05. Phase C - WorldBookSource 与 Prompt 兼容

## 目标

让世界书召回同时支持 keyword candidates 与 semantic candidates，并在当前 Prompt 输出中继续使用 `[World Book Entries]`。

## C1. Recall Models

新增 `WorldBookRecallModels.swift`：

```swift
struct WorldBookRecallResult: Sendable {
    let entries: [WorldBookRecallEntry]
    let trace: WorldBookRecallTrace
}

struct WorldBookRecallEntry: Sendable {
    let entry: WorldBookEntryRecord
    let finalRank: Int
    let keywordRank: Int?
    let semanticRank: Int?
    let semanticDistance: Float?
    let keywordHits: [String]
    let reasons: [WorldBookRecallReason]
}

enum WorldBookRecallReason: String, Sendable {
    case keyword
    case semantic
}
```

Trace 至少记录：

- query text 摘要。
- keyword candidate count。
- semantic candidate count。
- selected ids。
- omitted ids/reasons：disabled、duplicate、limitExceeded、semanticUnavailable、staleEmbedding。

## C2. WorldBookSource

新增 `WorldBookSource`：

```swift
struct WorldBookSource: Sendable {
    func recallEntries(
        worldBook: WorldBookRecord?,
        entries: [WorldBookEntryRecord],
        recentMessages: [MessageRecord],
        currentInput: String,
        limit: Int
    ) async throws -> WorldBookRecallResult
}
```

输入兼容当前 Chat 链路：

- `ChatViewModel` 仍通过 characterCard.worldBookId 找到当前 worldBook。
- `fetchWorldBookEntries(worldBookId:)` 仍提供候选范围。
- `recentMessages + currentInput` 仍是 keyword trigger context。

Semantic query 建议使用：

```text
Current input:
{currentInput}

Recent context:
{last 5 prompt-history messages}
```

融合规则：

1. worldBook disabled -> empty。
2. entry disabled -> omitted，不参与 keyword / semantic。
3. keyword candidates：复用 `KeywordMatcher` 规则，记录 `keywordHits`。
4. semantic candidates：query embedding + `WorldBookVectorStore.search(query:worldBookId:limit:)`。
5. semantic unavailable：fallback 到 keyword-only，trace 写 `semanticUnavailable`。
6. 去重：同一 entry 合并 keyword/semantic reason。
7. 排序：keyword+semantic > keyword-only > semantic-only；同组内考虑 semantic rank、priority desc、keyword rank、updatedAt desc。
8. 截断：先按 recall limit 截断，再交给 PromptAssembler token budget 裁剪。

排序可以后续微调，但测试必须锁定当前版本的稳定顺序。

## C3. PromptAssembler Compatible Path

当前 `PromptAssembler` 内部会调用 keyword matcher。Phase C 需要避免 semantic-only entry 被二次过滤。

推荐改法：

- `WorldBookSource` 成为 Chat 主链路的召回入口。
- `PromptAssembler.preview(...)` / `assemble(...)` 接收已经 preselected 的 `worldBookEntries`。
- `PromptAssembler` 不做 embedding/KNN/DB 访问；只负责 block 生成、token 预算和裁剪。
- 为兼容现有单元测试或旧调用方，可保留一个 explicit keyword fallback helper，但不要让 Chat 主链路绕过 `WorldBookSource`。

输出必须保持：

```text
[World Book Entries]
[World Book: {title}]
{content}
[/World Book Entries]
```

不做：

- 不输出 `[Background]`。
- 不把 world book 与 memory 混成一个 block。
- 不改变四层 Prompt 顺序：Example Dialogs -> World Book -> Memories -> Current Turn。

## C4. ChatViewModel Wiring

`ChatViewModel.generateResponse(...)` 当前路径：

```text
fetch characterCard
fetch worldBook
fetch worldBookEntries
retrieve memories
PromptAssembler.preview(...)
ContextManager.prepareHistory(...)
PromptAssembler.assemble(...)
```

目标路径：

```text
fetch characterCard
fetch worldBook
fetch worldBookEntries
bounded rebuild missing/stale for current worldBook
WorldBookSource.recallEntries(...)
retrieve memories
PromptAssembler.preview(... worldBookEntries: recalledWorldBookEntries ...)
ContextManager.prepareHistory(...)
PromptAssembler.assemble(... same recalledWorldBookEntries ...)
```

注意：

- bounded rebuild 失败不应阻止 keyword recall；记录 trace/log，继续 keyword-only。
- `preview` 和 `assemble` 必须使用同一批 recalled entries，避免 history budget 与最终 prompt 不一致。
- `AssemblyResult.triggeredEntries` 可以继续返回 selected world book ids；名称后续可改为 `selectedWorldBookEntries`，但本阶段避免大范围 API churn。

## C5. Tests

新增/更新：

- `WorldBookSourceTests.test_keyword_only_candidate_is_selected`
- `WorldBookSourceTests.test_semantic_only_candidate_is_selected_without_keyword_hit`
- `WorldBookSourceTests.test_keyword_and_semantic_duplicate_merges_reasons`
- `WorldBookSourceTests.test_disabled_world_book_returns_empty`
- `WorldBookSourceTests.test_disabled_entry_is_omitted`
- `WorldBookSourceTests.test_semantic_failure_falls_back_to_keyword_only`
- `PromptAssemblerTests.test_world_book_block_shape_remains_compatible_for_semantic_candidates`
- `ChatViewModelPromptAssemblyTests.test_semantic_world_book_entry_reaches_world_book_entries_block`

Phase C focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```
