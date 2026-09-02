import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/editor_controller.dart';
import '../models/video_clip.dart';
import '../widgets/audio_track_bar.dart';
import '../widgets/clip_timeline.dart';
import '../widgets/clip_tile.dart';
import '../widgets/inline_clip_editor.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/progress_dialog.dart';
import '../widgets/project_preview_controller.dart';
import '../widgets/project_preview_player.dart';
import 'about_screen.dart';

const _bgColor = Color(0xFF121214);

/// The main editing screen: one continuous surface where the persistent
/// project preview, the whole clip timeline, the currently-selected
/// clip's trim controls, background audio placement, and export all live
/// together - CapCut-style - instead of trimming a clip on a separate page.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  String? _selectedClipId;
  late final ProjectPreviewController _previewController;

  @override
  void initState() {
    super.initState();
    _previewController = ProjectPreviewController();
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  void _selectClip(VideoClip clip) {
    setState(() {
      _selectedClipId = _selectedClipId == clip.id ? null : clip.id;
    });
    if (_selectedClipId == clip.id) {
      _previewController.seekToClipStart(clip.id);
    }
  }

  void _closeInlineEditor() {
    setState(() => _selectedClipId = null);
  }

  void _applyInlineEdit(
    EditorController controller,
    VideoClip clip,
    Map<String, dynamic> result,
  ) {
    controller.updateClipSettings(
      clip.id,
      start: result['start'] as Duration,
      end: result['end'] as Duration,
      volumePercent: result['volumePercent'] as double,
      noiseCancellation: result['noiseCancellation'] as bool,
    );
    setState(() => _selectedClipId = null);
  }

  Future<void> _startExport(
    BuildContext context,
    EditorController controller,
  ) async {
    await _previewController.pause();

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

  String _formatShort(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
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

          // Keep the shared preview in sync with whatever clips currently
          // exist (fire-and-forget: cheap no-op when nothing relevant
          // changed, since the same active clip just gets re-indexed).
          _previewController.setClips(controller.clips);

          // If the selected clip was removed elsewhere, drop the stale
          // selection instead of pointing the inline editor at nothing.
          VideoClip? selectedClip;
          if (_selectedClipId != null) {
            for (final c in controller.clips) {
              if (c.id == _selectedClipId) {
                selectedClip = c;
                break;
              }
            }
            if (selectedClip == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _selectedClipId = null);
              });
            }
          }

          return Stack(
            children: [
              _buildBody(context, controller, selectedClip),
              LoadingOverlay(
                visible: controller.isBusy,
                message: controller.busyMessage,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    EditorController controller,
    VideoClip? selectedClip,
  ) {
    final projectDuration = controller.clips.fold<Duration>(
      Duration.zero,
      (sum, c) => sum + c.trimmedDuration,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (controller.clips.isNotEmpty) ...[
          ProjectPreviewPlayer(controller: _previewController),
          const SizedBox(height: 12),
        ],
        Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ClipTimeline(
          clips: controller.clips,
          selectedClipId: _selectedClipId,
          onTapClip: _selectClip,
        ),
        if (controller.backgroundAudioPath != null) ...[
          const SizedBox(height: 6),
          AudioTrackBar(
            label: controller.backgroundAudioPath!.split('/').last,
            totalProjectDuration: projectDuration,
            audioDuration: controller.backgroundAudioDuration,
            trimStart: controller.backgroundAudioTrimStart,
            trimEnd: controller.backgroundAudioTrimEnd,
            offset: controller.backgroundAudioOffset,
            onOffsetChanged: controller.setBackgroundAudioOffset,
            onTrimStartChanged: controller.setBackgroundAudioTrimStart,
            onTrimEndChanged: controller.setBackgroundAudioTrimEnd,
            onDragEnd: () => controller.persistProject(),
          ),
          const SizedBox(height: 4),
          Text(
            'Song starts at ${_formatShort(controller.backgroundAudioOffset)} '
            'and plays for ${_formatShort(controller.backgroundAudioTrimEnd - controller.backgroundAudioTrimStart)}. '
            'Drag the middle to move it, drag the edges to trim it.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white54),
          ),
        ],
        if (selectedClip != null)
          InlineClipEditor(
            key: ValueKey(selectedClip.id),
            clip: selectedClip,
            previewController: _previewController,
            onDone: (result) =>
                _applyInlineEdit(controller, selectedClip!, result),
            onClose: _closeInlineEditor,
          ),
        const SizedBox(height: 16),
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
              onTrim: () => _selectClip(clip),
              onRemove: () {
                if (_selectedClipId == clip.id) {
                  setState(() => _selectedClipId = null);
                }
                controller.removeClip(clip.id);
              },
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
          'Tip: tap a clip on the timeline (or its scissors icon below) to '
          "edit it right here - trim, noise cancellation and volume, all "
          "on this screen, with the preview above updating live.",
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => controller.removeBackgroundAudio(),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Remove Background Audio'),
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: Colors.amber.shade400,
          title: const Text('Noise cancellation'),
          subtitle: const Text('Reduce background hiss on the audio track'),
          value: controller.noiseCancellationEnabled,
          onChanged: controller.backgroundAudioPath == null
              ? null
              : controller.setNoiseCancellation,
        ),
        const SizedBox(height: 8),
        Text('Volume boost: ${controller.volumePercent.round()}%'),
        Slider(
          activeColor: Colors.amber.shade400,
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
  }
}
