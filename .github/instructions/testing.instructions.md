---
description: "Use when writing unit tests, integration tests, or setting up test infrastructure for the OpenChat project. Covers test structure, mocking, naming, and what to test."
applyTo: "**/*Tests*/**/*.swift"
---
# 测试规范

## 测试框架

- 使用 Swift Testing (`import Testing`)，不使用 XCTest
- 使用 `@Test` 标注测试函数
- 使用 `#expect()` 断言，不使用 `XCTAssert`

## 测试结构

```
OpenChatTests/
├── Core/
│   ├── NetworkingTests/
│   │   ├── SSEStreamParserTests.swift
│   │   └── APIClientTests.swift
│   ├── PromptEngineTests/
│   │   ├── PromptAssemblerTests.swift
│   │   ├── TokenCounterTests.swift
│   │   └── KeywordMatcherTests.swift
│   ├── ContextManagerTests/
│   │   ├── TruncationStrategyTests.swift
│   │   └── CompressionStrategyTests.swift
│   └── DatabaseTests/
│       └── MigrationTests.swift
└── Features/
    └── (ViewModel tests as needed)
```

## 命名

- 测试文件: `{被测类型}Tests.swift`
- 测试函数: `test_{场景}_{预期结果}` 或描述性名称

```swift
@Test func test_tokenCounter_cjkText_countsCorrectly() { ... }
@Test func test_truncation_exceedsBudget_dropsOldestMessages() { ... }
```

## 测试优先级

优先为以下模块编写测试（按重要程度排序）：

1. **TokenCounter**: token 计数准确性是整个系统的基础
2. **PromptAssembler**: 拼装顺序和预算分配的正确性
3. **KeywordMatcher**: 中英文关键词匹配规则
4. **SSEStreamParser**: SSE 解析的各种边界情况
5. **TruncationStrategy / CompressionStrategy**: 上下文管理策略
6. **WorldBookImportFormat**: Markdown 格式解析

ViewModel 和 View 不强制要求单元测试。

## Mock 方式

- Core 层服务通过协议抽象（或直接使用 struct + closure 注入）
- 数据库测试使用内存数据库: `DatabaseQueue()`（无 path 参数）
- 网络测试使用 `URLProtocol` mock，不发真实请求
- 不引入第三方 mock 框架

```swift
// 内存数据库
let db = try DatabaseQueue()
try migrator.migrate(db)

// URLProtocol mock
class MockURLProtocol: URLProtocol { ... }
```

## 测试数据

- 使用工厂方法创建测试数据: `makeTestCharacterCard()`, `makeTestMessage()`
- 工厂方法放在 `TestHelpers/` 目录
- 不使用 fixtures 文件（JSON 文件），直接在代码中构造

## 约束

- 测试不依赖网络、文件系统、UserDefaults
- 测试之间无顺序依赖（每个测试独立）
- 测试中可使用 `try!` 和 force unwrap（需注明原因）
- 异步测试使用 `async` 标注
