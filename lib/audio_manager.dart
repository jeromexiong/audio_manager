import 'dart:async';
import 'package:flutter/services.dart';

/// Play callback event enumeration
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
  int get position => _position;
  int _position = 0;

  /// Total current playing time (ms
  int get duration => _duration;
  int _duration = 0;

  /// If there are errors, return details
  String get error => _error;
  String _error;

  /// list of playback. Used to record playlists
  ///
  /// `⚠️ The objects in the list must contain the URL and title properties`,
  /// otherwise the previous song will not be played if [loop] is true on its own.
  void setPlaybackList(List list, bool loop) {
    _list = list;
    _loop = loop;
  }

  List get playbackList => _list;
  List _list;

  /// Whether to loop
  bool get loop => _loop;
  bool _loop;

  /// Playback info
  Map<String, dynamic> get info => _info;
  Map<String, dynamic> _info;

  Future<dynamic> _handler(MethodCall call) {
    switch (call.method) {
      case "buffering":
        if (_events != null)
          _events(AudioManagerEvents.buffering, call.arguments);
        break;
      case "playstatus":
        _setPlaying(call.arguments);
        break;
      case "timeupdate":
        _error = null;
        _position = call.arguments["position"];
        _duration = call.arguments["duration"];
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
        _error = call.arguments;
        if (_playing) _setPlaying(false);
        if (_events != null) _events(AudioManagerEvents.error, _error);
        break;
      case "next":
        if (_events != null) _events(AudioManagerEvents.next, null);
        break;
      case "previous":
        if (_events != null) _events(AudioManagerEvents.previous, null);
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
  /// `desc`: Notification details; `cover`: cover image address,` network` address, or `asset` address.
  Future<String> start(String url, String title,
      {String desc, String cover}) async {
    if (url == null || url.isEmpty) return "[url] can not be null or empty";
    if (title == null || title.isEmpty)
      return "[title] can not be null or empty";
    cover = cover ?? "";
    desc = desc ?? "";

    _info = {"url": url, "title": title, "desc": desc, "cover": cover};
    _initialize = true;
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
  Future<String> seekTo(int position) async {
    if (_preprocessing().isNotEmpty) return _preprocessing();
    if (position < 0 || position > duration)
      return "[position] must be greater than 0 and less than the total duration";
    return await _channel.invokeMethod("seekTo", {"position": position});
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
}
