import 'package:audio_manager/audio_manager.dart';
import 'package:flutter/material.dart';

import '../controllers/player_controller.dart';
import '../models/demo_track.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('audio_manager example'),
            actions: [
              IconButton(
                tooltip: 'Update info',
                icon: const Icon(Icons.edit_note),
                onPressed: controller.updateCurrentInfo,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _StatusBanner(controller: controller),
                Expanded(child: _TrackList(controller: controller)),
                _NowPlaying(controller: controller),
                _PlayerControls(controller: controller),
                _ProgressBar(controller: controller),
                _VolumeBar(controller: controller),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.error;
    if (error.isNotEmpty) {
      return Material(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.error_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            controller.isPlaying ? Icons.graphic_eq : Icons.music_note,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              controller.platformVersion,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (controller.isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.tracks;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: tracks.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final track = tracks[index];
        // 与播放卡片(currentTrack)严格一致，避免 currentIndex 越界时列表高亮与卡片不同步
        final selected = identical(track, controller.currentTrack);
        return ListTile(
          selected: selected,
          leading: _CoverImage(track: track, size: 44),
          title:
              Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(track.subtitle,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: selected ? const Icon(Icons.play_arrow) : null,
          onTap: () => controller.play(index),
        );
      },
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final track = controller.currentTrack;
    if (track == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          _CoverImage(track: track, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  track.subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: controller.playMode.name,
          icon: Icon(_modeIcon(controller.playMode)),
          onPressed: controller.nextMode,
        ),
        IconButton(
          tooltip: 'Previous',
          icon: const Icon(Icons.skip_previous),
          iconSize: 32,
          onPressed: controller.previous,
        ),
        IconButton.filled(
          tooltip: controller.isPlaying ? 'Pause' : 'Play',
          iconSize: 42,
          icon: Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: controller.playOrPause,
        ),
        IconButton(
          tooltip: 'Next',
          icon: const Icon(Icons.skip_next),
          iconSize: 32,
          onPressed: controller.next,
        ),
        IconButton(
          tooltip: 'Stop',
          icon: const Icon(Icons.stop),
          onPressed: controller.stop,
        ),
      ],
    );
  }

  IconData _modeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.sequence:
        return Icons.repeat;
      case PlayMode.shuffle:
        return Icons.shuffle;
      case PlayMode.single:
        return Icons.repeat_one;
    }
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final durationMs = controller.duration.inMilliseconds;
    final progress =
        durationMs > 0 ? controller.position.inMilliseconds / durationMs : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(_formatDuration(controller.position)),
          Expanded(
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: (_) {},
              onChangeEnd: (value) {
                controller.seek(
                  Duration(milliseconds: (durationMs * value).round()),
                );
              },
            ),
          ),
          Text(_formatDuration(controller.duration)),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

class _VolumeBar extends StatelessWidget {
  const _VolumeBar({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.volume_down),
          Expanded(
            child: Slider(
              value: controller.volume.clamp(0.0, 1.0),
              onChanged: controller.setVolume,
            ),
          ),
          const Icon(Icons.volume_up),
        ],
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.track, required this.size});

  final DemoTrack track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isNetwork = track.coverUrl.startsWith('http');
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Icon(Icons.music_note),
    );

    final image = isNetwork
        ? Image.network(
            track.coverUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => placeholder,
          )
        : Image.asset(
            track.coverUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => placeholder,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: image,
    );
  }
}
