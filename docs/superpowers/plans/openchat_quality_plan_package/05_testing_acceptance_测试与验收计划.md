# 05. 测试与验收计划

## 当前测试基线

静态统计显示 `OpenChatTests` 下有 31 个 Swift 测试文件，约 5,067 行，`@Test` 计数 197 个。覆盖集中在：

- 数据库迁移与 memory 表。
- Endpoint model。
- APIClient、Responses API、Thinking 参数。
- SSE 解析。
- PromptAssembler、KeywordMatcher、TokenCounter。
- ContextManager、Compression checkpoint。
- Memory extraction/vector/retrieval。
- ChatViewModel prompt assembly。

这是一个好的基础，但还缺少 Feature 保存流、UI、导入导出、架构边界和错误路径测试。

## 测试分层建议

| 层级 | 目标 | 示例 |
|---|---|---|
| Unit | 纯函数/小模块正确性 | TokenCounter、KeywordMatcher、WorldBookParser。 |
| Service | Core 服务行为 | APIClient mock URLProtocol、DatabaseManager in-memory、MemoryManager mock embedding。 |
| Feature VM | 用户操作流 | 保存角色卡失败不 dismiss、endpoint 测试连接、导入预览。 |
| Integration | 多模块链路 | Chat send → prompt → stream → save assistant。 |
| Resource Integration | 真实模型资源 | CoreML embedding/tokenizer。资源缺失时 skip。 |
| Architecture | 源码边界 | Core 不引用 App，Shared 不引用 Core。 |
| UI/Snapshot | SwiftUI 视觉与交互 | Settings、Chat、Editor 基础快照。 |

## P0 测试补充

### API Key Keychain

- 保存新 endpoint：DB 无明文 key，Keychain 有 key。
- 编辑 endpoint 不改 key：Keychain 保持旧值。
- 清除 key：Keychain 删除。
- 删除 endpoint：Keychain 删除。
- 旧 DB 明文字段迁移：迁移后 DB 字段清空，Keychain 可读。

### 保存失败展示

- Mock DB 抛错，点击保存后：
  - View 不 dismiss。
  - `errorMessage` 有值。
  - 保存按钮恢复可用。
- 世界书导入多条，其中一条失败：错误列表可见，不静默丢弃。

### 流式生成取消

- 正常完成：assistant message 落库。
- 取消时未收到任何 delta：placeholder 被移除。
- 取消时已有 delta：partial assistant message 落库或按策略确认丢弃。
- 网络失败时已有 delta：UI/DB 一致。
- 任意路径后 `isGenerating == false`、`streamTask == nil`。

### sqlite-vec 清理

- 创建 memory_entry + memory_embedding。
- 调用 `eraseAllData()`。
- 验证 memory_entry 和 memory_embedding 均为空。

### 资源缺失 gating

- 移除 `OpenChat/Resources/Models` 后，普通 test target 仍能跑。
- 真实 Embedding tests 标记 skip，输出原因。

## P1 测试补充

### 架构边界测试

建议新增 `OpenChatTests/ArchitectureTests/LayeringTests.swift`，读取源码文本做规则扫描。

规则示例：

- `OpenChat/Core/**/*.swift` 不包含 `AppConstants`、`AppState`。
- `OpenChat/Shared/**/*.swift` 不包含 `TokenCounter`、`DatabaseManager`、`APIClient`。
- `OpenChat/Features/**/*.swift` 不 import/直接构造 sibling feature 的 View。
- `OpenChat/Features/**/*View.swift` 不直接访问 DatabaseManager/APIClient，除非通过 ViewModel init 参数装配。

### 数据库一致性

- 旧库多个 default endpoint：migration 后只剩一个。
- 旧库多个 default model：每 endpoint 只剩一个。
- 重复 sortOrder：migration 修复或抛出可诊断错误。
- 并发写入消息：不会重复 sortOrder。

### 导入导出

- 空库导出。
- 完整库导出。
- 导出后导入新库 round-trip。
- 冲突 ID：skip/overwrite/remap 三种策略。
- API Key 不导出。
- 导入失败事务回滚。

## P2 测试补充

### Prompt 防注入

- 世界书里包含“ignore previous instructions”时，Prompt 仍保持数据块边界。
- 记忆里包含伪 system 指令时，不改变 system prompt。
- 角色卡 system prompt 为空时 fallback 正常。

### 预算硬限制

- 单个世界书条目超过预算：被截断。
- 单个 example dialog 超预算：被截断或丢弃。
- memory 排序按 importance + relevance。
- totalUsed 不超过 `totalBudget + allowedSafetyMargin`。

### 世界书导入

- Markdown 标题解析。
- YAML front matter。
- priority clamp。
- 非法 position 报错。
- keywords 支持中文标点。
- 内容中包含 Markdown 标题符号不误分段。

## CI 建议

新增 workflow job：

1. `Generate Project`：运行 `ruby scripts/generate_xcodeproj.rb`，检查工作区无意外 diff。
2. `Build`：`xcodebuild -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' build`。
3. `Unit Tests`：无模型权重也可运行。
4. `Architecture Tests`：源码扫描。
5. `Resource Integration Tests`：仅在 submodule/secret 可用时运行。

## 验收发布门槛

发布前至少满足：

- P0 全部关闭。
- 普通 CI 绿色。
- DB migration tests 绿色。
- 导入导出 round-trip 绿色。
- API Key 不明文出现在 DB、导出包、日志和错误弹窗。
- 手动测试覆盖：新增 endpoint、测试连接、新建角色、新建世界书、聊天、停止生成、重开应用、导出/导入。
