import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Duration + pixel dimensions of an imported video, probed once right
/// after import so the editor can plan trimming/normalization (and pick a
/// project aspect ratio) without re-opening the file later.
class VideoMetadata {
  final Duration duration;
  final int width;
  final int height;

  const VideoMetadata({
    required this.duration,
    required this.width,
    required this.height,
  });
}

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
  /// file to use as background music. Uses FileType.custom with an
  /// explicit extension list (instead of FileType.audio) so the OS opens a
  /// plain file/storage browser - on Android, FileType.audio can route
  /// through a "choose an audio app" chooser instead of letting the user
  /// browse files directly, which is not what we want here.
  Future<File?> pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3',
        'wav',
        'm4a',
        'aac',
        'ogg',
        'flac',
        'wma',
      ],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;
    return File(path);
  }

  /// Probes a freshly imported video's duration and display size (already
  /// rotation-corrected by the platform video decoder) in one pass, so the
  /// editor knows its true aspect ratio for the "keep original ratio"
  /// export behavior.
  Future<VideoMetadata> probeVideoMetadata(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      final size = controller.value.size;
      return VideoMetadata(
        duration: controller.value.duration,
        width: size.width.round(),
        height: size.height.round(),
      );
    } finally {
      await controller.dispose();
    }
  }

  /// Returns (and creates if necessary) the scratch directory used to store
  /// short-lived intermediate files produced while exporting (trimmed
  /// clips, concat lists, merged output, etc). This is separate from
  /// project storage - project media is copied into its own permanent
  /// folder by ProjectService and is never cleared by this method.
  Future<Directory> getWorkingDirectory() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/video_editor_work');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Returns (and creates if necessary) a named subdirectory inside the
  /// working directory - used to keep one clip's filmstrip thumbnails
  /// separate from another's.
  Future<Directory> newTempSubdirectory(String name) async {
    final base = await getWorkingDirectory();
    final dir = Directory('${base.path}/$name');
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
