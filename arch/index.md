# OpenChat — 项目总览

> iOS 角色扮演聊天应用，支持 OpenAI 兼容 API

## 项目定位

面向角色扮演爱好者的 iOS 聊天客户端。支持连接本地部署模型（llama.cpp、Ollama 等）和云端 API（OpenAI、DeepSeek 等），通过角色卡和世界书系统提供沉浸式角色扮演体验，并针对小模型的上下文限制做了专门的优化。

## 技术栈

| 层面 | 选型 |
|---|---|
| UI 框架 | SwiftUI |
| 架构模式 | MVVM + @Observable |
| 异步模型 | Swift Concurrency (async/await, AsyncSequence) |
| 持久化 | SQLite via GRDB.swift |
| 网络 | 原生 URLSession + AsyncBytes |
| SSE 解析 | 自实现（无第三方依赖） |
| 向量存储 | sqlite-vec |
| 嵌入模型 | MultilingualE5Small (CoreML) |
| 最低版本 | iOS 17+ |

## 当前实现状态

- 2026-04-14 已完成工程脚手架落地：`OpenChat.xcodeproj`、`OpenChat/` 四层目录、`OpenChatTests/`、`scripts/generate_xcodeproj.rb`
- 当前代码已落地的核心模块包括：数据库迁移与 Record、`APIClient`/`SSEStreamParser`、`PromptAssembler`、checkpoint-aware `ContextManager`、聊天/角色卡/世界书/设置等基础 Feature
- 已验证命令：
  - `xcodebuild -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
  - `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- 当前自动化测试结果：197 个 Swift Testing 测试全部通过，覆盖数据库迁移、compression checkpoint schema/API、SSE 解析、API 客户端、Prompt 四层组装、关键词匹配、Token 计数、上下文截断与 checkpoint 压缩、会话级 compression mode、Chat 发送链路当前输入去重与四层 request 顺序、Memory embedding/vector/retrieval 可靠性。

## 功能需求

### 1. 角色扮演系统
- **角色卡**：定义角色的性格、外貌、身材、语调、背景故事、示例对话
- **世界书**：定义世界设定，条目通过关键词触发动态注入 prompt
- **世界→角色层级**：角色卡归属于世界书，先选择世界再选择角色，支持跨世界导入角色
- **编辑器**：分 section 的表单化编辑，支持导入/导出
- **结构化导入**：世界书支持 Markdown 格式粘贴导入（方便从 ChatGPT 等工具生成后导入）

### 2. 模型智能优化
- **上下文控制**：将上下文长度控制在 40% 以内，保持模型对当前对话的专注度
- **对话剔除**：直接丢弃最早的消息（适用于本地模型 / 隐私内容）
- **对话压缩**：超过阈值时调用 API 生成持久化 checkpoint，后续请求复用 `compressed context + checkpoint 后历史`
- **策略可选**：每个会话可独立选择剔除或压缩策略；压缩策略下可选择标准模式（40%）或高智能模式（25% effective window × 90%）

### 3. Prompt 拼装
按四层顺序拼装发送给模型的 messages：
1. Stable Identity：角色卡 System Prompt、角色描述、场景设定、slowPlot directive
2. Stable Conversation State：压缩 checkpoint 摘要和 checkpoint 后历史，或剔除策略保留的最近历史
3. Current-Turn Context：`[Example Dialogs]`、`[World Book Entries]`、`[Memories]` 三类 labeled system block
4. Current Turn：最后一条 user message，内容为当前用户输入 + `[Time] <ISO8601> [/Time]`

`WorldBookEntryPosition.after_system` / `.before_history` 保留为旧数据兼容字段，不再决定最终 prompt 位置。

### 4. 跨对话记忆
- **记忆提取**：当前源码在 Chat 生成链路中每累计 10 条 user/assistant 消息后后台触发，调用 API 提取关键事件、事实、关系变化和摘要
- **向量存储**：使用 App Bundle 内的 CoreML 嵌入模型（MultilingualE5Small）和 tokenizer 将记忆向量化，`VectorStore` 在同一事务内保存 `memory_entry + memory_embedding`
- **记忆检索**：新对话开始时拉取近期摘要，每次发送消息时语义检索相关记忆并注入 prompt；语义检索异常时 fallback 到近期记忆
- **角色绑定**：记忆以角色卡为单位存储，同一角色的不同对话共享记忆

### 5. 时间感知
- 每次 prompt 拼装时自动把当前时间（ISO 8601 含时区）注入最后一条 Current Turn user message
- 格式：`[Time] 2026-04-15T14:30:00+08:00 [/Time]`
- 始终启用，不可关闭
- 帮助 LLM 感知时间流逝，提升角色扮演沉浸感

## 架构全景

```
┌──────────────────────────────────────────────────────┐
│                      App Layer                        │
│  AppState · DependencyContainer · ContentView         │
└──────────────────────┬───────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────┐
│                   Features Layer                      │
│  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │  Chat   │ │Character │ │WorldBook │ │ Settings │ │
│  │         │ │  Card    │ │          │ │          │ │
│  └────┬────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ │
└───────┼───────────┼────────────┼────────────┼───────┘
        │           │            │            │
┌───────▼───────────▼────────────▼────────────▼────────┐
│                    Core Layer                         │
│  ┌───────────┐ ┌────────────┐ ┌──────────────────┐   │
│  │Networking │ │PromptEngine│ │ContextManager    │   │
│  │APIClient  │ │Assembler   │ │Truncation/Compress│  │
│  │SSEParser  │ │TokenCounter│ │                   │  │
│  └───────────┘ └────────────┘ └──────────────────┘   │
│  ┌──────────────────────────┐ ┌──────────────────┐   │
│  │       Memory              │ │    Database       │   │
│  │ EmbeddingService          │ │ DatabaseManager   │   │
│  │ VectorStore               │ │ Migrations        │   │
│  │ MemoryManager             │ │ Records           │   │
│  └──────────────────────────┘ └──────────────────┘   │
└──────────────────────────────────────────────────────┘
        │
┌───────▼──────────────────────────────────────────────┐
│                   Shared Layer                        │
│  Extensions · Components · Protocols                  │
└──────────────────────────────────────────────────────┘
```

**依赖规则**：上层 → 下层单向依赖，Feature 间不直接引用。

## 数据流

```
用户输入
   │
   ▼
ChatViewModel
   │
   ├─→ MemoryManager: 检索相关记忆（向量化当前输入 → KNN 检索；异常时 fallback 到近期记忆）
   │
   ├─→ PromptAssembler: 计算固定段 token（含记忆段 + 时间上下文）
   │
   ├─→ ContextManager: 用剩余预算处理历史消息
   │       │
   │       ├─→ TruncationStrategy (剔除)
   │       └─→ CheckpointCompactor (压缩 checkpoint → APIClient)
   │
   ├─→ PromptAssembler: 最终拼装 [ChatMessage]
   │
   └─→ APIClient.streamMessage()
           │
           └─→ SSEStreamParser → StreamDelta → UI 更新

生成完成后达到周期阈值时：
ChatViewModel
   └─→ MemoryManager.extractMemories()
           │
           ├─→ APIClient: 调用 LLM 提取关键事件/摘要
           ├─→ EmbeddingService: 向量化记忆条目
           └─→ VectorStore: 原子存储 memory_entry + memory_embedding
```

## 文档导航

| 文档 | 内容 |
|---|---|
| [source-tree.md](source-tree.md) | 源码目录结构蓝图 |
| [data-model.md](data-model.md) | 数据模型定义（SQLite 表 + Swift 类型） |
| [modules/api-client.md](modules/api-client.md) | API 客户端模块（SSE 流式 / 多端点） |
| [modules/character-card.md](modules/character-card.md) | 角色卡模块（CRUD / 编辑器 / 导入导出） |
| [modules/world-book.md](modules/world-book.md) | 世界书模块（条目管理 / 关键词触发 / 导入） |
| [modules/prompt-assembly.md](modules/prompt-assembly.md) | Prompt 拼装引擎（顺序 / token 预算 / 接口） |
| [modules/context-manager.md](modules/context-manager.md) | 上下文管理（40%策略 / 剔除 / 压缩） |
| [modules/chat.md](modules/chat.md) | 聊天模块（消息展示 / 流式输出 / 交互） |
| [modules/memory/index.md](modules/memory/index.md) | 跨对话记忆系统（向量存储 / 嵌入模型 / 记忆提取检索） |
| [modules/settings.md](modules/settings.md) | 设置模块（API 配置 / 参数 / 数据管理） |
| [AntiEntropy/index.md](AntiEntropy/index.md) | 传播审计与 arch-test / arch-src / src-test 三边一致性结论 |
| [roadmap.md](roadmap.md) | 6 阶段落地路线图 |
