# 世界书向量化

> 状态：目标架构规划，尚未实现。

## 1. 为什么需要向量化

当前世界书靠关键词触发，Memory 靠语义检索。两套召回方式分离时，BackgroundWorker 很难公平地比较“一个语义相关的记忆”和“一个关键词命中的世界书条目”。

世界书向量化后，WorldBook 与 Memory 都能作为 semantic candidates 进入同一调度层：

```text
currentInput -> query embedding
  -> Memory KNN
  -> WorldBook KNN
  -> keyword trigger
  -> BackgroundWorker fusion
```

## 2. 目标表

建议追加 migration：

```sql
CREATE VIRTUAL TABLE world_book_entry_embedding USING vec0(
    entry_id TEXT PRIMARY KEY,
    embedding float[384]
);
```

如果需要可审计增量重建，追加普通表：

```text
world_book_entry_embedding_meta
  entryId TEXT PRIMARY KEY
  contentHash TEXT NOT NULL
  embeddedAt DATETIME NOT NULL
  embeddingModel TEXT NOT NULL
```

## 3. 索引内容

建议 embedding 文本不是单纯 `content`，而是稳定拼接：

```text
Title: {title}
Keywords: {keywords joined}
Content: {content}
```

原因：

- title 通常是高价值实体名。
- keywords 是用户显式触发意图。
- content 提供语义细节。

## 4. 更新时机

需要在以下场景重建或删除 embedding：

- 创建 world book entry。
- 修改 title / keywords / content。
- 删除 entry。
- 批量导入 world book。
- embedding 模型版本变更。

第一阶段可以采用 lazy rebuild：

- 读取 entry 时发现无 embedding 或 hash 不匹配。
- 后台排队重建。
- 本轮仍可用 keyword trigger fallback。

## 5. 召回融合

WorldBookBackgroundSource 候选来自两路：

1. keyword trigger
2. semantic KNN

融合规则建议：

- keyword 命中是强 boost，但不是唯一入口。
- semantic 相关但未 keyword 命中的条目可以进入候选池。
- `priority` 是 source 自带权重，不能单独决定是否注入。
- 已禁用 world book 或 entry 不应进入候选池。

## 6. 与现有字段兼容

- `position` 保留为旧数据字段，不再决定最终 prompt 位置。
- `priority` 继续作为排序信号。
- `keywords` 继续用于 trigger 和 embedding text。
- `isEnabled` 继续作为 hard filter。

## 7. 测试建议

- migration 创建 `world_book_entry_embedding`。
- entry 创建/修改/删除时 embedding 同步或标记重建。
- KNN 只返回当前 world book 或当前角色绑定世界书范围内的 entry。
- keyword-only、semantic-only、keyword+semantic 三类候选融合顺序稳定。
- disabled entry 不返回。
