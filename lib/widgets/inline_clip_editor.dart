import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/video_clip.dart';
import '../services/ffmpeg_service.dart';
import '../services/media_service.dart';
import 'trim_timeline.dart';

/// Inline, same-screen clip editor: video preview, CapCut-style filmstrip
/// trim timeline, and per-clip noise cancellation / volume boost controls -
/// all embedded directly on the main editor screen (below the project
/// timeline) instead of opening a separate route, so the whole project and
/// this clip's controls stay visible together.
class InlineClipEditor extends StatefulWidget {
  final VideoClip clip;
  final void Function(Map<String, dynamic> settings) onDone;
  final VoidCallback onClose;

  const InlineClipEditor({
    super.key,
    required this.clip,
    required this.onDone,
    required this.onClose,
  });

  @override
  State<InlineClipEditor> createState() => _InlineClipEditorState();
}

class _InlineClipEditorState extends State<InlineClipEditor> {
  final FFmpegService _ffmpegService = FFmpegService();
  final MediaService _mediaService = MediaService();

  late VideoPlayerController _controller;
  late Duration _start;
  late Duration _end;
  late double _volumePercent;
  late bool _noiseCancellation;

  List<String> _thumbnails = [];
  bool _videoReady = false;
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
    // Only reload the player/thumbnails/trim state when the user actually
    // selected a *different* clip - an unrelated rebuild (e.g. another
    // clip being imported elsewhere) must never reset in-progress edits.
    if (oldWidget.clip.id != widget.clip.id) {
      _controller.removeListener(_onTick);
      _controller.dispose();
      _loadClip(widget.clip);
    }
  }

  void _loadClip(VideoClip clip) {
    _loadedClipId = clip.id;
    _start = clip.trimStart;
    _end = clip.trimEnd;
    _volumePercent = clip.volumePercent;
    _noiseCancellation = clip.noiseCancellationEnabled;
    _videoReady = false;
    _thumbnailsLoading = true;
    _thumbnails = [];

    _controller = VideoPlayerController.file(File(clip.sourcePath));
    _controller.initialize().then((_) {
      if (!mounted || _loadedClipId != clip.id) return;
      setState(() => _videoReady = true);
      _controller.seekTo(_start);
    });
    _controller.addListener(_onTick);

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

  void _onTick() {
    if (!mounted) return;
    if (_controller.value.isPlaying && _controller.value.position >= _end) {
      _controller.pause();
      _controller.seekTo(_start);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final centis =
        ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds.$centis';
  }

  void _togglePlayback() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      final position = _controller.value.position;
      if (position >= _end || position < _start) {
        _controller.seekTo(_start);
      }
      _controller.play();
    }
    setState(() {});
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
          if (!_videoReady)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
            Center(
              child: IconButton(
                iconSize: 40,
                icon: Icon(
                  _controller.value.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                ),
                onPressed: _togglePlayback,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_start),
                  style: const TextStyle(color: Colors.amber, fontSize: 12),
                ),
                Text(
                  '${_formatDuration(_end - _start)} selected',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12),
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
                : TrimTimeline(
                    thumbnails: _thumbnails,
                    totalDuration: widget.clip.sourceDuration,
                    start: _start,
                    end: _end,
                    playhead: _controller.value.position,
                    onStartChanged: (value) {
                      setState(() => _start = value);
                      _controller.seekTo(value);
                    },
                    onEndChanged: (value) {
                      setState(() => _end = value);
                      _controller.seekTo(value);
                    },
                    onScrub: (value) => _controller.seekTo(value),
                  ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: Colors.amber.shade400,
              title: const Text('Noise cancellation',
                  style: TextStyle(fontSize: 13)),
              value: _noiseCancellation,
              onChanged: (value) =>
                  setState(() => _noiseCancellation = value),
            ),
            Text('Volume boost: ${_volumePercent.round()}%',
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
          ],
        ],
      ),
    );
  }
}
