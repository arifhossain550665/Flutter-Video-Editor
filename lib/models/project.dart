import 'video_clip.dart';

/// A saved editing project: its clips (with their trim/audio settings), an
/// optional background audio track (with its own trim range and where it
/// sits on the project timeline), and metadata used to show it in the
/// projects grid. Persisted to disk by ProjectService as project.json
/// inside the project's own folder.
class Project {
  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;

  String? backgroundAudioPath;
  Duration backgroundAudioDuration;
  Duration backgroundAudioTrimStart;
  Duration backgroundAudioTrimEnd;

  /// Where on the project's video timeline the trimmed audio segment
  /// starts playing (e.g. 5s in means the song starts 5 seconds into the
  /// video instead of at the very beginning).
  Duration backgroundAudioOffset;

  bool noiseCancellationEnabled;
  double volumePercent;
  String? thumbnailPath;
  final List<VideoClip> clips;

  Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.backgroundAudioPath,
    this.backgroundAudioDuration = Duration.zero,
    this.backgroundAudioTrimStart = Duration.zero,
    this.backgroundAudioTrimEnd = Duration.zero,
    this.backgroundAudioOffset = Duration.zero,
    this.noiseCancellationEnabled = false,
    this.volumePercent = 100,
    this.thumbnailPath,
    List<VideoClip>? clips,
  }) : clips = clips ?? [];

  Duration get totalDuration =>
      clips.fold(Duration.zero, (sum, c) => sum + c.trimmedDuration);

  Duration get backgroundAudioSegmentLength =>
      backgroundAudioTrimEnd - backgroundAudioTrimStart;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'backgroundAudioPath': backgroundAudioPath,
        'backgroundAudioDurationMs': backgroundAudioDuration.inMilliseconds,
        'backgroundAudioTrimStartMs':
            backgroundAudioTrimStart.inMilliseconds,
        'backgroundAudioTrimEndMs': backgroundAudioTrimEnd.inMilliseconds,
        'backgroundAudioOffsetMs': backgroundAudioOffset.inMilliseconds,
        'noiseCancellationEnabled': noiseCancellationEnabled,
        'volumePercent': volumePercent,
        'thumbnailPath': thumbnailPath,
        'clips': clips.map((c) => c.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      backgroundAudioPath: json['backgroundAudioPath'] as String?,
      backgroundAudioDuration: Duration(
          milliseconds: json['backgroundAudioDurationMs'] as int? ?? 0),
      backgroundAudioTrimStart: Duration(
          milliseconds: json['backgroundAudioTrimStartMs'] as int? ?? 0),
      backgroundAudioTrimEnd: Duration(
          milliseconds: json['backgroundAudioTrimEndMs'] as int? ?? 0),
      backgroundAudioOffset: Duration(
          milliseconds: json['backgroundAudioOffsetMs'] as int? ?? 0),
      noiseCancellationEnabled:
          json['noiseCancellationEnabled'] as bool? ?? false,
      volumePercent: (json['volumePercent'] as num?)?.toDouble() ?? 100,
      thumbnailPath: json['thumbnailPath'] as String?,
      clips: (json['clips'] as List<dynamic>? ?? [])
          .map((e) => VideoClip.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
