# Layering Repair Plan

> 创建时间：2026-04-27
> 来源：`arch/AntiEntropy/triangle-consistency.md` 的“分层规则与当前 Feature 装配漂移”。

## 目标

把当前 App / Features / Core / Shared 边界漂移拆成独立修复波次，避免在 Prompt、Database 一致性修复中混入跨层搬迁。最终状态必须二选一：要么源码重新满足 `App -> Features -> Core -> Shared` 单向依赖；要么文档明确承认并约束 App shell 例外。

## 当前漂移证据

| 漂移 | 当前文件 | 修复方向 |
|---|---|---|
| Core 直接读取 App 常量 | `OpenChat/Core/PromptEngine/PromptAssembler.swift`、`OpenChat/Core/Memory/MemoryManager.swift`、`OpenChat/Core/Networking/TitleGenerator.swift`、`OpenChat/Core/Database/DatabaseManager+EndpointModels.swift` | 将跨层使用的默认值迁移到 Core/Shared 配置类型，或通过依赖注入传入。 |
| Feature ViewModel 持有 AppState | `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift` | 注入 `presentError`、`markConversationListNeedsRefresh` 等小闭包或 Feature 层协议，避免 Feature 直接依赖 App。 |
| Feature 目录承载 App shell 导航 | `OpenChat/Features/Support/SidebarView.swift` | 将 shell composition 移到 `OpenChat/App/Views/SidebarView.swift`，或先把 `Features/Support` 明确迁到 App shell 命名空间。 |
| Feature 直接组合多个 sibling Feature | `OpenChat/Features/Support/SidebarView.swift` | App shell 负责跨 Feature 装配；单个 Feature 只暴露本 Feature view/view model。 |
| WorldBook 直接打开 CharacterCard UI | `OpenChat/Features/WorldBook/Views/WorldBookEditorView.swift` | 通过 App route state 或 Core 层关系服务表达跳转意图，不在 WorldBook 内直接构造 CharacterCard UI。 |
| Shared 反向调用 Core token 逻辑 | `OpenChat/Shared/Extensions/String+Token.swift` | 移到 `OpenChat/Core/PromptEngine/`，或删除扩展并让调用点直接使用 `TokenCounter.count`。 |

## 修复顺序

1. **边界决策**：确认是否保留 App shell 例外。推荐把 `Features/Support` 迁到 `OpenChat/App/Views/`，而不是在 Feature 层新增例外。
2. **常量归属修复**：把 Core 使用的 `AppConstants` 字段迁移到 Core/Shared 可依赖的位置，或改为构造参数注入。
3. **ChatViewModel 去 AppState**：用注入闭包替换 `appState.present(...)` 和会话列表刷新信号。
4. **SidebarView 迁移**：将跨 Feature 组合移动到 App 层，必要时运行 `ruby scripts/generate_xcodeproj.rb` 更新 Xcode project。
5. **WorldBook 跳转解耦**：把 CharacterCard 编辑/详情打开动作改为 App route 或 coordinator 事件。
6. **String+Token 归位**：移出 Shared，或删除扩展后替换调用点。
7. **新增边界测试**：加入源码扫描测试，至少覆盖 `OpenChat/Shared/*` 不引用 Core 符号、`OpenChat/Features/*` 不引用 App 层类型、Feature sibling 直接装配的禁止规则。
8. **文档回写**：更新 `arch/source-tree.md` 和受影响模块文档，记录最终边界和测试证据。

## 验证

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17'
```

验收标准：

- 全量 Swift Testing 测试通过。
- 新增边界测试通过。
- `arch/source-tree.md` 与实际文件位置、依赖方向一致。
- `arch/AntiEntropy/triangle-consistency.md` 中分层漂移从 Open 改为 Closed，或明确记录剩余例外与责任边界。
