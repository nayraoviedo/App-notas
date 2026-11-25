import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'background_remover.dart';
import 'in_app_camera_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Recortar y girar una foto antes de usarla.
/// Devuelve la ruta de la imagen recortada (o la original si no se cambió),
/// o null si se canceló.
Future<String?> cropImage(BuildContext context, String path) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => CropScreen(path: path), fullscreenDialog: true),
  );
}

/// Tomar foto (o elegir de la galería) y recortarla.
Future<String?> pickAndCropImage(
  BuildContext context,
  WidgetRef ref, {
  required bool camera,
  String? forNoteId,
}) async {
  final service = ref.read(cameraServiceProvider);
  String? path;
  if (camera) {
    final temp = await captureWithInAppCamera(context);
    if (temp != null) path = await service.savePhoto(temp);
  } else {
    path = await service.pickImageFromGallery();
  }
  if (path == null || !context.mounted) return null;
  return cropImage(context, path);
}

enum _Aspect {
  free('Libre', null),
  square('1:1', 1),
  portrait('3:4', 3 / 4),
  landscape('4:3', 4 / 3);

  const _Aspect(this.label, this.ratio);
  final String label;
  final double? ratio;
}

class CropScreen extends ConsumerStatefulWidget {
  const CropScreen({super.key, required this.path});
  final String path;

  @override
  ConsumerState<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends ConsumerState<CropScreen> {
  ui.Image? _image;

  /// Recorte en coordenadas de la imagen (píxeles).
  Rect _crop = Rect.zero;
  _Aspect _aspect = _Aspect.free;
  bool _changed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await File(widget.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _image = frame.image;
      _crop = Offset.zero & Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Size get _imgSize => Size(_image!.width.toDouble(), _image!.height.toDouble());

  Future<void> _rotate() async {
    final img = _image!;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)
      ..translate(img.height.toDouble(), 0)
      ..rotate(math.pi / 2);
    c.drawImage(img, Offset.zero, Paint());
    final rotated = await rec.endRecording().toImage(img.height, img.width);
    img.dispose();
    setState(() {
      _image = rotated;
      _crop = Offset.zero & _imgSize;
      _changed = true;
      _applyAspect();
    });
  }

  void _applyAspect() {
    final r = _aspect.ratio;
    if (r == null) return;
    final s = _imgSize;
    var w = s.width, h = w / r;
    if (h > s.height) {
      h = s.height;
      w = h * r;
    }
    _crop = Rect.fromCenter(center: s.center(Offset.zero), width: w, height: h);
  }

  bool _removing = false;

  Future<void> _removeBackground() async {
    final img = _image!;
    setState(() => _removing = true);
    try {
      final out = await removeBackground(img);
      if (!mounted) return;
      img.dispose();
      setState(() {
        _image = out;
        _changed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fondo quitado ✓ (se guarda como PNG transparente)')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  Future<void> _save() async {
    final img = _image!;
    final full = Offset.zero & _imgSize;
    if (!_changed && (_crop.width - full.width).abs() < 2 && (_crop.height - full.height).abs() < 2) {
      Navigator.pop(context, widget.path);
      return;
    }
    setState(() => _saving = true);
    final w = _crop.width.round(), h = _crop.height.round();
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      img,
      _crop,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final out = await rec.endRecording().toImage(w, h);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    final path = await ref
        .read(fileStorageProvider)
        .saveBytes(data!.buffer.asUint8List(), folder: 'images', ext: '.png');
    if (mounted) Navigator.pop(context, path);
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Recortar'),
        actions: [
          IconButton(
            tooltip: 'Quitar fondo',
            icon: const Icon(Icons.auto_fix_high_outlined),
            onPressed: img == null || _removing ? null : _removeBackground,
          ),
          IconButton(
            tooltip: 'Girar',
            icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
            onPressed: img == null ? null : _rotate,
          ),
          TextButton(
            onPressed: img == null || _saving ? null : _save,
            child: const Text('Listo', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: img == null || _saving || _removing
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: LayoutBuilder(builder: (context, c) {
                      final s = _imgSize;
                      final k = math.min(c.maxWidth / s.width, c.maxHeight / s.height);
                      final view = Size(s.width * k, s.height * k);
                      return Center(
                        child: SizedBox(
                          width: view.width,
                          height: view.height,
                          child: _CropArea(
                            image: img,
                            crop: _crop,
                            scale: k,
                            ratio: _aspect.ratio,
                            onChanged: (r) => setState(() {
                              _crop = r;
                              _changed = true;
                            }),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final a in _Aspect.values)
                          ChoiceChip(
                            label: Text(a.label),
                            selected: _aspect == a,
                            onSelected: (_) => setState(() {
                              _aspect = a;
                              _changed = true;
                              _applyAspect();
                            }),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Imagen con el marco de recorte: arrastrar dentro mueve, las esquinas
/// cambian el tamaño.
class _CropArea extends StatefulWidget {
  const _CropArea({
    required this.image,
    required this.crop,
    required this.scale,
    required this.ratio,
    required this.onChanged,
  });

  final ui.Image image;
  final Rect crop;
  final double scale;
  final double? ratio;
  final ValueChanged<Rect> onChanged;

  @override
  State<_CropArea> createState() => _CropAreaState();
}

class _CropAreaState extends State<_CropArea> {
  int? _corner; // 0 arriba-izq, 1 arriba-der, 2 abajo-der, 3 abajo-izq; null = mover

  Size get _img => Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  void _start(Offset local) {
    final r = _viewRect;
    final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    _corner = null;
    for (var i = 0; i < 4; i++) {
      if ((corners[i] - local).distance < 36) _corner = i;
    }
  }

  Rect get _viewRect => Rect.fromLTRB(
        widget.crop.left * widget.scale,
        widget.crop.top * widget.scale,
        widget.crop.right * widget.scale,
        widget.crop.bottom * widget.scale,
      );

  void _update(Offset delta) {
    final d = delta / widget.scale;
    var r = widget.crop;
    const minSide = 40.0;
    final bounds = Offset.zero & _img;
    if (_corner == null) {
      r = r.shift(d);
      final dx = r.left < 0 ? -r.left : (r.right > bounds.right ? bounds.right - r.right : 0.0);
      final dy = r.top < 0 ? -r.top : (r.bottom > bounds.bottom ? bounds.bottom - r.bottom : 0.0);
      r = r.shift(Offset(dx, dy));
    } else {
      var l = r.left, t = r.top, rt = r.right, b = r.bottom;
      switch (_corner) {
        case 0:
          l += d.dx;
          t += d.dy;
        case 1:
          rt += d.dx;
          t += d.dy;
        case 2:
          rt += d.dx;
          b += d.dy;
        case 3:
          l += d.dx;
          b += d.dy;
      }
      l = l.clamp(0.0, rt - minSide);
      t = t.clamp(0.0, b - minSide);
      rt = rt.clamp(l + minSide, bounds.right);
      b = b.clamp(t + minSide, bounds.bottom);
      r = Rect.fromLTRB(l, t, rt, b);
      final ratio = widget.ratio;
      if (ratio != null) {
        // Mantener la proporción ajustando el alto desde la esquina fija.
        final h = (r.width / ratio).clamp(minSide, bounds.height);
        r = (_corner == 0 || _corner == 1)
            ? Rect.fromLTRB(r.left, r.bottom - h, r.right, r.bottom)
            : Rect.fromLTRB(r.left, r.top, r.right, r.top + h);
        if (r.top < 0 || r.bottom > bounds.bottom) return;
      }
    }
    widget.onChanged(r);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => _start(d.localPosition),
      onPanUpdate: (d) => _update(d.delta),
      child: CustomPaint(
        painter: _CropPainter(widget.image, _viewRect),
        size: Size.infinite,
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.rect);
  final ui.Image image;
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    // Cuadriculado gris/blanco: así se nota lo transparente (sin fondo).
    canvas.drawRect(full, Paint()..color = Colors.white);
    final gray = Paint()..color = const Color(0xFFDDDDDD);
    const k = 12.0;
    for (var y = 0.0; y < size.height; y += k) {
      for (var x = ((y / k).round().isEven ? 0.0 : k); x < size.width; x += 2 * k) {
        canvas.drawRect(Rect.fromLTWH(x, y, k, k), gray);
      }
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      full,
      Paint()..filterQuality = FilterQuality.medium,
    );
    // Oscurecer fuera del recorte.
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(full), Path()..addRect(rect)),
      Paint()..color = Colors.black54,
    );
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, line);
    // Guías de tercios.
    final thin = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    for (final t in [1 / 3, 2 / 3]) {
      canvas.drawLine(Offset(rect.left + rect.width * t, rect.top),
          Offset(rect.left + rect.width * t, rect.bottom), thin);
      canvas.drawLine(Offset(rect.left, rect.top + rect.height * t),
          Offset(rect.right, rect.top + rect.height * t), thin);
    }
    // Esquinas.
    final corner = Paint()..color = Colors.white;
    for (final p in [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft]) {
      canvas.drawCircle(p, 9, corner);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect || old.image != image;
}
