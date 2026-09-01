import 'package:flutter/material.dart';

/// CapCut-style draggable/trimmable background-audio segment, drawn on the
/// project's timeline (scaled to [totalProjectDuration]).
///
/// - Dragging the middle of the bar *slides* the segment: it moves where
///   on the video timeline the audio starts playing, without changing
///   which part of the source file is used.
/// - Dragging the left edge trims the segment's in-point: the segment's
///   end stays anchored in place while its start (both on the timeline and
///   within the source file) moves.
/// - Dragging the right edge trims the segment's out-point: the segment's
///   start stays anchored while its end moves, changing how much of the
///   source file plays.
class AudioTrackBar extends StatelessWidget {
  final String label;
  final Duration totalProjectDuration;
  final Duration audioDuration;
  final Duration trimStart;
  final Duration trimEnd;
  final Duration offset;
  final ValueChanged<Duration> onOffsetChanged;
  final ValueChanged<Duration> onTrimStartChanged;
  final ValueChanged<Duration> onTrimEndChanged;
  final VoidCallback onDragEnd;

  static const double handleWidth = 18;
  static const double barHeight = 48;
  static const double minSegmentMs = 300;

  const AudioTrackBar({
    super.key,
    required this.label,
    required this.totalProjectDuration,
    required this.audioDuration,
    required this.trimStart,
    required this.trimEnd,
    required this.offset,
    required this.onOffsetChanged,
    required this.onTrimStartChanged,
    required this.onTrimEndChanged,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = totalProjectDuration.inMilliseconds <= 0
        ? 1.0
        : totalProjectDuration.inMilliseconds.toDouble();
    final audioDurationMs = audioDuration.inMilliseconds.toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;

        double xFromMs(double ms) => (ms / totalMs) * trackWidth;
        double msFromDx(double dx) => (dx / trackWidth) * totalMs;

        final offsetMs = offset.inMilliseconds.toDouble();
        final trimStartMs = trimStart.inMilliseconds.toDouble();
        final trimEndMs = trimEnd.inMilliseconds.toDouble();
        final segmentLengthMs = trimEndMs - trimStartMs;

        final startX = xFromMs(offsetMs).clamp(0.0, trackWidth);
        final endX =
            xFromMs(offsetMs + segmentLengthMs).clamp(0.0, trackWidth);
        final barWidth =
            (endX - startX).clamp(handleWidth * 1.5, trackWidth);

        void handleBodyDrag(double deltaDx) {
          final deltaMs = msFromDx(deltaDx);
          final maxOffsetMs =
              (totalMs - segmentLengthMs).clamp(0.0, totalMs);
          final newOffsetMs =
              (offsetMs + deltaMs).clamp(0.0, maxOffsetMs);
          onOffsetChanged(Duration(milliseconds: newOffsetMs.round()));
        }

        void handleLeftDrag(double deltaDx) {
          final deltaMs = msFromDx(deltaDx);
          // The end stays put: trimming from the left both consumes less
          // (or more) of the source's start AND shifts the timeline start
          // by the same amount, so the end position is unaffected.
          final maxTrimStartMs =
              (trimEndMs - minSegmentMs).clamp(0.0, trimEndMs);
          final newTrimStartMs =
              (trimStartMs + deltaMs).clamp(0.0, maxTrimStartMs);
          final appliedDelta = newTrimStartMs - trimStartMs;
          final newOffsetMs =
              (offsetMs + appliedDelta).clamp(0.0, totalMs);
          onTrimStartChanged(Duration(milliseconds: newTrimStartMs.round()));
          onOffsetChanged(Duration(milliseconds: newOffsetMs.round()));
        }

        void handleRightDrag(double deltaDx) {
          final deltaMs = msFromDx(deltaDx);
          final minTrimEndMs = trimStartMs + minSegmentMs;
          final maxByAudioSource = audioDurationMs;
          final maxByProjectEnd = totalMs - offsetMs + trimStartMs;
          var maxTrimEndMs =
              maxByAudioSource < maxByProjectEnd ? maxByAudioSource : maxByProjectEnd;
          // Guard against an invalid (upper < lower) clamp range in edge
          // cases, e.g. a source file shorter than the minimum segment.
          if (maxTrimEndMs < minTrimEndMs) maxTrimEndMs = minTrimEndMs;
          final newTrimEndMs =
              (trimEndMs + deltaMs).clamp(minTrimEndMs, maxTrimEndMs);
          onTrimEndChanged(Duration(milliseconds: newTrimEndMs.round()));
        }

        return SizedBox(
          height: barHeight,
          width: trackWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: startX,
                width: barWidth,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) =>
                      handleBodyDrag(details.delta.dx),
                  onHorizontalDragEnd: (_) => onDragEnd(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.teal.shade600,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.teal.shade200, width: 1),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        const Icon(Icons.music_note,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left:
                    (startX - handleWidth / 2).clamp(0.0, trackWidth),
                top: 0,
                bottom: 0,
                width: handleWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) =>
                      handleLeftDrag(details.delta.dx),
                  onHorizontalDragEnd: (_) => onDragEnd(),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: (endX - handleWidth / 2)
                    .clamp(0.0, trackWidth - handleWidth),
                top: 0,
                bottom: 0,
                width: handleWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) =>
                      handleRightDrag(details.delta.dx),
                  onHorizontalDragEnd: (_) => onDragEnd(),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
