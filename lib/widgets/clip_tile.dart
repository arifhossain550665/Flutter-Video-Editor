import 'package:flutter/material.dart';

import '../models/video_clip.dart';

class ClipTile extends StatelessWidget {
  final VideoClip clip;
  final VoidCallback onTrim;
  final VoidCallback onRemove;

  const ClipTile({
    super.key,
    required this.clip,
    required this.onTrim,
    required this.onRemove,
  });

  String _format(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final hasAudioTweaks =
        clip.noiseCancellationEnabled || clip.volumePercent != 100;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.movie_outlined)),
        title: Text(clip.fileName, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trim: ${_format(clip.trimStart)} - ${_format(clip.trimEnd)} '
              '(${(clip.trimmedDuration.inMilliseconds / 1000).toStringAsFixed(1)}s)',
            ),
            if (hasAudioTweaks)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  children: [
                    if (clip.noiseCancellationEnabled)
                      const _Badge(icon: Icons.graphic_eq, label: 'Denoised'),
                    if (clip.volumePercent != 100)
                      _Badge(
                        icon: Icons.volume_up,
                        label: '${clip.volumePercent.round()}%',
                      ),
                  ],
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.content_cut),
              tooltip: 'Trim',
              onPressed: onTrim,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Badge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.amber.shade400),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.amber.shade400),
          ),
        ],
      ),
    );
  }
}
