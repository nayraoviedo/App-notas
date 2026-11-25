import 'package:image_picker/image_picker.dart';

import '../../core/files/file_storage.dart';

/// Fotos con la cámara y selección de videos de la galería.
class CameraService {
  CameraService(this._storage);

  final FileStorage _storage;
  final _picker = ImagePicker();

  /// Devuelve la ruta de la foto ya copiada a la carpeta de la app.
  Future<String?> takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 2400,
    );
    if (file == null) return null;
    return _storage.importFile(file.path, folder: 'images');
  }

  Future<String?> pickImageFromGallery() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    return _storage.importFile(file.path, folder: 'images');
  }

  /// TODO: para videos muy pesados, guardar solo la referencia en lugar de copiar.
  Future<String?> pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return null;
    return _storage.importFile(file.path, folder: 'videos');
  }
}
