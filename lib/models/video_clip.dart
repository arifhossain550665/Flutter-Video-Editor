class VideoClip {
  final String id;
  final String path;
  final double sourceWidth;
  final double sourceHeight;
  final double volumePercent;
  final bool noiseCancellationEnabled;

  VideoClip({
    required this.id,
    required this.path,
    this.sourceWidth = 1280.0,
    this.sourceHeight = 720.0,
    this.volumePercent = 100.0,
    this.noiseCancellationEnabled = false,
  });

  VideoClip copyWith({
    String? id,
    String? path,
    double? sourceWidth,
    double? sourceHeight,
    double? volumePercent,
    bool? noiseCancellationEnabled,
  }) {
    return VideoClip(
      id: id ?? this.id,
      path: path ?? this.path,
      sourceWidth: sourceWidth ?? this.sourceWidth,
      sourceHeight: sourceHeight ?? this.sourceHeight,
      volumePercent: volumePercent ?? this.volumePercent,
      noiseCancellationEnabled: noiseCancellationEnabled ?? this.noiseCancellationEnabled,
    );
  }
}
