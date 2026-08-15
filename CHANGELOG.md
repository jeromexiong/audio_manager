## 0.9.3
- Add Swift Package Manager (SPM) support on iOS, coexisting with CocoaPods; the iOS entry point is now the pure-Swift `SwiftAudioManagerPlugin`
- Migrate iOS sources into the SPM package layout (`ios/audio_manager/Sources/audio_manager/`) and align the podspec deployment target with iOS 13.0
- Migrate the example app to SPM (CocoaPods deintegrated)
- Adopt `package:lints/recommended` and resolve all static-analysis findings (type annotations, file naming, web doc comments, example dependency placement) to pass the pub.dev analysis check
- Make the package web/WASM-compatible by removing the top-level `dart:io` import (`file()` now uses a conditional `local_file.File`, with a path-only stub on web)
- Add macOS support (AVFoundation, same method-channel contract; Now Playing/Control Center + media keys, system-volume sync via CoreAudio; no iOS-only audio-session/lock-screen/volume-view)

## 0.9.2
- Rebuild the web implementation on `package:web` (`HTMLAudioElement`), fixing the runtime crash, adding event forwarding, and resolving local assets in release builds
- Request the Android 13+ `POST_NOTIFICATIONS` permission at runtime and re-post the playback card once granted
- Fix pause being ineffective, volume not syncing, and notification display on iOS; migrate to the `UIScene` lifecycle
- Fix the notification cover not showing and `stop` leaking through release builds on Android
- Clear the leftover playback card when the app exits and sync the track index on switch
- Fix `timeupdate` clearing the error state and clamp `setVolume` arguments
- Upgrade the Android build toolchain and align the example's compileSdk/targetSdk with data backup rules
- Refactor the example into a layered controller-and-screen structure
- Use a reliable HTTPS cover in the example and add CI workflows

## 0.9.1
- Support Android 12+ `PendingIntent` flags and foreground service type
- Use `MediaSession` / `MediaStyle` for Android notification and lock-screen controls
- Add `updateInfo` to update title, description, and cover while playing
- Fix cover load failure stopping playback
- Fix shuffle mode so every track is visited before the sequence repeats
- Guard native events after Flutter engine detach
- Request Android audio focus and avoid iOS background audio mixing
- Migrate package and example to Dart 3
- Surface native start errors and clear stale loading state
- Sync iOS playback state with the real AVPlayer state
- Add notification title line and button visibility configuration
- Use AVURLAsset with a User-Agent for stream URLs
- Add `currentState` for native playback state queries
- Refactor the example into a layered controller and screen structure
- Use a reliable HTTPS cover in the example

### Fixed issues
- Closes [#98](https://github.com/jeromexiong/audio_manager/issues/98), [#99](https://github.com/jeromexiong/audio_manager/issues/99), [#84](https://github.com/jeromexiong/audio_manager/issues/84)
- Closes [#75](https://github.com/jeromexiong/audio_manager/issues/75), [#97](https://github.com/jeromexiong/audio_manager/issues/97), [#93](https://github.com/jeromexiong/audio_manager/issues/93), [#85](https://github.com/jeromexiong/audio_manager/issues/85)
- Closes [#58](https://github.com/jeromexiong/audio_manager/issues/58), [#60](https://github.com/jeromexiong/audio_manager/issues/60), [#62](https://github.com/jeromexiong/audio_manager/issues/62), [#63](https://github.com/jeromexiong/audio_manager/issues/63)
- Closes [#73](https://github.com/jeromexiong/audio_manager/issues/73), [#86](https://github.com/jeromexiong/audio_manager/issues/86), [#87](https://github.com/jeromexiong/audio_manager/issues/87), [#92](https://github.com/jeromexiong/audio_manager/issues/92)

## 0.8.2
- fix `playOrPause` method error
- Add support for loading covers from the app's data dir on Android

## 0.8.1
- update to flutter 2.0
- fix to null safety

## 0.7.3
- fix ios replay
- support web
- update android notification text to english

## 0.5.7+1
- Fix Crush while playing androin audio in offline [#28](https://github.com/jeromexiong/audio_manager/issues/28)
- Fix play local files [#37](https://github.com/jeromexiong/audio_manager/issues/37)
- Fix Repeat one [#40](https://github.com/jeromexiong/audio_manager/issues/40)
- Fix #36, #43, #45, #47
- Fix stop and play

## 0.5.5+3

- Play audio immediately
- `setRate` method to fix num conversion double
- Fix iOS remote Control previous/next error
- Fix iOS remove lock screen control from notification center

## 0.5.4+1

- Fix loading local file crash

## 0.5.4

- fix ios autoplay
- fix ios remote control of pre/next play event

## 0.5.3+3

- fix out of bounds
- fix repeated problem of notification service
- replace android notification chinese text to icon

## 0.5.3

- fix iOS stuck
- add `toPlay` and `toPause` method
- add interrupt pause

## 0.5.2+1

- remove `AndroidManifast.xml` redundant configuration
- Optimize playback status updates

## 0.5.1+5

- Supports playing local directory media files
- add seek completed callback
- Add volume control & volume changed callback

## 0.5.1

- Add internal playlist management

## 0.3.1+1

- Fix iOS remote command error

## 0.3.1

- Add `auto` attribute whether to play automatically, default is true
- Optimize the time type
- Fix repeat callbacks

## 0.2.1+hotfix.2

- Fix iOS loop playback

## 0.2.1

- Add cache hint
- Fix start and stop error
- List loop playback

## 0.1.5

- Optimization error prompt.

## 0.1.4

- Fix pub.dev support.
- Add method to get playback info.

## 0.1.3

- Fix Initialize before playing.

## 0.1.2

- Fix ios timeupdate.
- Customize the style of the slider of the demo

## 0.1.1

- update change log

## 0.0.2

- update `seekTo`, `rate`, `onEvents` callback handle.
- update demo

## 0.0.1

- Initial version, created by Jerome Xiong
