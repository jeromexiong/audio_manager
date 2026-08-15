// Web 端实现基于 package:web 的 HTMLAudioElement（替代已废弃的 dart:html）。
import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'audio_manager.dart';

class WrappedPlayer {
  double currentVolume = 1;
  double currentRate = 1;
  PlayMode playMode = PlayMode.sequence;
  String currentUrl = "";
  bool isPlaying = false;

  /// 事件回调，由插件注入到方法通道，向 Dart 侧转发播放器事件。
  void Function(String method, Object? arguments)? onEvent;

  web.HTMLAudioElement? player;

  /// 装载 [url]（不自动播放，是否播放由调用方按 isAuto 决定）。
  void start(String url) {
    currentUrl = url;
    destroy();
    recreateNode();
  }

  void play() {
    if (currentUrl.isEmpty) return;
    if (player == null) recreateNode();
    isPlaying = true;
    player?.play();
  }

  void setVolume(double volume) {
    currentVolume = volume;
    player?.volume = volume;
  }

  void setRate(double rate) {
    currentRate = rate;
    player?.playbackRate = rate;
  }

  void recreateNode() {
    if (currentUrl.isEmpty) {
      return;
    }
    final web.HTMLAudioElement node = web.HTMLAudioElement();
    player = node;
    node.src = currentUrl;
    node.loop = playMode == PlayMode.single;
    node.volume = currentVolume;
    node.playbackRate = currentRate;
    // package:web 的事件属性/EventListener 是 JSFunction，不能直接赋 Dart 闭包，
    // 需用 dart:js_interop 的 .toJS 把 Dart 函数导出为 JS 函数。
    node.onloadedmetadata = ((web.Event _) {
      final duration = node.duration;
      if (duration.isFinite && duration > 0) {
        _emit('ready', (duration * 1000).round());
      }
    }).toJS;
    node.ontimeupdate = ((web.Event _) {
      final position = node.currentTime;
      final duration = node.duration;
      _emit('timeupdate', {
        'position': position.isFinite ? (position * 1000).round() : 0,
        'duration': duration.isFinite ? (duration * 1000).round() : 0,
      });
    }).toJS;
    node.onplay = ((web.Event _) {
      if (!identical(player, node)) return;
      isPlaying = true;
      _emit('playstatus', true);
    }).toJS;
    node.onpause = ((web.Event _) {
      if (!identical(player, node)) return;
      isPlaying = false;
      _emit('playstatus', false);
    }).toJS;
    node.onended = ((web.Event _) {
      if (!identical(player, node)) return;
      isPlaying = false;
      _emit('ended', null);
    }).toJS;
    node.addEventListener('error', ((web.Event _) {
      _emit('error', node.error?.message ?? 'Web audio error');
    }).toJS);
  }

  /// [positionMs] 为毫秒，HTMLMediaElement.currentTime 单位为秒。
  void seekTo(double positionMs) {
    if (currentUrl.isEmpty) return;
    if (player == null) recreateNode();
    player?.currentTime = positionMs / 1000;
    _emit('seekComplete', positionMs.round());
    play();
  }

  /// 暂停时保留元素与进度，恢复播放只需再次 play()。
  void resume() {
    play();
  }

  void pause() {
    isPlaying = false;
    player?.pause();
  }

  void stop() {
    destroy();
    _emit('stop', null);
  }

  void release() {
    destroy();
  }

  void destroy() {
    isPlaying = false;
    final web.HTMLAudioElement? current = player;
    player = null;
    current?.pause();
  }

  void _emit(String method, Object? arguments) {
    onEvent?.call(method, arguments);
  }
}

class AudioManagerPlugin {
  // players by playerId
  Map<String, WrappedPlayer> players = {};
  MethodChannel? _channel;

  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
        'audio_manager',
        const StandardMethodCodec(),
        registrar);

    final AudioManagerPlugin instance = AudioManagerPlugin();
    instance._channel = channel;
    channel.setMethodCallHandler(instance.handleMethodCall);
  }

  WrappedPlayer getOrCreatePlayer(String playerId) {
    return players.putIfAbsent(playerId, () => WrappedPlayer());
  }

  WrappedPlayer start(String playerId, String url) {
    final WrappedPlayer player = getOrCreatePlayer(playerId);

    if (player.currentUrl == url) {
      return player;
    }

    player.start(url);
    return player;
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    final Map<String, dynamic> arguments = _argumentsOf(call.arguments);
    final playerId = arguments['playerId'] ?? "0";
    final player = getOrCreatePlayer(playerId);
    player.onEvent = (method, args) {
      _channel?.invokeMethod(method, args);
    };

    switch (call.method) {
      case "getPlatformVersion":
        return "Browser ";
      case "start":
        final String url = arguments["url"] ?? "";
        // String title = arguments["title"];
        // String desc = arguments["desc"];
        // String cover = arguments["cover"];
        final bool isAuto = arguments["isAuto"] ?? false;
        final bool isLocal = arguments["isLocal"] ?? false;
        // bool isLocalCover = arguments["isLocalCover"] ?? false;
        start(playerId, _resolveAssetUrl(url, isLocal: isLocal));
        if (isAuto) {
          player.play();
        }
        return "";
      case "playOrPause":
        if (player.isPlaying) {
          player.pause();
        } else {
          player.resume();
        }
        return player.isPlaying;
      case "play":
        player.resume();
        return player.isPlaying;
      case "pause":
        player.pause();
        return player.isPlaying;
      case "stop":
        player.stop();
        return null;
      case "release":
        player.release();
        return null;
      case "seekTo":
        final double position =
            (arguments['position'] as num?)?.toDouble() ?? 0;
        player.seekTo(position);
        return "";
      case "rate":
        final double rate = (arguments['rate'] as num?)?.toDouble() ?? 1.0;
        player.setRate(rate);
        return "";
      case "setVolume":
        // facade 发送的键是 value，不是 volume。
        final double volume = (arguments['value'] as num?)?.toDouble() ?? 1.0;
        player.setVolume(volume);
        // 与 Android 端一致：音量变化后回发 volumeChange，让 Dart 侧同步状态。
        _channel?.invokeMethod('volumeChange', volume);
        return "";
      case "currentVolume":
        return player.currentVolume;
      case "updateLrc":
        return "";
      case "updateInfo":
        return "";
      case "getState":
        final double positionMs = (player.player?.currentTime ?? 0) * 1000;
        final double durationMs = (player.player?.duration ?? 0) * 1000;
        return {
          'isPlaying': player.isPlaying,
          'position': positionMs.isFinite ? positionMs.round() : 0,
          'duration': durationMs.isFinite ? durationMs.round() : 0,
          'title': '',
          'desc': '',
          'cover': '',
          'url': player.currentUrl,
        };
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details:
              "The plugin for web doesn't implement the method '${call.method}'",
        );
    }
  }

  /// 框架解码出的 arguments 是 `Map<Object?, Object?>`，需安全地转为 `Map<String, dynamic>`，
  /// 否则直接赋给 `Map<String, dynamic>` 会触发运行时 TypeError。
  Map<String, dynamic> _argumentsOf(Object? arguments) {
    if (arguments is Map) {
      return arguments.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  /// Web 端资产存放在 `assets/<逻辑路径>`（release 构建会带上目录/编码），直接用逻辑路径
  /// 会 404。这里经 ui_web.assetManager 解析成实际服务路径，对应 Android 端的
  /// getAssetFilePathByName。非本地（http/https/file）URL 原样返回。
  String _resolveAssetUrl(String url, {required bool isLocal}) {
    if (!isLocal) return url;
    try {
      return ui_web.assetManager.getAssetUrl(url);
    } catch (_) {
      return url;
    }
  }
}
