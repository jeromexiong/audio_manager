import 'dart:async';
import 'dart:io';

import 'package:audio_manager/src/audio_info.dart';
import 'package:audio_manager/src/audio_type.dart';
import 'package:flutter/services.dart';

export 'package:audio_manager/src/audio_info.dart';
export 'package:audio_manager/src/audio_type.dart';

class AudioManager {
  static AudioManager? _instance;
  static AudioManager get instance => _getInstance();

  static AudioManager _getInstance() {
    _instance ??= AudioManager._();
    return _instance!;
  }

  static final MethodChannel _channel = const MethodChannel('audio_manager');

  AudioManager._() {
    _channel.setMethodCallHandler(_handler);
    getCurrentVolume();
  }

  /// 是否资源加载中
  bool get isLoading => _isLoading;
  bool _isLoading = true;

  /// Current playback status
  bool get isPlaying => _playing;
  bool _playing = false;

  void _setPlaying(bool playing) {
    if (_playing == playing) return;
    _playing = playing;
    _onEvents(AudioManagerEvents.playstatus, _playing);
  }

  /// Current playing time (ms
  Duration get position => _position;
  Duration _position = Duration(milliseconds: 0);

  /// Total current playing time (ms
  Duration get duration => _duration;
  Duration _duration = Duration(milliseconds: 0);

  /// get current volume 0~1
  double get volume => _volume;
  double _volume = 0;

  /// If there are errors, return details
  String? get error => _error;
  String? _error;

  /// list of playback. Used to record playlists
  List<AudioInfo> get audioList => _audioList;
  List<AudioInfo> _audioList = [];

  /// Set up playlists. Use the [play] or [start] method if you want to play
  set audioList(List<AudioInfo> list) {
    if (list.isEmpty) throw "[list] can not be null or empty";
    _audioList = list;
    if (playMode == PlayMode.shuffle) _resetShuffleQueue();
    _info = _selectTrack();
  }

  /// Currently playing subscript of [audioList]
  int get curIndex => _curIndex;
  int _curIndex = 0;
  List<int> _shuffleQueue = [];
  int _shuffleCursor = 0;

  /// Play mode [sequence, shuffle, single], default `sequence`
  PlayMode get playMode => _playMode;
  PlayMode _playMode = PlayMode.sequence;

  /// Whether to internally handle [next] and [previous] events. default true
  bool intercepter = true;

  /// Whether to auto play. default true
  bool get auto => _auto;
  bool _auto = true;

  /// Playback info
  AudioInfo? get info => _info;
  AudioInfo? _info;

  Future<dynamic> _handler(MethodCall call) {
    switch (call.method) {
      case "ready":
        _isLoading = false;
        _error = null;
        _duration = Duration(milliseconds: call.arguments ?? 0);
        _onEvents(AudioManagerEvents.ready, _duration);
        break;
      case "seekComplete":
        _position = Duration(milliseconds: call.arguments ?? 0);
        if (_duration.inMilliseconds != 0) {
          _onEvents(AudioManagerEvents.seekComplete, _position);
        }
        break;
      case "buffering":
        _onEvents(AudioManagerEvents.buffering, call.arguments);
        break;
      case "playstatus":
        _setPlaying(call.arguments ?? false);
        break;
      case "timeupdate":
        _position = Duration(milliseconds: call.arguments["position"] ?? 0);
        _duration = Duration(milliseconds: call.arguments["duration"] ?? 0);
        if (!_playing) _setPlaying(true);
        if (_position.inMilliseconds < 0 || _duration.inMilliseconds <= 0) {
          break;
        }
        if (_position > _duration) {
          _position = _duration;
          _setPlaying(false);
        }
        _onEvents(AudioManagerEvents.timeupdate,
            {"position": _position, "duration": _duration});
        break;
      case "error":
        _error = call.arguments;
        _isLoading = false;
        if (_playing) _setPlaying(false);
        _onEvents(AudioManagerEvents.error, _error);
        break;
      case "next":
        if (intercepter) next();
        _onEvents(AudioManagerEvents.next, null);
        break;
      case "previous":
        if (intercepter) previous();
        _onEvents(AudioManagerEvents.previous, null);
        break;
      case "ended":
        _onEvents(AudioManagerEvents.ended, null);
        break;
      case "stop":
        _onEvents(AudioManagerEvents.stop, null);
        _reset();
        break;
      case "volumeChange":
        _volume = call.arguments;
        _onEvents(AudioManagerEvents.volumeChange, _volume);
        break;
      default:
        _onEvents(AudioManagerEvents.unknow, call.arguments);
        break;
    }
    return Future.value(true);
  }

  String _preprocessing() {
    var errMsg = "";
    if (_info == null) errMsg = "you must invoke the [start] method first";
    if (_error != null && _error!.isNotEmpty) errMsg = _error!;
    if (_isLoading && (_error == null || _error!.isEmpty)) {
      errMsg = "audio resource loading....";
    }

    if (errMsg.isNotEmpty) _onEvents(AudioManagerEvents.error, errMsg);
    return errMsg;
  }

  Events? _events;
  bool _initialize = false;

  /// callback events
  void onEvents(Events events) {
    _events = events;
  }

  void _onEvents(AudioManagerEvents events, args) {
    if (_events == null) return;
    _events!(events, args);
  }

  Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  /// Initial playback. Preloaded playback information
  ///
  /// `url`: Playback address, `network` address or` asset` address.
  ///
  /// `title`: Notification play title
  ///
  /// `desc`: Notification details; `cover`: cover image address, `network` address, or `asset` address;
  /// `auto`: Whether to play automatically, default is true;
  Future<String> start(String url, String title,
      {required String desc,
      required String cover,
      bool? auto,
      int titleMaxLines = 1,
      bool showPreviousButton = false,
      bool showNextButton = true,
      bool showStopButton = true}) async {
    if (url.isEmpty) return "[url] can not be null or empty";
    if (title.isEmpty) return "[title] can not be null or empty";
    _info = AudioInfo(url,
        title: title,
        desc: desc,
        coverUrl: cover,
        titleMaxLines: titleMaxLines,
        showPreviousButton: showPreviousButton,
        showNextButton: showNextButton,
        showStopButton: showStopButton);
    _audioList.insert(0, _info!);
    return await play(index: 0, auto: auto);
  }

  /// This will load the file from the file-URI given by:
  /// `'file://${file.path}'`.
  Future<String> file(File file, String title,
      {required String desc, required String cover, required bool auto}) async {
    return await start("file://${file.path}", title,
        desc: desc, cover: cover, auto: auto);
  }

  Future<String> startInfo(AudioInfo audio, {required bool auto}) async {
    return await start(audio.url, audio.title,
        desc: audio.desc,
        cover: audio.coverUrl,
        titleMaxLines: audio.titleMaxLines,
        showPreviousButton: audio.showPreviousButton,
        showNextButton: audio.showNextButton,
        showStopButton: audio.showStopButton);
  }

  /// Play specified subscript audio if you want
  Future<String> play({int? index, bool? auto}) async {
    if (index != null && (index < 0 || index >= _audioList.length)) {
      throw "invalid index";
    }
    _auto = auto ?? true;
    _curIndex = index ?? _curIndex;
    if (playMode == PlayMode.shuffle) {
      if (_shuffleQueue.length != _audioList.length) _resetShuffleQueue();
      if (index != null) {
        _shuffleCursor = _shuffleQueue.indexOf(index);
        if (_shuffleCursor < 0) {
          _resetShuffleQueue();
          _shuffleCursor = _shuffleQueue.indexOf(index);
          if (_shuffleCursor < 0) {
            _shuffleCursor = 0;
            _curIndex = _shuffleQueue[_shuffleCursor];
          }
        }
      }
    }
    final random = _selectTrack();
    // Do not replay the same url
    if (_info!.url != random.url) {
      stop();
      _isLoading = true;
      _initialize = true;
    }
    _info = random;
    _onEvents(AudioManagerEvents.start, _info);

    final regx = RegExp(r'^(http|https|file):\/\/\/?([\w.]+\/?)\S*');
    final result = await _channel.invokeMethod('start', {
      "url": _info!.url,
      "title": _info!.title,
      "desc": _info!.desc,
      "cover": _info!.coverUrl,
      "isAuto": _auto,
      "isLocal": !regx.hasMatch(_info!.url),
      "isLocalCover": !regx.hasMatch(_info!.coverUrl),
      "titleMaxLines": _info!.titleMaxLines,
      "showPreviousButton": _info!.showPreviousButton,
      "showNextButton": _info!.showNextButton,
      "showStopButton": _info!.showStopButton,
    });
    if (result is String && result.isNotEmpty) {
      _isLoading = false;
      _error = result;
      _onEvents(AudioManagerEvents.error, result);
    }
    return result ?? "";
  }

  /// Play or pause; that is, pause if currently playing, otherwise play
  ///
  /// ⚠️ Must be preloaded
  ///
  /// [return] Returns the current playback status
  Future<bool> playOrPause() async {
    if (_preprocessing().isNotEmpty) return false;

    if (_initialize == false && _playing == false) {
      await play(index: _curIndex, auto: true);
      return true;
    } else {
      bool playing = await _channel.invokeMethod("playOrPause");
      _setPlaying(playing);
      return playing;
    }
  }

  /// to play status
  Future<bool> toPlay() async {
    if (_preprocessing().isNotEmpty) return false;
    bool playing = await _channel.invokeMethod("play");
    _setPlaying(playing);
    return playing;
  }

  /// to pause status
  Future<bool> toPause() async {
    if (_preprocessing().isNotEmpty) return false;
    bool playing = await _channel.invokeMethod("pause");
    _setPlaying(playing);
    return playing;
  }

  /// `position` Move location millisecond timestamp.
  ///
  /// ⚠️ You must after [AudioManagerEvents.ready] event invoked before you can change the playback progress
  Future<String> seekTo(Duration position) async {
    if (_preprocessing().isNotEmpty) return _preprocessing();
    if (position.inMilliseconds < 0 ||
        position.inMilliseconds > duration.inMilliseconds) {
      return "[position] must be greater than 0 and less than the total duration";
    }
    return await _channel
        .invokeMethod("seekTo", {"position": position.inMilliseconds});
  }

  /// `rate` Play rate, default [AudioRate.rate100] is 1.0
  Future<String> setRate(AudioRate rate) async {
    if (_preprocessing().isNotEmpty) return _preprocessing();
    const rates = [0.5, 0.75, 1, 1.5, 1.75, 2];
    double rateValue = rates[rate.index].toDouble();
    return await _channel.invokeMethod("rate", {"rate": rateValue});
  }

  /// stop play
  void stop() {
    _reset();
    _initialize = false;
    _channel.invokeMethod("stop");
  }

  void _reset() {
    if (_isLoading) return;
    _duration = Duration(milliseconds: 0);
    _position = Duration(milliseconds: 0);
    _setPlaying(false);
    _onEvents(AudioManagerEvents.timeupdate,
        {"position": _position, "duration": _duration});
  }

  /// release all resource
  void release() {
    _reset();
    _channel.invokeListMethod("release");
  }

  /// Update play details
  void updateLrc(String lrc) {
    if (_preprocessing().isNotEmpty) return;
    _channel.invokeMethod("updateLrc", {"lrc": lrc});
  }

  /// Update notification/remote-control metadata without restarting playback.
  Future<String> updateInfo(
      {String? title,
      String? desc,
      String? coverUrl,
      int? titleMaxLines,
      bool? showPreviousButton,
      bool? showNextButton,
      bool? showStopButton}) async {
    if (_preprocessing().isNotEmpty) return _preprocessing();
    final AudioInfo current = _info!;
    final String newTitle = title ?? current.title;
    final String newDesc = desc ?? current.desc;
    final String newCover = coverUrl ?? current.coverUrl;
    final int newTitleMaxLines = titleMaxLines ?? current.titleMaxLines;
    final bool newShowPreviousButton =
        showPreviousButton ?? current.showPreviousButton;
    final bool newShowNextButton = showNextButton ?? current.showNextButton;
    final bool newShowStopButton = showStopButton ?? current.showStopButton;
    current.title = newTitle;
    current.desc = newDesc;
    current.coverUrl = newCover;
    current.titleMaxLines = newTitleMaxLines;
    current.showPreviousButton = newShowPreviousButton;
    current.showNextButton = newShowNextButton;
    current.showStopButton = newShowStopButton;

    final regx = RegExp(r'^(http|https|file):\/\/\/?([\w.]+\/?)\S*');
    final result = await _channel.invokeMethod("updateInfo", {
      "title": newTitle,
      "desc": newDesc,
      "cover": newCover,
      "isLocalCover": !regx.hasMatch(newCover),
      "titleMaxLines": newTitleMaxLines,
      "showPreviousButton": newShowPreviousButton,
      "showNextButton": newShowNextButton,
      "showStopButton": newShowStopButton,
    });
    return result ?? "";
  }

  /// Switch playback mode. `Playmode` priority is greater than `index`
  PlayMode nextMode({PlayMode? playMode, int? index}) {
    int mode = index ?? (_playMode.index + 1) % 3;
    if (playMode != null) mode = playMode.index;
    switch (mode) {
      case 0:
        _playMode = PlayMode.sequence;
        break;
      case 1:
        _playMode = PlayMode.shuffle;
        _resetShuffleQueue();
        break;
      case 2:
        _playMode = PlayMode.single;
        break;
      default:
        _playMode = PlayMode.sequence;
        break;
    }
    return _playMode;
  }

  void _resetShuffleQueue() {
    if (_audioList.isEmpty) return;
    _shuffleQueue = _audioList.asMap().keys.toList()..shuffle();
    _shuffleCursor = _shuffleQueue.indexOf(_curIndex);
    if (_shuffleCursor < 0) _shuffleCursor = 0;
  }

  AudioInfo _selectTrack() {
    if (playMode == PlayMode.shuffle) {
      if (_shuffleQueue.length != _audioList.length) _resetShuffleQueue();
      _curIndex = _shuffleQueue[_shuffleCursor];
    } else if (_curIndex >= _audioList.length) {
      _curIndex = _audioList.length - 1;
    } else if (_curIndex < 0) {
      _curIndex = 0;
    }
    return _audioList[_curIndex];
  }

  /// play next audio
  Future<String> next() async {
    if (playMode == PlayMode.single) {
      return await play();
    }
    if (playMode == PlayMode.shuffle) {
      if (_shuffleQueue.length != _audioList.length) _resetShuffleQueue();
      _shuffleCursor = (_shuffleCursor + 1) % _shuffleQueue.length;
      _curIndex = _shuffleQueue[_shuffleCursor];
    } else {
      _curIndex = (_curIndex + 1) % _audioList.length;
    }
    return await play();
  }

  /// play previous audio
  Future<String> previous() async {
    if (playMode == PlayMode.single) {
      return await play();
    }
    if (playMode == PlayMode.shuffle) {
      if (_shuffleQueue.length != _audioList.length) _resetShuffleQueue();
      _shuffleCursor =
          (_shuffleCursor - 1 + _shuffleQueue.length) % _shuffleQueue.length;
      _curIndex = _shuffleQueue[_shuffleCursor];
    } else {
      int index = _curIndex - 1;
      _curIndex = index < 0 ? _audioList.length - 1 : index;
    }
    return await play();
  }

  /// set volume range(0~1). `showVolume`: show volume view or not and this is only in iOS
  /// ⚠️ IOS simulator is invalid, please use real machine
  Future<String> setVolume(double value, {bool showVolume = false}) async {
    // 原实现只对 value 做了上限、对另一变量做了下限，负值会原样传给原生
    final clamped = value.clamp(0.0, 1.0);
    final result = await _channel
        .invokeMethod("setVolume", {"value": clamped, "showVolume": showVolume});
    return result;
  }

  /// get current volume
  Future<double> getCurrentVolume() async {
    _volume = await _channel.invokeMethod("currentVolume");
    return _volume;
  }

  /// Query the current native playback state from a non-UI context.
  Future<Map<String, dynamic>> currentState() async {
    final result = await _channel.invokeMethod("getState");
    if (result is Map) return Map<String, dynamic>.from(result);
    return <String, dynamic>{};
  }
}
