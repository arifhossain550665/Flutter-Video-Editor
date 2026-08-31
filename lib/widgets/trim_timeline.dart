import 'dart:io';

import 'package:flutter/material.dart';

/// A CapCut-style trim timeline: a horizontal filmstrip of thumbnails with
/// draggable amber start/end handles and a tap/drag-to-scrub white playhead.
class TrimTimeline extends StatelessWidget {
  final List<String> thumbnails;
  final Duration totalDuration;
  final Duration start;
  final Duration end;
  final Duration playhead;
  final ValueChanged<Duration> onStartChanged;
  final ValueChanged<Duration> onEndChanged;
  final ValueChanged<Duration> onScrub;

  static const double handleWidth = 22;
  static const double minGapMs = 500;
  static const double trackHeight = 72;

  const TrimTimeline({
    super.key,
    required this.thumbnails,
    required this.totalDuration,
    required this.start,
    required this.end,
    required this.playhead,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onScrub,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = totalDuration.inMilliseconds <= 0
        ? 1.0
        : totalDuration.inMilliseconds.toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final usableWidth = trackWidth - handleWidth;

        double xFromMs(double ms) =>
            (ms / totalMs) * usableWidth + handleWidth / 2;

        double msFromX(double x) {
          final raw = ((x - handleWidth / 2) / usableWidth) * totalMs;
          return raw.clamp(0.0, totalMs).toDouble();
        }

        final startMs = start.inMilliseconds.toDouble();
        final endMs = end.inMilliseconds.toDouble();
        final playheadMs =
            playhead.inMilliseconds.toDouble().clamp(0.0, totalMs);

        final startX = xFromMs(startMs);
        final endX = xFromMs(endMs);
        final playheadX = xFromMs(playheadMs);

        void handleStartDrag(double deltaDx) {
          final newX = startX + deltaDx;
          var newMs = msFromX(newX);
          final maxMs = (endMs - minGapMs).clamp(0.0, totalMs);
          newMs = newMs.clamp(0.0, maxMs).toDouble();
          onStartChanged(Duration(milliseconds: newMs.round()));
        }

        void handleEndDrag(double deltaDx) {
          final newX = endX + deltaDx;
          var newMs = msFromX(newX);
          final minMs = (startMs + minGapMs).clamp(0.0, totalMs);
          newMs = newMs.clamp(minMs, totalMs).toDouble();
          onEndChanged(Duration(milliseconds: newMs.round()));
        }

        void handleScrub(double localX) {
          final ms =
              msFromX(localX + handleWidth / 2).clamp(startMs, endMs);
          onScrub(Duration(milliseconds: ms.round()));
        }

        return SizedBox(
          height: trackHeight,
          width: trackWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Filmstrip
              Positioned(
                left: handleWidth / 2,
                right: handleWidth / 2,
                top: 0,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: thumbnails.isEmpty
                      ? Container(color: const Color(0xFF2A2A2E))
                      : Row(
                          children: thumbnails
                              .map(
                                (path) => Expanded(
                                  child: Image.file(
                                    File(path),
                                    fit: BoxFit.cover,
                                    height: trackHeight,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: const Color(0xFF2A2A2E),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ),

              // Dim the parts of the filmstrip outside the selected range
              Positioned(
                left: handleWidth / 2,
                top: 0,
                bottom: 0,
                width: (startX - handleWidth / 2).clamp(0.0, trackWidth),
                child: IgnorePointer(
                  child: Container(color: Colors.black.withOpacity(0.55)),
                ),
              ),
              Positioned(
                left: endX,
                right: 0,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(color: Colors.black.withOpacity(0.55)),
                ),
              ),

              // Amber top/bottom border around the selected range
              Positioned(
                left: startX,
                width: (endX - startX).clamp(0.0, trackWidth),
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                            color: Colors.amber.shade400, width: 3),
                        bottom: BorderSide(
                            color: Colors.amber.shade400, width: 3),
                      ),
                    ),
                  ),
                ),
              ),

              // Playhead
              Positioned(
                left: playheadX - 1,
                top: -6,
                bottom: -6,
                child: IgnorePointer(
                  child: Container(width: 2, color: Colors.white),
                ),
              ),

              // Tap/drag-to-scrub layer, sits beneath the handles below
              Positioned(
                left: handleWidth / 2,
                right: handleWidth / 2,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) =>
                      handleScrub(details.localPosition.dx),
                  onHorizontalDragUpdate: (details) =>
                      handleScrub(details.localPosition.dx),
                ),
              ),

              // Start handle (drawn last among the two so both win drags
              // over the scrub layer beneath them)
              Positioned(
                left: (startX - handleWidth / 2)
                    .clamp(0.0, trackWidth - handleWidth),
                top: 0,
                bottom: 0,
                width: handleWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) =>
                      handleStartDrag(details.delta.dx),
                  child: _TrimHandle(color: Colors.amber.shade400),
                ),
              ),

              // End handle
              Positioned(
                left: (endX - handleWidth / 2)
                    .clamp(0.0, trackWidth - handleWidth),
                top: 0,
                bottom: 0,
                width: handleWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) =>
                      handleEndDrag(details.delta.dx),
                  child: _TrimHandle(color: Colors.amber.shade400),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrimHandle extends StatelessWidget {
  final Color color;
  const _TrimHandle({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 3,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
