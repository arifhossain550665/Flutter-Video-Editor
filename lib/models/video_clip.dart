/// Represents a single imported video clip together with the trim range
/// the user has chosen for it.
class VideoClip {
  final String id;
  final String sourcePath;
  final Duration sourceDuration;
  final Duration trimStart;
  final Duration trimEnd;

  VideoClip({
    required this.id,
    required this.sourcePath,
    required this.sourceDuration,
    Duration? trimStart,
    Duration? trimEnd,
  })  : trimStart = trimStart ?? Duration.zero,
        trimEnd = trimEnd ?? sourceDuration;

  Duration get trimmedDuration => trimEnd - trimStart;

  String get fileName => sourcePath.split('/').last;

  VideoClip copyWith({Duration? trimStart, Duration? trimEnd}) {
    return VideoClip(
      id: id,
      sourcePath: sourcePath,
      sourceDuration: sourceDuration,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
    );
  }
}
