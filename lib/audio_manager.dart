import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:audio_manager/src/AudioType.dart';
import 'package:audio_manager/src/AudioInfo.dart';

export 'package:audio_manager/src/AudioInfo.dart';
export 'package:audio_manager/src/AudioType.dart';

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
        _isLoading = false;
        _duration = Duration(milliseconds: call.arguments ?? 0);
        _onEvents(AudioManagerEvents.ready, _duration);
        break;
      case "seekComplete":
        _position = Duration(milliseconds: call.arguments ?? 0);
        if (_duration.inMilliseconds != 0)
          _onEvents(AudioManagerEvents.seekComplete, _position);
        break;
      case "buffering":
        _onEvents(AudioManagerEvents.buffering, call.arguments);
        break;
      case "playstatus":
        _setPlaying(call.arguments ?? false);
        break;
      case "timeupdate":
        _error = null;
        _position = Duration(milliseconds: call.arguments["position"] ?? 0);
        _duration = Duration(milliseconds: call.arguments["duration"] ?? 0);
        if (!_playing) _setPlaying(true);
        if (_position.inMilliseconds < 0 || _duration.inMilliseconds <= 0)
          break;
        if (_position > _duration) {
          _position = _duration;
          _setPlaying(false);
        }
        _onEvents(AudioManagerEvents.timeupdate,
            {"position": _position, "duration": _duration});
        break;
      case "error":
        _error = call.arguments;
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
    if (_error != null) errMsg = _error;
    if (_isLoading) errMsg = "audio resource loading....";

    if (errMsg.isNotEmpty) _onEvents(AudioManagerEvents.error, errMsg);
    return errMsg;
  }

  Events _events;
  bool _initialize;

  /// callback events
  void onEvents(Events events) {
    _events = events;
  }

  void _onEvents(AudioManagerEvents events, args) {
    if (_events == null) return;
    _events(events, args);
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
    return await play(index: 0, auto: auto);
  }

  /// This will load the file from the file-URI given by:
  /// `'file://${file.path}'`.
  Future<String> file(File file, String title,
      {String desc, String cover, bool auto}) async {
    return await start("file://${file.path}", title,
        desc: desc, cover: cover, auto: auto);
  }

  Future<String> startInfo(AudioInfo audio, {bool auto}) async {
    return await start(audio.url, audio.title,
        desc: audio.desc, cover: audio.coverUrl, auto: auto);
  }

  /// Play specified subscript audio if you want
  Future<String> play({int index, bool auto}) async {
    if (index != null && (index < 0 || index >= _audioList.length))
      throw "invalid index";
    stop();
    _auto = auto ?? true;
    _curIndex = index ?? _curIndex;
    _info = _initRandom();
    _onEvents(AudioManagerEvents.start, _info);

    _isLoading = true;
    _initialize = true;
    final regx = new RegExp(r'^(http|https|file):\/\/\/?([\w.]+\/?)\S*');
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
  Future<bool> playOrPause() async {
    if (_preprocessing().isNotEmpty) return false;

    if (_initialize == false && _playing == false) {
      play(index: _curIndex, auto: true);
    }
    bool playing = await _channel.invokeMethod("playOrPause");
    _setPlaying(playing);
    return playing;
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
        position.inMilliseconds > duration.inMilliseconds)
      return "[position] must be greater than 0 and less than the total duration";
    return await _channel
        .invokeMethod("seekTo", {"position": position.inMilliseconds});
  }

  /// `rate` Play rate, default [AudioRate.rate100] is 1.0
  Future<String> setRate(AudioRate rate) async {
    if (_preprocessing().isNotEmpty) return _preprocessing();
    const _rates = [0.5, 0.75, 1, 1.5, 1.75, 2];
    rate = rate ?? AudioRate.rate100;
    double _rate = _rates[rate.index].toDouble();
    return await _channel.invokeMethod("rate", {"rate": _rate});
  }

  /// stop play
  stop() {
    _reset();
    _initialize = false;
    _channel.invokeMethod("stop");
  }

  _reset() {
    // _duration = Duration(milliseconds: 0);
    _position = Duration(milliseconds: 0);
    _setPlaying(false);
    _onEvents(AudioManagerEvents.timeupdate,
        {"position": _position, "duration": _duration});
  }

  /// release all resource
  release() {
    _reset();
    _channel.invokeListMethod("release");
  }

  /// Update play details
  updateLrc(String lrc) {
    if (_preprocessing().isNotEmpty) return _preprocessing();
    _channel.invokeMethod("updateLrc", {"lrc": lrc});
  }

  /// Switch playback mode. `Playmode` priority is greater than `index`
  PlayMode nextMode({PlayMode playMode, int index}) {
    int mode = index ?? (_playMode.index + 1) % 3;
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
        _playMode = PlayMode.sequence;
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
    if (_curIndex >= _audioList.length) {
      _curIndex = _audioList.length - 1;
    }
    if (_curIndex < 0) {
      _curIndex = 0;
    }
    return _audioList[_curIndex];
  }

  /// play next audio
  Future<String> next() async {
    if (playMode != PlayMode.single) {
      _curIndex = (_curIndex + 1) % _audioList.length;
    }
    return await play();
  }

  /// play previous audio
  Future<String> previous() async {
    if (playMode != PlayMode.single) {
      num index = _curIndex - 1;
      _curIndex = index < 0 ? _audioList.length - 1 : index;
    }
    return await play();
  }

  /// set volume range(0~1). `showVolume`: show volume view or not and this is only in iOS
  /// ⚠️ IOS simulator is invalid, please use real machine
  Future<String> setVolume(double value, {bool showVolume = false}) async {
    var volume = min(value, 1);
    value = max(value, 0);
    final result = await _channel
        .invokeMethod("setVolume", {"value": volume, "showVolume": showVolume});
    return result;
  }

  /// get current volume
  Future<double> getCurrentVolume() async {
    _volume = await _channel.invokeMethod("currentVolume");
    return _volume;
  }
}
