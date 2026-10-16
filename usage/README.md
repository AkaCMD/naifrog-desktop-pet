# 用量显示：自行接入

这是本地 Windows 辅助程序。公开版本没有内置服务地址、账号或密钥，也不获取 Codex 官方用量。未接入时显示“未接入”；接入后查询失败保留上次成功数据，并标明连接失败。

## 接入步骤

1. 运行根目录 `Install.ps1 -WithUsage`。
2. 在 `%USERPROFILE%\.codex\pets\naifrog\usage` 中，将 `Provider.Example.ps1` 复制为 `Provider.Local.ps1`。
3. 用你自己的查询逻辑替换示例。脚本接受 `param([string]$Directory)`，**只返回一个**下面格式的 PowerShell 对象，不输出日志。请求设置超时（建议 15 秒），凭据自行通过环境变量、Windows 凭据存储等方式管理，勿写入源码或提交 Git。
4. 将安装目录 `settings.json` 的 `providerScript` 设为 `Provider.Local.ps1`，`unit` 设为你的单位，如 `元`、`tokens` 或 `额度`。
5. 重新启动辅助程序，点击“用量 → 刷新”。更新安装会保留 `settings.json` 和 `Provider.Local.ps1`。

```powershell
[pscustomobject]@{
    periodStart = 1767225600   # 周期起点，Unix 秒，用作提醒去重标识
    periodEnd = 1767830400     # 周期终点，Unix 秒，必须晚于起点
    used = 25.0               # 已用，使用最终单位，不自动除以 10000
    available = 75.0          # 当前可用，负余额显示为 0
    reserve = 10.0            # 储备总额，没有则填 0
    reserveActive = 0.0       # 已启用储备，范围 0..reserve
}
```

所有金额/计数使用相同单位，`used` 和储备必须非负。缺字段或无效数据属于查询失败，不会转换成零额度。适配器负责鉴权、返回结构转换和周期计算；不得混入调试输出。

**Provider.Example.ps1 返回的是虚构演示数据。** 只有当你明确启用它时才会显示，不能用来判断真实账户余额。

设置默认每 60 秒刷新，最低 15 秒；剩余比例 = 可用 /（已用 + 可用）。降至 20%、10% 或耗尽时提醒，每周期每档只提醒一次，记录存于安装目录 `alert-state.json`。未启用储备不加入可用余额。更新时间采用系统本地时区。

仅运行你信任的适配器，因为它拥有当前用户权限。不要提交凭据、DPAPI 文件、状态、日志或真实用量截图。

## 手动启动与重启

在安装目录执行以下命令，启动守护程序：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File .\Usage.Supervisor.ps1
```

从最新解压包重新运行根目录 `Install.ps1 -WithUsage` 会先结束该安装的旧辅助进程并启动新版，同时保留接入配置。`-NoStart` 则停止后保持不运行。

## 演示预览（不需要服务）

在临时副本中将 `providerScript` 设为 `Provider.Example.ps1`，然后执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\NailongUsage.ps1 -Preview -TestExitSeconds 10
```

预览不保存提醒记录。桌宠可见时按钮跟随图像与原生活动入口；隐藏桌宠或选择其他桌宠时用量窗口隐藏。

## 按钮布局

用量按钮为 56×28 的圆角胶囊，位于原生活动入口下方，水平居中，间距 4 像素（100% 缩放）。用量窗口不覆盖活动入口的点击区域；活动列表展开时允许部分重叠。按钮随桌宠移动，靠近任务栏时保持下方位置。
