# 奶蛙 Codex 桌宠

原版奶蛙动画桌宠，附可选的 Windows 用量按钮、气泡和低额度提醒。用量服务由用户自行接入；下载后没有预置账号、接口或密钥。

![奶蛙预览](docs/pet-preview.png)

## 下载与安装

到 [Releases](https://github.com/AkaCMD/naifrog-desktop-pet/releases/latest) 下载 `naifrog-desktop-pet-v1.0.0.zip`，解压后进入文件夹。

要求：支持自定义桌宠的 Codex 桌面版。安装脚本及用量组件要求 Windows 10/11、Windows PowerShell 5.1；自备音效额外需要 Python 3.11+。

在解压目录打开 PowerShell，只安装桌宠：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

同时安装用量显示：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -WithUsage
```

重启 Codex，在 **设置 → 外观 → 桌宠** 中选择 **奶蛙**。安装使用独立 ID `naifrog`，不会替换其他桌宠。也可手动将 `pet/` 内两个文件复制到 `~/.codex/pets/naifrog/`。

用量组件使用当前用户的启动项和 `Naifrog Usage Supervisor` 计划任务自动启动，在奶蛙可见时显示按钮。安装后未接入会显示 **未接入**，请按 [用量接入说明](usage/README.md) 配置。它不是 Codex 官方用量接口，也不会自动读取任何服务的账户凭据。

已安装版本再次运行安装命令即可更新，保留用量设置和自定义适配器。`-NoStart` 可在更新时不启动辅助程序。用量组件跟随 Codex 暴露的 UI 元素，应用升级可能需要调整；若任务计划注册失败，桌宠文件仍已安装，可按用量文档手动启动。

![用量气泡示例](docs/usage-demo.png)

上图为虚构演示数据，不代表真实账户用量。

## 可选音效

公开包不包含音效 WAV。你可以使用已获授权的本地 WAV，按 [音效配置说明](sound/README.md) 设置完成提示。

## 卸载

在解压目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

卸载只删除 `~/.codex/pets/naifrog/` 及匹配该路径的用量启动项、任务和进程。请先备份自己的适配器与设置。音效通知为手动配置，需自行恢复原来的 `notify`。

## 开发验证

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test.Usage.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\usage\Test.Regression.ps1
```

素材来源、修改说明和第三方许可见 [NOTICE.md](NOTICE.md)。本项目代码采用 [MIT](LICENSE)。
