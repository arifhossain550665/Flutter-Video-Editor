import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/video_clip.dart';

/// Full-screen trim editor for a single clip. Pops with a
/// `{'start': Duration, 'end': Duration}` map when the user taps Save.
class TrimScreen extends StatefulWidget {
  final VideoClip clip;
  const TrimScreen({super.key, required this.clip});

  @override
  State<TrimScreen> createState() => _TrimScreenState();
}

class _TrimScreenState extends State<TrimScreen> {
  late final VideoPlayerController _controller;
  late double _startMs;
  late double _endMs;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _startMs = widget.clip.trimStart.inMilliseconds.toDouble();
    _endMs = widget.clip.trimEnd.inMilliseconds.toDouble();
    _controller = VideoPlayerController.file(File(widget.clip.sourcePath));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
      _controller.seekTo(Duration(milliseconds: _startMs.round()));
    });
    _controller.addListener(_onTick);
  }

  void _onTick() {
    if (!_controller.value.isPlaying) return;
    final positionMs = _controller.value.position.inMilliseconds;
    if (positionMs >= _endMs) {
      _controller.pause();
      _controller.seekTo(Duration(milliseconds: _startMs.round()));
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  String _formatMs(double ms) {
    final duration = Duration(milliseconds: ms.round());
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _togglePlayback() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      if (_controller.value.position.inMilliseconds >= _endMs) {
        _controller.seekTo(Duration(milliseconds: _startMs.round()));
      }
      _controller.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.clip.sourceDuration.inMilliseconds.toDouble();
    final safeMax = totalMs > 0 ? totalMs : 1.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trim Clip'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop({
                'start': Duration(milliseconds: _startMs.round()),
                'end': Duration(milliseconds: _endMs.round()),
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                    const SizedBox(height: 8),
                    IconButton(
                      iconSize: 48,
                      icon: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                      ),
                      onPressed: _togglePlayback,
                    ),
                    Text('Start: ${_formatMs(_startMs)}   End: ${_formatMs(_endMs)}'),
                    RangeSlider(
                      values: RangeValues(
                        _startMs.clamp(0, safeMax),
                        _endMs.clamp(0, safeMax),
                      ),
                      min: 0,
                      max: safeMax,
                      onChanged: (values) {
                        setState(() {
                          _startMs = values.start;
                          _endMs = values.end;
                        });
                        _controller.seekTo(Duration(milliseconds: _startMs.round()));
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Clip length: ${((_endMs - _startMs) / 1000).toStringAsFixed(1)}s',
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
