# Chat Vibe Background 性能审计报告（2026-05-26）

## 结论

本轮性能问题主要来自两个热点叠加：`VibeBackgroundUIKitView` 在主线程按较高频率做低分辨率绘制、Core Image blur/color 后处理和粒子/尾迹绘制；同时流式回复每个 SSE delta 都直接修改 `messages[index]`，让超长会话 timeline 在生成期间频繁 invalidation。优化后保持现有布局、气泡样式、氛围背景入口和开关不变，只降低动画细节预算并合并 UI 刷新频率。

## 测试场景

- 设备：iOS Simulator `iPhone 17 Pro`
- 构建：Debug，`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat`
- Fixture：`--ui-testing --ui-testing-chat-performance`
- 数据：420 条固定历史消息，氛围背景默认开启，性能生成路径返回 120 个 SSE chunk
- 测试文件：`OpenChatUITests/ChatVibePerformanceUITests.swift`

## 指标

| 用例 | 指标 | 优化前 | 优化后 | 变化 |
|---|---:|---:|---:|---:|
| 超长会话 + 氛围背景滑动 | CPU Time | 4.082s | 2.079s | -49.1% |
| 超长会话 + 氛围背景滑动 | CPU Cycles | 15,653,543.779 kC | 6,848,530.012 kC | -56.2% |
| 超长会话 + 氛围背景滑动 | CPU Instructions | 50,655,936.950 kI | 19,392,422.929 kI | -61.7% |
| 超长会话 + 氛围背景滑动 | Scroll dragging/deceleration duration | 2.596s | 2.612s | +0.6% |
| 超长会话 + 氛围背景滑动 | Memory peak physical | 107,940 KB | 108,710 KB | +0.7% |
| 超长会话 + 氛围背景生成 | CPU Time | 9.592s | 7.557s | -21.2% |
| 超长会话 + 氛围背景生成 | Clock monotonic | 11.363s | 9.529s | -16.1% |
| 超长会话 + 氛围背景生成 | CPU Cycles | 38,351,696.311 kC | 30,553,906.805 kC | -20.3% |
| 超长会话 + 氛围背景生成 | CPU Instructions | 151,742,931.242 kI | 119,382,689.295 kI | -21.3% |
| 超长会话 + 氛围背景生成 | Memory peak physical | 215,829 KB | 215,305 KB | -0.2% |

说明：生成测试的完成条件仍通过可访问性层查询最终文本，因此 clock time 包含 XCTest 查找 `StaticText` 的开销；CPU/内存指标仍能反映 app 进程的 before/after 趋势。

## 代码变更证据

- `OpenChat/Features/Chat/Models/StreamingRenderBuffer.swift`：新增流式 delta 合并器，默认约 50ms 或 520 字符 flush，结束时强制 flush。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`：普通 `generateResponse` 和 Stage `streamAssistantResponse` 都接入 `StreamingRenderBuffer`，避免单路径优化。
- `OpenChat/Features/Chat/Views/VibeBackgroundUIKitView.swift`：改为 ProMotion 友好的 `preferredFrameRateRange` 范围提示，但按 phase 把调度上限限制到 idle/completing 24fps、waiting 30fps、streaming 60fps；动画 delta 使用 `targetTimestamp`，phase 内部 draw budget 控制实际绘制频率，避免固定锁死在单一设备刷新档位；离屏 render size 去掉 overscan；blur 与 color controls 合并成一次后处理链；stream tail 段数从 9 降到 5。
- `OpenChat/Features/Chat/Views/VibeBackgroundDriver.swift`：降低 streaming 粒子发射率，增加粒子上限 54。
- `OpenChat/App/UITestingSupport.swift`：新增 `--ui-testing-chat-performance` fixture，固定长会话数据和 120 chunk 流式响应。
- `OpenChatUITests/ChatVibePerformanceUITests.swift`：新增滑动和生成性能用例。
- `OpenChatTests/Features/ChatTests/StreamingRenderSegmentationTests.swift`：新增 `StreamingRenderBuffer` 合并策略测试。

## 牺牲

- 氛围背景不再把所有 phase 都固定到 30fps；为了控制主线程成本，idle/completing、waiting、streaming 分别用 24fps、30fps、60fps 的 phase 上限，实际 delta 仍按 Core Animation 的 `targetTimestamp` 推进。
- 粒子密度、stream tail 细节和离屏模糊半径降低；背景更偏大形体和色场，细碎粒子发光会少一些。
- 流式文本 UI 不再逐 SSE chunk 刷新，而是约 50ms/520 字符批量刷新；用户仍能看到实时输出，但极高频 chunk 下会少一些逐字跳动感。

## 验证命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/StreamingRenderSegmentationTests' '-only-testing:OpenChatTests/VibeBackgroundDriverTests'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_longVibeChatGenerationPerformance'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_longVibeChatScrollPerformance'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/ChatVibePerformanceUITests'
```

最终合并运行 `ChatVibePerformanceUITests` 执行 2 个 UI 性能测试，0 failures；最终 after 指标以上表合并运行输出为准。
