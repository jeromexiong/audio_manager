## Next
- Support Android 12+ `PendingIntent` flags and foreground service type
- Use `MediaSession` / `MediaStyle` for Android notification and lock-screen controls
- Add `updateInfo` to update title, description, and cover while playing
- Fix cover load failure stopping playback
- Fix shuffle mode so every track is visited before the sequence repeats
- Guard native events after Flutter engine detach
- Request Android audio focus and avoid iOS background audio mixing
- Migrate package and example to Dart 3

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
