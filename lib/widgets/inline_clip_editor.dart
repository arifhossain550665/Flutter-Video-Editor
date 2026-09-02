import 'package:flutter/material.dart';

import '../models/video_clip.dart';
import '../services/ffmpeg_service.dart';
import '../services/media_service.dart';
import 'project_preview_controller.dart';
import 'trim_timeline.dart';

/// Inline, same-screen clip editor: a CapCut-style filmstrip trim timeline
/// plus per-clip noise cancellation / volume boost controls, embedded
/// directly below the project timeline. It drives the shared
/// [ProjectPreviewController] (the one persistent preview at the top of
/// the editor) instead of opening its own separate video player, so
/// trimming this clip and watching the change happen both happen in the
/// exact same place.
class InlineClipEditor extends StatefulWidget {
  final VideoClip clip;
  final ProjectPreviewController previewController;
  final void Function(Map<String, dynamic> settings) onDone;
  final VoidCallback onClose;

  const InlineClipEditor({
    super.key,
    required this.clip,
    required this.previewController,
    required this.onDone,
    required this.onClose,
  });

  @override
  State<InlineClipEditor> createState() => _InlineClipEditorState();
}

class _InlineClipEditorState extends State<InlineClipEditor> {
  final FFmpegService _ffmpegService = FFmpegService();
  final MediaService _mediaService = MediaService();

  late Duration _start;
  late Duration _end;
  late double _volumePercent;
  late bool _noiseCancellation;

  List<String> _thumbnails = [];
  bool _thumbnailsLoading = true;
  String? _loadedClipId;

  @override
  void initState() {
    super.initState();
    _loadClip(widget.clip);
  }

  @override
  void didUpdateWidget(covariant InlineClipEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only reload when the user actually selected a *different* clip - an
    // unrelated rebuild elsewhere must never reset in-progress edits.
    if (oldWidget.clip.id != widget.clip.id) {
      _loadClip(widget.clip);
    }
  }

  void _loadClip(VideoClip clip) {
    _loadedClipId = clip.id;
    _start = clip.trimStart;
    _end = clip.trimEnd;
    _volumePercent = clip.volumePercent;
    _noiseCancellation = clip.noiseCancellationEnabled;
    _thumbnailsLoading = true;
    _thumbnails = [];

    // Point the shared preview at this clip's current in-point right away.
    widget.previewController.previewClipFilePosition(clip, _start);

    _loadThumbnails(clip);
  }

  Future<void> _loadThumbnails(VideoClip clip) async {
    try {
      final dir =
          await _mediaService.newTempSubdirectory('thumbs_${clip.id}');
      final thumbs = await _ffmpegService.generateThumbnails(
        inputPath: clip.sourcePath,
        totalDuration: clip.sourceDuration,
        outputDir: dir.path,
        count: 14,
      );
      if (mounted && _loadedClipId == clip.id) {
        setState(() {
          _thumbnails = thumbs;
          _thumbnailsLoading = false;
        });
      }
    } catch (_) {
      if (mounted && _loadedClipId == clip.id) {
        setState(() => _thumbnailsLoading = false);
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final centis =
        ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds.$centis';
  }

  void _commit() {
    widget.onDone({
      'start': _start,
      'end': _end,
      'volumePercent': _volumePercent,
      'noiseCancellation': _noiseCancellation,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.content_cut, size: 16, color: Colors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.clip.fileName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: _commit,
                child: const Text('Done'),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Close without applying',
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_start),
                style: const TextStyle(color: Colors.amber, fontSize: 12),
              ),
              Text(
                '${_formatDuration(_end - _start)} selected',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                _formatDuration(_end),
                style: const TextStyle(color: Colors.amber, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _thumbnailsLoading
              ? const SizedBox(
                  height: 64,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : AnimatedBuilder(
                  animation: widget.previewController,
                  builder: (context, _) {
                    final playhead =
                        widget.previewController.activeController?.value
                                .position ??
                            _start;
                    return TrimTimeline(
                      thumbnails: _thumbnails,
                      totalDuration: widget.clip.sourceDuration,
                      start: _start,
                      end: _end,
                      playhead: playhead,
                      onStartChanged: (value) {
                        setState(() => _start = value);
                        widget.previewController
                            .previewClipFilePosition(widget.clip, value);
                      },
                      onEndChanged: (value) {
                        setState(() => _end = value);
                        widget.previewController
                            .previewClipFilePosition(widget.clip, value);
                      },
                      onScrub: (value) => widget.previewController
                          .previewClipFilePosition(widget.clip, value),
                    );
                  },
                ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: Colors.amber.shade400,
            title: const Text("This clip's noise cancellation",
                style: TextStyle(fontSize: 13)),
            subtitle: const Text(
              'Only reduces hiss/hum if this clip actually has any',
              style: TextStyle(fontSize: 11),
            ),
            value: _noiseCancellation,
            onChanged: (value) =>
                setState(() => _noiseCancellation = value),
          ),
          Text("This clip's volume boost: ${_volumePercent.round()}%",
              style: const TextStyle(fontSize: 13)),
          Slider(
            activeColor: Colors.amber.shade400,
            value: _volumePercent,
            min: 100,
            max: 300,
            divisions: 20,
            label: '${_volumePercent.round()}%',
            onChanged: (value) => setState(() => _volumePercent = value),
          ),
          const Text(
            'Tip: the preview above doesn\'t play boosted volume live - '
            'the boost is audible in the exported video. Tap Done to save.',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
