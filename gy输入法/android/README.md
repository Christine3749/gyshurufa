# GY 输入法 Android 版（`android/`）

> 设计契约：`../ANDROID-DESIGN.md`（v2） · 施工拆解：`../ANDROID-V0.1-TASKS.md`
> 当前状态：**T0 工程脚手架 + T2 纯 JVM 候选治理实现**。T2 的编译、静态检查与单测待本机配置 JDK 17 后执行；T1 的 native 选型见 `docs/adr/0001-librime-android-integration.md`。

## 身份契约（升级 ABI，勿漂移）

| 字段 | 值 |
| --- | --- |
| applicationId | `wang.shurufa.inputmethod.GYInputAndroid` |
| 代码包 / namespace | `wang.shurufa.inputmethod.android` |
| IME 服务 | `wang.shurufa.inputmethod.android.GyInputMethodService` |
| 品牌显示名 | `输入法.网` |

唯一真相是 `identity.lock`；改动它 = 显式迁移。校验：`python scripts/verify_identity.py`
（含零 `<uses-permission>` 隐私门禁）。纪律与 `macos/scripts/verify-input-source-contract.sh` 一致。

## 构建前置

- JDK 17（Temurin 或同规格）
- Android SDK 34（cmdline-tools 或 Android Studio 均可）
- 首次构建生成 wrapper（jar 不入库，CI 同样现生成）：
  ```bash
  gradle wrapper --gradle-version 8.9 --distribution-type bin
  ```

## 常用命令

```bash
./gradlew ktlintCheck detekt testDebugUnitTest   # 质量门禁
./gradlew assembleDebug                          # 构建 debug APK
./gradlew installDebug                           # 部署到设备
adb shell dumpsys package wang.shurufa.inputmethod.GYInputAndroid | grep permission  # 零权限留证
```

## T0 完成定义（打勾即进入 T1）

- [ ] CI 全绿（身份门禁 → ktlint → detekt → 单测 → assembleDebug）
- [ ] 真机/模拟器：安装 → 启用 → 设为默认 → 任意输入框弹出占位键盘
- [ ] 占位键盘：字母直出、⌫ 删除、↵ 换行、空格上屏
- [ ] `dumpsys package` 截图证明零权限（营销资产同步归档）

## 结构

```
android/
├── identity.lock              # 身份契约锁（唯一真相）
├── scripts/
│   ├── verify_identity.py     # 身份 + 零权限门禁（CI 第一步）
│   └── render-launcher-icon.py# 启动图标渲染（VI 令牌：墨黑底 + 白 GY）
├── gradle/libs.versions.toml  # 版本目录（升级留痕处）
├── detekt.yml                 # 静态分析门禁（maxIssues: 0）
├── core/                      # 纯 JVM 核心逻辑（T2 起，不依赖 Android）
└── app/src/
    ├── main/kotlin/wang/shurufa/inputmethod/android/
    │   ├── GyInputMethodService.kt          # IME 服务（T0：占位键盘 + 最小输入链路）
    │   ├── SetupActivity.kt                 # 启用/设默认两步引导
    │   └── keyboard/
    │       ├── KeyboardLayout.kt            # 键位表（纯 JVM，T3 扩展点）
    │       └── PlaceholderKeyboardView.kt   # 自绘占位键盘（T3 替换为正式 KeyboardView）
    ├── test/kotlin/...        # 身份契约守卫 + 键位表结构约束
    └── androidTest/kotlin/... # 真机冒烟（服务可绑定最小契约）
```

## T0 已知边界（后续任务接管，勿在 T0 修补）

- 占位键盘无气泡/上滑/长按/滑删（T3/T4）；空格键模式标为静态文本（T6 模式机）
- 色板为简化浅色；VI 全令牌主题表 T3 接入
- librime JNI 未接入（T1）；候选 UI 未实现（T5，T2 治理与绝对索引映射已先行编码）
- release 未启用混淆（启用前必须完成 R8 全量回归）
