# 为 audio_manager 做贡献

感谢你对 audio_manager 感兴趣！

audio_manager 是一个开源 Flutter 音频插件，支持 iOS、Android、macOS、Windows、Linux 和 Web。社区通过播放能力、通知、系统媒体控制、文档和示例贡献，一起让这个项目变得更好。

## 参与方式

提交代码并不是唯一的贡献方式。你还可以通过以下方式参与：

- 在 GitHub Issues 中报告 bug，并提供复现步骤
- 在 GitHub Discussions 中提出功能建议和 API 讨论
- 参与 review 开源 Pull Request，帮助其他用户解答问题
- 创建示例、示例应用或配套插件，并与社区分享
- 把你的项目关联到 `audio-manager`、`flutter-plugin` 或 `audio-player` 等 topics，方便其他人发现
- 撰写关于 audio_manager 的博客、教程和使用指南

## 开发环境

要求：

- Flutter stable channel
- Dart 3 或更高版本
- 需要本地验证的平台工具链

开始开发：

```bash
flutter pub get
flutter analyze
flutter test
```

CI 还会验证桌面端构建：

```bash
cd example
flutter build macos --debug
flutter build windows --debug
flutter build linux --debug
```

## Pull Request 指南

1. Fork 仓库，并从 `dev` 创建分支。
2. 每个 Pull Request 只做一件事。
3. 行为变化需要补充或更新测试。
4. 用户可见行为变化需要同步更新 `README.md`、`CHANGELOG.md` 和相关文档。
5. 提交 PR 前运行 `flutter analyze` 和 `flutter test`。
6. Pull Request 的目标分支使用 `dev`。

维护者会 review 改动，等待 CI 通过后合入 `master`，并进入后续版本发布。

## 代码规范

- 遵循现有 Dart 和 Flutter 代码风格。
- 遵守 `package:lints/recommended`。
- 保持公共 API 名称清晰，并与当前 API 风格一致。
- 只在代码不易理解时补充注释。

## 社区

请保持友善并乐于帮助。audio_manager 是面向 Flutter 和 Dart 社区的插件项目，任何贡献，无论是一处文档修正还是一项新平台集成，都非常有价值。

感谢你帮助改进 audio_manager！

