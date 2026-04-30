# 世界书模块设计

> 所属层：`Features/WorldBook/`
> 依赖：Core/Database（WorldBookRecord, WorldBookEntryRecord）, Shared/Components

## 1. 功能范围

- 世界书的 CRUD（创建、查看、编辑、删除）
- 世界书条目的 CRUD
- 条目关键词触发机制（决定哪些条目注入 prompt）
- 结构化文本粘贴导入（方便用户从外部工具批量导入）
- 世界书与会话的绑定
- 世界书的启用/禁用管理

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `WorldBookListView.swift` | 世界书列表，显示所有世界书及其条目数量 |
| `WorldBookEditorView.swift` | 世界书编辑器，管理世界书基本信息及其条目列表 |
| `WorldBookEntryEditorView.swift` | 单个条目编辑器 |
| `WorldBookImportView.swift` | 结构化粘贴导入界面 |
| `WorldBookListViewModel.swift` | 列表数据管理 |
| `WorldBookEditorViewModel.swift` | 世界书及条目的编辑状态管理 |
| `WorldBookImportFormat.swift` | 导入格式定义与解析逻辑 |

## 3. 数据层级关系

```
WorldBook (世界书)
├── name: "中土世界"
├── description: "托尔金笔下的奇幻世界设定"
├── isEnabled: true
├── entries: [
│   ├── WorldBookEntry
│   │   ├── title: "精灵族"
│   │   ├── keywords: ["精灵", "elf", "瑞文戴尔"]
│   │   ├── content: "精灵是中土世界最古老的种族..."
│   │   ├── priority: 80
│   │   └── position: "after_system"
│   └── ...
│
└── characters: [                      ← 归属角色卡（通过 character_card.worldBookId 关联）
    ├── CharacterCard
    │   ├── name: "艾拉"
    │   └── worldBookId: "中土世界.id"
    └── ...
]
```

## 4. 关键词触发机制

### 4.1 触发时机

在 PromptAssembler 拼装 prompt 时执行关键词匹配：

1. 收集当前上下文中的文本（最近 N 条消息 + 当前用户输入）
2. 遍历当前会话绑定的世界书中所有已启用条目
3. 检查条目的 keywords 是否出现在上下文文本中
4. 命中的条目按 priority 降序排列
5. 在 token 预算内逐条注入 prompt

### 4.2 匹配规则

```swift
struct KeywordMatcher {
    /// 检查条目是否被当前上下文触发
    /// - contextText: 最近消息 + 用户输入的拼接文本
    /// - entry: 待检查的世界书条目
    /// - returns: 是否至少有一个关键词命中
    static func isTriggered(
        entry: WorldBookEntryRecord,
        contextText: String
    ) -> Bool
}
```

- **大小写不敏感**匹配
- **支持中文/日文等 CJK 字符**：直接子串匹配
- **英文单词**：全词匹配（前后为空格/标点/行首行尾）
- 条目 keywords 中任意一个命中即触发

### 4.3 注入位置

条目的 `position` 字段保留为既有数据兼容字段，不再控制最终 prompt 注入位置。当前实现会把所有当前轮命中的世界书条目按 priority 降序合并进 Current-Turn Context 的 `[World Book Entries]` system block。

| position 值 | 注入位置 | 典型用途 |
|---|---|---|
| `after_system` | 兼容旧数据；最终仍进入 `[World Book Entries]` block | 世界观基础设定 |
| `before_history` | 兼容旧数据；最终仍进入 `[World Book Entries]` block | 当前场景相关的动态知识 |

### 4.4 token 预算

- 世界书条目共享一个 token 预算池（由 PromptEngine 的 TokenBudget 分配）
- 按 priority 降序逐条扣减预算
- 预算耗尽时停止注入，低优先级条目被丢弃

## 5. 视图设计

### 5.1 WorldBookListView

```
┌─────────────────────────────────────────┐
│ 世界书                            [+]   │
│─────────────────────────────────────────│
│ ┌─ 中土世界 ──────────────── [开关] ──┐ │
│ │ 托尔金笔下的奇幻世界... · 12 条目   │ │
│ └─────────────────────────────────────┘ │
│ ┌─ 赛博朋克 2077 ──────── [开关] ──┐   │
│ │ 赛博朋克世界背景... · 8 条目      │   │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

- 每行显示：世界书名称 + 简介摘要 + 条目数 + 启用开关
- 左滑：删除
- 点击：进入世界书编辑器
- 右上角 [+]：新建世界书 / 粘贴导入

### 5.2 WorldBookEditorView

```
┌─────────────────────────────────────────┐
│ [返回]    中土世界             [导入]    │
│─────────────────────────────────────────│
│ Section: 基本信息                        │
│   名称: [中土世界___________]           │
│   简介: [托尔金笔下的奇幻世界设定]      │
│                                         │
│ Section: 角色 (3)                        │
│   ┌─ 🎭 艾拉 ─────────────────────────┐│
│   │  标签: 奇幻 · 精灵                 ││
│   └────────────────────────────────────┘│
│   ┌─ 🎭 甘道夫 ───────────────────────┐│
│   │  标签: 奇幻 · 巫师                 ││
│   └────────────────────────────────────┘│
│   [+ 新建角色] [↓ 从其他世界导入]       │
│                                         │
│ Section: 条目 (12)                       │
│   [🔍 搜索条目...]                      │
│   ┌─ 精灵族 ───── 优先级:80 ── [开关] ┐│
│   │  关键词: 精灵, elf, 瑞文戴尔       ││
│   └────────────────────────────────────┘│
│   ┌─ 霍比特人 ── 优先级:70 ── [开关] ┐ │
│   │  关键词: 霍比特, hobbit, 夏尔      │ │
│   └────────────────────────────────────┘│
│   [+ 添加条目]                          │
└─────────────────────────────────────────┘
```

- 上方编辑世界书基本信息
- **角色 section**：展示归属该世界的角色卡列表
  - 点击角色 → 进入角色卡详情
  - "新建角色"→ 创建角色卡并自动设置 worldBookId 为当前世界
  - "从其他世界导入"→ 选择已有角色卡复制到当前世界（生成新 ID，设置新 worldBookId）
- 下方管理条目列表
- 条目行显示：标题 + 关键词摘要 + 优先级 + 启用开关
- 点击条目 → 进入条目编辑器
- 支持拖拽排序（按 priority 重新赋值）

### 5.3 WorldBookEntryEditorView

```
┌─────────────────────────────────────────┐
│ [取消]    编辑条目             [保存]    │
│─────────────────────────────────────────│
│  标题: [精灵族_______________]          │
│                                         │
│  关键词:                                │
│  [精灵] [x] [elf] [x] [瑞文戴尔] [x]  │
│  [添加关键词...]                        │
│                                         │
│  内容:                                  │
│  [多行大文本编辑器                      │
│   精灵是中土世界最古老的种族，          │
│   他们不会自然死亡，拥有超凡的           │
│   感官和优雅的举止...                   │
│  ]                                      │
│                                         │
│  优先级: [====●=====] 80               │
│  注入位置: (●) system后  ( ) 历史前     │
│  启用: [开关]                           │
└─────────────────────────────────────────┘
```

- keywords 使用 TagEditor 风格的 UI
- content 使用大面积 TextEditor
- priority 使用 Slider (0-100)
- position 使用 Picker/SegmentedControl

## 6. 结构化导入

### 6.1 设计思路

用户可以先用 ChatGPT 等工具根据 wiki 页面按指定格式输出世界书内容，然后粘贴到 OpenChat 中导入。

### 6.2 导入格式规范

**Markdown 格式**（方便用户在 ChatGPT 等工具中生成）：

```markdown
## 精灵族
- keywords: 精灵, elf, 瑞文戴尔, 精灵族
- priority: 80
- position: after_system

精灵是中土世界最古老的种族，他们不会自然死亡，拥有超凡的感官和优雅的举止。
精灵分为多个族群：诺多精灵、辛达精灵、西尔凡精灵等。

## 霍比特人
- keywords: 霍比特, hobbit, 夏尔, 霍比特人
- priority: 70
- position: before_history

霍比特人身材矮小，通常不超过四英尺，喜欢和平安逸的生活。
他们居住在舒适的地洞中，热爱美食和烟草。
```

**解析规则**：
1. `## 标题` → 条目 title
2. `- keywords: a, b, c` → 条目 keywords 数组
3. `- priority: N` → 条目 priority（可选，默认 50）
4. `- position: xxx` → 条目 position（可选，默认 `before_history`）
5. 元数据行之后的正文 → 条目 content

### 6.3 WorldBookImportView

```
┌─────────────────────────────────────────┐
│ [取消]    导入世界书           [导入]    │
│─────────────────────────────────────────│
│ 请将按格式整理好的世界书内容粘贴到下方：│
│                                         │
│ [大面积文本输入框                        │
│  ## 精灵族                              │
│  - keywords: 精灵, elf                  │
│  ...                                    │
│ ]                                       │
│                                         │
│ [查看格式说明]                          │
│                                         │
│ ── 预览 ──                              │
│ 解析到 5 个条目：                        │
│  ✅ 精灵族 (3 个关键词)                 │
│  ✅ 霍比特人 (4 个关键词)               │
│  ⚠️ 矮人族 (缺少关键词，将使用标题)    │
│  ...                                    │
└─────────────────────────────────────────┘
```

- 粘贴文本后实时解析预览
- 显示每个条目的解析状态（成功/警告/错误）
- 确认导入后批量插入数据库

### 6.4 导入格式解析器

```swift
struct WorldBookImportFormat {
    struct ParsedEntry {
        var title: String
        var keywords: [String]
        var content: String
        var priority: Int
        var position: String
        var warnings: [String]       // 解析警告（如缺少关键词）
    }

    /// 解析 Markdown 格式的世界书文本
    static func parse(text: String) -> [ParsedEntry]

    /// 提供给用户的格式说明文本
    static var formatGuide: String
}
```

## 7. ViewModel 设计

### 7.1 WorldBookListViewModel

```swift
@Observable
final class WorldBookListViewModel {
    private(set) var worldBooks: [WorldBookWithCount] = []

    struct WorldBookWithCount {
        let worldBook: WorldBookRecord
        let entryCount: Int
    }

    func loadWorldBooks() async
    func deleteWorldBook(_ id: String) async throws
    func toggleEnabled(_ id: String) async throws
}
```

### 7.2 WorldBookEditorViewModel

```swift
@Observable
final class WorldBookEditorViewModel {
    // 世界书基本信息
    var name: String = ""
    var description: String = ""

    // 条目列表
    private(set) var entries: [WorldBookEntryRecord] = []
    var searchText: String = ""
    var filteredEntries: [WorldBookEntryRecord]

    let editingWorldBook: WorldBookRecord?  // nil = 创建模式

    func loadEntries() async
    func saveWorldBook() async throws -> WorldBookRecord
    func deleteEntry(_ id: String) async throws
    func toggleEntryEnabled(_ id: String) async throws
    func importEntries(from text: String) async throws -> [WorldBookImportFormat.ParsedEntry]
    func confirmImport(_ entries: [WorldBookImportFormat.ParsedEntry]) async throws
}
```

## 8. 与其他模块的交互

| 交互对象 | 交互方式 |
|---|---|
| `CharacterCard` | 角色卡通过 `worldBookId` 归属于世界书，世界书详情页展示归属角色列表，支持跨世界导入角色 |
| `Conversation` | 对话不再直接关联世界书，世界书通过角色卡间接关联到对话 |
| `PromptEngine` | 拼装时通过角色卡的 worldBookId 查询已启用条目 → KeywordMatcher 匹配 → 按 priority 注入 |
| `Chat` | ChatView 中可查看当前绑定的世界书和触发的条目（调试用） |

## 9. ChatGPT 辅助生成世界书的推荐 prompt

提供给用户参考的 prompt 模板（在格式说明中展示）：

```
请根据以下 Wiki 页面内容，按照下面的格式输出世界书条目：

格式要求：
- 每个条目以 "## 条目标题" 开头
- 第二行 "- keywords: 关键词1, 关键词2, ..." 列出触发关键词
- 第三行 "- priority: 数字" 设置优先级（0-100，越大越重要）
- 之后空一行写条目正文描述

Wiki 链接：{用户提供的链接}

请提取其中的重要概念、地点、角色、组织等，每个作为一个条目输出。
```
