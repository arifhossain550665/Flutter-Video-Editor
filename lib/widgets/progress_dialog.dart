import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/editor_controller.dart';

class ProgressDialog extends StatelessWidget {
  const ProgressDialog({super.key});

  String _stageLabel(ExportStage stage) {
    switch (stage) {
      case ExportStage.trimming:
        return 'Trimming clips...';
      case ExportStage.merging:
        return 'Merging clips...';
      case ExportStage.mixingAudio:
        return 'Mixing background audio...';
      case ExportStage.savingToGallery:
        return 'Saving to gallery...';
      case ExportStage.done:
        return 'Done';
      case ExportStage.error:
        return 'Something went wrong';
      case ExportStage.idle:
        return 'Preparing...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EditorController>(
      builder: (context, controller, _) {
        final progress = controller.overallProgress.clamp(0.0, 1.0);
        return AlertDialog(
          title: const Text('Exporting Video'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_stageLabel(controller.stage)),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text('${(progress * 100).toStringAsFixed(0)}%'),
            ],
          ),
        );
      },
    );
  }
}
