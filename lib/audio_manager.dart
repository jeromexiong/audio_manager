import 'dart:async';

import 'package:flutter/services.dart';

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

  bool _playing = false;
  /// 当前播放状态
  bool get isPlaying => _playing;

  Future<dynamic> _handler(MethodCall methodCall) {
    switch (methodCall.method) {
      case "buffering":
        if (_events != null)
          _events(AudioManagerEvents.buffering, methodCall.arguments);
        break;
      case "playstatus":
        _playing = methodCall.arguments;
        if (_events != null)
          _events(AudioManagerEvents.playstatus, methodCall.arguments);
        break;
      case "timeupdate":
        if (_events != null)
          _events(AudioManagerEvents.timeupdate, methodCall.arguments);
        break;
      case "error":
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

  /// 停止播放
  stop() {
    _channel.invokeMethod("stop");
  }

  /// 更新播放详情
  updateLrc(String lrc) {
    _channel.invokeMethod("updateLrc", {"lrc": lrc});
  }
}
