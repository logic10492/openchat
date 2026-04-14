# OpenChat — 项目约束

## 项目概述

iOS 角色扮演聊天应用，支持 OpenAI 兼容 API。详见 `arch/index.md`。

## 技术栈

- **语言**: Swift 6, iOS 17+
- **UI**: SwiftUI + @Observable (MVVM)
- **异步**: Swift Concurrency (async/await, AsyncSequence)
- **持久化**: SQLite via GRDB.swift
- **网络**: URLSession + AsyncBytes（无第三方网络库）
- **包管理**: Swift Package Manager

## 源码结构

按 `arch/source-tree.md` 中定义的 4 层结构组织代码：

```
OpenChat/
├── App/           → 应用入口、全局状态、依赖注入
├── Features/      → 业务模块（Chat / CharacterCard / WorldBook / Conversation / Settings）
├── Core/          → 基础设施（Networking / PromptEngine / ContextManager / Database）
├── Shared/        → 通用扩展、UI 组件、协议
└── Resources/     → 资源文件
```

## 架构规则

1. **单向依赖**: App → Features → Core → Shared。禁止反向依赖
2. **Feature 间隔离**: Features 之间不直接引用，通过 App 层或 Core 层间接交互
3. **MVVM 分层**: View 不直接访问数据库或网络，通过 ViewModel 中转
4. **ViewModel 使用 @Observable**: 不使用 ObservableObject/Published
5. **依赖注入**: ViewModel 通过 init 接收 Core 层服务，不自行创建
6. **文档同步**：源码应当保持和arch中文档的同步性，实现后需要在文档中注明对应的实现证据，以方便项目后续的修改
7. **harness原则**：实现前应当确保风格 命名的一致 错误处理要规范，同时编写完整规范的测试用例确保项目可用性，

## Swift 代码规范

- 优先使用 `struct` 而非 `class`，除非需要引用语义
- 使用 Swift Concurrency (`async/await`)，不使用 Combine 或回调
- 错误处理使用 typed `enum` 实现 `LocalizedError`，不使用泛 `Error`
- 所有数据库操作通过 GRDB Record 类型，不写裸 SQL
- 字符串不硬编码到 View 中，使用 `Localizable.xcstrings`

## 数据模型

所有持久化实体定义在 `arch/data-model.md`，包括 6 张表：
`api_endpoint`, `character_card`, `world_book`, `world_book_entry`, `conversation`, `message`

修改数据模型时：
- 只追加新 migration，不修改已有 migration
- 使用 GRDB `DatabaseMigrator` 管理版本
- 迁移命名格式: `v{N}_{description}`

## 模块设计文档

开发各模块前必须参考对应设计文档:

| 模块 | 设计文档 |
|---|---|
| API 客户端 | `arch/modules/api-client.md` |
| 角色卡 | `arch/modules/character-card.md` |
| 世界书 | `arch/modules/world-book.md` |
| Prompt 拼装 | `arch/modules/prompt-assembly.md` |
| 上下文管理 | `arch/modules/context-manager.md` |
| 聊天 | `arch/modules/chat.md` |
| 设置 | `arch/modules/settings.md` |

## 落地阶段

按 `arch/roadmap.md` 的 6 阶段推进。每个阶段完成后必须满足该阶段的验证标准 checklist。

## 详细约束

以下 `.instructions.md` 文件提供各领域的详细编码约束：

- `.github/instructions/swift-conventions.instructions.md` — Swift 语言规范
- `.github/instructions/swiftui-views.instructions.md` — SwiftUI 视图层规范
- `.github/instructions/grdb-database.instructions.md` — GRDB 数据库层规范
- `.github/instructions/networking-sse.instructions.md` — 网络层与 SSE 规范
- `.github/instructions/prompt-engine.instructions.md` — Prompt 拼装引擎规范
- `.github/instructions/context-manager.instructions.md` — 上下文管理规范
- `.github/instructions/testing.instructions.md` — 测试规范
