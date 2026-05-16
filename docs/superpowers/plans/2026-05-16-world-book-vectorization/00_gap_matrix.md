# 00. Gap Matrix

## Source / Arch / Test 对照

| 领域 | 当前源码 | 目标 | 缺口 | 计划阶段 |
|---|---|---|---|---|
| Schema | Phase A 后 `Migrations.swift` 最新到 `v16_create_world_book_entry_embedding_meta`；已有 `memory_embedding` 与 `world_book_entry_embedding` | 保持 v15/v16 schema，并在 Phase B indexer 写入 meta 状态 | Phase A schema 缺口已关闭；已有世界书 Core rebuild/backfill 入口已由 Phase B 关闭 | A/B closed |
| Vector store | Phase A 后已有 `WorldBookVectorStore` 服务 `world_book_entry_embedding` | 由 indexer/source 调用 | Phase A KNN 按 `worldBookId` 限定缺口已关闭；Phase C 已由 WorldBookSource 接入 Chat semantic recall | A/C closed |
| Meta / rebuild | 无世界书 embedding meta | `contentHash` + model + status 支持增量重建 | 已导入条目无 backfill；模型升级无重建依据 | B |
| Embedding text | Memory 只 embed `memory_entry.content` | 世界书 embed `Title + Keywords + Content` | semantic recall 无法利用 title/keywords | B |
| Existing imports | Markdown import 只保存 entries | 支持把现有 `world_book_entry` 扫描并向量化 | migration 后老数据不会自动拥有向量 | B/D |
| Keyword recall | Chat 主链路通过 `WorldBookSource` 输出 keyword + semantic candidates；`PromptAssembler` 保留 keyword fallback | WorldBook source 同时输出 keyword + semantic candidates | Phase C 已关闭 semantic-only 条目无法进入 prompt的缺口 | C closed |
| Prompt output | `[World Book Entries]` block 已存在；Phase C 已新增 preselected prompt path | 第一阶段继续使用同一 block | Phase C 已接收 source 预选条目并保持文本格式不变 | C closed |
| CRUD save | `saveWorldBookEntry` 只保存 record | 保存后同步 index 或标记 stale | 修改 title/keywords/content 后 embedding 可能过期 | D |
| Import | `WorldBookEditorView` 循环 `saveEntry` | 批量保存后批量 index 或标记 rebuild | 大批量导入可能留下未索引内容 | D |
| Delete | `deleteWorldBookEntry` / `deleteWorldBook` 不清理向量表 | 删除 entry/worldBook 同事务清理 embedding/meta | sqlite-vec virtual table 不能依赖 FK cascade | D |
| eraseAllData | 只删 `memory_embedding` | 同时删 world book embedding/meta | 清空数据后向量表会残留 | D |
| Tests | 只有 Memory vector、Prompt keyword tests | 新增 WorldBook vector/index/source/Chat focused tests | 缺 migration/backfill/semantic-only 覆盖 | A-D |

## 当前实现证据

- `OpenChat/Core/Database/Migrations.swift`：v4 已创建 `memory_embedding`，v15/v16 已创建 `world_book_entry_embedding` 与 `world_book_entry_embedding_meta`。
- `OpenChat/Core/Memory/EmbeddingService.swift`：embedding dimension 固定为 384。
- `OpenChat/Core/Memory/VectorStore.swift`：sqlite-vec SQL 和 embedding blob 转换可复用为实现参考。
- `OpenChat/Core/WorldBook/WorldBookVectorStore.swift`：Phase A 已提供 worldBook-scoped KNN、upsert、delete。
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`：当前世界书 block 由 `makeWorldBookBlock(...)` 生成，输出标签是 `[World Book Entries]`；Phase C preselected path 不再二次 keyword 过滤。
- `OpenChat/Core/WorldBook/WorldBookSource.swift`：Phase C 已提供 keyword + semantic candidates 融合。
- `OpenChat/Core/Database/DatabaseManager+Content.swift`：世界书 CRUD 当前没有 embedding 维护逻辑。
- `OpenChat/Features/WorldBook/Views/WorldBookEditorView.swift`：Markdown import 当前逐条保存 entry。

## 风险矩阵

| 风险 | 影响 | 处理 |
|---|---|---|
| migration 中尝试执行 CoreML embedding | migration 变慢、失败、破坏数据库初始化 | migration 只建表；runtime indexer 做 backfill |
| save entry 时 embedding 失败导致内容保存失败 | 用户世界书编辑体验变差 | 内容保存优先；embedding 失败记录为 `failed` / `needs_rebuild`，keyword fallback 仍可用 |
| semantic KNN 未限定 worldBookId | 召回其他世界书污染 prompt | `WorldBookVectorStore.search(... worldBookId:)` 必须先限定 entry 范围 |
| PromptAssembler 继续内部 keyword-only | semantic-only candidate 被二次过滤掉 | Phase C 改为消费 `WorldBookSource` 预选 candidate，同时保留兼容 fallback |
| delete worldBook 后 embedding 残留 | 数据污染、KNN 命中孤儿向量 | 删除 entry/worldBook 前显式删除 embedding/meta |
| existing imported entries 长期未 backfill | 用户看不到 semantic recall 改善 | 提供 `rebuildAllMissingOrStale`，并在当前世界书召回前做 bounded lazy rebuild |

## 完成判定

- 已导入世界书在 migration 后可通过 indexer rebuild 生成 embedding/meta。
- keyword-only、semantic-only、keyword+semantic 三类候选均能进入同一个 `[World Book Entries]` block。
- disabled worldBook / disabled entry 不进入候选。
- 删除 entry / worldBook / eraseAllData 不留下向量残留。
- 文档明确区分“当前已实现”与“后续 Background 目标”，不能把 BackgroundWorker 写成本计划已落地项。
