import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/fonts.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/cat_mascot.dart';
import '../../importing/import_service.dart';
import '../../notes/presentation/notes_list_screen.dart';
import '../../notes/presentation/notes_search_delegate.dart';
import '../domain/notebook.dart';
import 'notebook_form.dart';

/// Colores del inicio (cálidos, tipo diario ilustrado).
class HomeColors {
  static const cream = Color(0xFFFFF8EC);
  static const paper = Color(0xFFFFFDF7);
  static const peach = Color(0xFFFCE3CF);
  static const orange = Color(0xFFF39A6B);
  static const orangeDark = Color(0xFFE07B4C);
  static const border = Color(0xFFF2B48F);
  static const ink = Color(0xFF4A3B33);
}

/// Pantalla de inicio: estantería de cuadernos en carrusel (o cuadrícula),
/// accesos rápidos y los gatitos.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooks = ref.watch(notebooksProvider).valueOrNull;
    final counts = ref.watch(notebookCountsProvider).valueOrNull ?? const {};
    final notesCount = ref.watch(notesListProvider(null)).valueOrNull?.length ?? 0;

    return HomeView(
      notebooks: notebooks,
      counts: counts,
      notesCount: notesCount,
      onOpenNotebook: (nb) => context.push('/notebooks/${nb.id}'),
      onNotebookOptions: (nb) => _options(context, ref, nb),
      onNewNotebook: () => _create(context, ref),
      onAllNotes: () => context.push('/notebooks/all'),
      onSearch: () => showSearch(context: context, delegate: NotesSearchDelegate(ref)),
      onSettings: () => context.push('/settings'),
      onAdd: () => _addMenu(context, ref),
    );
  }

  Future<void> _addMenu(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: HomeColors.paper,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note, color: HomeColors.orangeDark),
              title: const Text('Nueva nota'),
              subtitle: const Text('Elige tapa y hoja'),
              onTap: () => Navigator.pop(context, 'note'),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined, color: HomeColors.orangeDark),
              title: const Text('Nuevo cuaderno'),
              subtitle: const Text('Para agrupar tus notas'),
              onTap: () => Navigator.pop(context, 'notebook'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: HomeColors.orangeDark),
              title: const Text('Importar PDF'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'note':
        await createNoteFlow(context, ref);
      case 'notebook':
        await _create(context, ref);
      case 'pdf':
        final service = ref.read(importServiceProvider);
        final pdf = await service.pickPdf();
        if (pdf == null || !context.mounted) return;
        final id = await runWithProgress(
            context, 'Importando PDF', (p) => service.importPdfAsNewNote(pdf, onProgress: p));
        if (id != null && context.mounted) context.push('/notes/$id');
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final r = await showNotebookForm(
      context,
      pickCover: ref.read(cameraServiceProvider).pickImageFromGallery,
    );
    if (r == null) return;
    await ref
        .read(notebooksRepositoryProvider)
        .create(r.name, color: r.color, coverPath: r.coverPath, style: r.style);
  }

  Future<void> _options(BuildContext context, WidgetRef ref, Notebook nb) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar nombre, color o portada'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Eliminar cuaderno'),
              subtitle: const Text('Las notas no se borran: quedan en "Todas las notas"'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    final repo = ref.read(notebooksRepositoryProvider);
    if (action == 'edit') {
      final r = await showNotebookForm(
        context,
        initial: nb,
        pickCover: ref.read(cameraServiceProvider).pickImageFromGallery,
      );
      if (r != null) {
        await repo.update(nb.id, name: r.name, color: r.color, coverPath: r.coverPath, style: r.style);
      }
    } else if (action == 'delete') {
      await repo.delete(nb.id);
    }
  }
}

/// El inicio sin depender de la base de datos (también se usa para las
/// capturas de pantalla automáticas).
class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.notebooks,
    required this.counts,
    required this.notesCount,
    required this.onOpenNotebook,
    required this.onNotebookOptions,
    required this.onNewNotebook,
    required this.onAllNotes,
    required this.onSearch,
    required this.onSettings,
    required this.onAdd,
  });

  /// null = cargando.
  final List<Notebook>? notebooks;
  final Map<String, int> counts;
  final int notesCount;
  final ValueChanged<Notebook> onOpenNotebook;
  final ValueChanged<Notebook> onNotebookOptions;
  final VoidCallback onNewNotebook;
  final VoidCallback onAllNotes;
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final VoidCallback onAdd;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  bool _grid = false;
  int _phrase = 0;
  final _page = PageController(viewportFraction: 0.64);

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.notebooks;
    final title = fontStyle('Pacifico', size: 26).copyWith(color: HomeColors.ink);

    return Scaffold(
      backgroundColor: HomeColors.cream,
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _SkyPainter())),
          SafeArea(
            child: Column(
              children: [
                // Encabezado
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('Mis cuadernos', style: title)),
                      IconButton(
                        tooltip: 'Buscar (también dentro de los audios)',
                        icon: const Icon(Icons.search, color: HomeColors.ink),
                        onPressed: widget.onSearch,
                      ),
                      IconButton(
                        tooltip: 'Ajustes',
                        icon: const Icon(Icons.settings_outlined, color: HomeColors.ink),
                        onPressed: widget.onSettings,
                      ),
                    ],
                  ),
                ),
                // Panel principal
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                    decoration: BoxDecoration(
                      color: HomeColors.paper,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      border: Border.all(color: HomeColors.border, width: 2),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
                          child: Row(
                            children: [
                              _Tab(
                                label: 'Cuadernos·${list?.length ?? 0}',
                                selected: true,
                                onTap: () {},
                              ),
                              const SizedBox(width: 6),
                              _Tab(
                                label: 'Notas·${widget.notesCount}',
                                selected: false,
                                onTap: widget.onAllNotes,
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: _grid ? 'Ver en carrusel' : 'Ver en cuadrícula',
                                icon: Icon(_grid ? Icons.view_carousel_outlined : Icons.grid_view,
                                    color: HomeColors.orangeDark),
                                onPressed: () => setState(() => _grid = !_grid),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: list == null
                              ? const Center(child: CircularProgressIndicator())
                              : _grid
                                  ? _gridView(list)
                                  : _carousel(list),
                        ),
                        _quickRow(),
                        const SizedBox(height: 8),
                        _cats(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _carousel(List<Notebook> list) {
    return LayoutBuilder(
      builder: (context, c) {
        final cardW = math.min(c.maxWidth * 0.58, (c.maxHeight - 20) / 1.4);
        return PageView.builder(
          controller: _page,
          padEnds: false,
          itemCount: list.length + 1,
          itemBuilder: (context, i) => Padding(
            padding: EdgeInsets.only(left: i == 0 ? 18 : 6, right: 6, top: 4, bottom: 8),
            child: Align(
              alignment: Alignment.topLeft,
              child: i == list.length
                  ? _NewNotebookCard(width: cardW, onTap: widget.onNewNotebook)
                  : _NotebookCard(
                      notebook: list[i],
                      count: widget.counts[list[i].id] ?? 0,
                      width: cardW,
                      onTap: () => widget.onOpenNotebook(list[i]),
                      onOptions: () => widget.onNotebookOptions(list[i]),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _gridView(List<Notebook> list) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 170,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.7,
        ),
        itemCount: list.length + 1,
        itemBuilder: (context, i) => LayoutBuilder(
          builder: (context, c) => i == list.length
              ? _NewNotebookCard(width: c.maxWidth, onTap: widget.onNewNotebook)
              : _NotebookCard(
                  notebook: list[i],
                  count: widget.counts[list[i].id] ?? 0,
                  width: c.maxWidth,
                  compact: true,
                  onTap: () => widget.onOpenNotebook(list[i]),
                  onOptions: () => widget.onNotebookOptions(list[i]),
                ),
        ),
      );

  Widget _quickRow() {
    Widget quick(IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(height: 4),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: HomeColors.ink)),
                ],
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: HomeColors.peach.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: HomeColors.border, width: 1.5),
              ),
              child: Row(
                children: [
                  quick(Icons.notes, 'Todas', const Color(0xFFF2A0A8), widget.onAllNotes),
                  quick(Icons.search, 'Buscar', const Color(0xFF8DBFE0), widget.onSearch),
                  quick(Icons.menu_book_outlined, 'Cuaderno', const Color(0xFFA5CF8E),
                      widget.onNewNotebook),
                  quick(Icons.tune, 'Ajustes', const Color(0xFFF0C26E), widget.onSettings),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: HomeColors.orange,
            borderRadius: BorderRadius.circular(22),
            elevation: 3,
            shadowColor: HomeColors.orangeDark,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: widget.onAdd,
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: HomeColors.orangeDark, width: 2),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 44),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Colinas con los gatitos y su globo de diálogo.
  Widget _cats() {
    return SizedBox(
      height: 132,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(child: CustomPaint(painter: _HillsPainter())),
          Positioned(
            left: 18,
            bottom: 10,
            child: AnimatedCatMascot(
              kind: CatKind.gray,
              size: 72,
              onTap: () => setState(() => _phrase++),
            ),
          ),
          Positioned(
            right: 20,
            bottom: 12,
            child: AnimatedCatMascot(
              kind: CatKind.orange,
              size: 86,
              onTap: () => setState(() => _phrase++),
            ),
          ),
          Positioned(
            left: 100,
            right: 116,
            top: 14,
            child: _Bubble(text: catPhrases[_phrase % catPhrases.length]),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? HomeColors.peach : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label, style: const TextStyle(fontSize: 17, color: HomeColors.ink)),
        ),
      );
}

class _NotebookCard extends StatelessWidget {
  const _NotebookCard({
    required this.notebook,
    required this.count,
    required this.width,
    required this.onTap,
    required this.onOptions,
    this.compact = false,
  });

  final Notebook notebook;
  final int count;
  final double width;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final coverW = width - 12;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onOptions,
      child: SizedBox(
        width: width,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Marco con borde punteado, como un álbum.
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: HomeColors.peach,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: HomeColors.border, width: 2),
                boxShadow: const [BoxShadow(blurRadius: 6, offset: Offset(2, 4), color: Color(0x22E07B4C))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: NotebookCover(
                  name: notebook.name,
                  color: notebook.color,
                  coverPath: notebook.coverPath,
                  style: notebook.style,
                  width: coverW,
                  showLabel: compact,
                ),
              ),
            ),
            if (!compact)
              Positioned(
                left: -8,
                right: -8,
                bottom: coverW * 0.18,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: HomeColors.border, width: 2),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              notebook.name.isEmpty ? 'Sin nombre' : notebook.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, color: HomeColors.ink),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              count == 1 ? '1 nota' : '$count notas',
                              style: const TextStyle(fontSize: 13, color: Colors.black45),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Opciones',
                        icon: const Icon(Icons.settings_outlined, color: HomeColors.ink),
                        onPressed: onOptions,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NewNotebookCard extends StatelessWidget {
  const _NewNotebookCard({required this.width, required this.onTap});
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: (width - 12) * 1.35 + 12,
          decoration: BoxDecoration(
            color: const Color(0xFFF6F2EA),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE3D9C8), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.add, color: HomeColors.orangeDark, size: 30),
              ),
              const SizedBox(height: 12),
              const Text('Nuevo cuaderno', style: TextStyle(color: HomeColors.ink, fontSize: 15)),
            ],
          ),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Container(
          key: ValueKey(text),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF9DB58A), width: 1.5),
          ),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF5E6B52))),
        ),
      );
}

/// Nubecitas y confeti suave de fondo.
class _SkyPainter extends CustomPainter {
  const _SkyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.85);
    void puff(Offset c, double r) {
      canvas.drawCircle(c, r, cloud);
      canvas.drawCircle(c + Offset(r * 0.9, r * 0.2), r * 0.8, cloud);
      canvas.drawCircle(c + Offset(-r * 0.9, r * 0.25), r * 0.7, cloud);
    }

    puff(Offset(size.width * 0.78, 30), 18);
    puff(Offset(size.width * 0.12, 70), 12);
    final dot = Paint()..color = const Color(0xFFF2C27A).withValues(alpha: 0.7);
    final rnd = math.Random(5);
    for (var i = 0; i < 14; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(rnd.nextDouble() * size.width, size.height * (0.55 + rnd.nextDouble() * 0.3)),
          width: 7,
          height: 5,
        ),
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => false;
}

/// Colinas verdes y arbustos al pie del inicio.
class _HillsPainter extends CustomPainter {
  const _HillsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final back = Path()
      ..moveTo(0, h * 0.62)
      ..quadraticBezierTo(w * 0.25, h * 0.38, w * 0.5, h * 0.6)
      ..quadraticBezierTo(w * 0.78, h * 0.32, w, h * 0.5)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFFDCEBC8));
    final front = Path()..moveTo(0, h * 0.82);
    // Arbustos con bordes redondeados.
    var x = 0.0;
    final rnd = math.Random(2);
    while (x < w) {
      final r = 16 + rnd.nextDouble() * 14;
      front.arcToPoint(Offset(x + r * 2, h * 0.82), radius: Radius.circular(r));
      x += r * 2;
    }
    front
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFFBFDBA6));
    canvas.drawPath(
        front,
        Paint()
          ..color = const Color(0xFF9DBF84)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_HillsPainter old) => false;
}
