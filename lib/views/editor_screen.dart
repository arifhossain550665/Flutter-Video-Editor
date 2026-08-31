import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/editor_controller.dart';
import '../models/video_clip.dart';
import '../widgets/clip_tile.dart';
import '../widgets/progress_dialog.dart';
import 'about_screen.dart';
import 'trim_screen.dart';

class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key});

  Future<void> _openTrimScreen(
    BuildContext context,
    EditorController controller,
    VideoClip clip,
  ) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => TrimScreen(clip: clip)),
    );
    if (result != null) {
      controller.updateClipSettings(
        clip.id,
        start: result['start'] as Duration,
        end: result['end'] as Duration,
        volumePercent: result['volumePercent'] as double,
        noiseCancellation: result['noiseCancellation'] as bool,
      );
    }
  }

  Future<void> _startExport(
    BuildContext context,
    EditorController controller,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ProgressDialog(),
    );

    final success = await controller.exportVideo();

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;

    if (success) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Export complete'),
          content: const Text(
            'Your video was processed and saved to the "Video Editor" album in your gallery.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Export failed'),
          content: Text(controller.errorMessage ?? 'Something went wrong.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    controller.resetExportState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<EditorController>(
          builder: (context, controller, _) =>
              Text(controller.project?.name ?? 'Edit Video'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<EditorController>(
        builder: (context, controller, _) {
          if (!controller.hasProject) {
            return const Center(child: Text('No project loaded.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Clips', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (controller.clips.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No clips yet. Add a video to get started.'),
                ),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: controller.clips.length,
                onReorder: controller.reorderClip,
                itemBuilder: (context, index) {
                  final clip = controller.clips[index];
                  return ClipTile(
                    key: ValueKey(clip.id),
                    clip: clip,
                    onTrim: () => _openTrimScreen(context, controller, clip),
                    onRemove: () => controller.removeClip(clip.id),
                  );
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => controller.importVideos(),
                icon: const Icon(Icons.add),
                label: const Text('Add More Clips'),
              ),
              const SizedBox(height: 4),
              Text(
                'Tip: tap the scissors on a clip to trim it and adjust that '
                "clip's own noise cancellation and volume.",
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white54),
              ),
              const Divider(height: 32),
              Text('Background Audio',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (controller.backgroundAudioPath == null)
                OutlinedButton.icon(
                  onPressed: () => controller.pickBackgroundAudio(),
                  icon: const Icon(Icons.folder_outlined),
                  label: const Text('Add Background Audio (from Storage)'),
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.audiotrack),
                  title: Text(
                    controller.backgroundAudioPath!.split('/').last,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => controller.removeBackgroundAudio(),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Noise cancellation'),
                subtitle:
                    const Text('Reduce background hiss on the audio track'),
                value: controller.noiseCancellationEnabled,
                onChanged: controller.backgroundAudioPath == null
                    ? null
                    : controller.setNoiseCancellation,
              ),
              const SizedBox(height: 8),
              Text('Volume boost: ${controller.volumePercent.round()}%'),
              Slider(
                value: controller.volumePercent,
                min: 100,
                max: 300,
                divisions: 20,
                label: '${controller.volumePercent.round()}%',
                onChanged: controller.backgroundAudioPath == null
                    ? null
                    : controller.setVolumePercent,
                onChangeEnd: controller.backgroundAudioPath == null
                    ? null
                    : (_) => controller.persistProject(),
              ),
              const Divider(height: 32),
              Text(
                'Total length: ${controller.totalTrimmedSeconds.toStringAsFixed(1)}s',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: controller.clips.isEmpty
                    ? null
                    : () => _startExport(context, controller),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Export Video'),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
