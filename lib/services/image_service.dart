import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageService {
  ImageService._();

  static final _picker = ImagePicker();

  static Future<String?> pickAndKeep() => _pickAndKeep(ImageSource.gallery);

  static Future<String?> takePhotoAndKeep() => _pickAndKeep(ImageSource.camera);

  static Future<List<String>> pickManyAndKeep({required int maxCount}) async {
    if (maxCount <= 0) return const [];
    final images = await _picker.pickMultiImage(
      imageQuality: 88,
      maxWidth: 1800,
      limit: maxCount,
    );
    if (images.isEmpty) return const [];
    final keptPaths = <String>[];
    try {
      for (final indexed in images.take(maxCount).indexed) {
        keptPaths.add(await _keep(indexed.$2, suffix: indexed.$1));
      }
      return keptPaths;
    } catch (_) {
      await deleteKeptImages(keptPaths);
      rethrow;
    }
  }

  static Future<String?> _pickAndKeep(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (image == null) return null;

    return _keep(image);
  }

  static Future<String> _keep(XFile image, {int suffix = 0}) async {
    final documents = await getApplicationDocumentsDirectory();
    final imageDir = Directory(p.join(documents.path, 'garden_images'));
    if (!await imageDir.exists()) await imageDir.create(recursive: true);
    final extension = p.extension(image.path).isEmpty
        ? '.jpg'
        : p.extension(image.path);
    final target = p.join(
      imageDir.path,
      '${DateTime.now().microsecondsSinceEpoch}_$suffix$extension',
    );
    try {
      return (await File(image.path).copy(target)).path;
    } on FileSystemException {
      // A partially copied file should never become an orphaned garden image.
      final partial = File(target);
      if (await partial.exists()) {
        await partial.delete().catchError((_) => partial);
      }
      rethrow;
    }
  }

  static Future<void> deleteKeptImages(Iterable<String> paths) async {
    await Future.wait(paths.map(deleteKeptImage));
  }

  static Future<void> deleteKeptImage(String path) async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      final imageDirectory = p.normalize(
        p.absolute(p.join(documents.path, 'garden_images')),
      );
      final candidate = p.normalize(p.absolute(path));
      if (!p.isWithin(imageDirectory, candidate)) return;

      final file = File(candidate);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Database changes must not fail just because Android has already cleaned
      // an image file or temporarily refuses access to it.
    }
  }
}
