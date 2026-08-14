import 'dart:io';

import 'package:audio_manager/audio_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/demo_track.dart';

class PlayerController extends ChangeNotifier {
  final List<DemoTrack> tracks = [];

  String platformVersion = 'Unknown';
  String error = '';
  bool isPlaying = false;
  bool isLoading = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double volume = 0.0;
  int currentIndex = 0;
  PlayMode playMode = AudioManager.instance.playMode;

  bool _disposed = false;

  DemoTrack? get currentTrack {
    if (tracks.isEmpty) return null;
    final index = currentIndex.clamp(0, tracks.length - 1);
    return tracks[index];
  }

  Future<void> init() async {
    try {
      platformVersion = await AudioManager.instance.platformVersion;
    } catch (_) {
      platformVersion = 'Unknown';
    }

    tracks.addAll([
      const DemoTrack(
        url: 'assets/xv.mp3',
        title: 'Assets',
        subtitle: 'assets playback',
        coverUrl: 'assets/ic_launcher.png',
      ),
      const DemoTrack(
        url:
            'https://raw.githubusercontent.com/jeromexiong/audio_manager/master/example/assets/aLIEz.m4a',
        title: 'Network',
        subtitle: 'network playback',
        coverUrl:
            'https://raw.githubusercontent.com/jeromexiong/audio_manager/master/example/assets/aLIEz.jpg',
      ),
    ]);

    AudioManager.instance.audioList = tracks.map(_toAudioInfo).toList();
    AudioManager.instance.intercepter = true;
    AudioManager.instance.onEvents(_onEvents);

    await _prepareLocalTrack();
    isLoading = true;
    _notify();
    await play(0, auto: false);
    isLoading = false;
    _syncFromManager();
    _notify();
  }

  AudioInfo _toAudioInfo(DemoTrack track) {
    return AudioInfo(
      track.url,
      title: track.title,
      desc: track.subtitle,
      coverUrl: track.coverUrl,
      titleMaxLines: 2,
      showPreviousButton: true,
      showNextButton: true,
      showStopButton: true,
    );
  }

  Future<void> _prepareLocalTrack() async {
    try {
      final audioFile = await rootBundle.load('assets/aLIEz.m4a');
      final documents = await getApplicationDocumentsDirectory();
      final file = File('${documents.path}/aLIEz.m4a');
      if (!await file.exists()) {
        await file.writeAsBytes(audioFile.buffer.asUint8List(), flush: true);
      }

      final track = DemoTrack(
        url: 'file://${file.path}',
        title: 'Local file',
        subtitle: 'copied from bundle',
        coverUrl: 'assets/aLIEz.jpg',
      );
      tracks.add(track);
      AudioManager.instance.audioList.add(_toAudioInfo(track));
    } catch (_) {
      // The local file is optional; tests and restricted platforms can skip it.
    }
  }

  void _onEvents(AudioManagerEvents events, dynamic args) {
    if (_disposed) return;

    switch (events) {
      case AudioManagerEvents.start:
        isLoading = true;
        error = '';
        break;
      case AudioManagerEvents.ready:
        isLoading = false;
        error = '';
        _syncFromManager();
        break;
      case AudioManagerEvents.seekComplete:
        _syncFromManager();
        break;
      case AudioManagerEvents.playstatus:
        isPlaying = AudioManager.instance.isPlaying;
        break;
      case AudioManagerEvents.timeupdate:
        position = AudioManager.instance.position;
        duration = AudioManager.instance.duration;
        break;
      case AudioManagerEvents.error:
        isLoading = false;
        error = args?.toString() ?? 'Unknown audio error';
        break;
      case AudioManagerEvents.volumeChange:
        volume = AudioManager.instance.volume;
        break;
      case AudioManagerEvents.ended:
        next();
        break;
      default:
        break;
    }
    _notify();
  }

  Future<void> play(int index, {bool auto = true}) async {
    if (index < 0 || index >= tracks.length) return;
    currentIndex = index;
    error = '';
    isLoading = true;
    _notify();

    final result = await AudioManager.instance.play(index: index, auto: auto);
    if (result.isNotEmpty) {
      error = result;
      isLoading = false;
    }
    _syncFromManager();
    _notify();
  }

  Future<void> playOrPause() async {
    final playing = await AudioManager.instance.playOrPause();
    isPlaying = playing;
    _notify();
  }

  Future<void> next() async {
    await AudioManager.instance.next();
    _syncFromManager();
    _notify();
  }

  Future<void> previous() async {
    await AudioManager.instance.previous();
    _syncFromManager();
    _notify();
  }

  Future<void> stop() async {
    AudioManager.instance.stop();
    isPlaying = false;
    position = Duration.zero;
    duration = Duration.zero;
    _notify();
  }

  Future<void> seek(Duration target) async {
    if (duration <= Duration.zero) return;
    await AudioManager.instance.seekTo(target);
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0.0, 1.0);
    await AudioManager.instance.setVolume(volume, showVolume: false);
    _notify();
  }

  Future<void> nextMode() async {
    playMode = AudioManager.instance.nextMode();
    _notify();
  }

  Future<void> updateCurrentInfo() async {
    final info = AudioManager.instance.info;
    if (info == null) return;
    await AudioManager.instance.updateInfo(
      title: '${info.title} · demo',
      desc: 'Updated from example',
      titleMaxLines: 2,
      showPreviousButton: true,
      showNextButton: true,
      showStopButton: true,
    );
    _syncFromManager();
    _notify();
  }

  void _syncFromManager() {
    position = AudioManager.instance.position;
    duration = AudioManager.instance.duration;
    volume = AudioManager.instance.volume;
    currentIndex = AudioManager.instance.curIndex;
    isPlaying = AudioManager.instance.isPlaying;
    playMode = AudioManager.instance.playMode;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    AudioManager.instance.release();
    super.dispose();
  }
}
