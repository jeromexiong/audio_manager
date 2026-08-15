import 'package:flutter/material.dart';

import 'app.dart';

/// A runnable example for the `audio_manager` plugin.
///
/// The player UI is defined in [AudioManagerExampleApp] and covers:
/// - local assets, local files, and network playback
/// - play / pause / next / previous / stop and seeking
/// - volume and playback rate
/// - notifications and lock-screen / system media controls
/// - querying playback state from background isolates
///
/// Minimal usage:
///
/// ```dart
/// import 'package:audio_manager/audio_manager.dart';
///
/// final audio = AudioManager.instance;
///
/// await audio.start(
///   'assets/xv.mp3',
///   'Example title',
///   desc: 'Example artist',
///   cover: 'assets/ic_launcher.png',
/// );
///
/// audio.onEvents((event, args) {
///   debugPrint('$event $args');
/// });
///
/// await audio.playOrPause();
///
/// await audio.updateInfo(
///   title: 'Updated title',
///   desc: 'Updated artist',
/// );
///
/// final state = await audio.currentState();
/// debugPrint('${state['isPlaying']}');
/// ```
void main() {
  runApp(const AudioManagerExampleApp());
}
