# Codex Usage Badge · Codex 用量条

为 Codex 桌面端增加额度显示、项目配色和会话 Token 统计，适配浅色与深色主题。

本 fork 的 Windows `0.10.1-fork.1` 试验版增加可靠启动入口：安装后从桌面“Codex 用量条”打开，首次启动即带连接参数，点击/输入不再取消加载，也不需要关闭重开。支持按当前安装包身份激活 Microsoft Store 客户端。[使用说明](docs/windows.md)。下方下载链接仍是上游版本，不包含此改进。

![Codex Usage Badge：原生风格额度圆环、项目配色与 Token 色块](assets/cover.png)

## 功能

- **额度圆环**：查看订阅剩余额度，绿、黄、红对应充足、偏低和即将耗尽。Plus 支持 5 小时与每周额度双圆环。
- **文件夹配色**：在项目菜单中选择颜色，方便区分不同项目。
- **会话 Token**：用蓝色色块表示用量，悬停查看累计 Token，按万、千万、亿显示。

## 下载

[**macOS v0.9.2 预发布版**](https://github.com/jaykinhoo9/codex-usage-badge/releases/tag/v0.9.2-macos) · [Windows v0.10.0](https://github.com/jaykinhoo9/codex-usage-badge/releases/tag/v0.10.0-windows)

| 系统 | 安装包 | 使用说明 |
| --- | --- | --- |
| macOS · Apple Silicon / Intel | [下载 ZIP](https://github.com/jaykinhoo9/codex-usage-badge/releases/download/v0.9.2-macos/CodexUsageBadge-macOS-0.9.2.zip) | [macOS 安装](docs/macos.md) |
| Windows 10 / 11 | [下载 ZIP](https://github.com/jaykinhoo9/codex-usage-badge/releases/download/v0.10.0-windows/CodexUsageBadge-Windows-0.10.0.zip) | [Windows 安装](docs/windows.md) |

macOS 和 Windows 安装后均可沿用原应用图标，启动时自动加载。Windows 后台在新窗口尚未开始操作时请求正常重开；点击、输入或后台启动时会跳过。需要已登录的 Codex 客户端和 Node.js 24+，安装器会优先查找客户端自带的运行环境。

[更新记录](CHANGELOG.md) · [问题反馈](https://github.com/jaykinhoo9/codex-usage-badge/issues) · [开发说明](docs/development.md) · [隐私与安全](SECURITY.md)

非官方项目，与 OpenAI 无关联。采用 [MIT 许可](LICENSE)。
