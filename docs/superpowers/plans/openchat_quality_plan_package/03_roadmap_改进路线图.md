# 03. 改进路线图

## 优先级定义

| 优先级 | 含义 |
|---|---|
| P0 | 影响数据安全、用户信任、主链路正确性；应立即修复。 |
| P1 | 影响长期可维护性和产品闭环；应在下一个主版本前修复。 |
| P2 | 增强体验、鲁棒性和 AI/RP 质量；可排入稳定迭代。 |
| P3 | 高级能力和精细化优化；在基础稳定后推进。 |

## P0：立即修复

1. API Key Keychain 化。
2. 保存/导入/模型操作错误不再吞掉。
3. 流式生成取消/失败后的 UI 与 DB 状态一致。
4. `eraseAllData` 显式清理 `memory_embedding`。
5. Embedding 资源缺失时测试不阻断普通 CI。
6. live 容器启动失败不再静默切 preview/in-memory。

## P1：核心工程化

1. 执行分层漂移修复。
2. 增加源码边界测试。
3. 数据库唯一索引与一致性迁移。
4. 完成全量导入导出。
5. 记忆提取游标改为 message sortOrder/state table。
6. 网络超时、重试、错误截断/脱敏。
7. 添加 CI workflow 和格式/lint 基线。

## P2：AI/RP 体验增强

1. Prompt 数据块边界与防注入。
2. Token 预算校准和 per-model 安全余量。
3. 世界书解析升级：front matter、YAML/JSON、priority clamp、错误预览。
4. 角色卡示例对话编辑器。
5. 头像选择与资源管理。
6. 记忆管理 UI：查看、禁用、删除、纠错。

## P3：高级 RP 能力

1. 分支对话/消息树。
2. lorebook 高级触发：regex、depth、constant、probability、recursive。
3. 回复风格 profile：文风、篇幅、NSFW/安全边界、第一/第三人称等。
4. 角色关系状态机：好感、情绪、长期目标。
5. 多模型策略：本地模型草稿 + 云端模型润色/压缩。

## 分阶段计划

### Sprint 0：建立可复现基线（1–2 天）

**目标**：先确保任何改动都可以被稳定验证。

**任务**

- 明确模型权重缺失时的测试策略：mock/skip/集成测试标签。
- 添加 `scripts/test.sh` 或 Makefile，统一运行 project generation、build、tests。
- 添加 `KNOWN_LIMITATIONS.md`：记录模型权重、导入导出未接线、Keychain 未完成等已知状态。
- 检查 `ruby scripts/generate_xcodeproj.rb` 后工程文件是否稳定。

**验收**

- 无模型权重时，普通单元测试可运行。
- 有模型权重时，可额外运行真实 embedding 集成测试。
- 构建/测试命令文档化。

### Sprint 1：可靠性与安全热修（3–5 天）

**目标**：先修最容易损害用户信任的问题。

**任务**

- API Key 迁移到 Keychain。
- APIEndpoint 编辑 UI 改 `SecureField`。
- 所有保存按钮去掉 `try?`，失败时展示错误。
- stream cancel 策略落地：保留部分回复并落库，或确认后丢弃。
- `eraseAllData` 与删除角色/记忆时清理 vector rows。
- live 容器失败显示错误页，不切 preview。

**验收**

- 数据库导出不含 API Key 明文。
- 保存失败不会关闭编辑页。
- 取消生成后刷新应用，聊天内容与用户看到的一致。
- 清空数据后 memory_entry 和 memory_embedding 都为空。

### Sprint 2：架构边界修复（5–7 天）

**目标**：把文档中的分层规则变成源码事实。

**任务**

- Core 使用的默认值迁移到 Core/Shared config 或通过 DI 注入。
- ChatViewModel 不再持有 AppState，改注入闭包/协议。
- `Features/Support/SidebarView.swift` 移入 App shell。
- WorldBook 不直接构造 CharacterCard UI，改 route/coordinator。
- `String+Token.swift` 移出 Shared 或删除。
- 添加源码扫描测试。

**验收**

- 边界测试通过。
- `arch/AntiEntropy/layering-repair-plan.md` 状态更新为 closed 或记录受控例外。

### Sprint 3：数据闭环与一致性（5–8 天）

**目标**：让用户数据可备份、可恢复、可迁移。

**任务**

- 追加 v13 migration：默认项 unique index、message sortOrder unique index、记忆提取 state table。
- 实现版本化导出 snapshot。
- 实现导入 dry-run：校验、冲突预览、资源缺失提示。
- JSON TEXT 字段保存前校验，读取失败记录错误。
- 添加导入导出 round-trip tests。

**验收**

- 导出 → 删除数据 → 导入后，角色卡/世界书/endpoint metadata/对话/消息/记忆一致。
- 冲突导入可选择跳过、覆盖或生成新 ID。
- 坏 JSON 输入不会静默变空。

### Sprint 4：AI/RP 质量增强（5–8 天）

**目标**：提升长期 RP 的稳定、沉浸和可控性。

**任务**

- Prompt 数据块边界和防注入指令。
- 预算内单项截断/摘要。
- per-model token budget safety margin。
- 世界书导入解析升级。
- 记忆质量 UI：禁用/删除/纠错/手动添加。
- 记忆提取游标用 message sortOrder。

**验收**

- Prompt 单元测试覆盖四层顺序、防注入边界、oversized block 截断。
- 世界书导入失败有错误列表，而不是部分静默失败。
- 记忆提取不会在“无新记忆”时重复处理同一段消息。

### Sprint 5：产品化与发布准备（持续）

**目标**：从“开发可用”升级为“长期可维护”。

**任务**

- 添加隐私清单 `.xcprivacy`。
- 数据库文件保护属性。
- UI 测试/snapshot tests。
- 日志脱敏与诊断导出。
- 性能基准：大世界书、长对话、大量记忆。
- App Store/分发前检查。

**验收**

- 敏感信息不会进入日志/错误弹窗/导出包。
- 大型 RP 数据集下 prompt 组装和检索性能可接受。
