# 对话角色不是 Agent

> 状态：目标架构原则。

## 1. 结论

OpenChat 的对话角色不应 agent 化。角色是 persona，不是 worker。

推荐表述：

> Role is not an agent. Role is the rendered persona produced from character card, relationship state, memory, world background, and current conversation state.

中文表述：

> 对话角色不是 agent，而是由角色卡、关系状态、长期记忆、世界背景和当前会话状态共同渲染出的 persona。

## 2. 为什么不 agent 化角色

- 角色的核心价值是稳定扮演，不是自主完成任务。
- 主聊天模型已经负责角色回复，再包一层 `CharacterAgent` 不会自然增加能力。
- agent 化会引入工具权、目标、任务队列和自治行为，容易破坏 RP 沉浸感。
- 用户期望与角色说话，而不是观察一组 agent 协商后输出。

## 3. 角色回复展示不等于 agent 化

角色回复保持主聊天模型的自然流式文本输出。UI 可以对模型自然输出的 Markdown 斜体动作做展示适配，例如：

```text
*她停下脚步，指尖轻轻碰了碰杯沿。*

“你刚才那句话，是认真的吗？”
```

这属于显示层适配，不等于让角色拥有 AgentCore runtime、tool call、后台目标或自治权限。

第一阶段不应强制 `[ACTION]` / `[SPEECH]` schema，也不应给普通角色回复开放 tool call，避免模型因工具可用而脱离角色进入任务型 thinking。若后续要做强结构化动作/台词，需要先单独解决流式半包解析、增量渲染和 fallback。

## 4. 血肉感来自状态，不来自 agent 权限

角色“有血肉”的来源应是可维护状态：

```text
CharacterCard
  静态设定：人格、外貌、语气、背景

RelationshipState
  用户与角色当前关系、信任、亲密度、冲突、承诺

ConversationState
  当前场景、情绪余波、未完成事件、近期目标

Memory
  跨对话事实、事件、关系变化

WorldBook
  世界规则和背景知识
```

这些状态由 Background 系统筛选注入，主聊天模型负责把状态渲染成角色回复。

## 5. 允许的“角色相关后台能力”

可以有后台能力维护角色状态，但它们不是角色本人：

- relationship updater：提取关系变化。
- conversation state tracker：维护当前场景和未完成事项。
- memory extractor：抽取长期记忆。
- BackgroundWorker：选择本轮应注入的背景。

这些 worker 不拥有角色发言权。

## 6. Prompt 边界

主模型看到的是：

```text
Stable Identity: character card / system prompt
Stable Conversation State: compressed or truncated history
Current Background: selected world, memory, relationship, scene entries
Current Turn: user input + time
```

主模型输出的是角色回复。

后台 worker 输出的是结构化数据，不是角色回复。
