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

说明：原始生成测试通过可访问性层查询最终长文本，因此 clock time 包含 XCTest 查找 `StaticText` 的开销；CPU/内存指标仍能反映 app 进程的 before/after 趋势。

## 2026-05-26 长流式回归复查

用户反馈长流式性能再次变差后，重新跑 `test_longVibeChatGenerationPerformance`。当前复查确认：此前 `StreamingRenderBuffer` 和背景渲染优化没有被整体回滚，但流式输出路径又出现新的热区和测试见证问题：

- `ChatInputBarHostView` 读取 `ChatViewModel.prefillNextRole` 时曾通过 `messages.last` 计算，使底部 composer 在每个流式 batch 中观察整条 `messages`。
- `StreamingRenderBuffer` 只在正常结束时强制 flush；SSE 错误早于 50ms / 520 字符阈值时，已收到的 partial delta 可能尚未进 UI/持久化路径。
- reasoning 流式内容没有独立 revision，长 reasoning 字符串进入 equality/hash 热路径，且 reasoning-only 输出不会推动流式滚动 revision。
- 原 UI 性能用例用 `StaticText` 的超长 label 查询 `Perf stream chunk 119`；在 120 chunk 合并成一个巨大 AX 文本元素后，XCTest 查询会不稳定。当前改为 DEBUG/UI-test-only 的 `chat.performanceGenerationComplete` 完成 marker，避免把超长文本查询成本和 app 生成成本混在一起。

本轮修复后，在同一 iPhone 17 Pro simulator 上单跑生成性能用例，结果为：

| 用例 | 指标 | 旧 after | 当前复查 | 相对旧 after |
|---|---:|---:|---:|---:|
| 超长会话 + 氛围背景生成 | CPU Time | 7.557s | 8.539s | +13.0% |
| 超长会话 + 氛围背景生成 | Clock monotonic | 9.529s | 10.057s | +5.5% |
| 超长会话 + 氛围背景生成 | CPU Cycles | 30,553,906.805 kC | 33,781,675.522 kC | +10.6% |
| 超长会话 + 氛围背景生成 | CPU Instructions | 119,382,689.295 kI | 128,721,492.476 kI | +7.8% |
| 超长会话 + 氛围背景生成 | Memory peak physical | 215,305 KB | 221,809 KB | +3.0% |

这说明当前仍比最初未优化状态好，但相比旧 after 基线确实退步了一段；后续如果继续压性能，应优先看流完成后的同步收尾、Markdown 大文本 accessibility 暴露、以及 `isGenerating` 覆盖范围是否仍让输入栏/背景/尾条气泡在内容已到达后继续参与 streaming 态渲染。

## 2026-05-26 UIKit Timeline 迁移复查

进一步确认瓶颈不只发生在流式更新中：会话变长后，纯滑动也会因为 SwiftUI `ScrollView + LazyVStack` 的消息分组、日期分隔、Markdown 文本和 observation fan-out 进入热路径。参考 Telegram-iOS master `ffd82647` 后，本轮不复制 Telegram 源码，只迁移其列表结构原则：稳定 entry merge、可复用节点/单元、可见范围驱动加载、scroll position restoration、分页历史窗口和滚动时避免全量重排。

当前落地：

- `ChatMessageTimelineView` 下沉为 UIKit `UICollectionView` timeline core，外层 SwiftUI shell、Liquid Glass toolbar、输入栏和 vibe background 保持不变。
- `ChatViewModel.loadMessages()` 初始只读取最近 120 条；向上接近顶部时每页加载 80 条更早消息；`hasEarlierMessages` 使用 `pageSize + 1` sentinel row，而不是 `records.count == pageSize` 的精确页大小猜测。
- Prompt/context 组装不绑定 UI window：生成链路仍从 DB 读取完整会话历史，再交给 `ContextManager.prepareHistory(...)` 按策略压缩/截断。
- `DatabaseManager.fetchRecentMessages` / `fetchMessages(beforeSortOrder:)` 提供 GRDB 分页窗口。
- `ChatTimelineViewController` 使用 diffable datasource、stable item id、prepend offset preservation、50ms streaming follow-scroll coalescing。
- 非 prepend 的跳底/流式跟随在 diffable snapshot apply completion 后执行；prepend 只恢复旧 offset，避免 collection view 对尚未提交的 indexPath 滚动。
- `ChatTimelineDataSource` 独立负责 diffable datasource、cell registration、snapshot；同一组 stable item id 下的流式尾条/content-only 变化走 `reconfigureItems` 快路径，避免重建完整插删事务。
- `ChatTimelineLayout` 独立负责 collection layout 和 viewport-relative bubble metrics。
- `ChatMessageCell`、`ChatTimelineTextCache`、`ChatTimelineHeightCache` 缓存 attributed text 和测量高度；文本缓存 key 使用 `messageID + contentRevision + role + font/style`，避免长流式正文反复参与字符串 hash。
- 手势/鼠标/触控板滚动期间，`ChatTimelineViewController` 通过 `onScrollingChanged` 让 `VibeBackgroundUIKitView` 暂停 display link，冻结最后一帧背景；程序化跳底和 prepend offset restoration 会短暂 suppress 滚动报告，idle 恢复任务约 50ms 节流，避免手滑路径继续和背景动画抢主线程。
- `UITestingSupport` 的性能 fixture 默认 1,000 条，可通过 `--ui-testing-chat-performance-count` 扩展到 10,000 条；UI 测试覆盖 1,000 / 3,000 / 10,000 条滑动。

首次 UIKit cell 自尺寸实现曾在模拟器中把消息气泡压成蓝色竖条。多模态检查通过模拟器截图确认后，修复为 `UILabel` 正文、viewport-relative bubble metrics 和确定性左/右/居中约束。修复后的截图检查覆盖静态 1K fixture、滚动后画面、生成中画面和 MCP 启动的 10K fixture。2026-05-27 00:27 CST 的 10K 截图 `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_c1f3f280-9a29-4f9c-9cd8-f9192e756c48.jpg` 与滚动后截图 `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_daa8ae43-e023-41a0-82e6-e8f83387c275.jpg` 均确认 flat bubble、输入栏与 Liquid Glass chrome 正常。

2026-05-27 在 iPhone 17 Pro simulator 串行单跑结果如下。该组数字在 UIKit timeline 的 `reconfigureItems` 后 layout invalidation、无更早历史时不生成顶部隐藏 load-earlier item 之后采集；同一 simulator 不并行跑 UI tests。

| 用例 | 历史条数 | Scroll Duration | CPU Time | Memory peak physical | 结果 |
|---|---:|---:|---:|---:|---|
| `test_longVibeChatScrollPerformance` | 1,000 | 2.579s | 2.968s | 102,517 KB | passed |
| `test_ultraLongVibeChatScrollPerformance_3000Messages` | 3,000 | 2.600s | 2.985s | 103,680 KB | passed |
| `test_extremeLongVibeChatScrollPerformance_10000Messages` | 10,000 | 2.600s | 4.211s | 107,875 KB | passed |
| `test_longVibeChatGenerationPerformance` | 1,000 | n/a | 3.345s | 187,010 KB | passed |

10,000 条 scroll duration 和 1,000 / 3,000 条基本持平，说明 timeline 热路径已经和 fixture 总历史长度解耦；10,000 条 CPU time 仍有 simulator 抖动和 layout invalidation 成本，需要 A15 真机短跑确认最终帧率结论。生成用例在 `reconfigureItems` 快路径和文本缓存 key 收紧后明显下降；后续仍应优先看真机上 assistant streaming row 的 accessibility 暴露和剩余文本 sizing，而不是再回到全 SwiftUI timeline。注意：UI 性能用例不能并行打同一个 simulator，也不要和 app-hosted `OpenChatTests` 并行；一次并行 1K/3K/generation 尝试污染了 runner 状态，3K 早退、1K 挂起，另一次并行 code/UI run 导致 app-hosted code test 被 UI runner launch 杀掉。以上表格只记录串行有效结果。

多模态检查：10K fixture 最新静态截图 `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_f8488e46-7614-4036-939e-4777fcb49d2b.jpg` 和滚动后截图 `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_2fd39bbc-d05f-4152-af4d-41fca5debc99.jpg` 均确认消息不是蓝色窄条，latest flat bubbles、顶部 capsule 与底部 Liquid Glass 输入栏正常。

2026-05-27 01:13 CST 追加多模态检查：MCP 启动 10K fixture 后截图 `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_3504cdd0-6bc9-481d-999a-164bb477fb32.jpg` 显示 9998/9999 最新消息为正常宽度 flat bubbles，顶部 Mara capsule 和底部输入栏仍保持 Liquid Glass；滚动后截图 `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_d0d84646-542f-486a-a119-13aa373ad940.jpg` 显示布局仍稳定，没有窄条、重叠或输入栏错位。

同日新增 DEBUG-only in-app autoscroll probe，参数为 `--ui-testing-chat-performance-autoscroll`，用于在不安装 UI test runner 的情况下连续滚动并打印 `OPENCHAT_PERF_AUTOSCROLL_RESULT`。iPhone 17 Pro simulator 10K fixture、4 秒自动滚动复跑结果：

```text
OPENCHAT_PERF_AUTOSCROLL_RESULT fixture_messages=10000 duration_s=4.000 frames=193 avg_frame_ms=20.766 p95_frame_ms=39.311 max_frame_ms=66.057 frames_over_16_7_ms=46 frames_over_33_4_ms=27 cpu_time_s=1.063 rss_start_kb=258816 rss_end_kb=278912 rss_peak_kb=279120 loaded_timeline_items=122
```

这条 probe 不能替代 XCTest 的系统 scrolling/deceleration metric，也不能直接外推为真机帧率；它的价值是证明 10K fixture 下热路径只承载约 122 个 timeline items，CPU/RSS 随 fixture 总历史长度保持窗口化。随后单跑 `test_extremeLongVibeChatScrollPerformance_10000Messages` 通过，scroll duration 2.550s、CPU time 2.595s、peak physical memory 108,366 KB。2026-05-27 02:08 CST 在 snapshot-completion scroll policy 修正后再次单跑 10K UI 性能用例通过，scroll duration 2.569s、CPU time 2.688s、peak physical memory 108,039 KB；同次多模态截图 `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_ff503b0c-283c-47f5-b263-6c25f05b2ab9.jpg` 和滚动后 `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_474837d7-4a71-47dc-b768-e182d9e6e4e8.jpg` 确认气泡、顶部 capsule 和底部 Liquid Glass 输入栏布局稳定。A15 真机验证在用户要求下暂停：此前 UI test runner 安装受 free developer app limit 阻塞，后续探索主 App no-runner probe 时已完成主 App build/install/launch，但用户正在使用设备，因此不再继续发送真机命令。

2026-05-27 14:30 CST 在 iPhone 17 Pro simulator 安装当前 build 后，针对“手滑仍卡”的路径补充了非程序化滚动冻结背景 display link 和 scroll-idle 任务节流，再跑 10K / 4 秒 DEBUG autoscroll probe：

```text
OPENCHAT_PERF_AUTOSCROLL_RESULT fixture_messages=10000 duration_s=4.000 frames=237 avg_frame_ms=16.878 p95_frame_ms=16.667 max_frame_ms=41.988 frames_over_16_7_ms=3 frames_over_33_4_ms=1 cpu_time_s=0.464 rss_start_kb=261456 rss_end_kb=268704 rss_peak_kb=280736 loaded_timeline_items=122
```

最终 build 后 14:40 CST 再次安装并复跑同一 probe：

```text
OPENCHAT_PERF_AUTOSCROLL_RESULT fixture_messages=10000 duration_s=4.000 frames=236 avg_frame_ms=16.949 p95_frame_ms=16.667 max_frame_ms=48.022 frames_over_16_7_ms=4 frames_over_33_4_ms=2 cpu_time_s=0.933 rss_start_kb=347424 rss_end_kb=380288 rss_peak_kb=387072 loaded_timeline_items=122
```

该最终 run 同时出现 simulator runtime 的 `UIAccessibilityLoaderWebShared` duplicate-class warning，RSS/CPU 明显高于 14:30 run；因此这里按事实记录最终数字，但不把这条 simulator RSS 直接外推为真机内存回归。两个 run 的共同结论一致：4 秒连续滚动仍只加载 122 个 timeline items，p95 frame interval 为 16.667ms。

同轮多模态截图 `/tmp/openchat-10k-after-launch.png` 和手势滑动后 `/tmp/openchat-10k-after-swipe.png` 确认：顶部 Mara capsule、设置按钮、底部 composer 仍是透明 Liquid Glass，消息内容从其背后通过，没有白色遮罩盖住控件；气泡保持正常宽度与左右对齐。

2026-05-27 02:27 CST 按验收标准点名单跑 `ChatVibePerformanceUITests.test_longVibeChatScrollPerformance` 通过：1,000 条 fixture、scroll duration 2.559s、CPU time 2.563s、peak physical memory 99,634 KB。02:41 CST 在 `editMessage(...)` / `deleteMessage(...)` 改为 visible-window 局部更新后再次单跑同一用例通过：scroll duration 2.609s、CPU time 2.673s、peak physical memory 93,358 KB。

2026-05-27 12:43 CST 在真机 `Constant Moderato`（iPhone 13 Pro Max / A15 / iOS 26.5）上完成主 App no-runner 10K autoscroll probe。`OpenChatUITests-Runner` 路径仍受 free developer profile 三个 App 限制阻塞，因此没有卸载任何用户 App，而是覆盖安装主 App 后用 `devicectl device process launch --console` 运行 DEBUG-only probe。结果：

```text
OPENCHAT_PERF_AUTOSCROLL_RESULT fixture_messages=10000 duration_s=4.000 frames=239 avg_frame_ms=16.737 p95_frame_ms=16.668 max_frame_ms=37.149 frames_over_16_7_ms=1 frames_over_33_4_ms=1 cpu_time_s=0.867 rss_start_kb=90176 rss_end_kb=95664 rss_peak_kb=95696 loaded_timeline_items=122
```

这条真机数据证明 10K fixture 下 UI 热路径仍只加载 122 个 timeline items；4 秒自动滚动期间仅 1 帧超过 16.7ms、1 帧超过 33.4ms，RSS 峰值约 95.7 MB。它不是 XCTest scrolling signpost metric，但足以验证 A15 上窗口化 timeline 没有随历史总量线性退化。

## 代码变更证据

- `OpenChat/Features/Chat/Models/StreamingRenderBuffer.swift`：新增流式 delta 合并器，默认约 50ms 或 520 字符 flush，结束时强制 flush。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`：普通 `generateResponse` 和 Stage `streamAssistantResponse` 都接入 `StreamingRenderBuffer`，避免单路径优化。
- `OpenChat/Features/Chat/Views/VibeBackgroundUIKitView.swift`：改为 ProMotion 友好的 `preferredFrameRateRange` 范围提示，但按 phase 把调度上限限制到 idle/completing 24fps、waiting 30fps、streaming 60fps；动画 delta 使用 `targetTimestamp`，phase 内部 draw budget 控制实际绘制频率，避免固定锁死在单一设备刷新档位；离屏 render size 去掉 overscan；blur 与 color controls 合并成一次后处理链；stream tail 段数从 9 降到 5；timeline 滚动期间停止 display link，保留最后一帧背景。
- `OpenChat/Features/Chat/Views/VibeBackgroundDriver.swift`：降低 streaming 粒子发射率，增加粒子上限 54。
- `OpenChat/App/UITestingSupport.swift`：新增 `--ui-testing-chat-performance` fixture，固定长会话数据和 120 chunk 流式响应。
- `OpenChat/Features/Chat/Views/UIKitTimeline/ChatTimelineViewController.swift`：新增 DEBUG-only `--ui-testing-chat-performance-autoscroll` probe，使用 `CADisplayLink` 连续滚动并输出 frame interval、CPU、RSS 和 loaded timeline item 数；非程序化滚动通过 `onScrollingChanged` 冻结背景 display link，程序化 scroll-to-bottom / prepend offset restoration 使用短 suppress window，idle 恢复任务约 50ms 节流。
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`：新增 `test_loadMessages_exposesRecentWindowAndSentinelHasEarlierState`，覆盖刚好 120 条和 121 条时的 UI window / `hasEarlierMessages` 边界。
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`：新增 `test_promptHistoryUsesDatabaseBeyondVisibleTimelineWindow`，覆盖 150 条 DB 历史、120 条可见 timeline window 时，API request 仍包含窗口外早期历史。
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`：新增 `test_deleteMessage_removesVisibleTimelineItemWithoutReloadingWindow` 和 `test_editMessage_truncatesVisibleTimelineTailWithoutReloadingWindow`，覆盖删除/编辑 visible row 后只局部变更当前 window，不通过 full `loadMessages()` 回填更早消息。
- `OpenChatUITests/ChatVibePerformanceUITests.swift`：新增滑动和生成性能用例。
- `OpenChatTests/Features/ChatTests/StreamingRenderSegmentationTests.swift`：新增 `StreamingRenderBuffer` 合并策略测试。
- `OpenChat/Features/Chat/Views/UIKitTimeline/`：新增 UIKit collection timeline core。
- `OpenChat/Core/Database/DatabaseManager+Conversations.swift`：新增最近窗口和 before-sort-order 分页读取。
- `OpenChatTests/Core/DatabaseTests/MessageWindowPaginationTests.swift`：新增窗口分页测试。

## 牺牲

- 氛围背景不再把所有 phase 都固定到 30fps；为了控制主线程成本，idle/completing、waiting、streaming 分别用 24fps、30fps、60fps 的 phase 上限，实际 delta 仍按 Core Animation 的 `targetTimestamp` 推进。
- 粒子密度、stream tail 细节和离屏模糊半径降低；背景更偏大形体和色场，细碎粒子发光会少一些。
- 流式文本 UI 不再逐 SSE chunk 刷新，而是约 50ms/520 字符批量刷新；用户仍能看到实时输出，但极高频 chunk 下会少一些逐字跳动感。

## 验证命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/StreamingRenderSegmentationTests' '-only-testing:OpenChatTests/VibeBackgroundDriverTests'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_longVibeChatGenerationPerformance'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_longVibeChatScrollPerformance'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_ultraLongVibeChatScrollPerformance_3000Messages'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_extremeLongVibeChatScrollPerformance_10000Messages'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MessageWindowPaginationTests'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/ChatVibePerformanceUITests'
```

最终合并运行 `ChatVibePerformanceUITests` 执行 2 个 UI 性能测试，0 failures；最终 after 指标以上表合并运行输出为准。
