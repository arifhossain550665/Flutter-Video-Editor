import 'dart:io';
import 'package:path_provider/path_provider.dart';

class VideoMetadata {
  final double width;
  final double height;

  VideoMetadata({required this.width, required this.height});
}

class MediaService {
  Future<VideoMetadata> probeVideoMetadata(String path) async {
    // প্রয়োজন অনুযায়ী আসল ফ্রেস বা এফএফএমপেগ ডিটেইলস রিটার্ন করতে পারেন
    return VideoMetadata(width: 1280.0, height: 720.0);
  }

  Future<Directory> newTempSubdirectory(String folderName) async {
    final tempDir = await getTemporaryDirectory();
    final newDir = Directory('${tempDir.path}/$folderName');
    if (!await newDir.exists()) {
      await newDir.create(recursive: true);
    }
    return newDir;
  }
}
