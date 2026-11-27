import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/files/file_storage.dart';

/// Fotos con la cámara y selección de imágenes y videos de la galería.
///
/// Las fotos se toman con la cámara dentro de la app; [recoverLostPhoto]
/// queda solo para fotos de versiones anteriores que usaban la cámara del
/// sistema.
class CameraService {
  CameraService(this._storage, this._prefs);

  final FileStorage _storage;
  final SharedPreferences _prefs;
  final _picker = ImagePicker();

  static const _pendingNoteKey = 'camera.pendingNoteId';

  /// Copia a la carpeta de la app una foto tomada con la cámara propia
  /// (ver `in_app_camera_screen.dart`) y devuelve la ruta final.
  Future<String> savePhoto(String tempPath) => _storage.importFile(tempPath, folder: 'images');

  /// Si la app se cerró mientras se tomaba una foto, devuelve
  /// (nota, ruta de la foto) para agregarla. Si no hay nada, null.
  Future<(String, String)?> recoverLostPhoto() async {
    final noteId = _prefs.getString(_pendingNoteKey);
    final LostDataResponse response;
    try {
      response = await _picker.retrieveLostData();
    } catch (_) {
      return null; // solo existe en Android
    }
    await _prefs.remove(_pendingNoteKey);
    if (response.isEmpty || noteId == null) return null;
    final file = response.file ?? response.files?.firstOrNull;
    if (file == null) return null;
    final path = await _storage.importFile(file.path, folder: 'images');
    return (noteId, path);
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
