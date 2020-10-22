/// Play callback event enumeration
enum AudioManagerEvents {
  /// start load data
  start,

  /// ready to play. If you want to invoke [seekTo], you must follow this callback
  ready,

  /// seek completed
  seekComplete,

  /// buffering size
  buffering,

  /// [isPlaying] status
  playstatus,
  timeupdate,
  error,
  next,
  previous,
  ended,

  /// Android notification bar click Close
  stop,

  /// ⚠️ IOS simulator is invalid, please use real machine
  volumeChange,
  unknow
}
typedef void Events(AudioManagerEvents events, args);

/// Play rate enumeration [0.5, 0.75, 1, 1.5, 1.75, 2]
enum AudioRate { rate50, rate75, rate100, rate150, rate175, rate200 }

/// play mode
enum PlayMode { sequence, shuffle, single }

class PlaybackState {
  final AudioState state;

  final Duration position;

  final Duration bufferedSize;

  final AudioRate speed;

  final error;

  const PlaybackState(
    this.state, {
    this.position,
    this.bufferedSize,
    this.speed,
    this.error,
  }) : assert(state != null);

  const PlaybackState.none()
      : this(
          AudioState.none,
          position: const Duration(seconds: 0),
          bufferedSize: const Duration(seconds: 0),
          speed: AudioRate.rate100,
        );
}

/// play state
enum AudioState { none, paused, playing, buffering, error }
