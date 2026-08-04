# GY 输入法 版本验收报告（Windows）

> 复制本模板，逐条真实填写；不要照抄示例数字。生成方式见文末「如何生成本报告」。

## 结论
- 版本号：`<version>`（例：0.9.39）
- 发布通道：`<channel>`（candidate / beta / stable）
- 本机是否真实生效：是 / 否
- 三侧（本机 / 仓库 release.json / 线上 API）是否一致：是 / 否

## 一、发布/版本链条（客观事实）
| 来源 | 版本 | state | sha256 |
|---|---|---|---|
| 仓库 `release/release.json` | | | |
| `native/release/GYInput-<version>/release.json` | | | |
| 线上 API（`/api/releases/latest`） | | | |

## 二、本机运行态
| 检查项 | 结果 |
|---|---|
| `HKLM:\SOFTWARE\GYInput\HostVersion` | |
| `install-state.json.coreVersion` | |
| `install-state.json.requiresClientReload` | |
| TSF DLL 注册（`HKLM:\SOFTWARE\Classes\CLSID\{5F689D3D-73E3-4C2B-979A-2DD86E438D6F}\InprocServer32`） | |
| `Validate-GYInput.ps1` 结果 | 全部通过 / 有失败项（附输出） |

## 三、本次操作中遇到的问题（如有）
逐条记录：现象 → 根因 → 是产品 bug 还是操作/环境问题 → 是否已有对应修复。

## 四、健康度评分（1-10，主观但要给依据）
| 维度 | 分数 | 依据 |
|---|---|---|
| 基础激活与本机运行稳定性 | | |
| 版本一致性（Host/Core） | | |
| 验证脚本可复用性 | | |
| 发布源同步可追溯性（本机/Git/线上是否可核对） | | |

## 五、待修正事项
逐条列出：问题 → 文件:行号 → 修复优先级（P0-P3）→ 代价估计 → 是否已修。

## 如何生成本报告的「一、二」部分
```bash
pwsh -File "native/installer/Get-GYReleaseState.ps1"
pwsh -File "native/installer/Validate-GYInput.ps1"
```
两个脚本都是只读的，不会修改注册表或仓库内容；把输出直接贴进对应表格即可。

## 已知的三处历史坑（复核时留意）
1. `$Host` 是 PowerShell 内建只读变量，手写脚本时不要用它接收安装路径变量名，用 `$hostPath`/`$hostPathTarget` 等替代名。
2. Windows PowerShell 默认没有 `HKCR:` 这个盘，查 TSF 注册要用 `HKLM:\SOFTWARE\Classes\CLSID\...`。
3. 仓库里的 `release.json`（顶层 `windows`/`macos`）和线上 API 响应（包了一层 `platforms.windows`/`platforms.macos`）形状不同，手写对比脚本时容易读错字段——`Get-GYReleaseState.ps1` 已经按正确形状处理，直接复用即可。
