// Abre varios cuadernos seguidos en un emulador (como hace la persona):
// entrar, volver, entrar a otro. Sirve para ver por qué la app vuelve al
// menú o se cierra al abrir el segundo cuaderno.
//
//   flutter drive --profile --driver=test_driver/integration_test.dart \
//     --target=integration_test/abrir_cuadernos_test.dart
import 'dart:ui';

import 'package:app_notas/app.dart';
import 'package:app_notas/core/providers.dart';
import 'package:app_notas/core/router.dart';
import 'package:app_notas/features/drawing/application/handwriting.dart';
import 'package:app_notas/features/drawing/domain/drawing.dart';
import 'package:app_notas/features/drawing/presentation/drawing_screen.dart';
import 'package:app_notas/main.dart' as app;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Drawing _page(int seed, {bool cover = false}) {
  final strokes = <Stroke>[
    for (var k = 0; k < 6; k++)
      Stroke(
        tool: (seed + k) % 3 == 0 ? ToolType.marker : ToolType.pen,
        color: 0xFF2255AA,
        size: 6,
        points: [
          for (var i = 0; i < 80; i++)
            StrokePoint(100.0 + i * 6, 200.0 + k * 90 + (i % 7) * 4, 0.5 + (i % 5) / 10),
        ],
      ),
  ];
  return Drawing.blank(paper: PaperStyle(template: cover ? PaperTemplate.cover : PaperTemplate.lined))
      .copyWith(layers: [DrawingLayer(id: 'l1', name: 'Capa 1', strokes: cover ? const [] : strokes)]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('abrir tres cuadernos seguidos', (tester) async {
    final errors = <String>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d.exceptionAsString());
      // ignore: avoid_print
      print('ERROR FLUTTER: ${d.exceptionAsString()}\n${d.stack}');
    };
    PlatformDispatcher.instance.onError = (e, s) {
      errors.add('$e');
      // ignore: avoid_print
      print('ERROR SIN ATRAPAR: $e\n$s');
      return true;
    };

    await app.main();
    Future<void> wait(int ms) async {
      for (var t = 0; t < ms; t += 100) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    await wait(3000);
    // Con el lector de letra bajado (como en el celular de nayra), al cerrar
    // cada hoja se lee lo escrito a mano.
    try {
      await tester.runAsync(() => Handwriting.instance.ensureModel().timeout(const Duration(minutes: 3)));
      // ignore: avoid_print
      print('== lector de letra listo: ${await tester.runAsync(() => Handwriting.instance.isReady())}');
    } catch (e) {
      // ignore: avoid_print
      print('== sin lector de letra: $e');
    }
    final container = ProviderScope.containerOf(tester.element(find.byType(AppNotas)));
    final repo = container.read(notesRepositoryProvider);
    final storage = container.read(fileStorageProvider);
    final store = container.read(drawingStoreProvider);

    final notebooks = <(String, String)>[];
    for (var n = 0; n < 3; n++) {
      final id = await repo.createNote(title: 'Cuaderno $n');
      String? first;
      for (var p = 0; p < 4; p++) {
        final path = await storage.newDrawingPath();
        await store.save(path, _page(n * 10 + p, cover: p == 0));
        await repo.addDrawingBlock(id, path);
        if (p == 1) first = path;
      }
      notebooks.add((id, first!));
    }

    String where() => appRouter.routerDelegate.currentConfiguration.uri.toString();

    for (final (k, (id, first)) in notebooks.indexed) {
      // ignore: avoid_print
      print('== abriendo cuaderno $k (desde ${where()})');
      appRouter.push('/notes/$id');
      await wait(800);
      appRouter.push('/notes/$id/drawing', extra: first);
      await wait(4000);
      // ignore: avoid_print
      print('== cuaderno $k abierto: ruta ${where()}, hojas=${find.byType(DrawingScreen).evaluate().length}');
      expect(find.byType(DrawingScreen), findsOneWidget, reason: 'el cuaderno $k no quedó abierto (${where()})');
      // Bajar un poco por las hojas, como al hojear.
      await tester.dragFrom(const Offset(200, 600), const Offset(0, -500));
      await wait(1500);
      // ignore: avoid_print
      print('== cuaderno $k tras bajar: ${where()}');
      // "Atrás" del sistema dos veces: a la nota y al inicio.
      await tester.binding.handlePopRoute();
      await wait(1500);
      // ignore: avoid_print
      print('== tras atrás 1: ${where()}');
      await tester.binding.handlePopRoute();
      await wait(1500);
      // ignore: avoid_print
      print('== tras atrás 2: ${where()}');
    }
    FlutterError.onError = oldOnError;
    // ignore: avoid_print
    print('== errores: ${errors.length}');
    expect(errors, isEmpty);
  });
}
