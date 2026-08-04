# GY 输入法

GY 输入法现在包含可安装的 Windows 原生 TSF 输入法核心，而不是网页输入模拟器。

## 架构契约

跨端实现遵循 [GY 产品标准](GY_INPUT_METHOD_PRODUCT_STANDARD.md) 与 [韧性输入法架构契约](release/ARCHITECTURE_CONTRACT.md)：稳定 Bridge、Session Guard、双完整 Engine、独立候选 UI 与 Data/Agent 故障域。输入路径离线且零网络；账户、同步和 AI 不得进入系统输入核心。

## 使用真正的输入法

在 PowerShell 运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\native\install.ps1
```

构建后的 DLL 位于 `native\build\bin\Release\GyIme.dll`。安装后，到 Windows 的中文（简体）键盘列表启用“GY 输入法（拼音）”。完整说明见 [native/README.md](native/README.md)。

## 旧网页项目

根目录的 Vite/React 项目仅保留为设置界面原型；它不会承担任何系统级输入职责，也不应通过 `npm run dev` 作为输入法运行。
