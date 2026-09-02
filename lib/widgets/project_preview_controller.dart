import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../models/video_clip.dart';

/// Drives a single continuous video preview across every trimmed clip laid
/// out end-to-end on the project timeline. It automatically switches the
/// underlying source file as playback (or scrubbing) crosses from one
/// clip into the next, so scrubbing/playing across the whole project
/// looks and feels like one continuous video - the way CapCut's main
/// preview works - without needing to actually render/export anything.
class ProjectPreviewController extends ChangeNotifier {
  List<VideoClip> _clips = [];
  VideoPlayerController? _activeController;
  int _activeClipIndex = -1;
  bool _disposed = false;

  bool get isReady => _activeController?.value.isInitialized ?? false;
  bool get isPlaying => _activeController?.value.isPlaying ?? false;
  double get aspectRatio => _activeController?.value.aspectRatio ?? 16 / 9;
  VideoPlayerController? get activeController => _activeController;

  Duration get totalDuration =>
      _clips.fold(Duration.zero, (sum, c) => sum + c.trimmedDuration);

  /// Current position expressed on the *project* timeline (0 at the very
  /// start of clip 1, counting continuously across every clip).
  Duration get position {
    if (_activeClipIndex < 0 ||
        _activeClipIndex >= _clips.length ||
        _activeController == null) {
      return Duration.zero;
    }
    final clip = _clips[_activeClipIndex];
    final localPosition = _activeController!.value.position - clip.trimStart;
    return _cumulativeStart(_activeClipIndex) +
        _clampToClipLength(localPosition, _activeClipIndex);
  }

  Duration _clampToClipLength(Duration d, int index) {
    final length = _clips[index].trimmedDuration;
    if (d < Duration.zero) return Duration.zero;
    if (d > length) return length;
    return d;
  }

  Duration _cumulativeStart(int index) {
    var sum = Duration.zero;
    for (var i = 0; i < index && i < _clips.length; i++) {
      sum += _clips[i].trimmedDuration;
    }
    return sum;
  }

  /// Call whenever the project's clip list changes (added/removed/
  /// reordered/trimmed). Keeps showing the same clip if it's still present
  /// (even at a new index after a reorder); otherwise resets to the start.
  Future<void> setClips(List<VideoClip> clips) async {
    final previousActiveId =
        (_activeClipIndex >= 0 && _activeClipIndex < _clips.length)
            ? _clips[_activeClipIndex].id
            : null;
    _clips = clips;

    if (clips.isEmpty) {
      await _teardownActiveController();
      _activeClipIndex = -1;
      notifyListeners();
      return;
    }

    if (previousActiveId != null) {
      final sameClipNewIndex =
          clips.indexWhere((c) => c.id == previousActiveId);
      if (sameClipNewIndex >= 0 && _activeController != null) {
        // Same clip is still loaded (maybe just reordered) - no need to
        // reload the player, just update the index bookkeeping.
        _activeClipIndex = sameClipNewIndex;
        notifyListeners();
        return;
      }
    }

    if (_activeController == null) {
      await _activateClip(0);
    }
  }

  Future<void> _activateClip(int index) async {
    if (_clips.isEmpty || index < 0 || index >= _clips.length) return;
    final wasPlaying = isPlaying;
    await _teardownActiveController();
    final clip = _clips[index];
    final controller = VideoPlayerController.file(File(clip.sourcePath));
    _activeController = controller;
    _activeClipIndex = index;
    await controller.initialize();
    if (_disposed) return;
    controller.addListener(_onActiveControllerTick);
    await controller.seekTo(clip.trimStart);
    notifyListeners();
    if (wasPlaying) {
      await controller.play();
    }
  }

  Future<void> _teardownActiveController() async {
    _activeController?.removeListener(_onActiveControllerTick);
    final old = _activeController;
    _activeController = null;
    await old?.dispose();
  }

  void _onActiveControllerTick() {
    if (_disposed || _activeController == null) return;
    if (_activeClipIndex < 0 || _activeClipIndex >= _clips.length) return;
    final clip = _clips[_activeClipIndex];
    final pos = _activeController!.value.position;
    if (_activeController!.value.isPlaying && pos >= clip.trimEnd) {
      _advanceOrStop();
      return;
    }
    notifyListeners();
  }

  Future<void> _advanceOrStop() async {
    if (_activeClipIndex + 1 < _clips.length) {
      await _activateClip(_activeClipIndex + 1);
    } else {
      await _activeController?.pause();
      if (_activeClipIndex >= 0 && _activeClipIndex < _clips.length) {
        await _activeController?.seekTo(_clips[_activeClipIndex].trimStart);
      }
      notifyListeners();
    }
  }

  Future<void> play() async {
    if (_clips.isEmpty) return;
    if (_activeController == null) {
      await _activateClip(0);
    }
    // If sitting at the very end of the last clip, restart from the top.
    if (_activeClipIndex == _clips.length - 1 && _activeController != null) {
      final clip = _clips[_activeClipIndex];
      if (_activeController!.value.position >= clip.trimEnd) {
        await seekTo(Duration.zero);
      }
    }
    await _activeController?.play();
    notifyListeners();
  }

  Future<void> pause() async {
    await _activeController?.pause();
    notifyListeners();
  }

  /// Seeks to [projectPosition] on the overall project timeline, switching
  /// the underlying clip if the position falls in a different one.
  Future<void> seekTo(Duration projectPosition) async {
    if (_clips.isEmpty) return;
    var remaining = projectPosition;
    var index = 0;
    for (; index < _clips.length; index++) {
      final length = _clips[index].trimmedDuration;
      if (remaining <= length || index == _clips.length - 1) break;
      remaining -= length;
    }
    remaining = _clampToClipLength(remaining, index);
    final targetInFile = _clips[index].trimStart + remaining;

    if (index != _activeClipIndex) {
      await _activateClip(index);
    }
    await _activeController?.seekTo(targetInFile);
    notifyListeners();
  }

  /// Convenience helper: seeks the preview to the very start of the clip
  /// with the given [clipId] on the project timeline.
  Future<void> seekToClipStart(String clipId) async {
    final index = _clips.indexWhere((c) => c.id == clipId);
    if (index < 0) return;
    await seekTo(_cumulativeStart(index));
  }

  /// Directly previews [clip] at a raw [filePosition] within its own
  /// source file, bypassing the project-timeline mapping entirely. Used by
  /// the inline trim editor to audition in/out points that haven't been
  /// applied yet, independent of the clip's currently committed trim.
  Future<void> previewClipFilePosition(
    VideoClip clip,
    Duration filePosition,
  ) async {
    final index = _clips.indexWhere((c) => c.id == clip.id);
    if (index < 0) return;
    if (_activeClipIndex != index || _activeController == null) {
      await _teardownActiveController();
      final controller = VideoPlayerController.file(File(clip.sourcePath));
      _activeController = controller;
      _activeClipIndex = index;
      await controller.initialize();
      if (_disposed) return;
      controller.addListener(_onActiveControllerTick);
    }
    await _activeController?.pause();
    await _activeController?.seekTo(filePosition);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _activeController?.removeListener(_onActiveControllerTick);
    _activeController?.dispose();
    super.dispose();
  }
}
