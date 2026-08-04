# GY macOS P0 修复包 — 构建与验证说明

> 生成：2026-08-05，Windows 端静态修改，**未经编译**。第一次构建如报错，把错误原文贴回 Kimi 即可。

## 包内容

```
GYInput/Sources/GYInputController.m   ← 覆盖同名文件
GYInput/Sources/GYRimeBridge.h        ← 覆盖同名文件
GYInput/Sources/GYRimeBridge.mm       ← 覆盖同名文件
```

## 修了什么

1. **整句选词丢剩余拼音（P0-1）**：选词提交后检查 Rime 是否还有未消费的拼音（如 `xiayigeban` 选"下一"剩 `yigeban`），有则保留为新的预编辑并刷新候选，不再静默丢弃。新增 `GYRimeBridge.remainingCompositionInput`。
2. **组合中标点穿透（P0-3）**：打着拼音按 `, . ? ! ; :` 时，先提交首选候选（带 Rime 学习），再输出中文标点；无候选时提交原拼音+标点。不再把 ASCII 按键透传给应用。

## Mac 上操作步骤

```bash
# 1. 解开 zip，把 GYInput/ 覆盖到仓库的 macos/ 目录
cd ~/path/to/gy输入法/macos
unzip -o ~/Downloads/gy-macos-p0fix-20260805.zip

# 2. 构建 + 冒烟
./scripts/build-macos.sh
./scripts/smoke-test-macos.sh
```

## 手工验证清单（TextEdit 里测）

| 用例 | 期望 |
|---|---|
| `nihao` + Space | 上屏"你好"（回归） |
| `xiayigeban` 选"下一" | 剩余 `yigeban` 继续作为预编辑，候选刷新，可继续选词 |
| 打 `wo` 后按 `，` | 上屏"我，"（首选+中文逗号） |
| 打 `wo` 后按 `。` 无候选情况（如乱敲字母后） | 原拼音 + 中文标点一起上屏 |
| Esc / 回车 / 退格 | 行为不变（回归） |
| Shift 切换中英 | 行为不变（回归） |

## 回滚

三个文件在 git 里均有历史，覆盖前可先 `git diff` 确认、`git checkout -- macos/` 回滚。
