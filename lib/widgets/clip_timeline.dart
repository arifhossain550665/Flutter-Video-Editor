import 'dart:io';

import 'package:flutter/material.dart';

import '../models/video_clip.dart';
import '../services/ffmpeg_service.dart';
import '../services/media_service.dart';

/// CapCut-style combined video track: every clip in the project laid out
/// on one continuous horizontal filmstrip, each segment sized proportional
/// to its trimmed duration, so the whole project reads as a single
/// timeline instead of a plain list. Tapping a segment opens that clip for
/// trimming.
class ClipTimeline extends StatefulWidget {
  final List<VideoClip> clips;
  final String? selectedClipId;
  final ValueChanged<VideoClip> onTapClip;

  const ClipTimeline({
    super.key,
    required this.clips,
    required this.onTapClip,
    this.selectedClipId,
  });

  @override
  State<ClipTimeline> createState() => _ClipTimelineState();
}

class _ClipTimelineState extends State<ClipTimeline> {
  final FFmpegService _ffmpegService = FFmpegService();
  final MediaService _mediaService = MediaService();
  final Map<String, String> _thumbnailCache = {};

  static const double _height = 64;

  @override
  void initState() {
    super.initState();
    _loadThumbnails();
  }

  @override
  void didUpdateWidget(covariant ClipTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.clips.map((c) => c.id).toSet();
    final newIds = widget.clips.map((c) => c.id).toSet();
    if (!oldIds.containsAll(newIds) || !newIds.containsAll(oldIds)) {
      _loadThumbnails();
    }
  }

  Future<void> _loadThumbnails() async {
    for (final clip in widget.clips) {
      if (_thumbnailCache.containsKey(clip.id)) continue;
      try {
        final dir =
            await _mediaService.newTempSubdirectory('cover_${clip.id}');
        final thumbs = await _ffmpegService.generateThumbnails(
          inputPath: clip.sourcePath,
          totalDuration: clip.sourceDuration,
          outputDir: dir.path,
          count: 1,
        );
        if (thumbs.isNotEmpty && mounted) {
          setState(() => _thumbnailCache[clip.id] = thumbs.first);
        }
      } catch (_) {
        // Best effort - a clip without a cached thumbnail just shows a
        // placeholder tile instead of blocking the timeline.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.clips.isEmpty) {
      return Container(
        height: _height,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2E),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Add clips to see them on the timeline',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }

    final totalMs = widget.clips.fold<int>(
      0,
      (sum, c) => sum + c.trimmedDuration.inMilliseconds,
    );
    final safeTotalMs = totalMs <= 0 ? 1 : totalMs;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: _height,
        child: Row(
          children: widget.clips.map((clip) {
            final flex = ((clip.trimmedDuration.inMilliseconds /
                        safeTotalMs) *
                    1000)
                .round()
                .clamp(1, 100000);
            final thumb = _thumbnailCache[clip.id];
            final isSelected = clip.id == widget.selectedClipId;
            return Expanded(
              flex: flex,
              child: GestureDetector(
                onTap: () => widget.onTapClip(clip),
                child: Container(
                  decoration: BoxDecoration(
                    border: isSelected
                        ? Border.all(color: Colors.amber.shade400, width: 3)
                        : const Border(
                            right: BorderSide(color: Colors.black, width: 1),
                          ),
                    image: thumb != null
                        ? DecorationImage(
                            image: FileImage(File(thumb)),
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: thumb == null ? const Color(0xFF2A2A2E) : null,
                  ),
                  alignment: Alignment.center,
                  child: Stack(
                    children: [
                      if (thumb == null)
                        const Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      if (clip.noiseCancellationEnabled ||
                          clip.volumePercent != 100)
                        const Positioned(
                          right: 3,
                          bottom: 3,
                          child: Icon(Icons.graphic_eq,
                              size: 14, color: Colors.amber),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
