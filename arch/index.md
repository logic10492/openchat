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
| 最低版本 | iOS 17+ |

## 当前实现状态

- 2026-04-14 已完成工程脚手架落地：`OpenChat.xcodeproj`、`OpenChat/` 四层目录、`OpenChatTests/`、`scripts/generate_xcodeproj.rb`
- 当前代码已落地的核心模块包括：数据库迁移与 Record、`APIClient`/`SSEStreamParser`、`PromptAssembler`、`ContextManager`、聊天/角色卡/世界书/设置等基础 Feature
- 已验证命令：
  - `xcodebuild -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - `xcodebuild -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' test`
- 当前自动化测试结果：12 个核心测试全部通过，覆盖数据库迁移、SSE 解析、API 客户端、Prompt 组装、关键词匹配、Token 计数、上下文截断与压缩

## 功能需求

### 1. 角色扮演系统
- **角色卡**：定义角色的性格、外貌、身材、语调、背景故事、示例对话
- **世界书**：定义世界设定，条目通过关键词触发动态注入 prompt
- **编辑器**：分 section 的表单化编辑，支持导入/导出
- **结构化导入**：世界书支持 Markdown 格式粘贴导入（方便从 ChatGPT 等工具生成后导入）

### 2. 模型智能优化
- **上下文控制**：将上下文长度控制在 40% 以内，保持模型对当前对话的专注度
- **对话剔除**：直接丢弃最早的消息（适用于本地模型 / 隐私内容）
- **对话压缩**：调用公开 API 将旧消息压缩为摘要（适用于可使用云端 API 的场景）
- **策略可选**：每个会话可独立选择剔除或压缩策略

### 3. Prompt 拼装
按以下顺序拼装发送给模型的 messages：
1. 角色卡 System Prompt
2. 世界书条目（position=after_system）
3. 角色描述（personality / appearance / physique / speechStyle / backstory）
4. 场景设定（scenario）
5. 世界书条目（position=before_history）
6. 示例对话（example dialogs）
7. 最近会话历史（经上下文管理处理）
8. 当前用户输入

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
│  │  Chat   │ │Character │ │WorldBook │ │Settings  │ │
│  │         │ │  Card    │ │          │ │          │ │
│  └────┬────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ │
└───────┼───────────┼────────────┼────────────┼────────┘
        │           │            │            │
┌───────▼───────────▼────────────▼────────────▼────────┐
│                    Core Layer                         │
│  ┌───────────┐ ┌────────────┐ ┌──────────────────┐   │
│  │Networking │ │PromptEngine│ │ContextManager    │   │
│  │APIClient  │ │Assembler   │ │Truncation/Compress│  │
│  │SSEParser  │ │TokenCounter│ │                   │  │
│  └───────────┘ └────────────┘ └──────────────────┘   │
│  ┌──────────────────────────────────────────────┐    │
│  │                 Database                      │    │
│  │  DatabaseManager · Migrations · Records       │    │
│  └──────────────────────────────────────────────┘    │
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
   ├─→ PromptAssembler: 计算固定段 token
   │
   ├─→ ContextManager: 用剩余预算处理历史消息
   │       │
   │       ├─→ TruncationStrategy (剔除)
   │       └─→ CompressionStrategy (压缩 → APIClient)
   │
   ├─→ PromptAssembler: 最终拼装 [ChatMessage]
   │
   └─→ APIClient.streamMessage()
           │
           └─→ SSEStreamParser → StreamDelta → UI 更新
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
| [modules/settings.md](modules/settings.md) | 设置模块（API 配置 / 参数 / 数据管理） |
| [roadmap.md](roadmap.md) | 6 阶段落地路线图 |
