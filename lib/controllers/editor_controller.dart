import 'package:flutter/foundation.dart';

import '../models/video_clip.dart';
import '../services/ffmpeg_service.dart';
import '../services/media_service.dart';

enum ExportStage {
  idle,
  trimming,
  merging,
  mixingAudio,
  savingToGallery,
  done,
  error,
}

/// Single source of truth for the editor screen: the list of imported
/// clips, the chosen background-audio/noise/volume settings, and the state
/// of an in-progress export.
class EditorController extends ChangeNotifier {
  final FFmpegService _ffmpegService = FFmpegService();
  final MediaService _mediaService = MediaService();

  final List<VideoClip> clips = [];
  String? backgroundAudioPath;
  bool noiseCancellationEnabled = false;
  double volumePercent = 100;

  ExportStage stage = ExportStage.idle;
  double overallProgress = 0.0;
  String? errorMessage;
  String? exportedFilePath;

  /// Opens the video picker, probes each selected file's duration and
  /// dimensions, and adds it to the clip list.
  Future<void> importVideos() async {
    final files = await _mediaService.pickVideoFiles();
    for (final file in files) {
      final metadata = await _mediaService.probeVideoMetadata(file.path);
      clips.add(
        VideoClip(
          id: '${DateTime.now().microsecondsSinceEpoch}_${clips.length}',
          sourcePath: file.path,
          sourceDuration: metadata.duration,
          sourceWidth: metadata.width > 0 ? metadata.width : 1280,
          sourceHeight: metadata.height > 0 ? metadata.height : 720,
        ),
      );
    }
    notifyListeners();
  }

  void removeClip(String id) {
    clips.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  void reorderClip(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final clip = clips.removeAt(oldIndex);
    clips.insert(newIndex, clip);
    notifyListeners();
  }

  /// Updates a clip's trim range and its own per-clip audio settings
  /// (noise cancellation + volume boost applied to that clip's original
  /// audio track, independent of the project-wide background audio track).
  void updateClipSettings(
    String id, {
    required Duration start,
    required Duration end,
    required double volumePercent,
    required bool noiseCancellation,
  }) {
    final index = clips.indexWhere((c) => c.id == id);
    if (index == -1) return;
    clips[index] = clips[index].copyWith(
      trimStart: start,
      trimEnd: end,
      volumePercent: volumePercent,
      noiseCancellationEnabled: noiseCancellation,
    );
    notifyListeners();
  }

  Future<void> pickBackgroundAudio() async {
    final file = await _mediaService.pickAudioFile();
    if (file != null) {
      backgroundAudioPath = file.path;
      notifyListeners();
    }
  }

  void removeBackgroundAudio() {
    backgroundAudioPath = null;
    noiseCancellationEnabled = false;
    volumePercent = 100;
    notifyListeners();
  }

  void setNoiseCancellation(bool value) {
    noiseCancellationEnabled = value;
    notifyListeners();
  }

  void setVolumePercent(double value) {
    volumePercent = value;
    notifyListeners();
  }

  double get totalTrimmedSeconds => clips.fold(
        0.0,
        (sum, c) => sum + c.trimmedDuration.inMilliseconds / 1000.0,
      );

  /// Picks the shared output resolution for the whole project: the first
  /// clip's own aspect ratio (so the export keeps the ratio the video was
  /// shot in - portrait stays portrait, landscape stays landscape - instead
  /// of being forced into a fixed 16:9 frame), capped to a sane maximum
  /// dimension so encodes stay fast, with both sides forced even (required
  /// by yuv420p/H.264).
  ({int width, int height}) _resolveTargetResolution() {
    const maxDimension = 1920;
    var width = clips.first.sourceWidth;
    var height = clips.first.sourceHeight;

    if (width <= 0 || height <= 0) {
      width = 1280;
      height = 720;
    }

    if (width > maxDimension || height > maxDimension) {
      if (width >= height) {
        height = (height * maxDimension / width).round();
        width = maxDimension;
      } else {
        width = (width * maxDimension / height).round();
        height = maxDimension;
      }
    }

    if (width % 2 != 0) width -= 1;
    if (height % 2 != 0) height -= 1;
    return (width: width, height: height);
  }

  /// Runs the full trim -> merge -> mix background audio -> save pipeline,
  /// reporting weighted progress across every stage through
  /// [overallProgress]. Returns true on success.
  Future<bool> exportVideo() async {
    if (clips.isEmpty) {
      errorMessage = 'Add at least one video clip before exporting.';
      stage = ExportStage.error;
      notifyListeners();
      return false;
    }

    errorMessage = null;
    exportedFilePath = null;
    overallProgress = 0.0;

    // Relative weight of each stage within the overall progress bar.
    const trimWeight = 0.50;
    const mergeWeight = 0.15;
    const mixWeight = 0.25;
    const saveWeight = 0.10;

    try {
      final hasAccess = await _mediaService.requestGalleryAccess();
      if (!hasAccess) {
        errorMessage = 'Gallery access was not granted. Enable photo '
            'library access in system settings to save your video.';
        stage = ExportStage.error;
        notifyListeners();
        return false;
      }

      await _mediaService.clearWorkingDirectory();

      stage = ExportStage.trimming;
      notifyListeners();

      final target = _resolveTargetResolution();

      final trimmedPaths = <String>[];
      for (var i = 0; i < clips.length; i++) {
        final clip = clips[i];
        final outputPath = await _mediaService.newTempFilePath('mp4');
        await _ffmpegService.trimAndNormalize(
          inputPath: clip.sourcePath,
          start: clip.trimStart,
          end: clip.trimEnd,
          targetWidth: target.width,
          targetHeight: target.height,
          outputPath: outputPath,
          noiseCancellation: clip.noiseCancellationEnabled,
          volumePercent: clip.volumePercent,
          onProgress: (p) {
            final clipShare = 1 / clips.length;
            final completedShare = i / clips.length;
            overallProgress = (completedShare + p * clipShare) * trimWeight;
            notifyListeners();
          },
        );
        trimmedPaths.add(outputPath);
      }

      stage = ExportStage.merging;
      notifyListeners();

      String mergedPath;
      if (trimmedPaths.length == 1) {
        mergedPath = trimmedPaths.first;
        overallProgress = trimWeight + mergeWeight;
        notifyListeners();
      } else {
        mergedPath = await _mediaService.newTempFilePath('mp4');
        final listFilePath = await _mediaService.newTempFilePath('txt');
        await _ffmpegService.concatClips(
          clipPaths: trimmedPaths,
          outputPath: mergedPath,
          listFilePath: listFilePath,
          onProgress: (p) {
            overallProgress = trimWeight + p * mergeWeight;
            notifyListeners();
          },
        );
      }

      var finalPath = mergedPath;

      if (backgroundAudioPath != null) {
        stage = ExportStage.mixingAudio;
        notifyListeners();
        final mixedPath = await _mediaService.newTempFilePath('mp4');
        await _ffmpegService.mixBackgroundAudio(
          videoPath: mergedPath,
          audioPath: backgroundAudioPath!,
          noiseCancellation: noiseCancellationEnabled,
          volumePercent: volumePercent,
          outputPath: mixedPath,
          onProgress: (p) {
            overallProgress = trimWeight + mergeWeight + p * mixWeight;
            notifyListeners();
          },
        );
        finalPath = mixedPath;
      } else {
        overallProgress = trimWeight + mergeWeight + mixWeight;
        notifyListeners();
      }

      stage = ExportStage.savingToGallery;
      notifyListeners();

      await _mediaService.saveVideoToGallery(finalPath);
      exportedFilePath = finalPath;
      overallProgress = trimWeight + mergeWeight + mixWeight + saveWeight;

      stage = ExportStage.done;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = e.toString();
      stage = ExportStage.error;
      notifyListeners();
      return false;
    }
  }

  void resetExportState() {
    stage = ExportStage.idle;
    overallProgress = 0.0;
    errorMessage = null;
    exportedFilePath = null;
    notifyListeners();
  }
}
