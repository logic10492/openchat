# Memory 数据模型

## 1. `memory_entry`

`memory_entry` 保存角色维度的长期记忆条目。当前 Record 为 `MemoryEntryRecord`。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | TEXT | PK, NOT NULL | UUID 字符串 |
| `characterCardId` | TEXT | NOT NULL, FK -> `character_card.id` | 所属角色卡 |
| `sourceConversationId` | TEXT | FK -> `conversation.id` | 来源对话，可为空 |
| `content` | TEXT | NOT NULL | LLM 抽取出的记忆文本 |
| `memoryType` | TEXT | NOT NULL | `event` / `fact` / `relationship` / `summary` |
| `importance` | INTEGER | NOT NULL, DEFAULT 50 | 重要性评分，当前解析后 clamp 到 0...100 |
| `createdAt` | DATETIME | NOT NULL | 创建时间 |
| `updatedAt` | DATETIME | NOT NULL | 更新时间 |

外键：

- `characterCardId -> character_card(id) ON DELETE CASCADE`
- `sourceConversationId -> conversation(id) ON DELETE SET NULL`

索引：

- `idx_memory_entry_characterCardId`
- `idx_memory_entry_sourceConversationId`

## 2. `memory_embedding`

`memory_embedding` 是 sqlite-vec 虚拟表，用于 KNN 检索。

```sql
CREATE VIRTUAL TABLE memory_embedding USING vec0(
    entry_id TEXT PRIMARY KEY,
    embedding float[384]
);
```

当前约束：

- `entry_id` 与 `memory_entry.id` 逻辑关联。
- 生产写入由 `VectorStore.insert(entry:embedding:)` 或 `VectorStore.insert(entries:)` 同时写 `memory_entry` 和 `memory_embedding`。
- 向量维度必须等于 `EmbeddingService.embeddingDimension == 384`。
- 删除单条或清空角色记忆时，需要同时删除 embedding 与 entry。

## 3. `conversation.lastExtractedSortOrder`

`conversation.lastExtractedSortOrder` 记录当前 conversation 自动记忆提取已经处理到的最大 message `sortOrder`。

语义：

- `nil`：该 conversation 尚未完成过自动提取，下一次提取会读取全部消息。
- 非空：下一次提取只处理 `message.sortOrder > lastExtractedSortOrder` 的消息。
- 提取成功并完成 memory/vector 写入后，更新为本批消息的最大 `sortOrder`。
- 提取跳过、解析失败、embedding 失败或 vector 写入失败时不推进。

这个字段由 `v13_add_last_extracted_sort_order` 追加，不能通过修改旧 migration 补写。

## 4. 类型枚举

```swift
enum MemoryType: String, Codable, CaseIterable, Sendable {
    case event
    case fact
    case relationship
    case summary
}
```

LLM 返回的 `type` 会做小写匹配；无法识别时 fallback 到 `.event`。

## 5. 迁移历史

| migration | 内容 |
|---|---|
| `v4_create_memory_tables` | 创建 `memory_entry` 与 `memory_embedding`，并添加 `characterCardId` / `sourceConversationId` 索引 |
| `v13_add_last_extracted_sort_order` | 在 `conversation` 追加 `lastExtractedSortOrder` |
| `v14_create_memory_entry_provenance` | 创建 `memory_entry_provenance` companion table |

迁移约束：

- 只追加新 migration，不修改已有 migration。
- 如要扩展 Hindsight-lite schema，优先追加 v15+ migration。
- 若只新增可选元数据且不影响现有 prompt 注入，可考虑新表而非大幅重写 `memory_entry`。

## 6. `memory_entry_provenance`

`memory_entry_provenance` 是 Hindsight-lite Phase C 追加的 companion table，保留记忆来源和提取元数据，避免一次性扩宽 `memory_entry` 主表。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `memoryEntryId` | TEXT | PK, NOT NULL, FK -> `memory_entry.id` | 与记忆条目一对一 |
| `sourceStartSortOrder` | INTEGER | | 来源消息起始 sortOrder |
| `sourceEndSortOrder` | INTEGER | | 来源消息结束 sortOrder |
| `sourceMessageIds` | TEXT | | JSON array，具体消息 ID |
| `extractionModel` | TEXT | | 执行提取的模型名称 |
| `extractionPromptVersion` | TEXT | NOT NULL, DEFAULT 'v1' | 提取 prompt 版本 |
| `confidence` | REAL | | 抽取器自报置信度（0...1） |
| `dedupeKey` | TEXT | | 去重键 |
| `tags` | TEXT | | JSON array，分类标签 |
| `createdAt` | DATETIME | NOT NULL | 创建时间 |
| `updatedAt` | DATETIME | NOT NULL | 更新时间 |

外键：`memoryEntryId -> memory_entry(id) ON DELETE CASCADE`

当前 Record：`MemoryEntryProvenanceRecord`

- `sourceMessageIds`、`tags` 使用 JSON array 字符串，沿用 `RecordCoders` 风格。
- 旧 `memory_entry` 没有 provenance 时仍能检索、展示和删除。

## 7. 当前缺口

- 没有显式的 `memory_entry_link`（reinforces / duplicates / contradicts / supersedes / summarizes 关系）。
- `latestMemoryDate(conversationId:)` 仍保留在 `DatabaseManager+Memory`，但自动提取 cutoff 已改用 `conversation.lastExtractedSortOrder`。

## 8. Hindsight-lite 目标 schema

为降低迁移风险，Hindsight-lite 优先使用 companion table，而不是直接把 `memory_entry` 扩成大宽表。

建议后续追加：

```text
memory_entry_link
  id TEXT PRIMARY KEY
  fromMemoryEntryId TEXT
  toMemoryEntryId TEXT
  relation TEXT
  createdAt DATETIME
```

`relation` 初始枚举：

- `reinforces`
- `duplicates`
- `contradicts`
- `supersedes`
- `summarizes`

迁移要求：

- 使用 v15+ 追加 migration。
- 旧 `memory_entry` 记录没有 provenance 时仍可检索和注入。
- reflect 生成的 observation 必须通过 `memory_entry_link(relation = summarizes)` 或等价 `basedOn` 结构保留来源。
