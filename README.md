# audio_manager
[![pub package](https://img.shields.io/pub/v/audio_manager.svg)](https://pub.dev/packages/audio_manager)

A Flutter plugin for music playback, notification handling, lock-screen controls, and desktop system media controls.

## Screenshots

| Android | iOS | macOS |
| --- | --- | --- |
| <img src="https://raw.githubusercontent.com/jeromexiong/audio_manager/master/screenshots/android.png" width="220" alt="The example app running in Android"> | <img src="https://raw.githubusercontent.com/jeromexiong/audio_manager/master/screenshots/iOS.png" width="220" alt="The example app running in iOS"> | <img src="https://raw.githubusercontent.com/jeromexiong/audio_manager/master/screenshots/macos.png" width="320" alt="The example app running in macOS"> |

## Supported platforms

| Platform | Playback / integration |
| --- | --- |
| iOS | AVPlayer + lock screen / Control Center |
| Android | MediaPlayer + MediaSession notification |
| macOS | AVPlayer + Now Playing / Control Center |
| Windows | Windows.Media.Playback + SMTC |
| Linux | GStreamer + MPRIS |
| Web | HTMLAudioElement |

## Installation

Add the dependency to `pubspec.yaml`:

```yaml
dependencies:
  audio_manager: ^1.0.0
```

## iOS
The plugin supports both CocoaPods and Swift Package Manager (SPM) on iOS. Flutter 3.24+ integrates it via SPM automatically; otherwise it falls back to CocoaPods.

Add the following permissions in the `info.plist` file
```xml
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
	</array>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
```
- ⚠️ Some methods are invalid in the simulator, please use the real machine
- ⚠️ Only add `UIBackgroundModes -> audio` when your app really keeps playing audio in the background. If the app does not provide background audio, App Store review may reject it with guideline 2.5.4.

## Android
Since `Android9.0 (API 28)`, the application disables HTTP plaintext requests by default. To allow requests, add `android:usesCleartextTraffic="true"` in `AndroidManifest.xml`
```xml
<application
	...
	android:usesCleartextTraffic="true"
	...
>
```
- ⚠️ Android minimum supported version 23 `(app/build.gradle -> minSdkVersion: 23)`
- ⚠️ Compile against Android SDK 34 or newer when targeting Android 12+ apps. The plugin now requires explicit `PendingIntent` flags, a media playback foreground service type, and Android 13+ receiver export flags.
- ⚠️ Android notification and lock-screen controls use `MediaSession` / `MediaStyle`. Custom notification icons and full custom layouts are not exposed by the public API.

## Desktop (macOS / Windows / Linux)

Desktop playback integrates with the system media controls: macOS Now Playing / Control Center, Windows SMTC (taskbar media flyout), and Linux MPRIS.

- **macOS**: to stream network audio, add the `com.apple.security.network.client` entitlement to the app's entitlements files (`DebugProfile.entitlements` / `Release.entitlements`):
  ```xml
  <key>com.apple.security.network.client</key>
  <true/>
  ```
- **Linux**: requires GStreamer development packages to build (`gst_player` lives in gst-plugins-bad):
  ```bash
  sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgstreamer-plugins-bad1.0-dev
  ```
- **Windows**: built with the Windows 10 SDK (C++/WinRT); requires Visual Studio 2022+.

## Usage
The plugin uses a singleton. Get `AudioManager.instance` and start playback directly.

## Quick start
You can use local `assets`, local files, or network resources.

```dart
// Initial playback. Preloaded playback information
AudioManager.instance
	.start(
		"assets/audio.mp3",
		// "network format resource"
		// "local resource (file://${file.path})"
		"title",
		desc: "desc",
		// cover: "network cover image resource"
		cover: "assets/ic_launcher.png")
	.then((err) {
	print(err);
});

// Play or pause; that is, pause if currently playing, otherwise play
AudioManager.instance.playOrPause();

// events callback
AudioManager.instance.onEvents((events, args) {
	print("$events, $args");
});
```

## Update metadata while playing

```dart
await AudioManager.instance.updateInfo(
  title: "new title",
  desc: "new artist",
  coverUrl: "https://example.com/new-cover.png",
  titleMaxLines: 2,
  showPreviousButton: true,
  showStopButton: false,
);
```

Playback speed is supported through `AudioManager.instance.setRate(AudioRate.rate150)`.

## Query state from background handlers

Firebase background isolates cannot reliably receive `AudioManager.onEvents`. For short-lived checks, query the native state directly:

```dart
final state = await AudioManager.instance.currentState();
print(state["isPlaying"]);
print(state["title"]);
```
