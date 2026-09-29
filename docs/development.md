# 开发与验证

开发环境：Node.js 24+、Python 3.10+。macOS 原生助手由 Xcode Command Line Tools 编译为 arm64 / x86_64 通用程序；普通用户使用安装包中的成品，无需编译。

```bash
npm ci
npx playwright install chromium --only-shell
python3 scripts/build_release.py
npm test
npm run test:privacy
```

macOS 额外运行原生测试：

```bash
node tests/startup-native.cjs .devtools/macos-startup-bridge
```

PowerShell 测试：`pwsh -File tests/windows.ps1`。Windows CI 还会运行 `tests/windows-native.ps1`，验证安装、快捷方式、后台停止和卸载。

`powershell -NoProfile -ExecutionPolicy Bypass -File tests/windows-launch.ps1` 使用模拟启动/包 API，验证 Store 身份精确匹配、冷启动、已连接复用、后台恢复和已有工作窗口保护。`tests/windows-startup-native.ps1` 还验证显式启动不依赖输入检测，且 Store 激活失败不回退到直接执行。运行前先构建 Windows 安装包。

Windows 启动适配器测试：`powershell -NoProfile -ExecutionPolicy Bypass -File tests/windows-startup-native.ps1`。它仅操作临时隐藏应用，检查进程身份、Raw Input 活动分类、正常退出/拒绝及重开。`startup/` 为 Windows 适配器；macOS 保持原有 `macos/startup/` 实现。

只构建 Windows：`python scripts/build_release.py --platform Windows`。其版本取自 `package.json` 的 `windowsVersion`，不修改 macOS 的 `version` 或已有发布附件。Windows 发布使用 `v<版本>-windows` 标签，只上传 Windows ZIP 和该 ZIP 的校验文件。

`build_release.py` 在 macOS 生成两个平台的 ZIP，在 Windows 生成 Windows ZIP。文件输出到 `dist/`，附带 SHA256 校验清单。发布前将本次源码加入 Git 暂存区，再执行隐私检查；检查覆盖所有受跟踪源码和安装包。

## 数据与兼容性

额度来自客户端 CLI 的账号接口。Plus 显示短周期与每周额度，Pro 显示周额度；大于 50% 为绿、10%～50% 为黄、小于 10% 为红。

Token 读取本机会话数据库中的累计值，包含缓存输入，不代表当前上下文大小。色块的四档分界为 100 万、1000 万和 1 亿；无记录时为灰色。额度约每分钟刷新，Token 约每 5 秒刷新。

插件依赖客户端内部界面和调试接口。自动化测试使用临时目录、模拟页面与独立测试应用，不读取真实账号。macOS 自动加载已完成本机真实客户端重启验证；Windows 安装流程由 CI 验证，已登录客户端的长期兼容性仍需更多设备反馈。
