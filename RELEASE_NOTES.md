# audio_manager 1.0.0 重大发版说明

- 发布日期：2026-08-15
- 版本：1.0.0
- 包地址：https://pub.dev/packages/audio_manager
- 仓库：https://github.com/jeromexiong/audio_manager
- Dart SDK：`>=3.0.0 <4.0.0`
- Flutter：`>=1.20.0`

## 本次定位

`audio_manager` 从移动端音频播放插件升级为跨平台音频播放插件，正式支持 iOS、Android、macOS、Windows、Linux 和 Web 六类平台。

1.0.0 保持原有核心 API 和单例使用方式，同时补齐桌面端原生播放、系统媒体控制、Web/WASM 兼容性、静态分析质量和示例文档。

## 全平台支持

| 平台 | 播放后端 | 系统集成 |
| --- | --- | --- |
| iOS | AVPlayer | 锁屏控制、Control Center、通知栏 |
| Android | MediaPlayer | MediaSession、通知栏、锁屏控制 |
| macOS | AVFoundation | Now Playing、Control Center、媒体键 |
| Windows | Windows.Media.Playback | SMTC、任务栏媒体浮层 |
| Linux | GStreamer | MPRIS、桌面媒体键 |
| Web | HTMLAudioElement | 浏览器内播放 |

## 主要能力

- 支持本地 asset、本地文件和网络资源播放
- 支持播放、暂停、上一首、下一首、停止、跳转、循环和随机播放
- 支持音量、倍速、播放状态和错误回调
- 支持播放中更新标题、描述和封面
- 支持从后台 isolate 查询当前播放状态
- Android 使用 MediaSession / MediaStyle 提供通知和锁屏控制
- iOS 使用 MPNowPlayingInfoCenter / MPRemoteCommandCenter 提供锁屏和 Control Center 控制
- macOS 使用 Now Playing / Control Center 和媒体键
- Windows 使用 SMTC 提供任务栏媒体控制
- Linux 使用 MPRIS 接入 GNOME / KDE 等桌面媒体控制
- Web 基于 `package:web` 和 `HTMLAudioElement`，并移除顶层 `dart:io` 依赖，兼容 Web/WASM

## 重要变化

### 1. iOS Swift Package Manager

- iOS 新增 Swift Package Manager（SPM）支持，与 CocoaPods 双轨并行
- iOS 插件入口迁移为纯 Swift 的 `SwiftAudioManagerPlugin`
- iOS 源码迁移到 `ios/audio_manager/Sources/audio_manager/`
- podspec 最低部署版本调整为 iOS 13.0
- Flutter 3.24+ 会自动通过 SPM 集成，旧工程可继续使用 CocoaPods

### 2. 桌面端支持

- macOS：AVFoundation 播放，接入 Now Playing / Control Center、媒体键和系统音量同步
- Windows：`Windows.Media.Playback` 播放，接入 SMTC 和任务栏媒体浮层
- Linux：GStreamer `gst_player` 播放，接入 MPRIS 桌面媒体控制

### 3. Web/WASM 兼容

- 使用 `package:web` 替代已废弃的 `dart:html`
- 移除顶层 `dart:io` 导入，`file()` 使用条件导入的本地文件实现
- 修复 Web 端运行时崩溃、事件转发和本地资源加载问题

### 4. 质量与文档

- 启用 `package:lints/recommended` 并修复静态分析问题
- 新增 README 截图、平台支持表、安装说明和示例文档
- 补齐 pubspec 的 `repository` 和 `issue_tracker` 元数据
- 更新 CI，增加 macOS、Windows、Linux 桌面构建验证

## API 兼容性

原有核心 API 保持不变：

```dart
final audio = AudioManager.instance;

await audio.start(
  'assets/audio.mp3',
  'Title',
  desc: 'Artist',
  cover: 'assets/ic_launcher.png',
);

audio.onEvents((event, args) {
  print('$event $args');
});

await audio.playOrPause();
await audio.updateInfo(title: 'New title', desc: 'New artist');
final state = await audio.currentState();
```

从 `0.9.x` 升级到 `1.0.0` 时，业务代码通常无需修改。需要关注的迁移点：

- 重新执行 `flutter pub get`
- iOS 工程重新运行 `pod install`，或让 Flutter 3.24+ 自动集成 SPM
- macOS 工程如需网络音频，添加 `com.apple.security.network.client` entitlement
- Linux 构建环境需要 GStreamer 开发包
- Windows 构建环境需要 Windows 10 SDK 和 Visual Studio 2022+

## 平台注意事项

### iOS

- 后台播放需要 `UIBackgroundModes -> audio`
- 部分能力在模拟器上不可用，建议使用真机验证
- 没有后台音频需求时不要随意开启后台音频模式

### Android

- 最低支持 Android 6.0（minSdk 23）
- Android 12+ 需要使用显式 `PendingIntent` flags
- Android 13+ 需要运行时申请 `POST_NOTIFICATIONS`
- HTTP 明文资源需要配置 `android:usesCleartextTraffic="true"`

### macOS

- 网络音频需要 network client entitlement
- 系统媒体控制通过 Now Playing / Control Center 提供

### Windows

- 使用 C++/WinRT 和 Windows 10 SDK
- 需要 Visual Studio 2022+
- 系统媒体控制通过 SMTC 提供

### Linux

- 使用 GStreamer 播放
- 需要安装 GStreamer 基础与 bad plugins 开发包
- 桌面媒体控制通过 MPRIS 提供

### Web

- 使用 HTMLAudioElement 播放
- 浏览器不支持后台播放、通知栏或锁屏控制
- 自动播放行为受浏览器策略限制

## 已知限制

- 通知、锁屏和后台播放能力集中在 iOS / Android
- 桌面端通过系统媒体控制提供播放操作，不等同于移动端通知栏
- Web 端不支持后台播放和系统级媒体控制
- pub.dev 的 `Publisher` 仍显示为 `unverified uploader`，需要在 pub.dev 创建并验证 Publisher 后转移包

## 发布验证

本地（macOS 开发机 + 容器 / Parallels Win11）：

- macOS：`flutter build macos --debug` 通过
- Windows：Parallels Win11 + VS 18 C++ workload + FVM Flutter 3.44.9，`flutter build windows --debug` 通过
- Linux：podman amd64 容器 + Flutter 3.47.0，`flutter build linux --debug` 通过
- iOS：SPM 集成构建通过
- Web：`flutter build web` 与 WASM dry run 通过
- `flutter analyze` 无问题，`flutter test` 全部通过
- CI 已新增 macOS / Windows / Linux 桌面构建 job（推送后自动验证）

发布后 pub.dev 静态分析、SPM 与 WASM 兼容性扣分项均已在代码层面消除，评分以发布后的刷新结果为准。

## 升级建议

1. 在 `pubspec.yaml` 中升级依赖：

```yaml
dependencies:
  audio_manager: ^1.0.0
```

2. 重新拉取依赖并运行测试：

```bash
flutter pub get
flutter test
```

3. 按平台配置章节检查移动端权限、桌面端 entitlement 和构建依赖。

