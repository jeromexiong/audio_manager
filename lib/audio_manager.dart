import 'dart:async';
import 'package:flutter/services.dart';

/// 播放回调事件枚举
enum AudioManagerEvents {
  buffering,
  playstatus,
  timeupdate,
  error,
  next,
  previous,
  unknow
}
typedef void Events(AudioManagerEvents events, args);

/// 播放速率枚举 [0.5, 0.75, 1, 1.5, 1.75, 2]
enum AudioManagerRate { rate50, rate75, rate100, rate150, rate175, rate200 }
const _rates = [0.5, 0.75, 1, 1.5, 1.75, 2];

class AudioManager {
  static AudioManager _instance;
  static AudioManager get instance => getInstance();
  static getInstance() {
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

  /// 当前播放状态
  bool get isPlaying => _playing;
  bool _playing = false;
  void _setPlaying(bool playing) {
    _playing = playing;
    if (_events != null) {
      _events(AudioManagerEvents.playstatus, _playing);
    }
  }

  /// 当前播放时长（毫秒
  int get position => _position;
  int _position = 0;

  /// 当前播放总时长（毫秒
  int get duration => _duration;
  int _duration = 0;

  Future<dynamic> _handler(MethodCall methodCall) {
    switch (methodCall.method) {
      case "buffering":
        if (_events != null)
          _events(AudioManagerEvents.buffering, methodCall.arguments);
        break;
      case "playstatus":
        _setPlaying(methodCall.arguments);
        break;
      case "timeupdate":
        _position = methodCall.arguments["position"];
        _duration = methodCall.arguments["duration"];
        if (!_playing) _setPlaying(true);
        if (_position < 0 || _duration < 0) break;
        if (_position > _duration) {
          _position = _duration;
          _setPlaying(false);
        }
        if (_events != null)
          _events(AudioManagerEvents.timeupdate,
              {"position": _position, "duration": _duration});
        break;
      case "error":
        if (_playing) _setPlaying(false);
        if (_events != null)
          _events(AudioManagerEvents.error, methodCall.arguments);
        break;
      case "next":
        if (_events != null) _events(AudioManagerEvents.next, null);
        break;
      case "previous":
        if (_events != null) _events(AudioManagerEvents.previous, null);
        break;
      default:
        if (_events != null)
          _events(AudioManagerEvents.unknow, methodCall.arguments);
        break;
    }
    return Future.value(true);
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

  /// `url`: 播放地址，`network`地址或者`asset`地址.
  ///
  /// `title`: 通知播放标题
  ///
  /// `desc`: 通知详情；`cover`: 封面图地址，`network`地址或者`asset`地址.
  Future<String> start(String url, String title,
      {String desc, String cover}) async {
    final regx = new RegExp(r'^(http|https):\/\/([\w.]+\/?)\S*');
    final result = await _channel.invokeMethod('start', {
      "url": url,
      "title": title,
      "desc": desc,
      "cover": cover,
      "isLocal": !regx.hasMatch(url),
      "isLocalCover": !regx.hasMatch(cover),
    });
    return result;
  }

  /// 播放或暂停；即若当前正在播放就暂停，反之就播放
  ///
  /// [return] 返回当前播放状态
  Future<bool> playOrPause() async {
    bool result = await _channel.invokeMethod("playOrPause");
    return result;
  }

  /// `position` 移动位置 毫秒时间戳
  Future<String> seekTo(int position) async {
    if (position < 0 || position > duration)
      throw "[position] must be greater than 0 and less than the total duration";
    return await _channel.invokeMethod("seekTo", {"position": position});
  }

  /// `rate` 播放速率，默认 1.0
  Future<String> setSpeed(AudioManagerRate rate) async {
    int _rate = _rates[rate.index];
    return await _channel.invokeMethod("seekTo", {"rate": _rate});
  }

  /// 停止播放
  stop() {
    _channel.invokeMethod("stop");
  }

  /// 更新播放详情
  updateLrc(String lrc) {
    _channel.invokeMethod("updateLrc", {"lrc": lrc});
  }
}
