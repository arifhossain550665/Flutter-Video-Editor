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
/// normalizing, thumbnail extraction, concatenating, and mixing/boosting/
/// denoising audio.
class FFmpegService {
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

  /// Builds the audio filter chain shared by both trimAndNormalize and
  /// mixBackgroundAudio: an optional highpass (removes low-frequency
  /// rumble/hum, which is most of what people perceive as "background
  /// noise") followed by an FFT-based denoiser, then an optional volume
  /// boost with a limiter so the boost never hard-clips. Returns an empty
  /// list if neither noise cancellation nor a volume change is requested.
  List<String> _audioFilters({
    required bool noiseCancellation,
    required double volumePercent,
    String? denoiseModelPath,
  }) {
    final filters = <String>[];
    if (noiseCancellation) {
      filters.add('highpass=f=100');
      if (denoiseModelPath != null) {
        // RNNoise: a neural network trained to separate speech from noise,
        // so - unlike a plain spectral filter - it also works on dynamic,
        // non-steady noise (crowd chatter, wind, traffic, keyboard
        // clicks), not just constant hiss/hum. mix=0.85 keeps it strong
        // without fully flattening the voice.
        final escapedPath = denoiseModelPath.replaceAll("'", r"'\''");
        filters.add("arnndn=m='$escapedPath':mix=0.85");
      } else {
        // Fallback when no trained model is bundled: two different
        // classical DSP denoisers stacked together. Effective on steady
        // hiss/hum/drone; cannot reliably separate speech from dynamic,
        // non-steady noise the way a trained model can.
        filters.add('anlmdn=s=0.001');
        filters.add('afftdn=nf=-45:nr=25:nt=w');
        filters.add('afftdn=nf=-40:nr=20:nt=w');
      }
    }
    final multiplier = (volumePercent / 100.0).clamp(0.1, 3.0).toDouble();
    if (multiplier != 1.0) {
      filters.add('volume=$multiplier');
      filters.add('alimiter=limit=0.95');
    }
    return filters;
  }

  /// Trims [inputPath] to the range [start, end], scales/pads it to
  /// [targetWidth]x[targetHeight] (the shared project resolution the caller
  /// decides once for the whole export - normally the first imported clip's
  /// own aspect ratio, so the exported video keeps that ratio instead of
  /// being forced into a fixed 16:9 frame), optionally denoises and/or
  /// boosts that clip's own audio track, and writes the result to
  /// [outputPath].
  Future<void> trimAndNormalize({
    required String inputPath,
    required Duration start,
    required Duration end,
    required int targetWidth,
    required int targetHeight,
    required String outputPath,
    bool noiseCancellation = false,
    double volumePercent = 100,
    String? denoiseModelPath,
    StageProgressCallback? onProgress,
  }) async {
    final duration = end - start;
    if (duration <= Duration.zero) {
      throw FFmpegProcessingException('Trim end must be after trim start.');
    }

    final hasAudio = await hasAudioStream(inputPath);

    final videoFilter =
        'scale=$targetWidth:$targetHeight:force_original_aspect_ratio=decrease,'
        'pad=$targetWidth:$targetHeight:(ow-iw)/2:(oh-ih)/2,setsar=1,'
        'fps=$_targetFps';

    String audioArgs;
    if (hasAudio) {
      final filters = _audioFilters(
        noiseCancellation: noiseCancellation,
        volumePercent: volumePercent,
        denoiseModelPath: denoiseModelPath,
      );
      final audioFilterArg = filters.isEmpty ? '' : '-af "${filters.join(',')}" ';
      audioArgs = '$audioFilterArg-c:a aac -b:a 192k -ar 44100 -ac 2';
    } else {
      audioArgs = '-an';
    }

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

  /// Mixes a background audio track into [videoPath], CapCut-style: only
  /// the [audioTrimStart]..[audioTrimEnd] slice of the source audio file is
  /// used, and that slice starts playing [timelineOffset] into the video
  /// instead of always at time zero. The output is always exactly
  /// [videoPath]'s own duration long - the audio segment is silence-padded
  /// or cut to fit, so placing a short or offset clip never shortens or
  /// lengthens the video itself.
  Future<void> mixBackgroundAudio({
    required String videoPath,
    required String audioPath,
    required Duration audioTrimStart,
    required Duration audioTrimEnd,
    required Duration timelineOffset,
    required bool noiseCancellation,
    required double volumePercent,
    required String outputPath,
    String? denoiseModelPath,
    StageProgressCallback? onProgress,
  }) async {
    final videoDuration = await getDuration(videoPath);
    final videoHasAudio = await hasAudioStream(videoPath);

    final trimStartSec = audioTrimStart.inMilliseconds / 1000.0;
    final trimEndSec = audioTrimEnd.inMilliseconds / 1000.0;
    final offsetMs = timelineOffset.inMilliseconds;

    final chain = StringBuffer(
        'atrim=start=$trimStartSec:end=$trimEndSec,asetpts=PTS-STARTPTS');
    if (offsetMs > 0) {
      // all=1 applies the delay to every channel regardless of whether the
      // source is mono or stereo.
      chain.write(',adelay=$offsetMs:all=1');
    }
    for (final f in _audioFilters(
      noiseCancellation: noiseCancellation,
      volumePercent: volumePercent,
      denoiseModelPath: denoiseModelPath,
    )) {
      chain.write(',$f');
    }
    // Pad with silence so the segment covers the rest of the video after
    // it ends - the explicit -t on the output command below then cuts
    // everything to exactly the video's length.
    chain.write(',apad');
    final bgChain = chain.toString();

    final String filterComplex;
    if (videoHasAudio) {
      filterComplex = '[1:a]$bgChain[bg];'
          '[0:a][bg]amix=inputs=2:duration=first:dropout_transition=2,'
          'alimiter=limit=0.95[aout]';
    } else {
      filterComplex = '[1:a]$bgChain[aout]';
    }

    final videoDurationSec = videoDuration.inMilliseconds / 1000.0;

    final command = '-y -i "$videoPath" -i "$audioPath" '
        '-filter_complex "$filterComplex" '
        '-map 0:v -map "[aout]" '
        '-c:v copy -c:a aac -b:a 192k -t $videoDurationSec '
        '-movflags +faststart "$outputPath"';

    await _runCommand(
      command,
      totalDuration: videoDuration,
      onProgress: onProgress,
      failureMessage: 'Failed to mix background audio.',
    );
  }

  /// Extracts [count] evenly spaced frame thumbnails across [totalDuration]
  /// from [inputPath] into [outputDir], scaled down to filmstrip size, for
  /// the CapCut-style trim timeline (and for a single-frame project cover
  /// thumbnail when [count] is 1). Returns the sorted list of thumbnail
  /// file paths (empty list if generation fails - callers fall back to a
  /// placeholder instead of blocking on it).
  Future<List<String>> generateThumbnails({
    required String inputPath,
    required Duration totalDuration,
    required String outputDir,
    int count = 12,
  }) async {
    final totalSeconds = totalDuration.inMilliseconds / 1000.0;
    if (totalSeconds <= 0) return [];

    final interval = (totalSeconds / count).clamp(0.1, double.infinity);
    final pattern = '$outputDir/thumb_%03d.jpg';

    final command = '-y -i "$inputPath" '
        '-vf "fps=1/$interval,scale=180:-2" '
        '-vsync vfr -qscale:v 4 '
        '"$pattern"';

    final completer = Completer<void>();
    await FFmpegKit.executeAsync(
      command,
      (session) async {
        if (completer.isCompleted) return;
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          completer.complete();
        } else {
          completer.completeError(
            FFmpegProcessingException('Failed to generate thumbnails for $inputPath'),
          );
        }
      },
      (Log log) {},
      (Statistics statistics) {},
    );

    try {
      await completer.future;
    } catch (_) {
      return [];
    }

    final dir = Directory(outputDir);
    if (!await dir.exists()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('thumb_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files.map((f) => f.path).toList();
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
