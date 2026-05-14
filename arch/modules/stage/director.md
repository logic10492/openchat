# Director / 导演

> 状态：目标架构规划，尚未实现。

Director 是 Stage 的舞台调度者。它可以影响场景节奏、参与角色和发言计划，但不能替角色成为用户正在对话的 persona。

## 1. 三种工作模式

### 1.1 `silent` / 闭嘴

导演不主动介入。

行为：

- 不生成导演建议。
- 不改变发言计划。
- 只保留用户显式导演指令。
- Stage 按默认策略选择角色回复。

适用：

- 用户只想和角色自然对话。
- 多角色自动调度应尽量少打扰。

### 1.2 `agent` / agent 模式

导演作为后台 agent 参与调度，但不直接对用户输出。

可以：

- 生成 stage instruction。
- 建议哪些角色应参与本轮。
- 建议发言顺序。
- 标记剧情节奏问题。
- 提醒冲突、未完成事件或场景连续性。

不可以：

- 直接生成 assistant 回复。
- 替角色写台词。
- 静默修改角色卡、世界书或长期记忆。
- 把内部分析暴露给主聊天 UI，除非用户打开调试/导演面板。

### 1.3 `userControlled` / 用户接管模式

用户显式以导演身份说话，输入被解释为舞台指令。

可以：

- 指定下个发言角色。
- 设置场景变化。
- 调整节奏。
- 要求某角色暂时退场或加入。
- 给角色行动约束。

限制：

- 用户导演指令不应被保存为角色本人说过的话。
- 指令应进入 Stage/ConversationState，而不是直接当作 user-to-character 台词。

## 2. 用户随时以导演身份说话

无论当前模式是 `silent`、`agent` 还是 `userControlled`，用户都可以临时以导演身份说话。

UI/数据层建议：

```swift
enum StageInputRole: String, Codable, Sendable {
    case participant
    case director
}
```

当用户切换为 `director`：

- 本轮输入作为 stage instruction。
- 不当作角色听到的普通台词，除非用户显式要求“让所有角色听到”。
- 可以影响 Background request、speaker plan 和 Stage state。

## 3. Director 输出 contract

```swift
struct DirectorPlan: Sendable {
    let mode: DirectorMode
    let stageInstructions: [StageInstruction]
    let speakerPlan: [SpeakerTurn]
    let diagnostics: DirectorDiagnostics
}

enum DirectorMode: String, Codable, Sendable {
    case silent
    case agent
    case userControlled
}
```

`DirectorPlan` 是结构化计划，不是 chat message。

## 4. 与 BackgroundWorker 的区别

| 项目 | Director | BackgroundWorker |
|---|---|---|
| 关注点 | 舞台调度、角色参与、节奏 | 背景条目选择、排序、裁剪 |
| 是否可输出给用户 | 默认不直接输出；用户可查看导演面板 | 默认不输出 |
| 是否能决定发言角色 | 可以建议 | 不可以 |
| 是否能选择背景条目 | 不直接选择 | 可以 |
| 是否能写角色台词 | 不可以 | 不可以 |
