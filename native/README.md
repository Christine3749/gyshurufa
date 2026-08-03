# GY 输入法原生核心（Windows TSF）

这不是网页或 Electron 模拟器。`GyIme.dll` 是 Windows Text Services Framework（TSF）文本服务：Windows 会把它加载为键盘输入法，候选项可提交到当前光标位置。

## 构建与安装

请在 **PowerShell** 中执行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\native\install.ps1
```

脚本使用本机 Visual Studio Build Tools 生成 x64 DLL，并只向当前用户注册输入法。随后在 Windows 的中文（简体）键盘列表中启用“GY 输入法（拼音）”。第一次安装后建议注销再登录一次。

卸载：

```powershell
.\native\install.ps1 -Uninstall
```

## 原生行为

- A–Z 开始 TSF 组合输入；Space / Enter 选首词，1–9 直选，方向键选词，Backspace / Esc 编辑或取消。
- 候选窗是 Win32 原生窗口，不读取网页文本，也不依赖浏览器、网络或 API key。
- 词典在 `src/PinyinEngine.cpp`，可继续扩充高频词库、用户词频 SQLite 与双拼方案。

> 安装/卸载会改动当前用户的 Windows 输入法配置，脚本不会自动执行，须由用户手动运行。
