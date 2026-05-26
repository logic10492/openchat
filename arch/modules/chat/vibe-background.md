# Vibe Background

> 状态：首版已实现，内容 watcher 尚未接入。
> 所属模块：`Features/Chat/`
> 目标：为聊天界面提供一种状态驱动的动态背景，让 Liquid Glass 前景 chrome 有可折射、可呼吸、可随对话节奏变化的视觉底层。内容驱动由后续 watcher 方案接入。

## 1. 核心定位

`vibe-background` 不是普通壁纸，也不是消息内容的可视化摘要。它更像聊天界面的环境层：

- **状态驱动**：根据输入、发送、等待、流式回复、停止、错误等会话状态改变运动节奏。
- **内容驱动预留**：首版不直接分析对话内容；后续通过独立 watcher 监听对话，选择颜色组和构成参数，再喂给背景渲染层。
- **玻璃底层**：背景位于消息列表与 Liquid Glass chrome 之后，为顶部角色胶囊、输入 capsule、工具按钮等玻璃表面提供柔和的采样色和折射感。
- **低频不抢戏**：视觉重点仍然是文字阅读。背景应以大面积、低对比、低细节的运动为主，避免在气泡下方出现高频纹理。

换句话说，Liquid Glass 是前景的材质与界面触感，`vibe-background` 是被玻璃采样的“气氛场”。

## 2. 与 Liquid Glass 的关系

这个方向和 Liquid Glass 很契合，原因是 Liquid Glass 需要一个有层次、但不过度具体的背板。纯色或静态渐变会让玻璃只剩透明控件；过于真实的图片又容易干扰文字。流体背景正好处在中间：

- **玻璃需要慢变化的底色**：熔岩泡、极光带、流体墨迹、粒子雾都能让玻璃表面产生轻微的色彩折射。
- **玻璃不适合承载所有内容**：当前 Chat 设计里消息气泡保持扁平色块，Liquid Glass 主要用于导航胶囊、输入 capsule、按钮和工具面板。`vibe-background` 应继续尊重这个边界，不把每条消息都做成玻璃。
- **背景负责情绪，chrome 负责操作**：背景表达对话氛围；按钮、输入框、设置入口继续用明确的系统交互样式。
- **模糊是保护层**：高斯模糊/材质模糊用于把流体运动压成低频色块，保证玻璃好看，同时保证聊天文本可读。

实现时可以把它看成三层：最底层是动态色场，中间层是高斯模糊和渐隐遮罩，最上层是消息列表与 Liquid Glass chrome。

## 3. 基础方案：Molten Aurora

初始方案可以命名为 `Molten Aurora`，也就是你说的“熔岩灯 + 极光背景 + 高斯模糊”。

更准确的核心循环是：

```text
熔岩灯 -> 流彩 -> 熔岩灯
```

静止态保持熔岩灯式的团块和慢漂移；用户输入、模型等待和流式回应会把团块拉伸成左右游移的流彩；回复结束后流彩重新聚合成熔岩灯。这样背景不是一直处于粒子特效或极光特效状态，而是在“可读的低频形体”和“生成中的流动能量”之间往返。

这个循环也更适合 Liquid Glass：熔岩灯阶段给玻璃提供稳定的大块采样色，流彩阶段给玻璃提供动态折射感，回到熔岩灯阶段时界面重新安静下来。

### 静止态

- 底部有缓慢漂移的熔岩泡，像高黏度液体在暗色池中浮沉。
- 上半屏有极光式的柔和光带，运动方向偏斜，不做明显条纹。
- 全屏套一层较重的模糊，让背景只保留体积、色温和方向感。
- 叠加非常轻的颗粒感，避免纯渐变显得塑料。
- 熔岩泡之间可以有轻微的颜色交换，但不要持续拉成丝带；静止态应读成“团块”，不是“流彩”。

### 用户发送请求

- 用户点击发送后，不再生成“熔岩泡落下”的独立物件。
- 发送动作只触发背景进入蓄压：原本缓慢漂移的团块被横向拉开，形成左右移动的宽色带。
- 色带可以轻微错层移动，像玻璃背后有几股不同速度的流彩在互相推挤。
- 如果用户快速连续发送，只提高色带亮度和横向位移幅度，不生成多个额外事件物件。

### LLM 等待回应

- 背景整体稍微降速，像系统在“蓄压”。
- 熔岩泡周围出现细小亮点，但不上升，表示回复尚未开始。
- 如果等待时间较长，亮点可以形成很慢的呼吸，而不是频繁闪烁。
- 熔岩团块继续被拉长，进入熔岩灯到流彩的过渡，但还不完全展开。

### LLM 流式回应

- 回复开始后，从底部向上冒出细小颗粒。
- 颗粒初速较慢，随后加速上升，与 token 流式输出形成心理同步。
- 粒子密度可以跟 `StreamingStats` 的 TPS 或输出 token 增量弱绑定：TPS 越高，上升颗粒越密，但需要限幅，避免高 TPS 时变成噪声。
- 颗粒到达中上部后逐渐融入流彩带，让“模型输出”从底部压力释放成上方光幕。
- 流彩不是高频彩虹线，而是被高斯模糊压过的宽色带；边缘可以粗糙，因为最终只保留色块运动。
- 回复结束时，粒子数量减少，流彩带缓慢收束，重新聚合成熔岩泡，回到静止态。

### 停止、错误和重新生成

- 停止生成：上升粒子不要立刻消失，而是快速失去加速度，像被关掉热源后自然沉静。
- 错误：不要用强红色警报背景。可以在底部色场出现一次低饱和暗红涟漪，同时由常规错误 UI 负责明确说明。
- 重新生成：旧回复对应的上升粒子淡出，新的一轮粒子从底部重新起势；不需要做“倒带”动画。

## 4. 渲染策略

因为 `vibe-background` 的最终输出会经过高斯模糊和半透明遮罩，原始渲染 pass 不需要追求精细边缘。首版可以主动利用这一点降低成本：

- **低分辨率渲染**：背景可以在屏幕宽高的 1/2、1/3 甚至 1/4 分辨率生成，再放大到全屏并模糊。聊天背景不需要像图标或文字一样保持像素级清晰。
- **弱化抗锯齿要求**：熔岩泡、色带和粒子在原始 pass 中允许有锯齿和硬边，后续高斯模糊会把它们压成柔和体积。
- **大形体优先**：先保证团块、色带、流向和亮度节奏成立，不要把预算花在细碎边缘、真实液体模拟或高粒子数。
- **分层模糊**：熔岩泡/流彩层用较重模糊，少量粒子层可以用较轻模糊或发光，避免全部糊成一片。
- **帧率分级**：idle 阶段可以低频更新；streaming 阶段提高更新频率；页面不可见、低电量或 Reduce Motion 时暂停或降级。
- **和消息刷新解耦**：背景动画不应依赖 `ChatMessageTimelineView` 的 body 刷新。流式 token 只投递少量状态参数，例如当前 phase、TPS bucket、response progress pulse。
- **UIKit 作为动画时钟**：当前实现不是 SwiftUI `Canvas` 驱动，而是 `UIViewRepresentable` 包一层 `VibeBackgroundUIKitView`，由 `CADisplayLink` 驱动自己的 motion state，再把低分辨率 Core Graphics 画面放大和模糊。这样 LLM 流式更新只影响状态输入，不直接触发整层背景重建。

这个策略意味着视觉实现不需要从一开始就做昂贵的流体模拟。更可控的做法是用低分辨率 metaball / mesh gradient / shader-like color field 生成粗糙动态图，再通过模糊和玻璃采样把它变成完整质感。

### 昼夜主题

背景不应只适配深色模式。夜间版可以保留深色熔岩池和高对比流彩；日间版需要独立调色，而不是简单把黑底提亮：

- 夜间：深蓝黑/暗紫/暖橙作为底色，流彩可以用较高饱和度和 screen-like 叠加，适合玻璃 chrome 的发光感。
- 日间：晨雾白/浅金/淡青作为底色，流彩透明度更低，混合方式更像轻微染色或水彩扩散，避免白底上出现脏色块。
- 日间粒子要更克制，优先读成空气中的细小反光，而不是夜间发光点。
- 两套主题共享同一状态机和运动语法，只替换 palette、透明度、背景遮罩和 chrome 对比度。
- 切换主题时不应该重置会话状态；背景可以平滑过渡到对应 palette。

## 5. 状态驱动模型

`vibe-background` 可以使用一个轻量的状态机，而不是让 View 直接根据零散布尔值拼动画。

| 输入来源 | 视觉参数 | 说明 |
|---|---|---|
| 会话状态 | 运动速度、方向、粒子发射、短促横向 impulse | idle / waiting / streaming / completed / stopped / error |
| 发送事件 | 进入蓄压，相邻色带横向错层移动 | 不再生成“熔岩泡落下”的独立物件 |
| 流式统计 | 粒子密度、上升速度、光带亮度 | 只做弱绑定，避免把 token 速度直译成刺眼动画 |
| 外观主题 | palette、透明度、背景遮罩和 chrome 对比度 | 夜间 / 日间共享运动语法，但使用不同调色 |
| 可访问性环境 | 降低或禁用动画、降低透明度 | Reduce Motion / Reduce Transparency / 高对比 |

首版状态语法应保持克制：发送后进入等待蓄压，色带快速移动一下再衰减；流式回应时色带展开并伴随细小粒子上升；回复结束后色带收束回熔岩灯。当前 demo 已验证的方向是横向色带比输入物件下坠更成立，因此后续实现应以色带 impulse 为主。

### 内容驱动预留

内容驱动暂不进入首版实现。后续可以单独构造一个 watcher：

- watcher 监听当前对话、角色卡、世界书、Stage 参与者和近期消息节奏。
- watcher 不直接驱动动画细节，只输出一个或多个颜色组，例如主色、辅色、暗部、粒子 accent、日间/夜间适配色。
- 背景渲染层只消费稳定的 palette token 和少量强度参数，避免每条消息都导致大幅跳色。
- 内容映射保持“气氛映射”，不要变成“背景复述文本”。比如角色是冷静、夜色、机械感，可以映射为更冷的色温、更细的粒子和更直的流线；不需要在背景里画机械零件。
- watcher 应独立于 `ChatMessageTimelineView` 刷新路径，避免内容分析和流式 UI 更新互相放大性能成本。

## 6. 其他同类背景方向

这些都属于和 `vibe-background` 相似的状态驱动背景，可以作为皮肤或后续迭代方向。

| 方向 | 交互语法 | 与 Liquid Glass 的契合点 | 风险 |
|---|---|---|---|
| **Bioluminescent Tide** | 用户输入像一颗光滴沉入暗潮；回复时细小冷光从底部升起 | 冷光、暗水、柔焦非常适合玻璃采样，适合夜间聊天 | 容易过暗，需要保证气泡下方对比度 |
| **Ink Diffusion** | 输入是一滴墨沉入水中；回复是细丝状墨雾反向上升并散开 | 墨水扩散天然适合高斯模糊，视觉高级且不需要具体图像 | 扩散纹理若太细，会影响文字阅读 |
| **Magnetic Field** | 输入像磁场扰动，回复时粒子沿场线向上排列 | 可表达“系统在组织回答”，适合工具、推理、技术聊天 | 线条容易变成装饰噪声，需要很低对比 |
| **Cloud Chamber** | 输入触发一次凝结轨迹；回复时雾粒沿隐藏流场上升 | 粒子雾在玻璃下方会形成很好的深度感 | 粒子数量和帧率需要严格控制 |
| **Thermal Vent** | 用户意图下沉成热源；回复像热流带着微粒上涌 | 和“从下往上冒出”的 LLM 回复逻辑最直接 | 如果做得太具象，会偏场景化而不是通用聊天背景 |
| **Nebula Bloom** | 输入像小型引力坍缩；回复时星尘向上展开成光云 | 色彩漂亮，适合角色扮演和宏大世界观 | 容易太华丽，和日常设置页/输入栏不一定统一 |
| **Breathing Membrane** | 整个背景像一层柔性膜，输入造成凹陷，回复造成向上的波纹 | 最克制，阅读干扰最小，和玻璃材质关系稳定 | 个性较弱，可能不如熔岩/极光有记忆点 |

优先级上，`Molten Aurora` 可以作为默认概念；`Bioluminescent Tide` 和 `Ink Diffusion` 最适合作为备选皮肤；`Magnetic Field` 更适合未来工具调用、推理模式或 agent 化工作流。

## 7. 建议的首版边界

首版不接入内容 watcher。建议只做一个可控、低风险的最小版本：

1. 只在 Chat 页面启用，不进入设置页、角色卡页或世界书编辑页。
2. 只读取会话状态、生成状态、流式 token 增量、外观主题和可访问性环境。
3. 默认提供 `off / subtle / vivid` 三档，`subtle` 作为默认候选。
4. `Reduce Motion` 开启时保留静态模糊色场，禁用色带 impulse 和粒子上升。
5. `Reduce Transparency` 或高对比设置开启时降低背景亮度，并加强消息区域遮罩。
6. 低电量模式下降低刷新频率，页面不可见时暂停动画。
7. 夜间和日间提供独立 palette，不把深色版本简单提亮成浅色版本。
8. 不引入新的数据库字段，首版偏好可以放在外观设置的 `UserDefaults`。

当前实现证据：

- `OpenChat/Features/Chat/Views/ChatView.swift`：在聊天 shell 的 `ZStack` 底层挂载 `ChatConversationBackground(isGenerating: viewModel.isGenerating)`，背景位于 `ChatEdgeEffectViewport` 和 timeline 之后，不进入 `InputBarView`。
- `OpenChat/Features/Chat/Views/ChatConversationBackground.swift`：把聊天背景入口从 chrome 杂项文件中独立出来，只负责组合 `VibeBackgroundView` 与页面 fallback 背景色。
- `OpenChat/Features/Chat/Views/VibeBackgroundView.swift`：SwiftUI shell 只读取环境值并桥接到 `VibeBackgroundUIKitRepresentable`，不再承载动画时钟。
- `OpenChat/Features/Chat/Views/VibeBackgroundUIKitRepresentable.swift`：用 `UIViewRepresentable` 把 SwiftUI 环境和 `VibeBackgroundUIKitView` 连接起来。
- `OpenChat/Features/Chat/Views/VibeBackgroundUIKitView.swift`：当前活跃渲染层。它用 `CADisplayLink` 驱动 motion state，按低分辨率 Core Graphics 生成背景，再做一次 Core Image blur / saturation / brightness 合并后处理，并在 `Reduce Motion`、`Reduce Transparency` 和 `window == nil` 时降级或暂停。刷新率策略遵循 ProMotion 的可变刷新模型，但不会追 120Hz：`preferredFrameRateRange` 按 phase 封顶到 idle/completing 24fps、waiting 30fps、streaming 60fps，并保留同一 phase 内部 draw budget；动画推进使用 `targetTimestamp` 计算 delta，避免把背景时钟锁死在某个固定设备刷新档位。离屏渲染尺寸去掉额外 overscan，只在最终绘制到屏幕时保留视觉 overscan。
- `OpenChat/Features/Chat/Views/VibeBackgroundDriver.swift`：保存跨 phase 的连续 motion state，避免 streaming/waiting/completing 切换时重置 flow、bandT 或粒子状态，从而减少 streaming 期间的抽搐感。streaming 粒子发射率和上限被限制，避免长回复期间背景动画和消息增量渲染长期争抢主线程。
- `OpenChat/Features/Chat/Views/VibeBackgroundUIKitPalette.swift`、`VibeBackgroundParticle.swift`：UIKit 路径使用的 palette 和粒子模型。
- `OpenChat/Features/Chat/Views/VibeBackgroundPalette.swift`、`VibeBackgroundPhase.swift`、`VibeBackgroundBlob.swift`、`VibeBackgroundShade.swift`：保留旧的 SwiftUI demo 资产和参数定义，供对照和后续收敛使用，但不再是当前渲染入口。

后续实现内容 watcher 或外观开关时，需要同步更新：

- `arch/modules/chat/views.md`：说明 `ChatView` 背景层的位置，以及它和 `ChatEdgeEffects`、`InputBarView` 的边界。
- `arch/modules/chat/evidence.md`：补充已实现文件、可访问性处理、性能验证和 UI 截图测试。
- 外观设置文档：如果加入开关或强度档位，需要同步 `arch/modules/settings/appearance.md`。

## 8. 验证要点

- 文本可读性：长消息、代码块、浅色/深色模式下，背景不能穿透成噪点。
- 布局边界：背景只在消息 viewport 背后活动，不改变输入栏高度、不影响 safe area。
- 性能：流式回复时不能因为粒子动画加重 `ChatMessageTimelineView` 的刷新压力。
- 可访问性：`Reduce Motion`、`Reduce Transparency`、高对比模式必须有明确 fallback。
- 截图回归：至少覆盖 idle、waiting、streaming、completed 四个状态，避免背景遮挡 composer 或导航胶囊。
- 验证优先级：streaming 期间重点看背景是否还会随 token 刷新产生整层重建或闪烁；如果仍有抖动，再考虑把 blur / color adjust 下沉到 Metal 或 Core Animation filter 路径。
