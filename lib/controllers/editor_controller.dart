import 'package:flutter/foundation.dart';

import '../models/project.dart';
import '../models/video_clip.dart';
import '../services/ffmpeg_service.dart';
import '../services/media_service.dart';
import '../services/project_service.dart';

enum ExportStage {
  idle,
  trimming,
  merging,
  mixingAudio,
  savingToGallery,
  done,
  error,
}

/// Single source of truth for the editor screen. Wraps one loaded [Project]
/// at a time: its clips, its background-audio/noise/volume settings, and
/// the state of an in-progress export. Every meaningful edit is persisted
/// to disk through ProjectService immediately, so a project always reopens
/// exactly where the user left it - CapCut-style.
class EditorController extends ChangeNotifier {
  final FFmpegService _ffmpegService = FFmpegService();
  final MediaService _mediaService = MediaService();
  final ProjectService _projectService = ProjectService();

  Project? _project;
  Project? get project => _project;
  bool get hasProject => _project != null;

  List<VideoClip> get clips => _project?.clips ?? const [];
  String? get backgroundAudioPath => _project?.backgroundAudioPath;
  Duration get backgroundAudioDuration =>
      _project?.backgroundAudioDuration ?? Duration.zero;
  Duration get backgroundAudioTrimStart =>
      _project?.backgroundAudioTrimStart ?? Duration.zero;
  Duration get backgroundAudioTrimEnd =>
      _project?.backgroundAudioTrimEnd ?? Duration.zero;
  Duration get backgroundAudioOffset =>
      _project?.backgroundAudioOffset ?? Duration.zero;
  bool get noiseCancellationEnabled =>
      _project?.noiseCancellationEnabled ?? false;
  double get volumePercent => _project?.volumePercent ?? 100;

  ExportStage stage = ExportStage.idle;
  double overallProgress = 0.0;
  String? errorMessage;
  String? exportedFilePath;

  /// Loads a project (freshly created or opened from the projects grid)
  /// as the one currently being edited, resetting any leftover export
  /// state from a previous project.
  Future<void> loadProject(Project project) async {
    _project = project;
    stage = ExportStage.idle;
    overallProgress = 0.0;
    errorMessage = null;
    exportedFilePath = null;
    notifyListeners();
  }

  /// Unloads the current project without touching its saved file - used
  /// when a just-created draft is abandoned (e.g. the user cancels the
  /// video picker) before anything worth keeping was added.
  void clearProject() {
    _project = null;
    notifyListeners();
  }

  /// Writes the current project's state to disk right now. Editor screen
  /// widgets call this directly for interactions that shouldn't save on
  /// every intermediate tick (e.g. a slider's onChangeEnd).
  Future<void> persistProject() async {
    if (_project == null) return;
    await _projectService.saveProject(_project!);
  }

  /// Opens the video picker, probes each selected file's duration and
  /// dimensions, copies it into the project's own permanent media folder,
  /// and adds it to the clip list. Generates the project's cover thumbnail
  /// from the first clip the first time this is called.
  Future<void> importVideos() async {
    if (_project == null) return;
    final files = await _mediaService.pickVideoFiles();
    if (files.isEmpty) return;

    for (final file in files) {
      final metadata = await _mediaService.probeVideoMetadata(file.path);
      final persistedPath =
          await _projectService.importMedia(_project!.id, file);
      _project!.clips.add(
        VideoClip(
          id: '${DateTime.now().microsecondsSinceEpoch}_${_project!.clips.length}',
          sourcePath: persistedPath,
          sourceDuration: metadata.duration,
          sourceWidth: metadata.width > 0 ? metadata.width : 1280,
          sourceHeight: metadata.height > 0 ? metadata.height : 720,
        ),
      );
    }

    if (_project!.thumbnailPath == null && _project!.clips.isNotEmpty) {
      try {
        final dir = await _projectService.projectDir(_project!.id);
        final firstClip = _project!.clips.first;
        final thumbs = await _ffmpegService.generateThumbnails(
          inputPath: firstClip.sourcePath,
          totalDuration: firstClip.sourceDuration,
          outputDir: dir.path,
          count: 1,
        );
        if (thumbs.isNotEmpty) {
          _project!.thumbnailPath = thumbs.first;
        }
      } catch (_) {
        // Best effort - a project without a thumbnail just shows a
        // placeholder icon in the projects grid.
      }
    }

    await persistProject();
    notifyListeners();
  }

  void removeClip(String id) {
    if (_project == null) return;
    _project!.clips.removeWhere((c) => c.id == id);
    persistProject();
    notifyListeners();
  }

  void reorderClip(int oldIndex, int newIndex) {
    if (_project == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final clip = _project!.clips.removeAt(oldIndex);
    _project!.clips.insert(newIndex, clip);
    persistProject();
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
    if (_project == null) return;
    final index = _project!.clips.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _project!.clips[index] = _project!.clips[index].copyWith(
      trimStart: start,
      trimEnd: end,
      volumePercent: volumePercent,
      noiseCancellationEnabled: noiseCancellation,
    );
    persistProject();
    notifyListeners();
  }

  /// Opens the file picker (storage, not a music-app chooser), copies the
  /// chosen audio file into the project's own media folder, probes its
  /// duration, and places it on the timeline starting at 0 with a default
  /// trim that fills (but never exceeds) the current project length.
  Future<void> pickBackgroundAudio() async {
    if (_project == null) return;
    final file = await _mediaService.pickAudioFile();
    if (file == null) return;
    final persistedPath =
        await _projectService.importMedia(_project!.id, file);
    final duration = await _ffmpegService.getDuration(persistedPath);
    final projectDuration = _project!.totalDuration;

    _project!.backgroundAudioPath = persistedPath;
    _project!.backgroundAudioDuration = duration;
    _project!.backgroundAudioTrimStart = Duration.zero;
    _project!.backgroundAudioTrimEnd =
        (projectDuration == Duration.zero || duration <= projectDuration)
            ? duration
            : projectDuration;
    _project!.backgroundAudioOffset = Duration.zero;

    await persistProject();
    notifyListeners();
  }

  void removeBackgroundAudio() {
    if (_project == null) return;
    _project!.backgroundAudioPath = null;
    _project!.backgroundAudioDuration = Duration.zero;
    _project!.backgroundAudioTrimStart = Duration.zero;
    _project!.backgroundAudioTrimEnd = Duration.zero;
    _project!.backgroundAudioOffset = Duration.zero;
    _project!.noiseCancellationEnabled = false;
    _project!.volumePercent = 100;
    persistProject();
    notifyListeners();
  }

  /// Moves the background audio segment to start [value] into the video
  /// timeline, without changing which part of the source file plays or
  /// how long the segment is (a "slide" edit).
  void setBackgroundAudioOffset(Duration value) {
    if (_project == null) return;
    _project!.backgroundAudioOffset = value;
    notifyListeners();
  }

  /// Adjusts the in-point of the background audio segment (dragging the
  /// left edge on the timeline).
  void setBackgroundAudioTrimStart(Duration value) {
    if (_project == null) return;
    _project!.backgroundAudioTrimStart = value;
    notifyListeners();
  }

  /// Adjusts the out-point of the background audio segment (dragging the
  /// right edge on the timeline).
  void setBackgroundAudioTrimEnd(Duration value) {
    if (_project == null) return;
    _project!.backgroundAudioTrimEnd = value;
    notifyListeners();
  }

  void setNoiseCancellation(bool value) {
    if (_project == null) return;
    _project!.noiseCancellationEnabled = value;
    persistProject();
    notifyListeners();
  }

  /// Updates the live slider value without writing to disk on every tick.
  /// Call [persistProject] (e.g. from the slider's onChangeEnd) once the
  /// user finishes dragging.
  void setVolumePercent(double value) {
    if (_project == null) return;
    _project!.volumePercent = value;
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
    if (_project == null || clips.isEmpty) {
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
          audioTrimStart: backgroundAudioTrimStart,
          audioTrimEnd: backgroundAudioTrimEnd,
          timelineOffset: backgroundAudioOffset,
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
