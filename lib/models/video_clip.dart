/// Represents a single imported video clip together with the trim range
/// and per-clip audio settings (noise cancellation + volume boost applied
/// to that clip's own original audio track) the user has chosen for it.
class VideoClip {
  final String id;
  final String sourcePath;
  final Duration sourceDuration;
  final int sourceWidth;
  final int sourceHeight;
  final Duration trimStart;
  final Duration trimEnd;
  final double volumePercent;
  final bool noiseCancellationEnabled;

  VideoClip({
    required this.id,
    required this.sourcePath,
    required this.sourceDuration,
    required this.sourceWidth,
    required this.sourceHeight,
    Duration? trimStart,
    Duration? trimEnd,
    this.volumePercent = 100,
    this.noiseCancellationEnabled = false,
  })  : trimStart = trimStart ?? Duration.zero,
        trimEnd = trimEnd ?? sourceDuration;

  Duration get trimmedDuration => trimEnd - trimStart;

  String get fileName => sourcePath.split('/').last;

  VideoClip copyWith({
    Duration? trimStart,
    Duration? trimEnd,
    double? volumePercent,
    bool? noiseCancellationEnabled,
  }) {
    return VideoClip(
      id: id,
      sourcePath: sourcePath,
      sourceDuration: sourceDuration,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      volumePercent: volumePercent ?? this.volumePercent,
      noiseCancellationEnabled:
          noiseCancellationEnabled ?? this.noiseCancellationEnabled,
    );
  }
}
