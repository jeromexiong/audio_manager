import 'dart:async';
import 'package:flutter/services.dart';
import 'package:audio_manager/src/PlayMode.dart';
import 'package:audio_manager/src/AudioInfo.dart';

/// Play callback event enumeration
enum AudioManagerEvents {
  ready,
  buffering,
  playstatus,
  timeupdate,
  error,
  next,
  previous,
  ended,
  unknow
}
typedef void Events(AudioManagerEvents events, args);

/// Play rate enumeration [0.5, 0.75, 1, 1.5, 1.75, 2]
enum AudioManagerRate { rate50, rate75, rate100, rate150, rate175, rate200 }
const _rates = [0.5, 0.75, 1, 1.5, 1.75, 2];

class AudioManager {
  static AudioManager _instance;
  static AudioManager get instance => _getInstance();
  static _getInstance() {
    if (_instance == null) {
      _instance = new AudioManager._();
    }
    return _instance;
  }

  static MethodChannel _channel;
  AudioManager._() {
    _channel = const MethodChannel('audio_manager')
      ..setMethodCallHandler(_handler);
  }

  /// Current playback status
  bool get isPlaying => _playing;
  bool _playing = false;
  void _setPlaying(bool playing) {
    _playing = playing;
    if (_events != null) {
      _events(AudioManagerEvents.playstatus, _playing);
    }
  }

  /// Current playing time (ms
  Duration get position => _position;
  Duration _position = Duration(milliseconds: 0);

  /// Total current playing time (ms
  Duration get duration => _duration;
  Duration _duration = Duration(milliseconds: 0);

  /// If there are errors, return details
  String get error => _error;
  String _error;

  /// list of playback. Used to record playlists
  List<AudioInfo> get audioList => _audioList;
  List<AudioInfo> _audioList = [];

  /// Set up playlists. Use the [play] or [start] method if you want to play
  set audioList(List<AudioInfo> list) {
    if (list == null || list.length == 0)
      throw "[list] can not be null or empty";
    _audioList = list;
    _info = _initRandom();
  }

  /// Currently playing subscript of [audioList]
  int get curIndex => _curIndex;
  int _curIndex = 0;
  List<int> _randoms = [];

  /// Play mode [sequence, shuffle, single], default `sequence`
  PlayMode get playMode => _playMode;
  PlayMode _playMode = PlayMode.sequence;

  /// Whether to internally handle [next] and [previous] events. default true
  bool intercepter = true;

  /// Whether to auto play. default true
  bool get auto => _auto;
  bool _auto = true;

  /// Playback info
  AudioInfo get info => _info;
  AudioInfo _info;

  Future<dynamic> _handler(MethodCall call) {
    switch (call.method) {
      case "ready":
        _duration = Duration(milliseconds: call.arguments ?? 0);
        if (_events != null) _events(AudioManagerEvents.ready, _duration);
        break;
      case "buffering":
        if (_events != null)
          _events(AudioManagerEvents.buffering, call.arguments);
        break;
      case "playstatus":
        _setPlaying(call.arguments);
        break;
      case "timeupdate":
        _error = null;
        _position = Duration(milliseconds: call.arguments["position"] ?? 0);
        _duration = Duration(milliseconds: call.arguments["duration"] ?? 0);
        if (!_playing) _setPlaying(true);
        if (_position.inMilliseconds < 0 || _duration.inMilliseconds < 0) break;
        if (_position > _duration) {
          _position = _duration;
          _setPlaying(false);
        }
        if (_events != null)
          _events(AudioManagerEvents.timeupdate,
              {"position": _position, "duration": _duration});
        break;
      case "error":
        _error = call.arguments;
        if (_playing) _setPlaying(false);
        if (_events != null) _events(AudioManagerEvents.error, _error);
        break;
      case "next":
        if (intercepter) next();
        if (_events != null) _events(AudioManagerEvents.next, null);
        break;
      case "previous":
        if (intercepter) previous();
        if (_events != null) _events(AudioManagerEvents.previous, null);
        break;
      case "ended":
        if (_events != null) _events(AudioManagerEvents.ended, null);
        break;
      default:
        if (_events != null) _events(AudioManagerEvents.unknow, call.arguments);
        break;
    }
    return Future.value(true);
  }

  bool _initialize;
  String _preprocessing() {
    if (_info == null) return "you must invoke the [start] method first";
    if (_error != null) return _error;
    if (_initialize != null && !_initialize)
      return "you must invoke the [start] method after calling the [stop] method";
    return "";
  }

  Events _events;

  /// 回调事件
  void onEvents(Events events) {
    _events = events;
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
      {String desc, String cover, bool auto}) async {
    if (url == null || url.isEmpty) return "[url] can not be null or empty";
    if (title == null || title.isEmpty)
      return "[title] can not be null or empty";
    cover = cover ?? "";
    desc = desc ?? "";

    _info = AudioInfo(url, title: title, desc: desc, coverUrl: cover);
    _audioList.insert(0, _info);
    _initialize = true;
    return await play(index: 0, auto: auto);
  }

  /// Play specified subscript audio if you want
  Future<String> play({int index, bool auto}) async {
    if (index != null && (index < 0 || index >= _audioList.length))
      throw "invalid index";
    _auto = auto ?? true;
    _curIndex = index ?? _curIndex;
    _info = _initRandom();

    final regx = new RegExp(r'^(http|https):\/\/([\w.]+\/?)\S*');
    final result = await _channel.invokeMethod('start', {
      "url": _info.url,
      "title": _info.title,
      "desc": _info.desc,
      "cover": _info.coverUrl,
      "isAuto": _auto,
      "isLocal": !regx.hasMatch(_info.url),
      "isLocalCover": !regx.hasMatch(_info.coverUrl),
    });
    return result;
  }

  /// Play or pause; that is, pause if currently playing, otherwise play
  ///
  /// ⚠️ Must be preloaded
  ///
  /// [return] Returns the current playback status
  Future<String> playOrPause() async {
    if (_preprocessing().isNotEmpty) return _preprocessing();
    bool result = await _channel.invokeMethod("playOrPause");
    return "playOrPause: $result";
  }

  /// `position` Move location millisecond timestamp
  Future<String> seekTo(Duration position) async {
    if (_preprocessing().isNotEmpty) return _preprocessing();
    if (position.inMilliseconds < 0 ||
        position.inMilliseconds > duration.inMilliseconds)
      return "[position] must be greater than 0 and less than the total duration";
    return await _channel
        .invokeMethod("seekTo", {"position": position.inMilliseconds});
  }

  /// `rate` Play rate, default 1.0
  Future<String> setSpeed(AudioManagerRate rate) async {
    if (_preprocessing().isNotEmpty) return _preprocessing();
    int _rate = _rates[rate.index];
    return await _channel.invokeMethod("seekTo", {"rate": _rate});
  }

  /// stop play
  stop() {
    _channel.invokeMethod("stop");
    _initialize = false;
  }

  /// Update play details
  updateLrc(String lrc) {
    if (_preprocessing().isNotEmpty) return _preprocessing();
    _channel.invokeMethod("updateLrc", {"lrc": lrc});
  }

  /// Switch playback mode
  PlayMode nextMode({PlayMode playMode}) {
    int mode = (_playMode.index + 1) % 3;
    if (playMode != null) mode = playMode.index;
    switch (mode) {
      case 0:
        _playMode = PlayMode.sequence;
        break;
      case 1:
        _playMode = PlayMode.shuffle;
        break;
      case 2:
        _playMode = PlayMode.single;
        break;
      default:
        break;
    }
    return _playMode;
  }

  AudioInfo _initRandom() {
    if (playMode == PlayMode.shuffle) {
      if (_randoms.length != _audioList.length) {
        _randoms = _audioList.asMap().keys.toList();
        _randoms.shuffle();
      }
      _curIndex = _randoms[_curIndex];
    }
    return _audioList[_curIndex];
  }

  /// play next audio
  Future<String> next() {
    print("next audio");
    if (playMode != PlayMode.single) {
      _curIndex = (_curIndex + 1) % _audioList.length;
    }
    return play();
  }

  /// play previous audio
  Future<String> previous() {
    print("previous audio");
    if (playMode != PlayMode.single) {
      num index = _curIndex - 1;
      _curIndex = index < 0 ? _audioList.length - 1 : index;
    }
    return play();
  }
}
