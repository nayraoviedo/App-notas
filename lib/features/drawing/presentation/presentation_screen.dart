import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'painters/drawing_painter.dart';
import 'painters/paper_painter.dart';
import 'widgets/canvas_item_view.dart';

/// Presentar las hojas a pantalla completa (para exponer en clase o al
/// compartir pantalla): desliza para cambiar de hoja y arrastra el dedo
/// para el puntero láser, que se borra solo.
class PresentationScreen extends StatefulWidget {
  const PresentationScreen({super.key, required this.paths, this.initial = 0});

  final List<String> paths;
  final int initial;

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _LaserPoint {
  _LaserPoint(this.at, this.time);
  final Offset at;
  final int time;
}

class _PresentationScreenState extends State<PresentationScreen> {
  late final _pager = PageController(initialPage: widget.initial);
  late int _page = widget.initial;
  bool _laser = true;
  bool _chrome = true;
  final _trail = <_LaserPoint>[];
  Timer? _ticker;

  static const _fadeMs = 700;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pager.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  void _addPoint(Offset p) {
    setState(() => _trail.add(_LaserPoint(p, _now)));
    _ticker ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      final cut = _now - _fadeMs;
      setState(() => _trail.removeWhere((e) => e.time < cut));
      if (_trail.isEmpty) {
        _ticker?.cancel();
        _ticker = null;
      }
    });
  }

  void _go(int dir) {
    final to = (_page + dir).clamp(0, widget.paths.length - 1);
    _pager.animateToPage(to, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.paths.length;
    return Scaffold(
      backgroundColor: const Color(0xFF202124),
      body: Stack(children: [
        PageView.builder(
          controller: _pager,
          // Con el láser, deslizar dibuja; se cambia de hoja con las flechas.
          physics: _laser ? const NeverScrollableScrollPhysics() : null,
          itemCount: n,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => Center(child: _Slide(path: widget.paths[i])),
        ),
        if (_laser)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _chrome = !_chrome),
              onPanStart: (d) => _addPoint(d.localPosition),
              onPanUpdate: (d) => _addPoint(d.localPosition),
              child: CustomPaint(painter: _LaserPainter(_trail, _now, _fadeMs)),
            ),
          )
        else
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _chrome = !_chrome),
            ),
          ),
        if (_chrome) ...[
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                label: const Text('Salir'),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: Material(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Hoja anterior',
                        color: Colors.white,
                        onPressed: _page > 0 ? () => _go(-1) : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text('${_page + 1} / $n', style: const TextStyle(color: Colors.white)),
                      IconButton(
                        tooltip: 'Hoja siguiente',
                        color: Colors.white,
                        onPressed: _page < n - 1 ? () => _go(1) : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                      const SizedBox(width: 6),
                      TextButton.icon(
                        onPressed: () => setState(() => _laser = !_laser),
                        icon: Icon(_laser ? Icons.highlight : Icons.swipe,
                            color: _laser ? Colors.redAccent : Colors.white),
                        label: Text(_laser ? 'Láser' : 'Deslizar',
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          if (_laser && _trail.isEmpty)
            const Positioned(
              top: 20,
              right: 20,
              child: SafeArea(
                child: Text('Arrastra el dedo para señalar',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
              ),
            ),
        ],
      ]),
    );
  }
}

class _Slide extends ConsumerWidget {
  const _Slide({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(drawingFileProvider(path)).valueOrNull;
    if (d == null) return const CircularProgressIndicator();
    return FittedBox(
      fit: BoxFit.contain,
      child: Container(
        width: d.width,
        height: d.height,
        color: Colors.white,
        child: Stack(fit: StackFit.expand, children: [
          PaperView(paper: d.paper),
          DrawingLayersStaticView(drawing: d, painterFor: StaticLayerPainter.new),
        ]),
      ),
    );
  }
}

class _LaserPainter extends CustomPainter {
  _LaserPainter(this.trail, this.now, this.fadeMs);
  final List<_LaserPoint> trail;
  final int now;
  final int fadeMs;

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty) return;
    for (var i = 1; i < trail.length; i++) {
      final a = trail[i - 1], b = trail[i];
      if ((b.at - a.at).distance > 80) continue; // otro toque
      final life = (1 - (now - b.time) / fadeMs).clamp(0.0, 1.0);
      canvas.drawLine(
        a.at,
        b.at,
        Paint()
          ..color = Colors.red.withValues(alpha: 0.25 * life)
          ..strokeWidth = 18
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawLine(
        a.at,
        b.at,
        Paint()
          ..color = Colors.redAccent.withValues(alpha: life)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
    final tip = trail.last;
    final life = (1 - (now - tip.time) / fadeMs).clamp(0.0, 1.0);
    canvas.drawCircle(tip.at, 9, Paint()..color = Colors.red.withValues(alpha: life));
    canvas.drawCircle(tip.at, 4, Paint()..color = Colors.white.withValues(alpha: life));
  }

  @override
  bool shouldRepaint(_LaserPainter old) => true;
}
