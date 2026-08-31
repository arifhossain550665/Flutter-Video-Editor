import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/video_clip.dart';
import '../services/ffmpeg_service.dart';
import '../services/media_service.dart';
import '../widgets/trim_timeline.dart';

/// CapCut-style full-screen trim editor for a single clip: video preview,
/// a thumbnail-filmstrip trim timeline with draggable handles, and
/// per-clip noise cancellation / volume boost controls.
///
/// Pops with a `{'start': Duration, 'end': Duration, 'volumePercent':
/// double, 'noiseCancellation': bool}` map when the user taps Save.
class TrimScreen extends StatefulWidget {
  final VideoClip clip;
  const TrimScreen({super.key, required this.clip});

  @override
  State<TrimScreen> createState() => _TrimScreenState();
}

class _TrimScreenState extends State<TrimScreen> {
  final FFmpegService _ffmpegService = FFmpegService();
  final MediaService _mediaService = MediaService();

  late final VideoPlayerController _controller;
  late Duration _start;
  late Duration _end;
  late double _volumePercent;
  late bool _noiseCancellation;

  List<String> _thumbnails = [];
  bool _videoReady = false;
  bool _thumbnailsLoading = true;

  @override
  void initState() {
    super.initState();
    _start = widget.clip.trimStart;
    _end = widget.clip.trimEnd;
    _volumePercent = widget.clip.volumePercent;
    _noiseCancellation = widget.clip.noiseCancellationEnabled;

    _controller = VideoPlayerController.file(File(widget.clip.sourcePath));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _videoReady = true);
      _controller.seekTo(_start);
    });
    _controller.addListener(_onTick);

    _loadThumbnails();
  }

  Future<void> _loadThumbnails() async {
    try {
      final dir = await _mediaService
          .newTempSubdirectory('thumbs_${widget.clip.id}');
      final thumbs = await _ffmpegService.generateThumbnails(
        inputPath: widget.clip.sourcePath,
        totalDuration: widget.clip.sourceDuration,
        outputDir: dir.path,
        count: 14,
      );
      if (mounted) {
        setState(() {
          _thumbnails = thumbs;
          _thumbnailsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _thumbnailsLoading = false);
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
    final centis = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
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

  void _save() {
    Navigator.of(context).pop({
      'start': _start,
      'end': _end,
      'volumePercent': _volumePercent,
      'noiseCancellation': _noiseCancellation,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121214),
        title: const Text('Trim Clip'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: !_videoReady
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                    ),
                  ),
                  IconButton(
                    iconSize: 52,
                    color: Colors.white,
                    icon: Icon(
                      _controller.value.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                    ),
                    onPressed: _togglePlayback,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_start),
                          style: const TextStyle(
                              color: Colors.amber, fontSize: 13),
                        ),
                        Text(
                          '${_formatDuration(_end - _start)} selected',
                          style:
                              const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          _formatDuration(_end),
                          style: const TextStyle(
                              color: Colors.amber, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _thumbnailsLoading
                        ? const SizedBox(
                            height: 72,
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
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
                            onScrub: (value) {
                              _controller.seekTo(value);
                            },
                          ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.amber.shade400,
                          title: const Text('Noise cancellation'),
                          subtitle: const Text(
                            "Reduce hiss/background noise in this clip's audio",
                            style: TextStyle(fontSize: 12),
                          ),
                          value: _noiseCancellation,
                          onChanged: (value) =>
                              setState(() => _noiseCancellation = value),
                        ),
                        Text('Volume boost: ${_volumePercent.round()}%'),
                        Slider(
                          activeColor: Colors.amber.shade400,
                          value: _volumePercent,
                          min: 100,
                          max: 300,
                          divisions: 20,
                          label: '${_volumePercent.round()}%',
                          onChanged: (value) =>
                              setState(() => _volumePercent = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
    );
  }
}
