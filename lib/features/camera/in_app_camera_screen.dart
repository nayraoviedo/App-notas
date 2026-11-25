import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Toma una foto con la cámara DENTRO de la app. Devuelve la ruta temporal
/// de la foto, o null si se canceló.
///
/// Antes se abría la app de cámara del sistema; en muchos celulares Android
/// cerraba esta app mientras tanto (para liberar memoria) y al volver
/// aparecía el inicio. Con la cámara propia la app nunca se va al fondo.
Future<String?> captureWithInAppCamera(BuildContext context) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const InAppCameraScreen(), fullscreenDialog: true),
    );

class InAppCameraScreen extends StatefulWidget {
  const InAppCameraScreen({super.key});

  @override
  State<InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<InAppCameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  int _index = 0;
  CameraController? _ctl;
  FlashMode _flash = FlashMode.off;
  String? _error;
  bool _blocked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctl = _ctl;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (ctl != null && ctl.value.isInitialized) {
        _ctl = null;
        ctl.dispose();
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed && _ctl == null && _cameras.isNotEmpty) {
      _open(_cameras[_index]);
    }
  }

  Future<void> _start() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _blocked = status.isPermanentlyDenied || status.isRestricted;
        _error = _blocked
            ? 'La cámara está bloqueada para la app. Actívala en Ajustes → Permisos → Cámara.'
            : 'Para tomar fotos, la app necesita permiso para usar la cámara.';
      });
      return;
    }
    try {
      _cameras = await availableCameras();
    } catch (e) {
      setState(() => _error = 'No se encontró la cámara: $e');
      return;
    }
    if (_cameras.isEmpty) {
      setState(() => _error = 'Este teléfono no tiene cámara disponible.');
      return;
    }
    _index = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    if (_index < 0) _index = 0;
    await _open(_cameras[_index]);
  }

  Future<void> _open(CameraDescription cam) async {
    final old = _ctl;
    _ctl = null;
    await old?.dispose();
    final ctl = CameraController(cam, ResolutionPreset.high, enableAudio: false);
    try {
      await ctl.initialize();
      await ctl.setFlashMode(_flash).catchError((_) {});
    } catch (e) {
      await ctl.dispose();
      if (mounted) setState(() => _error = 'No se pudo abrir la cámara: $e');
      return;
    }
    if (!mounted) {
      await ctl.dispose();
      return;
    }
    setState(() {
      _ctl = ctl;
      _error = null;
    });
  }

  Future<void> _shoot() async {
    final ctl = _ctl;
    if (ctl == null || !ctl.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await ctl.takePicture();
      if (mounted) Navigator.pop(context, file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo tomar la foto: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFlash() async {
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await _ctl?.setFlashMode(next);
      setState(() => _flash = next);
    } catch (_) {}
  }

  void _flip() {
    if (_cameras.length < 2) return;
    _index = (_index + 1) % _cameras.length;
    _open(_cameras[_index]);
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _ctl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                if (ctl != null)
                  IconButton(
                    tooltip: 'Flash',
                    icon: Icon(
                      switch (_flash) {
                        FlashMode.auto => Icons.flash_auto,
                        FlashMode.always => Icons.flash_on,
                        _ => Icons.flash_off,
                      },
                      color: Colors.white,
                    ),
                    onPressed: _toggleFlash,
                  ),
              ],
            ),
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
                            const SizedBox(height: 12),
                            Text(_error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _blocked
                                  ? openAppSettings
                                  : () {
                                      setState(() => _error = null);
                                      _start();
                                    },
                              child: Text(_blocked ? 'Abrir ajustes' : 'Dar permiso'),
                            ),
                          ],
                        ),
                      )
                    : ctl == null || !ctl.value.isInitialized
                        ? const CircularProgressIndicator(color: Colors.white)
                        : AspectRatio(
                            // La vista previa viene en horizontal: se invierte.
                            aspectRatio: 1 / ctl.value.aspectRatio,
                            child: CameraPreview(ctl),
                          ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 12, 32, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48),
                  GestureDetector(
                    onTap: _shoot,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      padding: const EdgeInsets.all(5),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _busy ? Colors.white54 : Colors.white,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cambiar cámara',
                    iconSize: 32,
                    icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
                    onPressed: _cameras.length < 2 ? null : _flip,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
