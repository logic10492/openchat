# 07. 架构分层修复计划

## 当前目标架构

项目文档定义的方向是：

```text
App → Features → Core → Shared
```

含义：

- App 负责入口、全局状态、依赖注入、跨 Feature 组合。
- Features 负责具体业务 UI/ViewModel。
- Core 负责数据库、网络、Prompt、上下文、记忆等基础能力。
- Shared 只放不依赖上层的通用扩展、组件、协议。

## 当前漂移点

| 漂移 | 证据 | 风险 |
|---|---|---|
| Core 依赖 App 常量 | `PromptAssembler`、`MemoryManager`、`TitleGenerator`、`DatabaseManager+EndpointModels` 使用 `AppConstants` | Core 无法独立测试/复用，依赖方向反转。 |
| Feature VM 持有 AppState | `ChatViewModel.swift:13` | Feature 与 App 全局状态耦合。 |
| Feature 目录承载 App shell | `Features/Support/SidebarView.swift` 组合多个 Feature | Feature sibling 直接耦合。 |
| WorldBook 直接打开 CharacterCard UI | `WorldBookEditorView` | Feature 间依赖扩大。 |
| Shared 调 Core | `Shared/Extensions/String+Token.swift:3-6` 调 `TokenCounter` | Shared 不再是底层。 |

## 修复原则

1. **先迁移常量，再改调用点**：避免大范围同时改 Prompt/Memory 逻辑。
2. **App shell 统一收口跨 Feature 导航**：Feature 内只暴露自己的 View 与事件。
3. **以测试封锁回归**：修复后马上加源码边界测试。
4. **不追求一次性完美**：允许短期保留受控例外，但必须文档化并有 TODO 截止。

## Step 1：Core 常量归属

新增：

```swift
struct CoreDefaults: Sendable {
    var defaultMaxContextTokens: Int
    var defaultTemperature: Double
    var slowPlotModePrompt: String
}
```

或拆成：

- `PromptDefaults`
- `ModelDefaults`
- `MemoryDefaults`

把 Core 需要的默认值移入 Core 层。AppConstants 只保留 UI/App 层显示相关常量。

## Step 2：ChatViewModel 去 AppState

当前：

```swift
let appState: AppState
appState.present(error: ...)
appState.conversationListNeedsRefresh = true
```

改为：

```swift
struct ChatViewModelActions: Sendable {
    var presentError: @MainActor @Sendable (String) -> Void
    var markConversationListNeedsRefresh: @MainActor @Sendable () -> Void
}
```

App 层创建 VM 时注入闭包。

## Step 3：SidebarView 移到 App

将：

```text
OpenChat/Features/Support/SidebarView.swift
```

迁到：

```text
OpenChat/App/Views/SidebarView.swift
```

同时更新 Xcode project 生成脚本或重新生成 project。

## Step 4：WorldBook 与 CharacterCard 解耦

当前 WorldBook 编辑器直接创建 CharacterCard 编辑/详情 View。改为：

```swift
enum WorldBookEditorEvent {
    case openCharacterDetail(id: String)
    case openCharacterEditor(id: String?)
}
```

WorldBook Feature 发事件，App route 接收后打开对应 CharacterCard 页面。

## Step 5：String+Token 归位

选项 A：删除 `String.approximatedTokenCount`，调用点直接用 `TokenCounter.count`。

选项 B：把扩展移动到 `Core/PromptEngine/String+Token.swift`。

推荐 A，减少魔法扩展。

## Step 6：架构边界测试

新增测试文件，扫描源码内容：

```swift
@Test func coreDoesNotDependOnApp() throws { ... }
@Test func sharedDoesNotDependOnCore() throws { ... }
@Test func featuresDoNotDependOnAppState() throws { ... }
@Test func featureSiblingsAreNotDirectlyComposed() throws { ... }
```

## 验收标准

- [ ] `OpenChat/Core` 不引用 `AppConstants`、`AppState`。
- [ ] `OpenChat/Shared` 不引用 Core 类型。
- [ ] Feature VM 不持有 App 全局状态。
- [ ] App shell 负责跨 Feature 组合。
- [ ] 架构边界测试加入 CI。
- [ ] `arch/source-tree.md` 更新。
- [ ] `arch/AntiEntropy/layering-repair-plan.md` 标记完成或记录剩余例外。
