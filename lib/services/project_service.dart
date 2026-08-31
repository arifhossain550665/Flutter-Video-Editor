import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/project.dart';

/// Reads/writes projects to <appDocuments>/projects/<id>/project.json, and
/// copies any media the user picks into that project's own media/ folder so
/// a project keeps working even if the original file the user picked
/// disappears or the OS clears the system picker's cache. This is what
/// gives the app CapCut-style persistent projects instead of everything
/// living only in memory for the current session.
class ProjectService {
  Future<Directory> _projectsRootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/projects');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// The folder that owns everything belonging to one project: its
  /// project.json, its media/ subfolder, and its thumbnail image.
  Future<Directory> projectDir(String projectId) async {
    final root = await _projectsRootDir();
    final dir = Directory('${root.path}/$projectId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _mediaDir(String projectId) async {
    final dir = await projectDir(projectId);
    final mediaDir = Directory('${dir.path}/media');
    if (!await mediaDir.exists()) await mediaDir.create(recursive: true);
    return mediaDir;
  }

  /// Copies [source] into the project's own media folder and returns the
  /// new, project-owned path. Used for both imported video clips and
  /// background audio tracks so a project is fully self-contained and
  /// survives app restarts.
  Future<String> importMedia(String projectId, File source) async {
    final dir = await _mediaDir(projectId);
    final extension =
        source.path.contains('.') ? source.path.split('.').last : 'dat';
    final destPath =
        '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.$extension';
    final copied = await source.copy(destPath);
    return copied.path;
  }

  /// Lists every saved project, most recently updated first.
  Future<List<Project>> listProjects() async {
    final root = await _projectsRootDir();
    final projects = <Project>[];
    for (final entity in root.listSync()) {
      if (entity is! Directory) continue;
      final file = File('${entity.path}/project.json');
      if (!await file.exists()) continue;
      try {
        final jsonMap =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        projects.add(Project.fromJson(jsonMap));
      } catch (_) {
        // Skip a corrupted project file instead of crashing the whole list.
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<Project> createProject({String? name}) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final now = DateTime.now();
    final project = Project(
      id: id,
      name: name ?? _defaultName(now),
      createdAt: now,
      updatedAt: now,
    );
    await projectDir(id);
    await saveProject(project);
    return project;
  }

  /// Writes the project's current state to disk. Called after every
  /// meaningful edit so the project is always resumable, CapCut-style.
  Future<void> saveProject(Project project) async {
    project.updatedAt = DateTime.now();
    final dir = await projectDir(project.id);
    final file = File('${dir.path}/project.json');
    await file.writeAsString(jsonEncode(project.toJson()));
  }

  Future<void> deleteProject(String id) async {
    final dir = await projectDir(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  String _defaultName(DateTime d) {
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final time = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    return 'Project $date $time';
  }
}
