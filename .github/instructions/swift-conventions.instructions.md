---
description: "Use when writing any Swift code. Covers naming, types, concurrency, error handling, and general Swift idioms for the OpenChat project."
applyTo: "**/*.swift"
---
# Swift 语言规范

## 命名

- 类型名 `PascalCase`，变量/函数 `camelCase`，常量 `camelCase`
- 协议名使用形容词（`Sendable`）或 `-able`/`-ible` 后缀，描述能力而非身份
- 布尔变量使用 `is`/`has`/`should` 前缀: `isEnabled`, `hasUnsavedChanges`
- 工厂方法使用 `make` 前缀: `makeDefaultConfig()`

## 类型选择

- 优先 `struct`，仅在需要引用语义/继承/deinit 时用 `class`
- ViewModel 使用 `class` + `@Observable`（需要引用语义和 SwiftUI 观察）
- 数据库 Record 使用 `struct` + `Codable + FetchableRecord + PersistableRecord`
- 网络请求/响应模型使用 `struct` + `Codable`
- 错误类型使用 `enum` + `LocalizedError`
- 配置/选项使用 `struct`

## Swift Concurrency

- 所有异步操作使用 `async/await`，不使用 Combine、DispatchQueue、回调闭包
- 网络请求、数据库读写均为 `async throws`
- 流式数据使用 `AsyncThrowingStream` 或 `AsyncSequence`
- 可取消操作持有 `Task` 引用，通过 `task.cancel()` 取消
- 无共享可变状态的类型标记 `Sendable`
- `@MainActor` 仅用于 ViewModel 和 View 相关代码

## 错误处理

- 每个模块定义自己的错误枚举: `APIError`, `DatabaseError`, `PromptError`
- 错误枚举实现 `LocalizedError`，提供 `errorDescription`
- 不使用 `try!` 或 `force unwrap`（除非在测试中且有明确注释）
- `guard let` 优先于 `if let` 用于 early return

## 可选值

- 优先 `guard let` early return，避免深层嵌套
- 使用 `??` 提供合理默认值
- 使用 `map`/`compactMap` 处理集合中的可选值
- 不使用隐式解包可选值 (`!`) 除非 `@IBOutlet`（本项目无 UIKit 故不应出现）

## 集合

- 优先使用 `map`/`filter`/`reduce` 而非手动循环
- 大集合操作考虑 `lazy`
- 空集合检查用 `.isEmpty` 而非 `.count == 0`

## 访问控制

- 默认 `internal`（不显式标注）
- ViewModel 的方法和计算属性: `internal`（View 可见）
- ViewModel 的可变状态: `private(set)` 对外只读
- Core 层对外暴露的接口: `internal`（同 module）
- 纯实现细节: `private`
- 不使用 `open` 或 `public`（单 target 项目）

## 字符串

- 用户可见文本放入 `Localizable.xcstrings`，代码中使用 `String(localized:)`
- 日志/调试文本可硬编码
- 多行字符串使用 `"""`
- 字符串拼接优先使用插值 `\(variable)` 而非 `+`

## 文件组织

每个 `.swift` 文件内部按以下顺序排列：
1. `import` 声明
2. 类型定义（属性 → init → 方法）
3. `extension` 分组（协议一致性各自一个 extension）
4. `private` 辅助函数

单个文件不超过 300 行。超过时按职责拆分。
