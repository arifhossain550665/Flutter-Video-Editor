import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'project_preview_controller.dart';

/// The persistent, always-visible video preview at the top of the editor
/// screen - CapCut-style. Backed by a [ProjectPreviewController], so it
/// keeps working seamlessly as playback/scrubbing crosses from one clip
/// into the next, instead of only showing a single clip at a time.
class ProjectPreviewPlayer extends StatelessWidget {
  final ProjectPreviewController controller;

  const ProjectPreviewPlayer({super.key, required this.controller});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final videoController = controller.activeController;
        final ready = controller.isReady && videoController != null;

        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: controller.aspectRatio,
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: ready
                      ? VideoPlayer(videoController)
                      : const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 40,
                  icon: Icon(
                    controller.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  onPressed: ready
                      ? () {
                          if (controller.isPlaying) {
                            controller.pause();
                          } else {
                            controller.play();
                          }
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_formatDuration(controller.position)} / '
                  '${_formatDuration(controller.totalDuration)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
