import 'dart:async';
import 'dart:html';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'audio_manager.dart';

class WrappedPlayer {
  double pausedAt;
  double currentVolume = 1;
  double currentRate = 1;
  PlayMode playMode = PlayMode.sequence;
  String currentUrl;
  bool isPlaying = false;

  AudioElement player;

  void start(String url) {
    currentUrl = url;

    stop();
    recreateNode();
    if (isPlaying) {
      resume();
    }
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
    if (currentUrl == null) {
      return;
    }
    player = AudioElement(currentUrl);
    player.loop = playMode == PlayMode.single;
    player.volume = currentVolume;
    player.playbackRate = currentRate;
  }

  void seekTo(double position) {
    isPlaying = true;
    if (currentUrl == null) {
      return;
    }
    if (player == null) {
      recreateNode();
    }
    player.play();
    player.currentTime = position;
  }

  void resume() {
    seekTo(pausedAt ?? 0);
  }

  void pause() {
    pausedAt = player.currentTime;
    _cancel();
  }

  void stop() {
    pausedAt = 0;
    _cancel();
  }

  void release() {
    _cancel();
    player = null;
  }

  void _cancel() {
    isPlaying = false;
    player?.pause();
    player = null;
  }
}

class AudioManagerPlugin {
  // players by playerId
  Map<String, WrappedPlayer> players = {};

  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'audio_manager',
      const StandardMethodCodec(),
      registrar.messenger,
    );

    final AudioManagerPlugin instance = AudioManagerPlugin();
    channel.setMethodCallHandler(instance.handleMethodCall);
  }

  WrappedPlayer getOrCreatePlayer(String playerId) {
    return players.putIfAbsent(playerId, () => WrappedPlayer());
  }

  Future<WrappedPlayer> start(String playerId, String url) async {
    final WrappedPlayer player = getOrCreatePlayer(playerId);

    if (player.currentUrl == url) {
      return player;
    }

    player.start(url);
    return player;
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    Map<String, dynamic> arguments = call.arguments;
    final playerId = call.arguments['playerId'];
    var player = getOrCreatePlayer(playerId);
    switch (call.method) {
      case "getPlatformVersion":
        return ("Browser ");
      case "start":
        final String url = arguments["url"];
        String title = arguments["title"];
        String desc = arguments["desc"];
        String cover = arguments["cover"];
        bool isAuto = arguments["isAuto"] ?? false;
        bool isLocal = arguments["isLocal"] ?? false;
        bool isLocalCover = arguments["isLocalCover"] ?? false;
        player = await start(playerId, url);
        player.player.autoplay = isAuto;
        return 1;
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
        break;
      case 'release':
        player.release();
        return 1;
      case "seekTo":
        double position = call.arguments['position'] ?? 0;
        player.seekTo(position);
        break;
      case 'rate':
        double rate = call.arguments['rate'] ?? 1.0;
        player.setRate(rate);
        return 1;
      case "setVolume":
        double volume = call.arguments['volume'] ?? 1.0;
        player.setVolume(volume);
        break;
      case "currentVolume":
        return player.currentVolume;
      case 'updateLrc':
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details:
              "The plugin for web doesn't implement the method '${call.method}'",
        );
    }
  }
}
