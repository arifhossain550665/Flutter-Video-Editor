import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/editor_controller.dart';
import 'about_screen.dart';
import 'editor_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Editor'),
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
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.movie_creation_outlined,
                      size: 96, color: Colors.white70),
                  const SizedBox(height: 24),
                  const Text(
                    'Import videos to start editing',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () async {
                      await controller.importVideos();
                      if (controller.clips.isNotEmpty && context.mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const EditorScreen()),
                        );
                      }
                    },
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('Import Videos'),
                  ),
                  if (controller.clips.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const EditorScreen()),
                        );
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(
                        'Continue editing (${controller.clips.length} clips)',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
