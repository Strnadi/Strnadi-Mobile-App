import 'package:flutter/material.dart';

class RecordingPlaybackControls extends StatelessWidget {
  const RecordingPlaybackControls({
    super.key,
    required this.position,
    required this.duration,
    required this.progress,
    required this.isPlaying,
    required this.onTogglePlay,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final double progress;
  final bool isPlaying;
  final VoidCallback onTogglePlay;
  final ValueChanged<int> onSeek;

  String _formatPlayerTime(Duration duration) {
    final seconds = duration.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12.0),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
      ),
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatPlayerTime(position),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              _formatPlayerTime(duration),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.replay_10, size: 28),
              onPressed: () => onSeek(-10),
            ),
            const SizedBox(width: 4),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
              ),
              child: IconButton(
                icon: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                ),
                iconSize: 56,
                onPressed: onTogglePlay,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.forward_10, size: 28),
              onPressed: () => onSeek(10),
            ),
          ],
        ),
      ],
    ),
  );
}
