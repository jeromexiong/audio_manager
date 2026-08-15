# audio_manager_example

A runnable Flutter example for the `audio_manager` plugin.

It demonstrates local assets, local files, network playback, player controls, volume, seeking, and system media controls.

## Run

```bash
flutter pub get
flutter run
```

You can also run it on a specific platform:

```bash
flutter run -d macos
flutter run -d windows
flutter run -d linux
flutter run -d chrome
```

## Notes

- iOS and Android notifications, lock-screen controls, and background audio should be tested on a real device or a supported emulator configuration.
- Desktop playback integrates with macOS Now Playing / Control Center, Windows SMTC, and Linux MPRIS.
- The web demo uses `HTMLAudioElement` and does not provide notification or background playback behavior.
