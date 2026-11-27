// Capturas de pantalla automáticas (las genera GitHub Actions).
//
//   flutter test screenshot_test --update-goldens
//
// Las imágenes quedan en screenshot_test/out/. Necesita FLUTTER_ROOT (para la
// fuente Roboto y los íconos) y, opcional, las fuentes de Google en
// screenshot_test/fonts/ (las descarga el workflow).
import 'dart:async';
import 'dart:io';

import 'package:app_notas/core/fonts.dart';
import 'package:app_notas/core/providers.dart';
import 'package:app_notas/core/theme.dart';
import 'package:app_notas/features/drawing/data/drawing_store.dart';
import 'package:app_notas/features/drawing/domain/drawing.dart';
import 'package:app_notas/features/expenses/data/expenses_repository.dart';
import 'package:app_notas/features/expenses/domain/expense.dart';
import 'package:app_notas/features/expenses/presentation/expenses_screen.dart';
import 'package:app_notas/features/notebooks/presentation/notebook_form.dart';
import 'package:app_notas/features/notebooks/domain/notebook.dart';
import 'package:app_notas/features/notebooks/presentation/library_screen.dart';
import 'package:app_notas/features/notes/domain/note.dart';
import 'package:app_notas/features/notes/domain/note_block.dart';
import 'package:app_notas/features/notes/presentation/book_view_screen.dart';
import 'package:app_notas/features/notes/presentation/create_note_sheet.dart';
import 'package:app_notas/features/drawing/presentation/drawing_screen.dart';
import 'package:app_notas/features/settings/settings.dart';
import 'package:app_notas/features/journal/domain/journal.dart';
import 'package:app_notas/features/journal/presentation/journal_screen.dart';
import 'package:app_notas/features/study/domain/flashcard.dart';
import 'package:app_notas/features/study/presentation/study_screen.dart';
import 'package:app_notas/features/study/presentation/exam_screen.dart';
import 'package:app_notas/features/planner/domain/planner.dart';
import 'package:app_notas/features/planner/presentation/planner_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = Size(1080, 2340);
const _dpr = 2.75;

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  var any = false;
  for (final f in files) {
    final file = File(f);
    if (!file.existsSync()) continue;
    loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    any = true;
  }
  if (any) await loader.load();
}

Future<void> _loadFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final material = '$root/bin/cache/artifacts/material_fonts';
  await _loadFont('Roboto', [
    '$material/Roboto-Regular.ttf',
    '$material/Roboto-Medium.ttf',
    '$material/Roboto-Bold.ttf',
  ]);
  await _loadFont('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  // Fuentes de Google descargadas por el workflow: se registran con el
  // nombre interno que usa google_fonts.
  final dir = Directory('screenshot_test/fonts');
  if (!dir.existsSync()) return;
  for (final f in dir.listSync().whereType<File>()) {
    final family = f.uri.pathSegments.last.split('.').first.replaceAll('_', ' ');
    // También con su nombre normal (para el tema de las capturas).
    await _loadFont(family, [f.path]);
    // google_fonts intenta cargar la letra en segundo plano y falla (no hay
    // internet en las pruebas): ese error se ignora, aquí se registra a mano.
    String? internal, bold;
    runZonedGuarded(() {
      internal = fontStyle(family).fontFamily;
      bold = fontStyle(family, base: const TextStyle(fontWeight: FontWeight.bold)).fontFamily;
    }, (_, __) {});
    if (internal != null) await _loadFont(internal!, [f.path]);
    if (bold != null && bold != internal) await _loadFont(bold!, [f.path]);
  }
}

Future<void> _phoneSize(WidgetTester tester) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = _dpr;
  addTearDown(tester.view.reset);
}

/// Mismo tema que la app, con la letra manuscrita cargada a mano (en las
/// pruebas google_fonts no descarga nada).
ThemeData _theme() {
  final t = AppTheme.light('Normal');
  return t.copyWith(
    textTheme: Typography.englishLike2021.merge(t.textTheme).apply(fontFamily: 'Patrick Hand', fontSizeFactor: 1.1),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamily: 'Patrick Hand'),
  );
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 400));
  // Las imágenes (cabecera, stickers) se decodifican de verdad antes de la foto.
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
}

// ------------------------------------------------------------ Datos de ejemplo

Drawing _samplePage() => Drawing(
      width: Drawing.a4Width,
      height: Drawing.a4Height,
      paper: const PaperStyle(template: PaperTemplate.grid, spacing: 46),
      layers: [
        DrawingLayer(
          id: 'l1',
          name: 'Capa 1',
          strokes: [
            Stroke(tool: ToolType.fountain, color: 0xFFB3261E, size: 5, points: [
              for (var i = 0; i <= 60; i++)
                StrokePoint(120 + i * 6.0, 520 + 30 * (i % 20 < 10 ? i % 10 : 10 - i % 10) / 10, 0.5),
            ]),
          ],
          items: const [
            TextItem(
              id: 't1',
              x: 500,
              y: 160,
              text: 'Mi diario de estudio',
              font: 'Dancing Script',
              size: 72,
              color: 0xFF4E8C7A,
              width: 900,
              align: TextItemAlign.center,
            ),
            StickerItem(id: 's1', x: 260, y: 360, sticker: 'memo_yellow', width: 220, height: 220),
            StickerItem(id: 's2', x: 760, y: 380, sticker: 'memo_heart', width: 220, height: 200),
            StickerItem(id: 's3', x: 820, y: 1180, sticker: 'cactus', width: 180, height: 220),
            StickerItem(id: 's4', x: 180, y: 1200, sticker: 'flower', width: 200, height: 200),
            StickerItem(id: 's5', x: 500, y: 760, sticker: 'tape_pink', width: 260, height: 56),
            TextItem(id: 't2', x: 500, y: 860, text: 'Lunes', font: 'Pacifico', size: 64, color: 0xFFE38B3C),
            ShapeItem(id: 'sh1', x: 500, y: 1010, shape: ShapeKind.star, width: 160, height: 160,
                color: 0xFFE0A000, fill: 0x59E0A000),
          ],
        ),
      ],
    );

class _FakeStore extends DrawingStore {
  @override
  Future<Drawing> load(String path) async => switch (path) {
        'cover' => const NewNoteOptions(
                title: 'Biología', withSheet: true, paper: PaperStyle(), landscape: false)
            .coverPage(),
        'p2' => Drawing.blank(paper: const PaperStyle(template: PaperTemplate.dailyPlan))
            .copyWith(tab: 'Tareas', tabColor: 0xFFE8C17A),
        'p3' => Drawing.blank(paper: const PaperStyle(template: PaperTemplate.cornell))
            .copyWith(tab: 'Clase 2', tabColor: 0xFFE59C8B),
        _ => _samplePage().copyWith(tab: 'Diario', tabColor: 0xFF8FB3C6),
      };

  @override
  Future<void> save(String path, Drawing drawing) async {}
}

final _notebooks = [
  const Notebook(id: '1', name: 'Diario', color: 0xFFFFC8DD,
      style: CoverStyle(pattern: CoverPattern.gingham, sticker: 'cat:orange')),
  const Notebook(id: '2', name: 'Universidad', color: 0xFFBDE0FE,
      style: CoverStyle(pattern: CoverPattern.clouds, sticker: 'cat:gray')),
  const Notebook(id: '3', name: 'Recetas', color: 0xFFFFD6A5,
      style: CoverStyle(pattern: CoverPattern.dots, sticker: '')),
];

Widget _app(Widget home, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: _theme(), home: home),
    );

void main() {
  setUpAll(_loadFonts);

  testWidgets('inicio', (tester) async {
    await _phoneSize(tester);
    await tester.pumpWidget(_app(HomeView(
      notebooks: _notebooks,
      counts: const {'1': 12, '2': 30, '3': 4},
      notesCount: 46,
      onOpenNotebook: (_) {},
      onNotebookOptions: (_) {},
      onNewNotebook: () {},
      onAllNotes: () {},
      onSearch: () {},
      onSettings: () {},
      onAdd: () {},
      onExpenses: () {},
    )));
    await _shot(tester, '01_inicio');
  });

  testWidgets('inicio en carrusel', (tester) async {
    await _phoneSize(tester);
    await tester.pumpWidget(_app(HomeView(
      notebooks: _notebooks,
      counts: const {'1': 12, '2': 30, '3': 4},
      notesCount: 46,
      onOpenNotebook: (_) {},
      onNotebookOptions: (_) {},
      onNewNotebook: () {},
      onAllNotes: () {},
      onSearch: () {},
      onSettings: () {},
      onAdd: () {},
    )));
    await tester.tap(find.byIcon(Icons.view_carousel));
    await _shot(tester, '02_inicio_carrusel');
  });

  testWidgets('crear nota', (tester) async {
    await _phoneSize(tester);
    await tester.pumpWidget(_app(const Scaffold(
      backgroundColor: Color(0xFFF3F4F6),
      body: CreateNoteForm(),
    )));
    await _shot(tester, '03_crear_nota');
    await tester.tap(find.text('Elegir tapa').first);
    await _shot(tester, '04_crear_nota_tapas');
  });

  Future<void> openDrawing(WidgetTester tester, {String path = 'p1'}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _phoneSize(tester);
    await tester.pumpWidget(_app(
      DrawingScreen(noteId: 'n1', path: path),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        drawingStoreProvider.overrideWithValue(_FakeStore()),
        blocksProvider.overrideWith((ref, id) => Stream.value(const [
              DrawingBlock(id: 'b0', position: 0, path: 'cover'),
              DrawingBlock(id: 'b1', position: 1, path: 'p1'),
            ])),
      ],
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('hoja', (tester) async {
    await openDrawing(tester);
    await _shot(tester, '05_hoja');
  });

  testWidgets('tapa', (tester) async {
    await openDrawing(tester, path: 'cover');
    await _shot(tester, '06_tapa');
  });

  testWidgets('panel de plumas', (tester) async {
    await openDrawing(tester);
    await tester.tap(find.byTooltip('Bolígrafo')); // ya elegida: abre el panel
    await tester.pump();
    await tester.tap(find.byTooltip('Pluma estilográfica'));
    await _shot(tester, '07_plumas');
  });

  testWidgets('panel de formas', (tester) async {
    await openDrawing(tester);
    await tester.tap(find.text('Insertar'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Formas').last);
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, '08_formas');
  });

  for (final (i, tab) in ['Básico', 'Memo', 'Texto', 'Natural'].indexed) {
    testWidgets('stickers $tab', (tester) async {
      await openDrawing(tester);
      await tester.tap(find.text('Insertar'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Stickers').last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.tap(find.text(tab).last);
      await _shot(tester, '${(9 + i).toString().padLeft(2, '0')}_stickers_${tab.toLowerCase()}');
    });
  }

  testWidgets('editor de texto', (tester) async {
    await openDrawing(tester);
    await tester.tap(find.byTooltip('Texto: toca la hoja para escribir'));
    await tester.pump();
    await tester.tapAt(const Offset(200, 600));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField).last, 'Hoy aprendí algo nuevo ✨');
    await _shot(tester, '13_texto');
  });

  Future<void> openBook(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _phoneSize(tester);
    final now = DateTime(2026, 11, 25);
    await tester.pumpWidget(_app(
      const BookViewScreen(noteId: 'n1', initialPage: 1),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        drawingStoreProvider.overrideWithValue(_FakeStore()),
        noteProvider.overrideWith((ref, id) => Stream.value(
            Note(id: 'n1', title: 'Biología', createdAt: now, updatedAt: now))),
        blocksProvider.overrideWith((ref, id) => Stream.value(const [
              DrawingBlock(id: 'b0', position: 0, path: 'cover'),
              DrawingBlock(id: 'b1', position: 1, path: 'p1'),
              DrawingBlock(id: 'b2', position: 2, path: 'p2'),
              DrawingBlock(id: 'b3', position: 3, path: 'p3'),
            ])),
      ],
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('cuaderno para hojear', (tester) async {
    await openBook(tester);
    await _shot(tester, '14_cuaderno');
  });

  testWidgets('hojeando', (tester) async {
    await openBook(tester);
    final g = await tester.startGesture(const Offset(330, 420));
    await g.moveBy(const Offset(-30, 0));
    await tester.pump();
    await g.moveBy(const Offset(-110, 0));
    await tester.pump();
    await _shot(tester, '15_hojeando');
    await g.up();
    await tester.pump(const Duration(seconds: 1));
  });

  Future<void> openBookDesktop(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 11, 25);
    await tester.pumpWidget(_app(
      const BookViewScreen(noteId: 'n1'),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        drawingStoreProvider.overrideWithValue(_FakeStore()),
        noteProvider.overrideWith((ref, id) => Stream.value(
            Note(id: 'n1', title: 'Biología', createdAt: now, updatedAt: now))),
        blocksProvider.overrideWith((ref, id) => Stream.value(const [
              DrawingBlock(id: 'b0', position: 0, path: 'cover'),
              DrawingBlock(id: 'b1', position: 1, path: 'p1'),
              DrawingBlock(id: 'b2', position: 2, path: 'p2'),
              DrawingBlock(id: 'b3', position: 3, path: 'p3'),
              DrawingBlock(id: 'b4', position: 4, path: 'p4'),
            ])),
      ],
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('cuaderno abierto en la compu (dos hojas)', (tester) async {
    await openBookDesktop(tester);
    // Se abre directo en las hojas 2 y 3, no en la tapa.
    expect(find.text('2–3 / 5'), findsOneWidget);
    await _shot(tester, '14b_cuaderno_compu');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('hojeando en la compu', (tester) async {
    await openBookDesktop(tester);
    final g = await tester.startGesture(const Offset(900, 380));
    await g.moveBy(const Offset(-30, 0));
    await tester.pump();
    await g.moveBy(const Offset(-260, 0));
    await tester.pump();
    await _shot(tester, '15b_hojeando_compu');
    await g.up();
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('gastos', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _phoneSize(tester);
    await tester.pumpWidget(_app(
      const ExpensesScreen(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        expensesRepositoryProvider.overrideWithValue(_FakeExpenses()),
      ],
    ));
    await tester.pump(const Duration(milliseconds: 200));
    await _shot(tester, '16_gastos');
  });

  testWidgets('stickers gatitos', (tester) async {
    await openDrawing(tester);
    await tester.tap(find.text('Insertar'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Stickers').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.tap(find.text('Gatitos').last);
    await _shot(tester, '18_stickers_gatitos');
  });

  Future<void> openJournal(WidgetTester tester) async {
    final now = DateTime.now();
    var st = const JournalState(habits: [
      Habit(id: 'h1', name: 'Tomar agua', emoji: '💧'),
      Habit(id: 'h2', name: 'Leer', emoji: '📚'),
      Habit(id: 'h3', name: 'Repasar', emoji: '✍️'),
    ]);
    for (var i = 0; i < 14; i++) {
      final d = DateTime(now.year, now.month, now.day - i);
      if (d.month != now.month) break;
      st = st.setDay(d, DayEntry(mood: Mood.values[i % 4], text: i == 0 ? 'Terminé el resumen de biología 🎉' : ''));
      if (i % 3 != 2) st = st.toggle('h1', d);
      if (i.isEven) st = st.toggle('h2', d);
    }
    SharedPreferences.setMockInitialValues({'journal.data': st.encode()});
    final prefs = await SharedPreferences.getInstance();
    await _phoneSize(tester);
    await tester.pumpWidget(_app(
      const JournalScreen(),
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    ));
    await tester.pump();
  }

  testWidgets('diario', (tester) async {
    await openJournal(tester);
    await _shot(tester, '19_diario');
  });

  testWidgets('hábitos', (tester) async {
    await openJournal(tester);
    await tester.tap(find.text('Hábitos'));
    await tester.pumpAndSettle();
    await _shot(tester, '20_habitos');
  });

  testWidgets('estudio', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _phoneSize(tester);
    final now = DateTime.now();
    await tester.pumpWidget(_app(
      const StudyScreen(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        flashcardsProvider.overrideWith((ref) => Stream.value([
              Flashcard(id: '1', front: '¿Qué es la mitosis?', back: 'División celular que da dos células iguales.', due: now),
              Flashcard(id: '2', front: 'Fases de la mitosis', back: 'Profase, metafase, anafase y telofase.', due: now),
              Flashcard(id: '3', front: 'Capital de Bolivia', back: 'Sucre (sede de gobierno: La Paz)', due: now.add(const Duration(days: 3))),
            ])),
      ],
    ));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('¿Qué es la mitosis?'));
    await tester.pump();
    await _shot(tester, '21_estudio');
  });

  Future<void> openPlanner(WidgetTester tester, Widget screen) async {
    final now = DateTime.now();
    final st = PlannerState(
      classes: const [
        ClassSlot(id: '1', subject: 'Biología', weekday: 1, start: 8 * 60, end: 10 * 60, room: 'A-12', color: 0xFFB8E0D2),
        ClassSlot(id: '2', subject: 'Química', weekday: 2, start: 10 * 60, end: 12 * 60, color: 0xFFF9D5A7),
        ClassSlot(id: '3', subject: 'Cálculo', weekday: 3, start: 8 * 60, end: 9 * 60 + 30, color: 0xFFA7C7E7),
        ClassSlot(id: '4', subject: 'Inglés', weekday: 4, start: 14 * 60, end: 16 * 60, color: 0xFFD5B8F0),
        ClassSlot(id: '5', subject: 'Biología', weekday: 5, start: 8 * 60, end: 10 * 60, room: 'Lab 3', color: 0xFFB8E0D2),
        ClassSlot(id: '6', subject: 'Historia', weekday: 3, start: 15 * 60, end: 17 * 60, color: 0xFFF4A7B9),
      ],
      reminders: [
        Reminder(id: 'a', title: 'Parcial de Biología', subject: 'Biología', due: now.add(const Duration(days: 1, hours: 2))),
        Reminder(id: 'b', title: 'Informe de laboratorio', kind: ReminderKind.homework, subject: 'Química', due: now.add(const Duration(days: 5))),
        Reminder(id: 'c', title: 'Exposición', kind: ReminderKind.homework, subject: 'Historia', due: now.add(const Duration(days: 16))),
        Reminder(id: 'd', title: 'Práctica 2', kind: ReminderKind.homework, due: now.subtract(const Duration(days: 2)), done: true),
      ],
    );
    SharedPreferences.setMockInitialValues({'planner.data': st.encode()});
    final prefs = await SharedPreferences.getInstance();
    await _phoneSize(tester);
    await tester.pumpWidget(_app(screen, overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notebooksProvider.overrideWith((ref) => Stream.value(const [])),
    ]));
    await tester.pump();
  }

  testWidgets('horario', (tester) async {
    await openPlanner(tester, const PlannerScreen());
    await _shot(tester, '22_horario');
  });

  testWidgets('pendientes', (tester) async {
    await openPlanner(tester, const PlannerScreen(initialTab: 1));
    await _shot(tester, '23_pendientes');
  });

  testWidgets('modo examen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _phoneSize(tester);
    final now = DateTime.now();
    await tester.pumpWidget(_app(
      const ExamScreen(seed: 3),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        flashcardsProvider.overrideWith((ref) => Stream.value([
              Flashcard(id: '1', front: '¿Qué orgánulo produce energía en la célula?', back: 'La mitocondria', due: now),
              Flashcard(id: '2', front: 'Capital de Bolivia', back: 'Sucre', due: now),
              Flashcard(id: '3', front: '¿Qué es la mitosis?', back: 'División celular en dos células iguales', due: now),
              Flashcard(id: '4', front: 'Fórmula del agua', back: 'H₂O', due: now),
              Flashcard(id: '5', front: 'Autor de "Raza de bronce"', back: 'Alcides Arguedas', due: now),
            ])),
      ],
    ));
    await tester.pump();
    await tester.pump();
    await _shot(tester, '24_examen');
  });

  testWidgets('gastos del mes con presupuesto', (tester) async {
    SharedPreferences.setMockInitialValues({
      'expenses.budgets': '{"Carne":100,"Verduras":80,"Frutas":50}',
      'expenses.shopping': '[{"id":"1","n":"Leche","c":"Lácteos"},{"id":"2","n":"Arroz","c":"Abarrotes"}]',
    });
    final prefs = await SharedPreferences.getInstance();
    await _phoneSize(tester);
    await tester.pumpWidget(_app(
      const ExpensesScreen(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        expensesRepositoryProvider.overrideWithValue(_FakeExpenses()),
      ],
    ));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Mes'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pump(const Duration(milliseconds: 200));
    await _shot(tester, '25_gastos_mes');
  });

  testWidgets('gastos: nuevo gasto con categorías doodle', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await _phoneSize(tester);
    await tester.pumpWidget(_app(
      const ExpensesScreen(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        expensesRepositoryProvider.overrideWithValue(_FakeExpenses()),
      ],
    ));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '26_gastos_categorias');
  });

  testWidgets('stickers doodles', (tester) async {
    await openDrawing(tester);
    await tester.tap(find.text('Insertar'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Stickers').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.tap(find.text('Doodles').last);
    await _shot(tester, '26_doodles');
  });

  testWidgets('insertar', (tester) async {
    await openDrawing(tester);
    await tester.tap(find.text('Insertar'));
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, '27_insertar');
  });

  testWidgets('portadas nuevas', (tester) async {
    await _phoneSize(tester);
    await tester.pumpWidget(_app(Scaffold(
      body: Center(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final p in [CoverPattern.sageFlowers, CoverPattern.blueTrellis, CoverPattern.tulipChecker, CoverPattern.starryCat])
              NotebookCover(
                name: 'Notebook',
                color: p.preferredColor!,
                style: CoverStyle(pattern: p, sticker: ''),
                width: 170,
              ),
          ],
        ),
      ),
    )));
    await _shot(tester, '17_portadas');
  });
}

class _FakeExpenses implements ExpensesRepository {
  @override
  Stream<List<Expense>> watchRange(DateTime from, DateTime to) {
    final mon = from;
    final n = DateTime.now();
    // El mes anterior gastó algo distinto (para la comparación).
    final k = from.isBefore(DateTime(n.year, n.month, 1)) ? 0.8 : 1.0;
    Expense e(int d, String c, double a, String t) =>
        Expense(id: '$d$c$t', day: mon.add(Duration(days: d)), category: c, amount: a * k, description: t);
    return Stream.value([
      e(0, 'Pasaje', 5, 'Micro a la U'),
      e(0, 'Fotocopias', 3.5, 'Apuntes de cálculo'),
      e(1, 'Almuerzo', 15, 'Almuerzo en el comedor'),
      e(0, 'Verduras', 12, 'Tomate y cebolla'),
      e(0, 'Carne', 45, 'Pollo'),
      e(1, 'Frutas', 18.5, 'Plátanos y manzanas'),
      e(2, 'Lácteos', 14, 'Leche y queso'),
      e(3, 'Verduras', 9, 'Lechuga'),
      e(4, 'Carne', 60, 'Carne molida'),
      e(5, 'Pan', 6, 'Marraquetas'),
    ].where((x) => !x.day.isBefore(from) && x.day.isBefore(to)).toList());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
