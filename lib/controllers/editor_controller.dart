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
/// clips, the chosen audio/noise/volume settings, and the state of an
/// in-progress export.
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

  /// Opens the video picker, probes each selected file's duration, and adds
  /// it to the clip list.
  Future<void> importVideos() async {
    final files = await _mediaService.pickVideoFiles();
    for (final file in files) {
      final duration = await _mediaService.probeVideoDuration(file.path);
      clips.add(
        VideoClip(
          id: '${DateTime.now().microsecondsSinceEpoch}_${clips.length}',
          sourcePath: file.path,
          sourceDuration: duration,
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

  void updateClipTrim(String id, Duration start, Duration end) {
    final index = clips.indexWhere((c) => c.id == id);
    if (index == -1) return;
    clips[index] = clips[index].copyWith(trimStart: start, trimEnd: end);
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

  /// Runs the full trim -> merge -> mix audio -> save pipeline, reporting
  /// weighted progress across every stage through [overallProgress].
  /// Returns true on success.
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

      final trimmedPaths = <String>[];
      for (var i = 0; i < clips.length; i++) {
        final clip = clips[i];
        final outputPath = await _mediaService.newTempFilePath('mp4');
        await _ffmpegService.trimAndNormalize(
          inputPath: clip.sourcePath,
          start: clip.trimStart,
          end: clip.trimEnd,
          outputPath: outputPath,
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
