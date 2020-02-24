# audio_manager
[![pub package](https://img.shields.io/pub/v/audio_manager.svg)](https://pub.dartlang.org/packages/audio_manager)

A flutter plugin for music playback, including notification handling.
> This plugin is developed for iOS based on AVPlayer, while android is based on mediaplayer

<img src="https://raw.githubusercontent.com/jeromexiong/audio_manager/master/screenshots/android.png" height="300" alt="The example app running in Android"><img src="https://raw.githubusercontent.com/jeromexiong/audio_manager/master/screenshots/iOS.png" height="300" alt="The example app running in iOS">

## iOS
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

## Android
Since `Android9.0 (API 28)`, the application disables HTTP plaintext requests by default. To allow requests, add `android:usesCleartextTraffic="true"` in `AndroidManifest.xml`
```xml
<application
	...
	android:usesCleartextTraffic="true"
	...
>
```
> Android minimum support version 23 **(build.gradle -> minSdkVersion: 23)**

## How to use?
The `audio_manager` plugin is developed in singleton mode. You only need to get`AudioManager.instance` in the method to quickly start using it.

## Quick start
⚠️ you can use local `assets` resources or `network` resources

```dart
// Initial playback. Preloaded playback information
AudioManager.instance
	.start(
		"assets/audio.mp3",
		// "network format resource"
		"title",
		desc: "desc",
		cover: "assets/ic_launcher.png",
		// cover: "network cover image resource")
	.then((err) {
	print(err);
});

// Play or pause; that is, pause if currently playing, otherwise play
AudioManager.instance.playOrPause()

// events callback
AudioManager.instance.onEvents((events, args) {
	print("$events, $args");
}
```
