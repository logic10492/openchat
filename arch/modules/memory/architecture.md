# Memory 架构边界

## 1. 模块定位

Memory 模块负责跨对话长期记忆，不负责同一会话的窗口压缩。当前职责边界如下：

- `Core/Memory`：记忆提取、语义检索、embedding、sqlite-vec 向量存储、错误类型。
- `Core/Database`：`memory_entry`、`memory_embedding`、`conversation.lastExtractedSortOrder` 的持久化结构和 CRUD。
- `Core/Background`：把 Memory recall result 映射为 `BackgroundCandidate`，再由 `BackgroundWorker` 选择进入 `BackgroundPacket`。
- `Core/PromptEngine`：从 `BackgroundPacket` 读取 selected memory entries，注入兼容 `[Memories]` system block，并按 token 预算裁剪。
- `Features/Chat`：决定发送链路中的提取时机，调用 `BackgroundManager.prepare(...)`，显示提取状态。
- `Features/CharacterCard`：提供角色维度的记忆查看、搜索和删除管理。

## 2. 文件职责

| 文件 | 职责 |
|---|---|
| `Core/Memory/MemoryManager.swift` | 提取与检索编排层；解析 LLM 返回的 `ExtractedMemory`；生成 `MemoryRecallResult` 并处理 fallback tiers |
| `Core/Memory/MemoryRecallModels.swift` | recall result / entry / trace / fallback / omission DTO |
| `Core/Memory/MemoryRecallTool.swift` | Background Phase 4B read-only source tool，只包装 `MemoryManager.recallMemories(...)` 并透传 `MemoryRecallResult` |
| `Core/Background/MemoryBackgroundSource.swift` | Background Phase 4D adapter，把 `MemoryRecallResult.entries` / trace metadata 映射为 `BackgroundCandidate(sourceType: .memory)` |
| `Core/Background/BackgroundManager.swift` | Chat 主链路的 background source 编排入口，调用 Memory / WorldBook sources 后交给 worker |
| `Core/Background/BackgroundWorker.swift` | deterministic candidate selector，不读写 DB、不联网、不拼 prompt |
| `Core/Background/BackgroundPacket.swift` | 当前轮被选中的 background entries 与 diagnostics DTO |
| `Core/Background/BackgroundAssembler.swift` | 把 packet-selected memory / worldBook entries 转成 PromptAssembler 兼容 prompt items |
| `Core/Memory/EmbeddingService.swift` | CoreML MultilingualE5Small 加载、tokenizer 调用、384 维向量生成 |
| `Core/Memory/XLMRobertaTokenizer.swift` | 读取 `tokenizer.json`，生成固定长度 input IDs / attention mask |
| `Core/Memory/VectorStore.swift` | sqlite-vec 插入、批量原子写入、KNN 检索、删除 |
| `Core/Memory/MemoryDependencies.swift` | `EmbeddingProvider`、`MemoryVectorStore` 协议，便于测试注入 |
| `Core/Memory/MemoryError.swift` | `MemoryType` 与 `MemoryError` |
| `Core/Database/Records/MemoryEntryRecord.swift` | `memory_entry` GRDB Record |
| `Core/Database/DatabaseManager+Memory.swift` | 记忆查询、保存、删除、计数等 DB 操作 |
| `Features/Chat/ViewModels/ChatViewModel+Support.swift` | 发送链路中的前置提取、检索和 prompt 组装调用 |
| `Features/Chat/Models/MemoryExtractionPhase.swift` | Chat 内联提取状态 |
| `Features/Chat/Views/MemoryExtractionIndicator.swift` | 提取状态 UI |
| `Features/CharacterCard/Views/MemoryListView.swift` | 角色记忆列表 UI |
| `Features/CharacterCard/ViewModels/MemoryListViewModel.swift` | 记忆列表加载、过滤和删除 |

## 3. 依赖方向

```
Features/Chat
  -> Core/Memory
  -> Core/Database
  -> Shared

Features/CharacterCard
  -> Core/Memory
  -> Core/Database
  -> Shared

Core/Background
  -> Core/Memory
  -> Core/WorldBook
  -> Core/Database

Core/PromptEngine
  -> Core/Background
  -> Core/Database Records
```

约束：

- `Core/Memory` 不依赖 `Features`。
- `PromptAssembler` 只消费 `MemoryEntryRecord`，不调用 `MemoryManager`。
- 当前 Chat 主链路通过 `BackgroundPacket` 间接消费 memory entries；旧 `PromptAssembler` direct overload 保留为兼容 / rollback path。
- `ChatViewModel` 通过 init 接收 `MemoryManager`，不自行创建 embedding 或 vector store。
- 记忆 UI 通过 `MemoryListViewModel` 访问 `DatabaseManager` / `MemoryManager`，View 不直接做数据库操作。

## 4. 与其他记忆相关系统的区别

| 系统 | 作用 | 是否跨对话 | 是否进入 Memory 模块 |
|---|---|---:|---:|
| `memory_entry` | 角色长期记忆 | 是 | 是 |
| `memory_embedding` | 长期记忆向量索引 | 是 | 是 |
| `conversation.lastExtractedSortOrder` | 自动提取进度边界 | 单 conversation | 是，作为提取 cutoff |
| compression checkpoint | 同一会话长历史压缩 | 否 | 否，属于 `Core/ContextManager` |
| recent messages | 当前会话历史 | 否 | 否，由 Chat/ContextManager 处理 |

## 5. 当前设计取舍

- 保存抽取后的事件/事实/关系/摘要，而不是保存每条原始消息向量，减少噪声和索引体积。
- embedding 在本地执行，长期记忆检索不需要额外网络请求。
- LLM 只参与自动提取；正常 recall 不走生成式 LLM。
- 检索失败不阻断聊天；semantic 不可用时 fallback 到 keyword + recent high-value，提取失败不推进 cutoff。
- 当前记忆条目主表仍较扁平；source range/provenance 已由 `memory_entry_provenance` 建模，manual reflect observation 的 based-on 关系已由 `memory_entry_link` 建模。dedupe/reinforce 自动应用、冲突解决和 idle/background reflect 仍未实现。

## 6. Background 目标边界

Background 目标架构中，Memory 不再直接进入 prompt，而是先作为 `MemoryBackgroundSource` 产出候选条目：

```text
MemoryManager.recallMemories(...)
  -> MemoryRecallTool
  -> MemoryBackgroundSource
  -> BackgroundCandidate(sourceType: .memory)
  -> BackgroundWorker
  -> BackgroundPacket
  -> BackgroundAssembler / PromptAssembler
```

这不改变 Memory 的 retain 职责：自动提取、embedding 和持久化仍属于 `Core/Memory`。2026-05-17 Phase 4B/4D 已完成 `MemoryRecallTool` 与 `MemoryBackgroundSource` 的 source tool / adapter 层；2026-05-17 Phase 5/6 已完成 `BackgroundWorker` / `BackgroundPacket` / Chat-Prompt compatible switch。当前产品运行时由 `ChatViewModel` 调用 `BackgroundManager.prepare(...)`，再把 packet 交给 `PromptAssembler.preview(... backgroundPacket:)` / `assemble(... backgroundPacket:)` 输出 `[Memories]`。

已实现的 `MemoryRecallResult` / `MemoryRecallTrace` 是 Background 的输入边界：Memory 自己产出可解释的排序、fallback 和 omission 信息；read-only `MemoryRecallTool` 暴露该 result；`MemoryBackgroundSource` 再把这些信息包装进 `BackgroundCandidate` metadata。`BackgroundWorker` 负责跨 source selection，`PromptAssembler` 只按 packet order 和 token budget 做兼容 block 裁剪，不重新实现 Memory 排序逻辑。详见 `arch/modules/background/index.md` 与 `arch/modules/memory/hindsight-lite.md`。
