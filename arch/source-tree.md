# 源码目录结构蓝图

## 概述

项目采用 **Feature-based** 分层结构，顶层按 App / Features / Core / Shared 四层组织。每个 Feature 模块内部遵循 MVVM（Views / ViewModels / Models）。Core 层放置业务无关的基础设施。

## 目录树

```
OpenChat/
├── OpenChatApp.swift                  # @main 入口，Scene 配置
├── ContentView.swift                  # 根导航视图（TabView / NavigationSplitView）
│
├── App/
│   ├── AppState.swift                 # 全局应用状态（当前会话、激活角色卡等）
│   ├── AppConstants.swift             # 全局常量（默认 token 上限、prompt 标记等）
│   └── DependencyContainer.swift      # 依赖注入容器（数据库、网络等单例的持有与分发）
│
├── Features/
│   ├── Chat/
│   │   ├── Views/
│   │   │   ├── ChatView.swift              # 聊天主界面（消息列表 + 输入栏）
│   │   │   ├── MessageBubbleView.swift     # 单条消息气泡（支持 Markdown 渲染）
│   │   │   ├── InputBarView.swift          # 底部输入栏（文本框 + 发送/停止按钮）
│   │   │   └── ChatSettingsSheet.swift     # 当前会话设置面板（上下文策略选择等）
│   │   ├── ViewModels/
│   │   │   └── ChatViewModel.swift         # 消息列表状态、发送/流式接收/重新生成/编辑
│   │   └── Models/
│   │       └── MessageDisplayItem.swift    # 消息展示用 DTO（从 DB Message 转换）
│   │
│   ├── CharacterCard/
│   │   ├── Views/
│   │   │   ├── CharacterCardListView.swift     # 角色卡列表（Grid / List 切换）
│   │   │   ├── CharacterCardEditorView.swift   # 角色卡编辑器（分 section 表单）
│   │   │   └── CharacterCardDetailView.swift   # 角色卡详情预览
│   │   ├── ViewModels/
│   │   │   ├── CharacterCardListViewModel.swift
│   │   │   └── CharacterCardEditorViewModel.swift
│   │   └── Models/
│   │       └── CharacterCardField.swift        # 编辑器字段枚举 / 校验规则
│   │
│   ├── WorldBook/
│   │   ├── Views/
│   │   │   ├── WorldBookListView.swift         # 世界书列表
│   │   │   ├── WorldBookEditorView.swift       # 世界书编辑器
│   │   │   ├── WorldBookEntryEditorView.swift  # 单条世界书条目编辑
│   │   │   └── WorldBookImportView.swift       # 结构化粘贴导入界面
│   │   ├── ViewModels/
│   │   │   ├── WorldBookListViewModel.swift
│   │   │   └── WorldBookEditorViewModel.swift
│   │   └── Models/
│   │       └── WorldBookImportFormat.swift     # 导入格式解析规则
│   │
│   ├── Conversation/
│   │   ├── Views/
│   │   │   ├── ConversationListView.swift      # 会话列表（侧边栏 / 主界面）
│   │   │   └── ConversationRowView.swift       # 单行会话摘要
│   │   └── ViewModels/
│   │       └── ConversationListViewModel.swift
│   │
│   ├── Memory/
│   │   ├── Views/
│   │   │   └── MemoryListView.swift            # 角色记忆列表界面
│   │   └── ViewModels/
│   │       └── MemoryListViewModel.swift       # 记忆列表状态管理
│   │
│   └── Settings/
│       ├── Views/
│       │   ├── SettingsView.swift              # 设置主界面
│       │   ├── APIEndpointEditorView.swift     # API 端点增删改
│       │   ├── ModelParametersView.swift       # 模型参数调节（滑杆等）
│       │   └── DataManagementView.swift        # 数据导出/导入/清除
│       └── ViewModels/
│           ├── SettingsViewModel.swift
│           └── APIEndpointEditorViewModel.swift
│
├── Core/
│   ├── Networking/
│   │   ├── APIClient.swift                 # OpenAI-compatible HTTP 请求封装（根据 apiMode 分发）
│   │   ├── SSEStreamParser.swift           # Server-Sent Events 流式解析器（支持 typed events）
│   │   ├── APIMode.swift                   # API 模式枚举（chatCompletions / responses）
│   │   ├── APIEndpointConfig.swift         # 端点配置 VO（URL / key / model / apiMode）
│   │   ├── APIRequest.swift                # Chat Completions 请求体构建
│   │   ├── APIResponse.swift               # Chat Completions 响应模型（ChatCompletion / StreamDelta）
│   │   ├── ResponsesAPIRequest.swift       # Responses API 请求体构建（system → instructions 提取）
│   │   ├── ResponsesAPIResponse.swift      # Responses API 响应模型 + 到统一类型的转换
│   │   ├── ModelParameters.swift           # 模型采样参数（含 API 模式过滤）
│   │   ├── ChatMessage.swift               # 消息结构体（role + content
│   │   ├── APIResponse.swift               # Chat Completions 响应模型（ChatCompletion / StreamDelta）
│   │   ├── ResponsesAPIRequest.swift       # Responses API 请求体构建（system → instructions 提取）
│   │   ├── ResponsesAPIResponse.swift      # Responses API 响应模型 + 到统一类型的转换
│   │   ├── ModelParameters.swift           # 模型采样参数（含 API 模式过滤）
│   │   ├── ChatMessage.swift               # 消息结构体（role + content）
│   │   └── APIError.swift                  # 统一错误类型
│   │
│   ├── PromptEngine/
│   │   ├── PromptAssembler.swift           # Prompt 拼装主逻辑
│   │   ├── PromptSegment.swift             # 拼装段定义（角色描述/场景/世界书/历史/记忆等）
│   │   ├── TokenCounter.swift              # Token 计数器（基于字符近似或 tiktoken）
│   │   └── TokenBudget.swift               # 各段 token 预算分配策略
│   │
│   ├── ContextManager/
│   │   ├── ContextManager.swift            # 上下文窗口管理主逻辑
│   │   ├── ContextStrategy.swift           # 策略协议 + 枚举（剔除 / 压缩）
│   │   ├── TruncationStrategy.swift        # 对话剔除：FIFO 删除最早消息
│   │   └── CompressionStrategy.swift       # 对话压缩：调用外部 API 压缩
│   │
│   ├── Memory/
│   │   ├── EmbeddingService.swift          # CoreML MultilingualE5Small 嵌入模型推理
│   │   ├── VectorStore.swift               # sqlite-vec 向量存储封装（插入/KNN检索/删除）
│   │   ├── MemoryManager.swift             # 记忆提取与检索编排
│   │   └── MemoryError.swift               # 记忆模块统一错误类型
│   │
│   └── Database/
│       ├── DatabaseManager.swift           # GRDB DatabaseQueue 初始化与迁移
│       ├── Migrations.swift                # 数据库版本迁移定义
│       └── Records/
│           ├── CharacterCardRecord.swift   # GRDB Record：角色卡
│           ├── WorldBookRecord.swift       # GRDB Record：世界书
│           ├── WorldBookEntryRecord.swift  # GRDB Record：世界书条目
│           ├── ConversationRecord.swift    # GRDB Record：会话
│           ├── MessageRecord.swift         # GRDB Record：消息
│           ├── MemoryEntryRecord.swift     # GRDB Record：记忆条目
│           └── APIEndpointRecord.swift     # GRDB Record：API 端点配置
│
├── Shared/
│   ├── Extensions/
│   │   ├── String+Token.swift              # 字符串 token 估算扩展
│   │   ├── Date+Formatting.swift           # 日期格式化
│   │   └── View+Modifiers.swift            # 通用 View modifier
│   ├── Components/
│   │   ├── MarkdownTextView.swift          # Markdown 渲染组件
│   │   ├── LoadingIndicator.swift          # 通用加载指示器
│   │   └── EmptyStateView.swift            # 空状态占位视图
│   └── Protocols/
│       └── Identifiable+Extensions.swift   # 通用协议扩展
│
└── Resources/
    ├── Assets.xcassets/                    # 图片/颜色资源
    ├── Localizable.xcstrings               # 本地化字符串
    └── DefaultPrompts.swift                # 内置默认 prompt 模板
```

## 分层职责

| 层 | 职责 | 依赖方向 |
|---|---|---|
| **App** | 应用生命周期、全局状态、依赖注入 | → Core, Features |
| **Features** | 业务功能模块，各自包含 Views / ViewModels / Models | → Core, Shared |
| **Core** | 业务无关的基础能力：网络、数据库、Prompt 引擎、上下文管理 | → Shared |
| **Shared** | 纯工具代码：扩展、通用 UI 组件、协议 | 无外部依赖 |

## 依赖规则

1. **单向依赖**：上层可以依赖下层，下层不可反向依赖上层
2. **Feature 间隔离**：Features 之间不直接引用，通过 App 层协调或通过 Core 层服务间接交互
3. **Core 模块间可横向引用**：例如 PromptEngine 可以引用 Database 中的 Record 类型
4. **ViewModel 持有 Core 服务引用**：通过初始化注入，不直接创建

## 第三方依赖

| 库 | 用途 | 引入层 |
|---|---|---|
| **GRDB.swift** | SQLite ORM + 迁移 | Core/Database |
| **sqlite-vec** | 向量相似度搜索 | Core/Memory |
| *(可选) swift-markdown-ui* | Markdown 渲染 | Shared/Components |

> 项目倾向于最小化第三方依赖，网络层和 SSE 解析均使用系统原生 API。
