# 落地路线图

## 概述

项目分 6 个阶段推进，每个阶段产出可独立验证的成果。后一阶段依赖前一阶段的产物。

## 当前落地状态（2026-05-17）

- 工程基线已落地：`OpenChat.xcodeproj`、`OpenChat` app target、`OpenChatTests` test target、GRDB Swift Package、四层源码目录
- 自动化验证已通过：
  - `xcodebuild -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
  - `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- 当前通过的 Swift Testing 测试（319 个 / 61 suites）覆盖：
  - `MigrationTests`
  - `SSEStreamParserTests` + `SSEParserTypedEventsTests`
  - `APIClientTests` + `APIClientResponsesModeTests`
  - `DeepSeekV4RequestTests`
  - `ResponsesAPIRequestTests` + `ResponsesAPIResponseTests`
  - `ModelParametersAPIModeTests`
  - `TitleGeneratorTests`
  - `PromptAssemblerTests`
  - `KeywordMatcherTests`
  - `TokenCounterTests`
  - `TruncationStrategyTests`
  - `CompressionStrategyTests`
  - `CompressionPolicyTests`
  - `CompressionSourceHasherTests`
  - `PreparedHistoryTests`
  - `CompressionSummarizerTests`
  - `CheckpointCompactorTests`
  - `CompressionCheckpointReuseTests`
  - `CompressionCheckpointDatabaseTests`
  - `DatabaseManager+MemoryTests`
  - `ModelObjectTests`
  - `EmbeddingServiceTests`
  - `VectorStoreTests`
  - `MemoryManagerRetrievalTests`
  - `MemoryReflectModelsTests`
  - `MemoryExtractionParsingTests`
  - `MemoryExtractionCutoffTests`
  - `MemoryExtractionPhaseTests`
  - `WorldBookVectorStoreTests`
  - `WorldBookEmbeddingTextBuilderTests`
  - `WorldBookEntryHasherTests`
  - `WorldBookEmbeddingIndexerTests`
  - `WorldBookSourceTests`
  - `DatabaseManagerWorldBookTests`
  - `WorldBookEditorViewModelTests`
  - `SettingsViewModelWorldBookIndexTests`
  - `ChatViewModelPromptAssemblyTests`
  - `CriticalSaveFlowTests`
  - `APIEndpointEditorViewModelSecurityTests`
  - `AgentDescriptorTests`
  - `AgentPolicyTests`
  - `DeterministicAgentExecutorTests`
  - `AgentDiagnosticsTests`
  - `MemoryRecallToolTests`
  - `WorldBookRecallToolTests`
  - `BackgroundSourceTests`
- 已补齐的工程实现证据：
  - 工程生成与 target 依赖：`scripts/generate_xcodeproj.rb`
  - App 装配：`OpenChat/OpenChatApp.swift`、`OpenChat/App/DependencyContainer.swift`
  - Core 数据库：`OpenChat/Core/Database/*`
  - Core 网络：`OpenChat/Core/Networking/*`
  - Core Prompt/Context：`OpenChat/Core/PromptEngine/*`、`OpenChat/Core/ContextManager/*`
  - Core WorldBook vectorization：`OpenChat/Core/WorldBook/*`
  - Core AgentCore foundation：`OpenChat/Core/AgentCore/*`
  - Features：`OpenChat/Features/Chat/*`、`OpenChat/Features/CharacterCard/*`、`OpenChat/Features/WorldBook/*`、`OpenChat/Features/Settings/*`
- 说明：当前代码已经具备后续 Phase 所需的大部分骨架与核心实现，但仍建议继续按本路线图做逐阶段 UI 冒烟、交互完善与文档收口，不把“已编译/已测试”误判为“所有用户路径都已验收”

---

## Phase 1: 基础骨架

**目标**：搭建项目结构、数据库层、API 客户端，实现最简可用的聊天功能。

### 任务

1. 创建 Xcode 项目，按 `source-tree.md` 建立目录结构
2. 引入 GRDB.swift（Swift Package Manager）
3. 实现 `DatabaseManager`：初始化 + v1 迁移（全部 6 张表）
4. 实现所有 GRDB Record 类型
   - `APIMode` 枚举：Chat Completions / Responses API 双模式支持
   - 适配器模式：根据 `endpoint.apiMode` 分发请求，上层透明
6. 实现 `APIEndpointConfig`、`APIRequest`、`APIResponse`、`ResponsesAPIRequest`、`Responses
   - `sendMessage()` 非流式请求
   - `streamMessage()` 流式请求
   - `SSEStreamParser` SSE 解析
   - `APIMode` 枚举：Chat Completions / Responses API 双模式支持
   - 适配器模式：根据 `endpoint.apiMode` 分发请求，上层透明
6. 实现 `APIEndpointConfig`、`APIRequest`、`APIResponse`、`ResponsesAPIRequest`、`ResponsesAPIResponse`、`APIError`
7. 实现最简 `ChatView` + `ChatViewModel`：
   - 硬编码 API 端点
   - 消息列表展示
   - 输入栏发送
   - 流式输出显示
8. 实现 `ContentView` 基础导航结构

### 产出

- 可编译运行的 iOS App
- 可连接本地模型或 OpenAI API 进行基础对话
- 流式输出正常工作

### 验证标准

- [ ] App 启动无崩溃
- [ ] 数据库正确创建所有表
- [ ] 输入文本并发送后，能收到 AI 流式回复
- [ ] 消息正确保存到数据库，重启后可恢复

---

## Phase 2: 设置与端点管理

**目标**：允许用户配置 API 端点和模型参数，取代硬编码。

### 任务

1. 实现 `SettingsView` 主界面
2. 实现 `APIEndpointEditorView` + `APIEndpointEditorViewModel`
   - 端点 CRUD
   - 连接测试
   - 设置默认端点
3. 实现 `ModelParametersView`：全局默认参数调节
4. 实现 `SettingsViewModel`：UserDefaults 读写
5. 实现 `ConversationListView` + `ConversationListViewModel`：
   - 会话列表
   - 创建新会话
   - 删除会话
6. 改造 `ChatViewModel`：从 DB 读取端点配置，应用全局/会话参数

### 产出

- 完整的设置界面
- 多端点配置管理
- 会话列表管理

### 验证标准

- [ ] 可添加/编辑/删除 API 端点
- [ ] 连接测试功能正常
- [ ] 可切换不同端点进行对话
- [ ] 模型参数调节后影响 API 请求
- [ ] 多会话独立工作

---

## Phase 3: 角色卡系统

**目标**：实现角色卡 CRUD 和基础 prompt 注入。

### 任务

1. 实现 `CharacterCardListView` + `CharacterCardListViewModel`
   - Grid/List 视图切换
   - 搜索、标签筛选
2. 实现 `CharacterCardEditorView` + `CharacterCardEditorViewModel`
   - 分 section 表单
   - 校验与保存
3. 实现 `CharacterCardDetailView`
4. 实现角色卡导入/导出（JSON 格式）
5. 会话创建时选择角色卡
6. 实现基础 `PromptAssembler`（仅处理角色卡字段注入）：
   - system prompt
   - 角色描述拼接
   - 场景设定
   - 示例对话
7. `ChatView` 导航栏显示角色卡头像和名称

### 产出

- 完整的角色卡管理界面
- 角色卡字段注入 prompt
- 角色扮演对话基本可用

### 验证标准

- [ ] 可创建/编辑/删除角色卡
- [ ] 角色卡各字段正确注入到 API 请求的 messages 中
- [ ] 示例对话正确以 `[Example Dialogs]` labeled system block 注入
- [ ] 导入/导出功能正常
- [ ] 切换角色卡后对话风格明显改变

---

## Phase 4: 世界书系统

**目标**：实现世界书 CRUD 和关键词触发注入。

### 任务

1. 实现 `WorldBookListView` + `WorldBookListViewModel`
2. 实现 `WorldBookEditorView` + `WorldBookEditorViewModel`
3. 实现 `WorldBookEntryEditorView`
4. 实现 `WorldBookImportView` + `WorldBookImportFormat` 导入解析器
5. 实现 `KeywordMatcher`：关键词匹配算法
6. 扩展 `PromptAssembler`：
   - 世界书条目动态注入（`after_system` / `before_history` 作为旧数据兼容字段，最终统一进入 `[World Book Entries]` block）
   - 按 priority 排序注入
7. 会话创建/设置中选择世界书
8. `ChatSettingsSheet` 基础版本

### 产出

- 完整的世界书管理界面
- 结构化粘贴导入功能
- 关键词触发动态注入

### 验证标准

- [ ] 可创建世界书并添加条目
- [ ] 关键词匹配正确触发条目注入（CJK + 英文）
- [ ] 按 priority 排序注入
- [ ] 旧 position 字段不拆分最终位置，命中条目统一进入 `[World Book Entries]` block
- [ ] 粘贴导入正确解析 Markdown 格式
- [ ] 启用/禁用开关即时生效

---

## Phase 5: 上下文管理

**目标**：实现完整的 token 预算系统和上下文缩减策略。

### 任务

1. 实现 `TokenCounter`：近似 token 计数算法
2. 实现 `TokenBudget`：各段预算分配策略
3. 完善 `PromptAssembler`：
   - 完整的预算计算与分配
   - 超预算自动裁剪
   - 两阶段调用（固定段计算 → 历史处理 → 最终拼装）
4. 实现 `ContextManager`：
   - TruncationStrategy：FIFO 剔除
   - CompressionStrategy：调用 API 压缩
5. 实现 `ChatSettingsSheet` 完整版：上下文策略选择 + 模型参数覆盖
6. 实现 Token 使用情况展示（ChatView 导航栏 📊）
7. 设置中添加：默认上下文策略 + 压缩端点配置

### 产出

- 完整的 token 预算管理
- 两种上下文缩减策略可用
- Token 使用透明可见

### 验证标准

- [ ] Token 计数与 tiktoken 误差在 ±15% 以内
- [ ] 40% 上下文限制正确执行
- [ ] 对话剔除策略正确保留最近消息
- [ ] 对话压缩策略成功调用 API 生成摘要
- [ ] 压缩结果持久化，不重复压缩
- [ ] Token 使用报告数值准确
- [ ] 会话级策略覆盖全局默认

---

## Phase 6: 打磨与优化

**目标**：UI 完善、性能优化、边界情况处理、数据管理。

### 任务

1. **消息交互完善**：
   - 消息编辑
   - 重新生成
   - 删除
   - 长按菜单
2. **UI 打磨**：
   - Markdown 渲染优化
   - 流式光标动画
   - 自动滚动优化
   - 空状态界面
   - 加载状态
3. **数据管理**：
   - 全量数据导出/导入
   - 数据清除
   - 导出安全提醒
4. **性能优化**：
   - 大量消息列表的懒加载
   - 数据库查询优化（分页加载消息）
   - 流式输出节流
5. **错误处理**：
   - 统一错误弹窗/Toast
   - 网络断开恢复
   - 数据库错误恢复
6. **边界情况**：
   - 空角色卡/世界书时的 fallback
   - API 端点被删除后的会话处理
   - 超大消息处理

### 产出

- 生产质量的完整应用
- 良好的错误处理和用户体验

### 验证标准

- [ ] 消息编辑/重新生成/删除功能正常
- [ ] Markdown 渲染正确（粗体/斜体/代码块/列表）
- [ ] 100+ 条消息列表滚动流畅
- [ ] 数据导出/导入完整可恢复
- [ ] 各类错误有友好提示
- [ ] 无崩溃、无数据丢失

---

## 阶段依赖关系

```
Phase 1 (基础骨架)
    │
    ├── Phase 2 (设置与端点管理)
    │       │
    │       ├── Phase 3 (角色卡系统)
    │       │       │
    │       │       └── Phase 4 (世界书系统)
    │       │               │
    │       │               └── Phase 5 (上下文管理)
    │       │                       │
    │       │                       └── Phase 6 (打磨与优化)
    │       │                               │
    │       │                               └── Phase 7 (跨对话记忆系统)
    │       │
    │       └─────────────────────────┘
    │
    └─────────────────────────────────┘
```

每个 Phase 完成后应可独立运行和测试。

---

## Phase 7: 跨对话记忆系统

**目标**：实现同一角色跨对话的记忆存储与语义检索，重构世界→角色层级关系。

### 前置重构

1. 数据库迁移 v2：`character_card` 表新增 `worldBookId` 外键（角色卡归属世界书）
2. 数据库迁移 v3：`conversation` 表移除 `worldBookId` 列（世界书通过角色卡间接关联）
3. 更新导航流程：世界书详情页包含归属角色列表，支持跨世界导入角色

### 记忆系统

4. 集成 sqlite-vec SPM 包
5. 数据库迁移 v4：创建 `memory_entry` 表 + `memory_embedding` sqlite-vec 虚拟表
6. 解压并编译 MultilingualE5Small CoreML 模型，加入 App Bundle
7. 实现 `EmbeddingService`：CoreML 推理 + XLMRobertaTokenizer 分词，输出 384 维归一化向量
8. 实现 `VectorStore`：sqlite-vec 向量 CRUD 封装（插入 / KNN 检索 / 删除）
9. 实现 `MemoryManager`：记忆提取（调用 API 提取结构化事件）+ 语义检索编排
10. 更新 `PromptSegment` + `PromptAssembler`：记忆作为 `[Memories]` block 注入 Current-Turn Context，时间上下文并入 `.currentTurn`，记忆 token 预算上限为剩余预算的 15%
11. 更新 `ChatViewModel`：发送消息时检索记忆、离开对话时触发记忆提取
12. 实现 `MemoryListView` + `MemoryListViewModel`：按角色查看/删除记忆
13. 更新 `DependencyContainer`：注入 `MemoryManager`、`EmbeddingService`、`VectorStore`

### 产出

- 角色卡归属世界书的层级导航
- 周期阈值和视图消失时触发记忆提取入口
- 新对话和每次发送时语义检索记忆注入 prompt
- 记忆管理界面

### 验证标准

- [x] sqlite-vec 向量插入和 KNN 检索结果正确（`VectorStoreTests`）
- [x] CoreML 模型输出 384 维归一化向量（`EmbeddingServiceTests`）
- [x] 记忆提取执行后可原子存储；失败时不留下半索引记忆（`MemoryManagerRetrievalTests`、`VectorStoreTests`）
- [ ] 周期阈值与 `ChatView.onDisappear` 自动触发路径有端到端测试覆盖
- [x] 新对话和每次发送时相关记忆可检索并注入 prompt；语义检索失败时 fallback 到近期记忆（`MemoryManagerRetrievalTests`、`ChatViewModelPromptAssemblyTests`）
- [ ] 导航流正确：世界列表 → 角色列表 → 对话
- [ ] 记忆列表可查看/搜索/删除
- [ ] 数据库迁移 v2/v3/v4 后数据完整性保持
- [ ] 时间上下文始终注入 prompt（ISO 8601 格式）
- [ ] 所有现有测试仍通过

---

## Agent 开发指引

每个 Phase 交给 agent 开发时，应提供：

1. **本 Phase 的任务文档**（上述对应章节）
2. **相关模块设计文档**（`arch/modules/` 中的对应文件）
3. **数据模型文档**（`arch/data-model.md`）
4. **源码目录结构**（`arch/source-tree.md`）
5. **上一个 Phase 的产出代码**（作为基础）

Agent 完成后应：
1. 代码编译通过
2. 满足验证标准中的所有 checklist
3. 不破坏已有功能
