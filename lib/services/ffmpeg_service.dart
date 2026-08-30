import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/log.dart';
import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:ffmpeg_kit_flutter_new/media_information_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:ffmpeg_kit_flutter_new/stream_information.dart';

/// Reports progress for a single FFmpeg processing stage, from 0.0 to 1.0.
typedef StageProgressCallback = void Function(double stageProgress);

/// Thrown whenever an FFmpeg session fails or media information can't be
/// read. Carries the raw FFmpeg console output for debugging.
class FFmpegProcessingException implements Exception {
  final String message;
  final String? logs;
  FFmpegProcessingException(this.message, {this.logs});

  @override
  String toString() =>
      'FFmpegProcessingException: $message${logs != null ? '\n$logs' : ''}';
}

/// Wraps every FFmpeg / FFprobe operation the editor needs: trimming,
/// normalizing, concatenating, and mixing/boosting/denoising audio.
class FFmpegService {
  // All trimmed clips are normalized to this resolution/frame rate before
  // concatenation so the concat demuxer can safely stream-copy them together
  // even if the source clips came from different cameras/apps.
  static const int _targetWidth = 1280;
  static const int _targetHeight = 720;
  static const int _targetFps = 30;

  /// Reads the duration of the media file at [path].
  Future<Duration> getDuration(String path) async {
    final MediaInformation? information = await _probe(path);
    if (information == null) {
      throw FFmpegProcessingException('Unable to read media information for $path');
    }
    final durationString = information.getDuration();
    if (durationString == null) return Duration.zero;
    final seconds = double.tryParse(durationString) ?? 0.0;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// Returns true if the media file at [path] contains at least one audio
  /// stream.
  Future<bool> hasAudioStream(String path) async {
    final MediaInformation? information = await _probe(path);
    if (information == null) return false;
    final List<StreamInformation> streams = information.getStreams();
    for (final stream in streams) {
      if (stream.getType() == 'audio') return true;
    }
    return false;
  }

  Future<MediaInformation?> _probe(String path) async {
    final MediaInformationSession session =
        await FFprobeKit.getMediaInformation(path);
    return session.getMediaInformation();
  }

  /// Trims [inputPath] to the range [start, end], scales/pads it to a
  /// standard resolution and frame rate, and writes the result to
  /// [outputPath]. Normalizing here is what allows [concatClips] to safely
  /// stream-copy every clip together afterwards.
  Future<void> trimAndNormalize({
    required String inputPath,
    required Duration start,
    required Duration end,
    required String outputPath,
    StageProgressCallback? onProgress,
  }) async {
    final duration = end - start;
    if (duration <= Duration.zero) {
      throw FFmpegProcessingException('Trim end must be after trim start.');
    }

    final hasAudio = await hasAudioStream(inputPath);

    final videoFilter =
        'scale=$_targetWidth:$_targetHeight:force_original_aspect_ratio=decrease,'
        'pad=$_targetWidth:$_targetHeight:(ow-iw)/2:(oh-ih)/2,setsar=1,'
        'fps=$_targetFps';

    final audioArgs = hasAudio ? '-c:a aac -b:a 192k -ar 44100 -ac 2' : '-an';

    final command = '-y '
        '-ss ${_formatTimestamp(start)} '
        '-i "$inputPath" '
        '-t ${_formatTimestamp(duration)} '
        '-vf "$videoFilter" '
        '-c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p '
        '$audioArgs '
        '-movflags +faststart '
        '"$outputPath"';

    await _runCommand(
      command,
      totalDuration: duration,
      onProgress: onProgress,
      failureMessage: 'Failed to trim clip: $inputPath',
    );
  }

  /// Concatenates a list of already-normalized clips (same codec,
  /// resolution and frame rate) into a single file using the concat
  /// demuxer, which is fast because it can stream-copy instead of
  /// re-encoding.
  Future<void> concatClips({
    required List<String> clipPaths,
    required String outputPath,
    required String listFilePath,
    StageProgressCallback? onProgress,
  }) async {
    if (clipPaths.isEmpty) {
      throw FFmpegProcessingException('No clips to concatenate.');
    }

    final listFile = File(listFilePath);
    final buffer = StringBuffer();
    for (final path in clipPaths) {
      final escaped = path.replaceAll("'", r"'\''");
      buffer.writeln("file '$escaped'");
    }
    await listFile.writeAsString(buffer.toString());

    var totalDuration = Duration.zero;
    for (final path in clipPaths) {
      totalDuration += await getDuration(path);
    }

    final command = '-y -f concat -safe 0 -i "$listFilePath" '
        '-c copy -movflags +faststart "$outputPath"';

    await _runCommand(
      command,
      totalDuration: totalDuration,
      onProgress: onProgress,
      failureMessage: 'Failed to merge clips together.',
    );
  }

  /// Mixes a background audio track into [videoPath]. When [noiseCancellation]
  /// is true, an adaptive FFT noise-reduction filter (afftdn) is applied to
  /// the background track first. [volumePercent] (100-300) boosts the
  /// background track's loudness, with a limiter applied afterwards so the
  /// boosted audio never hard-clips. If the source video already has its own
  /// audio track, the two tracks are mixed together; otherwise the
  /// background track becomes the video's only audio.
  Future<void> mixBackgroundAudio({
    required String videoPath,
    required String audioPath,
    required bool noiseCancellation,
    required double volumePercent,
    required String outputPath,
    StageProgressCallback? onProgress,
  }) async {
    final videoDuration = await getDuration(videoPath);
    final videoHasAudio = await hasAudioStream(videoPath);
    final volumeMultiplier = (volumePercent / 100.0).clamp(0.1, 3.0);

    final noiseFilter = noiseCancellation ? 'afftdn=nf=-25,' : '';

    final String filterComplex;
    if (videoHasAudio) {
      filterComplex = '[1:a]${noiseFilter}volume=$volumeMultiplier[bg];'
          '[0:a][bg]amix=inputs=2:duration=first:dropout_transition=2,'
          'alimiter=limit=0.95[aout]';
    } else {
      filterComplex =
          '[1:a]${noiseFilter}volume=$volumeMultiplier,alimiter=limit=0.95[aout]';
    }

    final command = '-y -i "$videoPath" -i "$audioPath" '
        '-filter_complex "$filterComplex" '
        '-map 0:v -map "[aout]" '
        '-c:v copy -c:a aac -b:a 192k -shortest '
        '-movflags +faststart "$outputPath"';

    await _runCommand(
      command,
      totalDuration: videoDuration,
      onProgress: onProgress,
      failureMessage: 'Failed to mix background audio.',
    );
  }

  Future<void> _runCommand(
    String command, {
    required Duration totalDuration,
    StageProgressCallback? onProgress,
    required String failureMessage,
  }) async {
    final completer = Completer<void>();
    final logs = StringBuffer();
    final totalMs = totalDuration.inMilliseconds <= 0
        ? 1
        : totalDuration.inMilliseconds;

    await FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          onProgress?.call(1.0);
          if (!completer.isCompleted) completer.complete();
        } else if (ReturnCode.isCancel(returnCode)) {
          if (!completer.isCompleted) {
            completer.completeError(
              FFmpegProcessingException('$failureMessage (cancelled)',
                  logs: logs.toString()),
            );
          }
        } else {
          if (!completer.isCompleted) {
            completer.completeError(
              FFmpegProcessingException(failureMessage, logs: logs.toString()),
            );
          }
        }
      },
      (Log log) {
        logs.writeln(log.getMessage());
      },
      (Statistics statistics) {
        final processedMs = statistics.getTime();
        if (processedMs > 0 && onProgress != null) {
          final progress = (processedMs / totalMs).clamp(0.0, 1.0);
          onProgress(progress);
        }
      },
    );

    return completer.future;
  }

  String _formatTimestamp(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final millis = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds.$millis';
  }
}
