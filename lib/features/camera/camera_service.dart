import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/files/file_storage.dart';

/// Fotos con la cámara y selección de imágenes y videos de la galería.
///
/// Android a veces cierra la app mientras la cámara está abierta (sobre todo
/// en teléfonos con poca memoria). Para no perder la foto, antes de abrir la
/// cámara se guarda a qué nota iba; al volver a abrir la app,
/// [recoverLostPhoto] la recupera y la agrega a esa nota.
class CameraService {
  CameraService(this._storage, this._prefs);

  final FileStorage _storage;
  final SharedPreferences _prefs;
  final _picker = ImagePicker();

  static const _pendingNoteKey = 'camera.pendingNoteId';

  /// Devuelve la ruta de la foto ya copiada a la carpeta de la app.
  /// [forNoteId]: nota a la que va la foto (para recuperarla si Android
  /// cierra la app mientras la cámara está abierta).
  Future<String?> takePhoto({String? forNoteId}) async {
    if (forNoteId != null) await _prefs.setString(_pendingNoteKey, forNoteId);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2400,
      );
      if (file == null) return null;
      return _storage.importFile(file.path, folder: 'images');
    } finally {
      await _prefs.remove(_pendingNoteKey);
    }
  }

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
