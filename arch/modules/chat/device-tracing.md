# Chat 真机长流式 Trace 流程

## 目标

用于定位真实站点长流式输出在真机上仍然卡顿的剩余热点。该流程只 attach 已安装的 OpenChat 进程并采集 Instruments trace，不安装、不卸载、不清理 app 数据，避免破坏真机里已经配置好的端点、API Key 和会话状态。

## 脚本入口

```bash
python3 scripts/trace_long_stream_device.py doctor
python3 scripts/trace_long_stream_device.py prepare --device <device-udid-or-name>
python3 scripts/trace_long_stream_device.py record --device <device-udid-or-name> --time-limit 60s
```

实现位置：`scripts/trace_long_stream_device.py`。

默认值：

- bundle id：`fukujusou.openchat.com`
- 进程名：`OpenChat`
- Instruments 模板：`Time Profiler`
- 输出目录：`/private/tmp/openchat-long-stream-<timestamp>/`

## 采集前准备

1. 等手机系统更新完成并解锁。
2. 确认 OpenChat 是已经配置真实站点的那份 app。
3. 手动打开 OpenChat，进入目标聊天页面。
4. 保持当前背景开关状态不变；如果要对比背景开/关，分别采两轮 trace，并在 `capture-notes.md` 里注明。
5. 不在采集中粘贴 API Key、真实 endpoint secret 或隐私聊天内容。

## 分阶段命令

### 1. 环境检查

```bash
python3 scripts/trace_long_stream_device.py doctor
```

用途：

- 确认 `xctrace` 可用。
- 确认 `Time Profiler`、`SwiftUI`、`Hitches` 等模板/Instrument 存在。
- 列出已连接真机候选。

手机正在更新或暂时没连接时，可只检查本机工具：

```bash
python3 scripts/trace_long_stream_device.py doctor --skip-devices
```

### 2. 只读预检查

```bash
python3 scripts/trace_long_stream_device.py prepare --device <device-udid-or-name>
```

用途：

- 确认真机上已安装 `fukujusou.openchat.com`。
- 确认 OpenChat 当前是否正在运行。
- 导出 `device-apps.json`、`device-processes.json` 和 `prepare-manifest.json` 到 run 目录。

如果显示 `Running process: not found`，手动打开 OpenChat 到目标聊天页后再运行 `record`。

### 3. 采集 Time Profiler

```bash
python3 scripts/trace_long_stream_device.py record --device <device-udid-or-name> --time-limit 60s
```

采集开始后立刻在手机上触发一次长回复。建议单轮 45-90 秒，覆盖：

- 等待首 token；
- 中段长流式输出开始变卡的位置；
- 流式结束和最终落库/统计刷新。

脚本会输出：

- `.trace` 包：可直接用 Instruments 打开。
- `trace-toc.xml`：`xctrace export --toc` 的 XML 摘要。
- `manifest.json`：设备、bundle、进程、模板、时长和命令记录。
- `capture-notes.md`：手动补充背景状态、会话类型、复现动作和可见卡顿时间点。
- `record.log`：xctrace 命令输出。

## 推荐采集矩阵

先做最小矩阵，避免被网络波动污染：

| 轮次 | 背景 | 操作 | 目的 |
|---|---|---|---|
| A | 当前设置 | 真实站点长回复一次 | 复现用户实际卡顿 |
| B | 关闭 Vibe Background | 同一类长回复一次 | 分离背景 draw 成本 |
| C | 当前设置 | 长回复中手动上滑/下滑 | 分离流式更新 + 滚动布局成本 |

每一轮都使用新的 run 目录，并在 `capture-notes.md` 写清楚背景状态和可见症状。

## 分析关注点

打开 `.trace` 后优先看主线程 Call Tree，按 Self Weight / Running Time 排序：

- `ChatTimelineViewController`、`ChatTimelineDataSource`、`UICollectionViewDiffableDataSource`：流式尾条是否仍触发过多 snapshot/reconfigure/layout。
- `ChatTimelineLayout`、`ChatTimelineHeightMeasurer`、`NSString.boundingRect`、`UILabel` / TextKit：长文本高度测量是否仍在主线程占比高。
- `ChatTimelineTextCache`、`NSAttributedString`、`AttributedString(markdown:)`：Markdown 预解析是否已经离开主线程；若主线程仍出现大量 parse，需要追查 fallback。
- `VibeBackgroundUIKitView`、Core Graphics、Core Image、`CIContext`：背景 draw / blur / color 后处理是否抢主线程。
- `UIAccessibility`：超长流式文本的 accessibility label 是否形成额外成本。
- `URLSession`、JSON decode、SSE parser：确认网络和解析是否只是后台成本，还是把主线程挤爆。

如果 A 卡、B 明显不卡，下一步优先拆背景异步绘制或降低 streaming phase 背景预算。如果 A/B 都卡，优先继续拆流式尾条的主线程提交、文本测量和 diff/layout。

## 约束

- 不运行 install / uninstall / terminate / launch，除非明确要重启 app。默认流程只 attach 现有进程。
- 不修改签名配置和 `OpenChat.xcodeproj`。
- 不把 `.trace` 提交进 git；trace 默认保存在 `/private/tmp`。
- 真机 trace 会增加运行时开销，因此只用来定位热点，不把绝对帧率当作最终用户体验数值。
