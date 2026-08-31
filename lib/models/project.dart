import 'video_clip.dart';

/// A saved editing project: its clips (with their trim/audio settings), an
/// optional background audio track, and metadata used to show it in the
/// projects grid. Persisted to disk by ProjectService as project.json
/// inside the project's own folder.
class Project {
  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  String? backgroundAudioPath;
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
    this.noiseCancellationEnabled = false,
    this.volumePercent = 100,
    this.thumbnailPath,
    List<VideoClip>? clips,
  }) : clips = clips ?? [];

  Duration get totalDuration =>
      clips.fold(Duration.zero, (sum, c) => sum + c.trimmedDuration);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'backgroundAudioPath': backgroundAudioPath,
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
