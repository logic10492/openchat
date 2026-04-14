---
description: "Use when creating or modifying SwiftUI views, view modifiers, or UI components in the OpenChat project. Covers MVVM binding, layout, navigation, and accessibility."
applyTo: "**/Views/**/*.swift"
---
# SwiftUI 视图层规范

## MVVM 绑定

- View 通过 `@State private var viewModel` 持有 ViewModel（页面级）
- 子组件通过 `@Binding` 或 closure 回调接收数据，不直接持有 ViewModel
- View 内不包含业务逻辑：不直接调用数据库、网络、PromptEngine
- View 内可包含纯 UI 逻辑（动画状态、sheet 展示标记等）

```swift
// ✅ 正确
struct ChatView: View {
    @State private var viewModel: ChatViewModel
    var body: some View {
        MessageList(messages: viewModel.messages)
        InputBarView(text: $viewModel.inputText, onSend: { Task { await viewModel.sendMessage() } })
    }
}

// ❌ 错误：View 直接操作数据库
struct ChatView: View {
    let db: DatabaseManager
    var body: some View { /* db.fetch(...) */ }
}
```

## ViewModel 规范

- 使用 `@Observable final class`，不使用 `ObservableObject` + `@Published`
- 外部只读状态使用 `private(set)`
- 异步方法标记 `async`，View 中通过 `Task {}` 调用
- 初始化通过 init 注入依赖，不使用 `@Environment` 注入 Core 服务

```swift
@Observable
final class ChatViewModel {
    private let db: DatabaseManager
    private let apiClient: APIClient

    private(set) var messages: [MessageDisplayItem] = []
    private(set) var isGenerating = false
    var inputText = ""

    init(db: DatabaseManager, apiClient: APIClient, conversation: ConversationRecord) { ... }

    func sendMessage() async { ... }
}
```

## 布局

- 优先使用 `List` / `LazyVStack` 处理长列表（消息列表等）
- 表单界面使用 `Form` + `Section`
- 避免深层嵌套（超过 3 层时提取子视图）
- 使用 `ViewThatFits` 或 `GeometryReader` 做自适应布局时注明原因

## 导航

- 使用 `NavigationStack` + `navigationDestination(for:)`，不使用 `NavigationLink(destination:)`
- Sheet 使用 `sheet(item:)` 或 `sheet(isPresented:)`
- 导航状态由 ViewModel 或父视图管理

## 组件提取

- 超过 40 行的 View body 必须提取子组件
- 可复用组件放 `Shared/Components/`
- 模块专用子组件放在该模块的 `Views/` 下
- 子组件通过参数接收数据，不依赖父组件具体类型

## 预览

- 每个 View 文件提供 `#Preview {}`
- Preview 使用 mock 数据，不依赖真实数据库或网络
- 复杂组件提供多个 Preview 变体（空状态、加载中、错误状态、正常数据）

## 性能

- 消息列表使用 `LazyVStack` 而非 `VStack`
- 图片（头像）使用合理的 resize 后再显示，不加载原图到内存
- 流式输出更新：若逐 token 更新导致卡顿，引入 50ms 节流
- 避免在 `body` 中做计算，移到 ViewModel 的计算属性

## 可访问性

- 所有可交互元素有 `accessibilityLabel`
- 图标按钮必须有 label（不只是图标）
- 列表项有合理的 `accessibilityHint`
