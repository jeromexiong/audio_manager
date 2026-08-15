# Contributing to audio_manager

Thank you for your interest in contributing to audio_manager!

audio_manager is an open-source Flutter audio plugin maintained by the community. It supports iOS, Android, macOS, Windows, Linux, and Web, and it welcomes contributions that make playback, notifications, system media controls, documentation, and examples better for everyone.

## Ways to contribute

Contributing code is not the only way to help. Here are other useful ways to get involved:

- Report bugs and share reproduction steps in GitHub Issues
- Propose feature ideas and discuss API changes in GitHub Discussions
- Review open pull requests and help answer questions from other users
- Create examples, sample apps, or companion plugins and share them with the community
- Associate your project with topics such as `audio-manager`, `flutter-plugin`, or `audio-player` to help others discover it
- Write blog posts, tutorials, and how-to guides about audio_manager

## Development setup

Requirements:

- Flutter stable channel
- Dart 3 or newer
- Platform toolchains for the platforms you want to verify locally

Get started:

```bash
flutter pub get
flutter analyze
flutter test
```

The CI also verifies desktop builds:

```bash
cd example
flutter build macos --debug
flutter build windows --debug
flutter build linux --debug
```

## Pull request guidelines

1. Fork the repository and create a branch from `dev`.
2. Keep each pull request focused on one change.
3. Add or update tests when behavior changes.
4. Update `README.md`, `CHANGELOG.md`, and other documentation when user-facing behavior changes.
5. Run `flutter analyze` and `flutter test` before opening the pull request.
6. Open the pull request against `dev`.

Maintainers will review the changes, wait for CI to pass, and merge them to `master` for a future release.

## Code style

- Follow the existing Dart and Flutter conventions.
- Respect `package:lints/recommended`.
- Keep public API names clear and consistent with the current API.
- Add meaningful comments only where the code is not self-explanatory.

## Community

Please be respectful and helpful. audio_manager is built for the Flutter and Dart community, and every contribution, from a small documentation fix to a new platform integration, is appreciated.

Thank you for helping improve audio_manager!

