import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/editor_controller.dart';
import 'views/projects_screen.dart';

void main() {
  runApp(const VideoEditorApp());
}

class VideoEditorApp extends StatelessWidget {
  const VideoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EditorController(),
      child: MaterialApp(
        title: 'INC Gang',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        home: const ProjectsScreen(),
      ),
    );
  }
}
