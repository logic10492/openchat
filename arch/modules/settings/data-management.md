# 数据管理

> 父文档：[settings/index.md](index.md)

## 1. 功能描述

- 导出所有应用数据
- 从文件导入数据
- 清除所有数据
- 重建世界书语义索引：仅维护 `world_book_entry_embedding` / `world_book_entry_embedding_meta`，不得删除角色卡、世界书、世界书条目、对话或消息

## 2. 视图设计

```
Section: 世界书语义索引
  [重建世界书语义索引]  ← 非破坏性，只补建/刷新索引

Section: 数据导出
  [导出所有数据]
  [导入数据]

Section: 危险操作
  [清除所有数据]  ← 红色，二次确认
```

实现证据：
- `OpenChat/Features/Settings/Views/DataManagementView.swift`：索引维护、数据导出占位、危险操作拆成独立 `Section`；清除入口只打开 confirmation dialog。
- `OpenChat/Features/Settings/ViewModels/SettingsViewModel.swift`：`rebuildWorldBookSemanticIndex()` 只调用 `WorldBookEmbeddingIndexer.rebuildAllMissingOrStale(limit: nil)`；`clearAllData()` 才调用 `DatabaseManager.eraseAllData()`。
- `OpenChatTests/Features/SettingsTests/SettingsViewModelWorldBookIndexTests.swift`：覆盖手动 rebuild 会补建索引，并保持角色卡、世界书和世界书条目存在。

## 3. 导出格式

导出为单个 JSON 文件：

```json
{
  "formatVersion": 1,
  "exportedAt": "2026-04-14T12:00:00Z",
  "data": {
    "endpoints": [...],
    "characterCards": [...],
    "worldBooks": [...],
    "worldBookEntries": [...],
    "conversations": [...],
    "messages": [...],
    "settings": {
      "defaultTemperature": 0.8,
      ...
    }
  }
}
```

## 4. 导出流程

1. 导出全部数据库表内容
2. 导出 UserDefaults 中的设置
3. 序列化为 JSON
4. 通过 `ShareSheet` 或保存到文件

## 5. 导入流程

1. 用户选择 JSON 文件
2. 解析并验证格式版本
3. 提示用户：覆盖现有数据 / 合并（跳过已存在 ID 的记录）
4. 批量写入数据库
5. 更新 UserDefaults

## 6. 清除数据

1. 二次确认弹窗："确定要清除所有数据吗？此操作不可恢复。"
2. 清空所有数据库表
3. 重置 UserDefaults 到默认值
4. 不删除 API 端点配置（用户可能还需要）

清除数据不得与“重建世界书语义索引”共用按钮、共用确认弹窗或共用同一 Form row。重建索引是可重复的维护操作；清除数据是不可逆危险操作。

## 7. 安全考虑

- 导出文件包含 API Key 明文 → 在导出确认弹窗中提醒用户
- 导出文件使用 `.openchat` 扩展名便于识别
