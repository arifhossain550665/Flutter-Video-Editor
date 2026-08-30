import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Handles all interaction with the file system, the system file/media
/// pickers and the device photo gallery.
class MediaService {
  /// Opens the system file picker and lets the user select one or more
  /// video files.
  Future<List<File>> pickVideoFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result == null) return [];
    return result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();
  }

  /// Opens the system file picker and lets the user select a single audio
  /// file to use as background music.
  Future<File?> pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;
    return File(path);
  }

  /// Uses the video_player plugin to quickly probe the duration of a video
  /// file right after it has been imported.
  Future<Duration> probeVideoDuration(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      return controller.value.duration;
    } finally {
      await controller.dispose();
    }
  }

  /// Returns (and creates if necessary) the scratch directory used to store
  /// intermediate files produced while editing (trimmed clips, concat lists,
  /// merged output, etc).
  Future<Directory> getWorkingDirectory() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/video_editor_work');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Generates a unique path inside the working directory for a new
  /// intermediate file with the given [extension] (no leading dot).
  Future<String> newTempFilePath(String extension) async {
    final dir = await getWorkingDirectory();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '${dir.path}/clip_$timestamp.$extension';
  }

  /// Deletes every file currently sitting in the working directory. Called
  /// at the start of a fresh export so old intermediate files never pile up.
  Future<void> clearWorkingDirectory() async {
    final dir = await getWorkingDirectory();
    if (!await dir.exists()) return;
    for (final entity in dir.listSync()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {
        // Best effort cleanup - ignore files that are locked or already gone.
      }
    }
  }

  /// Ensures the app has permission to write to the photo library / gallery,
  /// requesting it from the user if necessary.
  Future<bool> requestGalleryAccess() async {
    final hasAccess = await Gal.hasAccess();
    if (hasAccess) return true;
    return Gal.requestAccess();
  }

  /// Saves the finished video at [path] into the device photo gallery inside
  /// a dedicated "Video Editor" album.
  Future<void> saveVideoToGallery(String path) async {
    await Gal.putVideo(path, album: 'Video Editor');
  }
}
