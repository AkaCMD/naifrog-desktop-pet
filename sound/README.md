# 自备音效（可选）

本包不含 WAV；本地版本曾使用 [Tomorins/nailong-codex-pet](https://github.com/Tomorins/nailong-codex-pet) 的音效。其分发限制见该项目 ASSET-USAGE.md。本目录的播放接口是独立实现，请自行提供有权使用的 WAV。

要求 Windows、Python 3.11+，Codex 支持 `notify` 完成事件。用你自己的常驻目录保存 `notify.py`，将 `local.example.json` 复制为同目录 `local.json`，填写 WAV 的绝对路径（推荐 JSON 中使用 `/`）。如 Codex 数据目录不同，可另加 `codexHome`。

备份 `~/.codex/config.toml`，在任何 `[表名]` 之前的**顶层**设置通知命令（替换两个路径为你的实际路径）：

```toml
notify = ["C:/path/to/python.exe", "C:/path/to/sound/notify.py"]
```

如果已有 `notify`，先把原数组完整复制到 `local.json` 的 `forwardNotify` 中，再替换顶层 `notify`；脚本会将原始事件参数转发给旧命令。不要增加重复的 `notify`，不要改变其他配置。重启 Codex 后，只有选中 `custom:naifrog` 且收到 `agent-turn-complete` 事件才播放。

可先执行 `python C:/path/to/sound/notify.py --play` 测试 WAV。卸载时将 `notify` 恢复为原值，再删除自己配置的音效目录。此配置完全可选，不影响桌宠和用量按钮。
