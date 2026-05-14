# 10. 提交与发布检查清单

## 每次提交前

- [ ] 没有新增 `try?` 吞掉关键保存/删除/导入错误。
- [ ] 没有在 `OpenChat/Core` 引入 App 层类型。
- [ ] 没有在 `OpenChat/Shared` 引入 Core 层类型。
- [ ] 新增 Feature 不直接构造 sibling Feature 的 View，除非在 App shell。
- [ ] 修改数据模型时只追加 migration，不修改旧 migration。
- [ ] 新增用户可见字符串进入 `Localizable.xcstrings`。
- [ ] 新增网络错误不会泄漏 Authorization/API Key。
- [ ] 新增 Prompt 数据块有边界和预算控制。

## 修改数据库时

- [ ] Migration 命名 `vN_description`。
- [ ] 有旧库迁移测试。
- [ ] 有空库创建测试。
- [ ] 有数据修复策略。
- [ ] 不破坏已有 Record decode。
- [ ] 如涉及删除/清空，确认 sqlite-vec 虚拟表也清理。

## 修改 Chat 生成链路时

- [ ] 正常完成保存 assistant。
- [ ] 取消生成 UI/DB 一致。
- [ ] 网络失败 UI/DB 一致。
- [ ] `isGenerating` 在所有路径恢复。
- [ ] 不在 MainActor 做过重解析/循环。
- [ ] Prompt preview 与实际发送消息一致。

## 修改 Prompt/Memory/WorldBook 时

- [ ] 四层顺序不变。
- [ ] 当前输入不在历史里重复。
- [ ] `[Time]` 仍在最后 current turn。
- [ ] 世界书/记忆/示例对话都有 token cap。
- [ ] 注入内容有边界，不能覆盖系统规则。
- [ ] 记忆提取不会重复处理已处理消息。

## 修改 Settings/API Endpoint 时

- [ ] API Key 不进入 SQLite 明文。
- [ ] API Key 不回显。
- [ ] 测试连接失败有错误提示。
- [ ] 保存失败不 dismiss。
- [ ] 默认 endpoint/model DB 约束不被破坏。

## 发布前

- [ ] P0 问题全部关闭。
- [ ] CI build/test 绿色。
- [ ] 无模型权重时普通测试绿色。
- [ ] 有模型权重时 integration tests 绿色。
- [ ] 导出/导入 round-trip 通过。
- [ ] 清空数据能清空 message、conversation、memory_entry、memory_embedding。
- [ ] API Key 不在 DB、导出文件、日志、错误弹窗中出现。
- [ ] `.xcprivacy` 存在并准确。
- [ ] 数据库文件保护属性设置。
- [ ] 手动端到端测试：配置 endpoint → 新建角色/世界书 → 聊天 → 停止生成 → 重启 → 导出 → 清空 → 导入。
