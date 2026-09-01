import 'package:flutter/material.dart';

/// A full-screen semi-transparent overlay with a spinner and status
/// message. Shown over a screen's content (inside a Stack) while the app
/// is busy with any background operation - importing videos, copying
/// background audio, generating a thumbnail, etc - so the UI never looks
/// frozen during I/O or FFmpeg work.
class LoadingOverlay extends StatelessWidget {
  final bool visible;
  final String message;

  const LoadingOverlay({
    super.key,
    required this.visible,
    this.message = 'Loading...',
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.black87,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
