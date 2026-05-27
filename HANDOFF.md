# OpenChat Long Timeline Refactor Handoff

Date: 2026-05-27

## Goal

Move the chat timeline away from SwiftUI `ScrollView + LazyVStack` hot path and toward a Telegram-inspired long-list architecture while preserving the current SwiftUI shell and Liquid Glass chat chrome. UIKit is acceptable for the message timeline if the visible design contract remains intact:

- Top toolbar/capsule, input bar, buttons, and background should keep the current Liquid Glass look.
- Message bubbles should remain flat bubbles, not glass surfaces.
- Very long conversations should scroll without obvious dropped frames.
- Streaming should not invalidate or relayout the entire history for every token.

## Visual Authority

The canonical edge-effect visual is the user-provided screenshot from 2026-05-27 and the earlier local commit `e1c17f625b7f819373fee0a47d5cd074bad1e311` (`Add chat scroll edge effects`). Treat that as the source of truth for the top and bottom fade/gradient blur. Do not describe the result as "Telegram-like" unless Telegram itself has been launched or a concrete Telegram screenshot has been compared.

Telegram remains a source-code architecture reference only: bounded list windows, reusable visible nodes/cells, stable transactions, and wallpaper-owned edge-effect layering. OpenChat's visual contract is local, not copied from Telegram.

## Current Direction

Implemented a first UIKit timeline core:

- `OpenChat/Features/Chat/Views/ChatMessageTimelineView.swift` is now a SwiftUI wrapper around `ChatTimelineUIKitRepresentable`.
- New UIKit files live in `OpenChat/Features/Chat/Views/UIKitTimeline/`.
- `ChatTimelineViewController` owns a `UICollectionView`, scroll-position policy, prepend offset preservation, coalesced streaming follow-scroll, and load-earlier triggering.
- `ChatTimelineDataSource` owns diffable snapshots, cell registration, stable item ids, and a same-order `reconfigureItems` path for streaming/content-only updates. That fast path now invalidates layout after apply so growing streaming rows are remeasured.
- `ChatTimelineViewController.update(...)` applies the diffable snapshot first, then runs scroll-position policy from the apply completion. This avoids calling `scrollToItem` for a new last item before it exists in the collection data source. Prepend still only restores the visual offset.
- `ChatTimelineLayout` owns the collection layout and viewport-relative bubble metrics.
- `ChatMessageCell` renders message rows with UIKit labels, flat bubble styling, context menu actions, and text/height caches.
- `ChatTimelineTextCache` keys attributed text by `messageID + contentRevision + role + font/style`, avoiding repeated full-string hashing on long streaming content.
- `ChatTimelineItemBuilder` builds load-earlier, date separator, message, extraction, diagnostics, and performance-marker items from display state.
- Edge effects keep the `e1c17f6` split by OS version. On iOS 26+, the UIKit timeline owns the native `UIScrollView.topEdgeEffect` / `bottomEdgeEffect` soft style so long-list scrolling stays on the `UICollectionView` path without a SwiftUI full-viewport mask. On iOS 17-25, `ChatEdgeEffectViewport` still provides the original SwiftUI fade mask plus material fallback.
- While the user scrolls, `ChatTimelineViewController` reports non-programmatic `scrollViewDidScroll` activity back to `ChatView`, and `VibeBackgroundUIKitView` stops its `CADisplayLink` until the timeline is idle. Programmatic scroll-to-bottom and prepend offset restoration are briefly suppressed so streaming follow-scroll does not look like a user drag. Idle detection is throttled to avoid creating a new work item for every scroll event.

Do not copy Telegram code. Use its architecture lessons: bounded visible item range, stable identities, reusable nodes/cells, async/paged history, height/layout caching, and explicit scroll-position preservation.

## Telegram Evidence

Checked Telegram-iOS `master` on 2026-05-27 from GitHub raw sources:

- `submodules/TelegramUI/Sources/ChatHistoryListNode.swift`
  - `historyMessageCount` is `44`, and chat history locations request bounded windows around the current anchor instead of materializing the whole chat.
  - `displayedItemRangeChanged` feeds visible/loaded range changes back into history navigation and hole filling.
- `submodules/Display/Source/ListView.swift`
  - Maintains persistent `items`, reusable `itemNodes`, `displayedItemRange`, and explicit delete/insert/update transactions.
  - The transaction API accepts `stationaryItemRange` and scroll targets so prepends/reloads can preserve the user's visual anchor.
- `submodules/TelegramUI/Sources/PreparedChatHistoryViewTransition.swift`
  - Builds a stable merge from old/new `ChatHistoryEntry` arrays into delete/insert/update lists before applying a list transaction.
- `submodules/TelegramUI/Sources/ChatControllerNode.swift`
  - Chat owns `topBackgroundEdgeEffectNode` and `bottomBackgroundEdgeEffectNode`, creates them with `backgroundNode.makeEdgeEffectNode()`, inserts them above message transition content, and updates top with `WallpaperEdgeEffectEdge(edge: .top, size: 80.0), blur: true`; bottom uses `edge: .bottom, size: min(60.0, blurFrame.height), blur: false`.
- `submodules/TelegramUI/Components/EdgeEffect/Sources/EdgeEffect.swift`
  - Generic list edge effects use an `EdgeEffectView` with a masked content view, optional `VariableBlurView(maxBlurRadius: 1.0)`, and a precomputed non-linear edge gradient.
- `submodules/WallpaperBackgroundNode/Sources/WallpaperEdgeEffectNodeImpl.swift`
  - Chat wallpaper edge effects clone/sample background content and gradient state, mask it with `EdgeEffectView.generateEdgeGradient(...)`, and only add variable blur when the caller asks for it.

The OpenChat migration maps those ideas to native project constraints: GRDB recent/before windows, `UICollectionViewDiffableDataSource`, stable `ChatTimelineItem.stableID`, prepend offset restoration, and targeted `reconfigureItems` for streaming/content-only changes.
For the visual edge treatment, OpenChat does not vendor Telegram code or private variable-blur filters. The current visual implementation intentionally follows the local `e1c17f6`/screenshot contract: iOS 26+ uses native scroll edge effects on the `UICollectionView`, while older systems keep the SwiftUI fade/material fallback in `ChatEdgeEffects.swift`. The Telegram source evidence only informs why edge effects are outside the reusable message rows and chrome.

## Telegram 120fps Detail Pass

Checked local Telegram-iOS clone at `ffd82647ee97c68e4da4802fe9717ccccd8105c9` on 2026-05-27.

Why Telegram can stay smooth on older devices:

- It does not treat a chat as a normal UIKit list of Auto Layout cells. `ChatHistoryListNodeImpl` subclasses Telegram's `ListViewImpl`, which keeps persistent `items`, reusable `itemNodes`, and `displayedItemRange` in `submodules/Display/Source/ListView.swift`.
- History is aggressively bounded at the source. `ChatHistoryListNode.swift` defines `historyMessageCount = 44`, then uses `ChatHistoryLocationInput(... count: historyMessageCount)` for initial/search/navigation windows. It navigates by anchor and fills holes instead of materializing the whole transcript in the visual list.
- Visible range is a data contract, not just a scroll callback. `displayedItemRangeChanged` feeds `processDisplayedItemRangeChanged(...)`, which converts the visible range back to message indices and uses a small extended range for work such as translation/fact-check prefetch.
- List mutations are explicit transactions. `PreparedChatHistoryViewTransition.swift` converts old/new `ChatHistoryEntry` arrays into delete/insert/update lists, `scrollToItem`, and `stationaryItemRange`; `ChatHistoryListNode` applies those through `ListView.transaction(...)`.
- `ListView` builds and updates item nodes off the main scrolling path. `deleteAndInsertItemsTransaction(...)` computes operations, calls `fillMissingNodes(...)`, `updateNodes(...)`, and `updateAdjacent(...)`, then replays prepared operations on the main thread/VSync path.
- Message rows have an async layout contract. `ChatMessageItemImpl.nodeConfiguredForParams(...)` creates a node, calls `node.asyncLayout()`, computes layout with neighboring items, and only returns to the main queue to apply the prepared node. `updateNode(...)` does the same for existing nodes.
- Text is not rendered as `UILabel` inside a stack view. `ChatMessageTextBubbleContentNode` uses `InteractiveTextNodeWithEntities` / `TextNode`, enables `displaysAsynchronously`, computes `TextNodeLayout`, and applies layer frames directly. `TextNode.drawParameters(forAsyncLayer:)` passes the cached layout to async drawing.
- Edge effects live outside row reuse. `ChatControllerNode` owns top/bottom `WallpaperEdgeEffectNode`s above message transition content; top uses a wallpaper edge with blur, bottom uses a bottom edge without blur. Generic `EdgeEffectView` caches gradient images and optional variable blur rather than rebuilding a full-screen mask around the list.

Current OpenChat gap versus that model:

- The UI window is now bounded (`loaded_timeline_items=122` for a 10K fixture), so the old full-history problem is mostly fixed.
- The row hot path is still too UIKit-heavy for 120fps on A14/A15: `ChatMessageCell` uses `UIStackView`, multiple `UILabel`s, Auto Layout constraints, `layoutSubviews` metric updates, and per-layout shadow-path updates.
- Height measurement is cached, but it still uses `NSAttributedString.boundingRect(...)` and the cell repeats a separate UIKit label layout. Telegram's equivalent caches a full text layout object and draws from it.
- `UICollectionViewFlowLayout + sizeForItemAt` still asks into sizing code during layout. Telegram's list engine keeps cached item-node frames and replays prepared frame operations.
- Streaming/content-only updates use `reconfigureItems`, then invalidate layout. That is a good short-term bridge, but Telegram's transaction model can update one node with a prepared layout/apply closure without forcing the collection layout to rediscover as much state.
- `ChatMessageCell.apply(...)` still assigns `messageLabel.accessibilityLabel = item.content`; for very long visible assistant rows or streaming rows, exposing the full text to AX can create avoidable main-thread work.

Next migration step if the goal is 120fps instead of "acceptable":

1. Replace `ChatMessageCell`'s `UIStackView` and Auto Layout constraints with manual frames based on a cached `ChatTimelineRowLayout`.
2. Promote the cache from height-only to full row layout: bubble frame, text frame, speaker/reasoning/footer/stats frames, attributed text, and measured text height keyed by message id/revision/width/style.
3. Move the body text path from `UILabel` toward a draw-backed text view/layer or a TextKit/CoreText prelayout object; first phase can keep `UILabel` but must stop using Auto Layout for it.
4. Replace or bypass `UICollectionViewFlowLayout` sizing with cached layout attributes once manual row layout is stable.
5. Truncate or gate full accessibility labels for long/streaming rows while preserving useful accessibility summaries.

## Data Windowing

Added message pagination APIs:

- `DatabaseManager.fetchRecentMessages(conversationId:limit:)`
- `DatabaseManager.fetchMessages(conversationId:beforeSortOrder:limit:)`

`ChatViewModel` now loads a recent window first:

- Initial timeline window: `120`
- Earlier page size: `80`
- State: `hasEarlierMessages`, `isLoadingEarlierMessages`
- Method: `loadEarlierMessagesIfNeeded()`
- `hasEarlierMessages` is sentinel-based, not exact-page-count based. Initial load asks for `120 + 1`, exposes only the newest 120 rows, and sets `hasEarlierMessages` only when the sentinel exists. Earlier loads ask for `80 + 1`, expose only the newest 80 rows from that page, and use the extra row only to decide whether another page remains.
- `editMessage(...)` and `deleteMessage(...)` no longer call `loadMessages()` after mutating the DB. They now update the visible timeline window locally (`replaceTimelineMessage`, `removeTimelineMessage`, `removeTimelineMessages`) so deleting or editing a visible item does not refill the window with older rows and does not force a full timeline reload.

This is intentional. Do not go back to loading the full conversation into the timeline unless a separate transcript/search surface is being built.

Prompt/context assembly remains DB/Core-owned. `generateResponse(...)` still reads `databaseManager.fetchMessages(conversationId:)` and passes that full DB history into `ContextManager.prepareHistory(...)`; the UI window is only for timeline display. `ChatViewModelPromptAssemblyTests.test_promptHistoryUsesDatabaseBeyondVisibleTimelineWindow` covers this by loading a 120-row visible window from a 150-message DB conversation and proving the API request still includes messages outside the visible window.

## Tests Already Run

Current valid serial runs after the load-earlier/top-gap fix and layout invalidation:

- `git diff --check`
- `jq empty OpenChat/Resources/Localizable.xcstrings`
- `xcodebuild test ... '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`
  - 35 Swift Testing tests passed on 2026-05-27 02:36 CST
  - Includes `test_loadMessages_exposesRecentWindowAndSentinelHasEarlierState`, covering exact 120-message and 121-message sentinel boundaries.
  - Includes `test_promptHistoryUsesDatabaseBeyondVisibleTimelineWindow`, covering that prompt assembly uses DB/Core history beyond the visible UI timeline window.
  - Includes `test_deleteMessage_removesVisibleTimelineItemWithoutReloadingWindow` and `test_editMessage_truncatesVisibleTimelineTailWithoutReloadingWindow`, covering local visible-window updates after delete/edit instead of full `loadMessages()` refill.
- `xcodebuild build -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- `xcodebuild test ... '-only-testing:OpenChatTests/MessageWindowPaginationTests' '-only-testing:OpenChatTests/StreamingRenderSegmentationTests'`
  - 11 Swift Testing tests passed on 2026-05-27 02:02 CST
- `xcodebuild test ... '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_longVibeChatScrollPerformance'`
  - 1,000 seeded messages
  - latest serial rerun on 2026-05-27 02:41 CST after local edit/delete window updates: scroll duration 2.609s, CPU time 2.673s, peak physical memory 93,358 KB
  - previous serial rerun on 2026-05-27 02:27 CST: scroll duration 2.559s, CPU time 2.563s, peak physical memory 99,634 KB
  - earlier valid run: scroll duration 2.579s, CPU time 2.968s, peak physical memory 102,517 KB
- `xcodebuild test ... '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_longVibeChatGenerationPerformance'`
  - 1,000 seeded messages
  - clock 5.405s, CPU time 3.345s, peak physical memory 187,010 KB
- `xcodebuild test ... '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_ultraLongVibeChatScrollPerformance_3000Messages'`
  - 3,000 seeded messages
  - scroll duration 2.600s, CPU time 2.985s, peak physical memory 103,680 KB
- `xcodebuild test ... '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_extremeLongVibeChatScrollPerformance_10000Messages'`
  - 10,000 seeded messages
  - scroll duration 2.600s, CPU time 4.211s, peak physical memory 107,875 KB
- In-app DEBUG autoscroll probe on simulator:
  - Command shape: `xcrun simctl launch --console-pty ... --ui-testing --ui-testing-chat-performance --ui-testing-chat-performance-count 10000 --ui-testing-chat-performance-autoscroll --ui-testing-chat-performance-autoscroll-duration 4 --ui-testing-chat-performance-autoexit`
  - Latest result after installing the final current build on 2026-05-27 14:40 CST: `OPENCHAT_PERF_AUTOSCROLL_RESULT fixture_messages=10000 duration_s=4.000 frames=236 avg_frame_ms=16.949 p95_frame_ms=16.667 max_frame_ms=48.022 frames_over_16_7_ms=4 frames_over_33_4_ms=2 cpu_time_s=0.933 rss_start_kb=347424 rss_end_kb=380288 rss_peak_kb=387072 loaded_timeline_items=122`
  - The same run emitted the simulator runtime warning `Class UIAccessibilityLoaderWebShared is implemented in both ... WebCore.axbundle ... and ... WebKit.axbundle`; treat the higher RSS/CPU as simulator-noisy unless reproduced.
  - The important architectural signal is `loaded_timeline_items=122` with a 10,000-message fixture, confirming the UI hot path is windowed.
- In-app DEBUG autoscroll probe on real A15 device:
  - Device: `Constant Moderato`, iPhone 13 Pro Max (`iPhone14,3`), iOS 26.5, Xcode destination id `00008110-000E4D912202401E`
  - UI test runner path is blocked by the free developer profile app limit while installing `OpenChatUITests-Runner`; installed apps consuming the limit are `fukujusou.openchat.com`, `com.example.piliplus.GZAC7644XS`, and `com.fukujusou.erosfe.GZAC7644XS`. Do not uninstall user apps without explicit approval.
  - Main app no-runner probe command shape: `xcrun devicectl device process launch --device 00008110-000E4D912202401E --terminate-existing --console --timeout 20 fukujusou.openchat.com --ui-testing --ui-testing-chat-performance --ui-testing-chat-performance-count 10000 --ui-testing-chat-performance-autoscroll --ui-testing-chat-performance-autoscroll-duration 4 --ui-testing-chat-performance-autoexit`
  - 2026-05-27 12:43 CST result: `OPENCHAT_PERF_AUTOSCROLL_RESULT fixture_messages=10000 duration_s=4.000 frames=239 avg_frame_ms=16.737 p95_frame_ms=16.668 max_frame_ms=37.149 frames_over_16_7_ms=1 frames_over_33_4_ms=1 cpu_time_s=0.867 rss_start_kb=90176 rss_end_kb=95664 rss_peak_kb=95696 loaded_timeline_items=122`
  - This validates the long-list hot path on A15 without installing the UI test runner: the 10K fixture still loads only 122 timeline items, with one frame over 16.7ms and one over 33.4ms during the 4-second autoscroll.
- Final 10K UI performance rerun after doc/probe edits:
  - `xcodebuild test ... '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_extremeLongVibeChatScrollPerformance_10000Messages'`
  - scroll duration 2.550s, CPU time 2.595s, peak physical memory 108,366 KB
- 10K UI performance rerun after snapshot-completion scroll policy fix:
  - `xcodebuild test ... '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_extremeLongVibeChatScrollPerformance_10000Messages'`
  - scroll duration 2.569s, CPU time 2.688s, peak physical memory 108,039 KB

Do not run multiple `ChatVibePerformanceUITests` or mix UI and app-hosted `OpenChatTests` in parallel against the same simulator. Parallel attempts polluted the runner state: one 3K run exited early before bootstrapping, one 1K run hung, and one app-hosted code-test run was killed by a UI runner launch. The serial runs above are the valid metrics.

Simulator visual checks after fixes:

- `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_d7e10c0a-8fd9-4a5e-a767-5fea4e89a945.jpg`
  - static 1K fixture: normal flat bubbles, readable assistant text, Liquid Glass chrome intact
- `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_7f0849c4-5be9-4a74-a753-6aa3edf41e4b.jpg`
  - after scroll: bubbles and input bar remain correctly placed
- `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_fc495208-68a1-44c5-a548-81d41ac0ee18.jpg`
  - generation: new user bubble and assistant reply render correctly
- `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_e88214b7-439f-49fc-9dfd-5d19f26ca3c9.jpg`
  - static 10K fixture after DataSource/Layout split: normal flat bubbles, latest messages visible, Liquid Glass chrome intact
- `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_c1f3f280-9a29-4f9c-9cd8-f9192e756c48.jpg`
  - MCP-launched 10K fixture on 2026-05-27 00:27 CST: latest bubbles render at normal width; top capsule and input bar keep the Liquid Glass look
- `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_daa8ae43-e023-41a0-82e6-e8f83387c275.jpg`
  - same 10K fixture after simulator scroll gesture: layout remains stable with flat bubbles and intact chrome
- `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_f8488e46-7614-4036-939e-4777fcb49d2b.jpg`
  - latest 10K fixture on 2026-05-27 00:50 CST after top-gap fix: newest 9998/9999 bubbles render at normal width; top capsule and input bar remain Liquid Glass
- `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_2fd39bbc-d05f-4152-af4d-41fca5debc99.jpg`
  - same 10K fixture after scroll gestures: no collapsed strips, no incoherent overlap, bottom glass input remains stable
- `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_3504cdd0-6bc9-481d-999a-164bb477fb32.jpg`
  - 10K fixture on 2026-05-27 01:13 CST, checked with multimodal view: latest 9998/9999 bubbles render at normal width; top capsule/input remain Liquid Glass.
- `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_d0d84646-542f-486a-a119-13aa373ad940.jpg`
  - same 10K fixture after simulator scroll gestures, checked with multimodal view: layout remains stable and readable.
- `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_ff503b0c-283c-47f5-b263-6c25f05b2ab9.jpg`
  - 10K fixture after snapshot-completion scroll policy fix: latest 9998/9999 bubbles render at normal width; top capsule and bottom input bar keep the Liquid Glass look.
- `/var/folders/xk/7wq8b_wj4lj3k0jblhvckqtc0000gn/T/screenshot_optimized_474837d7-4a71-47dc-b768-e182d9e6e4e8.jpg`
  - same 10K fixture after simulator scroll gestures: user and assistant bubbles keep normal width/alignment, with no overlap or input-bar displacement.
- `/tmp/openchat-10k-after-launch.png`
  - current installed 10K fixture on 2026-05-27 14:32 CST, checked with multimodal view: message content passes behind the transparent top capsule and bottom input bar; there is no white overlay covering chrome.
- `/tmp/openchat-10k-after-swipe.png`
  - same fixture after coordinate swipe gestures: top capsule/settings button and bottom composer stay transparent Liquid Glass over message content, and bubbles remain normal width/alignment.

## Current Known Risks

- The 2026-05-27 performance regression after restoring edge visuals was caused by applying `GeometryReader + mask` around the UIKit timeline on iOS 26. That path has been removed; do not reintroduce a SwiftUI `.mask` or full-viewport material overlay around `ChatTimelineUIKitRepresentable` on iOS 26.
- A second hand-scroll regression came from only freezing the vibe background on drag/autoscroll paths. Real simulator mouse/trackpad scrolling can arrive as observed `scrollViewDidScroll` activity, so the current boundary is: non-programmatic scroll events freeze the background display link until idle; programmatic scrolls are suppressed for a short window.
- Fixed the "very strange" simulator visual state. Root cause was UIKit self-sizing with text/bubble width constraints collapsing rows into narrow vertical strips. The cell now uses `UILabel` and explicit viewport-relative bubble metrics in `preferredLayoutAttributesFitting`.
- `test_longVibeChatGenerationPerformance` now uses a stable collection-view `accessibilityValue == "chat.performanceGenerationComplete"` completion signal instead of querying the final huge text or relying on a visible marker cell.
- Generation CPU/memory improved after the `reconfigureItems` path and cache-key tightening, but still needs real-device confirmation. If continuing, inspect accessibility exposure and any remaining text sizing during the streaming assistant row.
- A15 UI-test-runner validation is still blocked by device-side free developer app limit while installing `OpenChatUITests-Runner`; do not delete apps from the device without user approval. Main-app no-runner autoscroll validation completed on 2026-05-27 12:43 CST.
- `ruby scripts/generate_xcodeproj.rb` was run to add the new Swift files. It produced noisy `OpenChat.xcodeproj` and scheme UUID churn. Signing values should remain script-owned and preserved. Do not manually edit signing settings.
- Existing dirty changes predated this pass in some chat model/viewmodel/test/doc files. Do not revert unrelated user work.

## Immediate Next Steps

1. Run a final `git diff --check` / `jq empty OpenChat/Resources/Localizable.xcstrings` after any further doc edits.
2. Real-device validation is allowed again per the user's later instruction, but avoid installing or removing device apps without explicit approval.
3. Consider a follow-up optimization pass for generation CPU/memory:
   - avoid exposing huge streaming labels to accessibility while generating;
   - cache measured text heights outside `systemLayoutSizeFitting`;
   - consider a draw-backed text node for assistant rows if `UILabel` still spends too much time in Auto Layout.

## Useful Commands

```sh
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_longVibeChatScrollPerformance'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_longVibeChatGenerationPerformance'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_ultraLongVibeChatScrollPerformance_3000Messages'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/ChatVibePerformanceUITests/test_extremeLongVibeChatScrollPerformance_10000Messages'
git diff --check
xcrun simctl launch --console-pty <sim-udid> fukujusou.openchat.com --ui-testing --ui-testing-chat-performance --ui-testing-chat-performance-count 10000 --ui-testing-chat-performance-autoscroll --ui-testing-chat-performance-autoscroll-duration 4 --ui-testing-chat-performance-autoexit
```
