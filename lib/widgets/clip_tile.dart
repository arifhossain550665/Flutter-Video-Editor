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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.movie_outlined)),
        title: Text(clip.fileName, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          'Trim: ${_format(clip.trimStart)} - ${_format(clip.trimEnd)} '
          '(${(clip.trimmedDuration.inMilliseconds / 1000).toStringAsFixed(1)}s)',
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
