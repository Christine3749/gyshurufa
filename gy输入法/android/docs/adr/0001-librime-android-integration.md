# ADR 0001：Android librime 以仓库源码 + NDK 构建

- 状态：已决定架构，尚未完成实现
- 日期：2026-08-05
- 关联：ANDROID-DESIGN.md §二、ANDROID-V0.1-TASKS.md T1

## 背景

Android 必须与桌面端使用同一套 Rime 行为，且 v0.1 不申请联网权限。现有 Windows
native 工程已经包含两个可复用的、受版本控制的输入：

- librime 源码：`native/third_party/librime`，当前提交
  `1d0df6e40cdcac17a986adc65e4668ae84ae0ada`。
- 共享词库源：`native/runtime/rime/shared`，17 个文件、20,686,023 bytes（2026-08-05
  本地核验）。`luna_pinyin.schema.yaml` 的菜单页大小为 96；Android bridge 仍必须在
  治理后限制到 75 个可见候选。

`macos/GYInput/Resources/rime-data` 在当前工作区不存在，不能把它写成 Android 的数据
来源。Windows 的 `runtime/rime/lib/rime.dll` 与 `rime.lib` 是 Windows 产物，绝不可打进
Android APK。

## 决策

1. **以仓库内的 librime 源码经 Android NDK 构建动态库**，而非下载或无校验地嵌入第三方
   预编译库。生产 ABI 是 `arm64-v8a`、`armeabi-v7a`、`x86`、`x86_64`；不以包体为由裁减。
2. 将 `native/runtime/rime/shared` 作为唯一的 Android 共享词库源。Gradle 在构建期复制到
   generated assets，并对相对路径 + SHA-256 清单做校验；不得在 `app/src` 维护第二份手工副本。
3. 首次启用时把 assets 复制到应用私有 `filesDir/rime/shared`，再调用 Rime `deploy`。
   学习数据放在 `noBackupFilesDir/rime/user`，因此既不需要存储权限，也不会被系统云备份。
   部署必须在设置引导/预热阶段完成，不能放在首次 `onStartInput` 的热路径里。
4. JNI 只暴露语义 API：初始化/部署、`processKey`、跨页采集原始候选、按绝对原始索引提交、
   清空组合、简繁/英文模式、清空 userdb。候选质量治理和显示序号映射仍留在 Kotlin `:core`，
   JNI 不能重新实现或绕过它。

## 备选方案

Trime 维护的预编译 librime 只能作为应急候选：必须先记录其准确版本、源码提交、每 ABI 的
SHA-256、许可证、Boost/插件依赖，以及 minSdk 26 的真机结果。上述证据不齐时不得接入，
否则构建不可复现，也无法证明与桌面行为一致。

## 当前阻塞与下一步

本机可用 Android Studio 附带的 JDK 21、Android SDK 36/36.1 和 NDK 27.1.12297006；但项目
契约所需的 JDK 17、SDK 34、Gradle 8.9 尚未就绪，AGP 8.5.2/Kotlin 插件也不在本地缓存。
一次受控的依赖解析在 64 秒后超时，故当前不能构建/链接/在设备上验证 JNI；不可将此写成
“没有 Android SDK”。
这不是以 stub 冒充引擎完成的理由。配置好工具链后，按下面顺序完成 T1：

1. 建立 CMake/Gradle externalNativeBuild，并为四个 ABI 编译出 `libgyrime.so`；记录 NDK 版本。
2. 实现 assets staging + 哈希清单，验证 Rime 在私有目录可 deploy；首次部署完成前 IME 显示
   明确的本地准备状态，绝不阻塞主线程。
3. 实现 bridge，并以 instrumented test 验证 `nihao` 候选含“你好”、跨页绝对索引提交、
   `zh_hans`/`ascii_mode` 和 userdb 清理。
4. 在 arm64 真机记录首次部署时长、后续键盘冷启动与候选刷新 P95；只有后两项满足设计预算
   才能关闭 T1。

## 结果

T1 目前是**架构已锁、实现待工具链**。T2 可以并且已经以纯 JVM 模块先行；T5 只能接收
`CandidateSnapshot.selectionAt()` 生成的选择令牌，不能从 UI 下标自行计算 Rime 索引。
