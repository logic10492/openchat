# 角色卡模块设计

> 所属层：`Features/CharacterCard/`
> 依赖：Core/Database（CharacterCardRecord）, Shared/Components

## 1. 功能范围

- 角色卡的 CRUD（创建、查看、编辑、删除）
- 角色卡列表浏览与搜索筛选
- 角色卡详情预览
- 角色卡导入/导出（JSON 格式，兼容主流格式）
- 角色卡与会话的绑定

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `CharacterCardListView.swift` | 角色卡列表（支持 List 切换，搜索，标签筛选） |
| `CharacterCardEditorView.swift` | 角色卡编辑器（多 section 表单） |
| `CharacterCardDetailView.swift` | 角色卡只读详情预览 |
| `CharacterCardListViewModel.swift` | 列表数据加载、搜索、排序、删除 |
| `CharacterCardEditorViewModel.swift` | 编辑/创建的表单状态管理、校验、保存 |
| `CharacterCardField.swift` | 编辑器字段定义与校验规则 |

## 3. 数据结构

### 3.1 角色卡字段详述

基于 `CharacterCardRecord`（见 data-model.md），编辑器按以下 section 组织：

**Section 1: 基本信息**
| 字段 | UI 控件 | 必填 | 说明 |
|---|---|---|---|
| name | TextField | 是 | 角色名称，不超过 100 字符 |
| avatar | ImagePicker | 否 | 点击设置头像，支持从相册选择或拍照 |
| tags | TagEditor | 否 | 标签列表，用于列表筛选 |
| creatorNotes | TextEditor | 否 | 创作者备注，仅供管理用，不进入 prompt |
| worldBookId | Picker | 否 | 所属世界书（可选，从已有世界书列表中选择） |

**Section 2: 角色描述**
| 字段 | UI 控件 | 必填 | 说明 |
|---|---|---|---|
| personality | TextEditor | 否 | 性格描述，如 "温柔、内向、喜欢读书" |
| appearance | TextEditor | 否 | 外貌描述，如 "银色长发、蓝色瞳孔" |
| physique | TextEditor | 否 | 身材描述 |
| speechStyle | TextEditor | 否 | 说话风格/语调，如 "使用敬语、偶尔说古语" |
| backstory | TextEditor | 否 | 角色背景故事 |

**Section 3: 对话设定**
| 字段 | UI 控件 | 必填 | 说明 |
|---|---|---|---|
| systemPrompt | TextEditor | 否 | 自定义 system prompt（会覆盖默认模板） |
| scenario | TextEditor | 否 | 默认场景设定 |
| exampleDialogs | ExampleDialogEditor | 否 | 示例对话列表（可增删条目） |

### 3.2 示例对话格式

存储为 JSON 数组：
```json
[
  {"role": "user", "content": "你好，请问你是谁？"},
  {"role": "assistant", "content": "我是艾拉，银月森林的守护者。有什么我能帮助你的吗？"},
  {"role": "user", "content": "这里是哪里？"},
  {"role": "assistant", "content": "这里是银月森林的入口，前方就是精灵族的领地了。"}
]
```

编辑器中以对话气泡形式呈现，用户可逐条添加/编辑/删除/调整顺序。

## 4. 视图设计

### 4.1 CharacterCardListView

```
┌─────────────────────────────────────────┐
│ 角色卡                             [+]  │  ← 导航栏：标题 + 新建按钮
│─────────────────────────────────────────│
│ [🔍 搜索角色卡...]                       │  ← 搜索栏
│ [全部] [奇幻] [科幻] [日常] ...          │  ← 标签筛选（横向滚动）
│─────────────────────────────────────────│
│ ┌──────┬─────────────────────────┐      │
│ │ 头像 │ 名称                     │      │  ← List 模式
│ │      │ 标签 · 标签              │      │
│ ├──────┼─────────────────────────┤      │
│ │ 头像 │ 名称                     │      │
│ │      │ 标签                     │      │
│ └──────┴─────────────────────────┘      │
└─────────────────────────────────────────┘
```

- 列表模式：行显示头像+名称+标签
- 长按/左滑：删除、复制
- 点击：进入详情预览

> **实现证据**: `CharacterCardListView.swift` — 仅保留 List 模式，已移除 Grid 模式及视图切换 Picker

### 4.2 CharacterCardEditorView

```
┌─────────────────────────────────────────┐
│ [取消]    编辑角色卡           [保存]    │
│─────────────────────────────────────────│
│ Section: 基本信息                        │
│   [ 头像选择区域 ]                       │
│   名称: [_______________]               │
│   标签: [奇幻] [x] [添加+]              │
│   备注: [_______________]               │
│                                         │
│ Section: 角色描述                        │
│   性格: [多行文本编辑器]                 │
│   外貌: [多行文本编辑器]                 │
│   身材: [多行文本编辑器]                 │
│   语调: [多行文本编辑器]                 │
│   背景: [多行文本编辑器]                 │
│                                         │
│ Section: 对话设定                        │
│   System Prompt: [多行文本编辑器]        │
│   场景: [多行文本编辑器]                 │
│   示例对话:                             │
│     👤 你好，请问你是谁？               │
│     🤖 我是艾拉...                      │
│     [+ 添加对话]                        │
└─────────────────────────────────────────┘
```

- 使用 `Form` + `Section` 布局
- 保存时校验 name 非空
- 支持 dismiss 前提示未保存变更

### 4.3 CharacterCardDetailView

- 只读模式展示完整角色卡信息
- 顶部大头像 + 名称
- 各 section 折叠/展开
- 底部操作栏：编辑、复制、导出、删除
- 右上角"开始对话"快捷按钮 → 创建新会话并绑定此角色卡- **所属世界**：显示角色卡归属的世界书名称（若有）
- **记忆** section：显示该角色的记忆条目总数，点击进入 `MemoryListView`
## 5. ViewModel 设计

### 5.1 CharacterCardListViewModel

```swift
@Observable
final class CharacterCardListViewModel {
    // 状态
    private(set) var cards: [CharacterCardRecord] = []
    var searchText: String = ""
    var selectedTag: String? = nil

    // 计算属性
    var filteredCards: [CharacterCardRecord]  // 根据 searchText + selectedTag 过滤
    var allTags: [String]                    // 从所有卡片中提取去重的标签

    // 方法
    func loadCards() async
    func deleteCard(_ card: CharacterCardRecord) async throws
    func duplicateCard(_ card: CharacterCardRecord) async throws
}
```

### 5.2 CharacterCardEditorViewModel

```swift
@Observable
final class CharacterCardEditorViewModel {
    // 表单状态（与各字段一一对应）
    var name: String = ""
    var avatarData: Data? = nil
    var personality: String = ""
    var appearance: String = ""
    var physique: String = ""
    var speechStyle: String = ""
    var backstory: String = ""
    var systemPrompt: String = ""
    var scenario: String = ""
    var exampleDialogs: [ChatMessage] = []
    var tags: [String] = []
    var creatorNotes: String = ""

    // 编辑模式
    let editingCard: CharacterCardRecord?   // nil = 创建模式
    var hasUnsavedChanges: Bool

    // 校验
    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    var validationErrors: [String]

    // 方法
    func loadFromRecord(_ record: CharacterCardRecord)
    func save() async throws -> CharacterCardRecord
}
```

## 6. 导入/导出

### 6.1 导出格式

采用 JSON，字段名与 `CharacterCardRecord` 一致：

```json
{
  "formatVersion": 1,
  "type": "openchat_character_card",
  "data": {
    "name": "艾拉",
    "personality": "温柔、内向...",
    "appearance": "银色长发...",
    ...
    "exampleDialogs": [...]
  }
}
```

### 6.2 导入兼容

- 优先识别 OpenChat 自身格式
- 兼容 SillyTavern V2 Character Card 格式（`spec: "chara_card_v2"`）：
  - 映射 `description` → `personality`
  - 映射 `first_mes` → 首条示例对话
  - 映射 `mes_example` → `exampleDialogs`
  - 映射 `personality` → `personality`（追加）
  - 映射 `scenario` → `scenario`
- 通过 `Share Sheet` 或 `Files.app` 打开 `.json` 文件触发导入

### 6.3 导入/导出入口

- 列表页工具栏：导入按钮（选择文件 / 粘贴 JSON）
- 详情页操作栏：导出按钮 → ShareSheet / 保存到文件

## 7. 与其他模块的交互

| 交互对象 | 交互方式 |
|---|---|
| `Conversation` | 创建会话时选择角色卡 → `conversation.characterCardId`（世界书通过角色卡间接关联） |
| `WorldBook` | 角色卡通过 `worldBookId` 归属于世界书，世界书详情页可查看归属角色 |
| `PromptEngine` | 拼装时读取角色卡字段注入 system prompt、角色描述、场景、示例对话 |
| `Chat` | ChatView 顶部显示当前角色卡头像+名称，点击可查看/切换 |
| `Memory` | 角色卡关联的跨对话记忆条目，角色详情页提供记忆列表入口 |
