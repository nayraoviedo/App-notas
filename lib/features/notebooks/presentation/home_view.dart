import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/fonts.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/cat_mascot.dart';
import '../domain/notebook.dart';
import 'notebook_form.dart';

/// Colores del inicio (cálidos, tipo diario).
class HomeColors {
  static const cream = Color(0xFFFFF9EE);
  static const header = Color(0xFFFCF0DF);
  static const panel = Colors.white;
  static const terracotta = Color(0xFFE07B55);
  static const terracottaDark = Color(0xFF8A3B22);
  static const brown = Color(0xFF6B3A1E);
  static const yellow = Color(0xFFF6C744);
  static const ink = Color(0xFF3B2A22);
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
    this.onCatOptions,
    this.onExpenses,
    this.onStudy,
    this.onJournal,
    this.onPlanner,
    this.greeting,
  });

  /// Horario de clases y pendientes.
  final VoidCallback? onPlanner;

  /// Lo primero que dicen los gatitos al abrir (saludo, aviso de examen…).
  final String? greeting;

  /// Tarjetas de repaso y "pregúntale a tus notas".
  final VoidCallback? onStudy;

  /// Calendario de ánimos y hábitos.
  final VoidCallback? onJournal;

  /// Abrir el cuaderno fijo "Gastos".
  final VoidCallback? onExpenses;

  /// Mantener presionado un gatito: cambiar su foto o su nombre.
  final void Function(CatKind kind)? onCatOptions;

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
  bool _carousel = false;
  int _phrase = 0;
  bool _talking = false;
  CatKind _speaker = CatKind.orange;
  final _page = PageController(viewportFraction: 0.7);

  @override
  void initState() {
    super.initState();
    if (widget.greeting != null) {
      _greetingText = widget.greeting;
      _talking = true;
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) setState(() => _talking = false);
      });
    }
  }

  /// Saludo inicial (se reemplaza por frases al tocar un gatito).
  String? _greetingText;

  bool get _night {
    final h = DateTime.now().hour;
    return h >= 23 || h < 5;
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _meow(CatKind who) {
    setState(() {
      _greetingText = null;
      _speaker = who;
      _phrase++;
      _talking = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _talking = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.notebooks;
    // El inicio conserva su estilo crema de diario también en modo oscuro.
    final t = Theme.of(context);
    return Theme(
      data: t.brightness == Brightness.light ? t : AppTheme.light(),
      child: _scaffold(list),
    );
  }

  Widget _scaffold(List<Notebook>? list) {
    return Scaffold(
      backgroundColor: HomeColors.cream,
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: HomeColors.panel,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: list == null
                        ? const Center(child: CircularProgressIndicator())
                        : _carousel
                            ? _carouselView(list)
                            : _gridView(list),
                  ),
                  Positioned(
                    right: 18,
                    bottom: 18,
                    child: Material(
                      color: HomeColors.brown,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 4,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: widget.onAdd,
                        child: const SizedBox(
                          width: 52,
                          height: 52,
                          child: Icon(Icons.add, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ Encabezado

  Widget _header(BuildContext context) {
    // Ilustración de los gatitos (assets/home/home_header.webp). Encima van
    // zonas táctiles invisibles sobre cada gatito y los botones.
    return Container(
      color: HomeColors.header,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              final h = w * 420 / 1062;
              Widget zone(CatKind kind, double l, double r) => Positioned(
                    left: w * l,
                    width: w * (r - l),
                    top: h * 0.24,
                    height: h * 0.55,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _meow(kind),
                      onLongPress: () => widget.onCatOptions?.call(kind),
                      child: ValueListenableBuilder(
                        valueListenable: catPhotos,
                        builder: (context, photos, _) => photos[kind] == null
                            ? const SizedBox.expand()
                            // Si pusiste la foto real, aparece en un marquito.
                            : Align(
                                alignment: Alignment.topRight,
                                child: CatMascot(kind: kind, size: h * 0.26),
                              ),
                      ),
                    ),
                  );
              return SizedBox(
                width: w,
                height: h,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Image.asset('assets/home/home_header.webp', fit: BoxFit.cover),
                    ),
                    zone(CatKind.gray, 0.2, 0.46),
                    zone(CatKind.orange, 0.53, 0.84),
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Buscar',
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
                    // Botón amarillo para cambiar de vista.
                    Positioned(
                      right: 12,
                      top: 10,
                      child: Material(
                        color: HomeColors.yellow,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() => _carousel = !_carousel),
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: Icon(Icons.swap_vert, size: 20, color: HomeColors.ink),
                          ),
                        ),
                      ),
                    ),
                    if (_talking)
                      Positioned(
                        top: _greetingText != null ? h * 0.06 : h * 0.2,
                        left: _greetingText != null ? w * 0.18 : (_speaker == CatKind.gray ? w * 0.04 : null),
                        right: _greetingText != null ? w * 0.18 : (_speaker == CatKind.orange ? w * 0.02 : null),
                        child: _Bubble(
                          text: _greetingText ??
                              [
                                if (catNames.value[_speaker] case final n?) '$n:',
                                _night
                                    ? 'Zzz… 😴 (estoy durmiendo)'
                                    : catPhrases[_phrase % catPhrases.length],
                              ].join(' '),
                        ),
                      ),
                    // De noche los gatitos duermen.
                    if (_night) ...[
                      Positioned(left: w * 0.36, top: h * 0.2, child: const _Zzz()),
                      Positioned(left: w * 0.72, top: h * 0.18, child: const _Zzz()),
                    ],
                  ],
                ),
              );
            }),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              // Indicador de vista: carrusel · cuadrícula.
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ViewDot(
                    icon: Icons.view_carousel,
                    selected: _carousel,
                    onTap: () => setState(() => _carousel = true),
                  ),
                  const SizedBox(width: 10),
                  _ViewDot(
                    icon: Icons.grid_view_rounded,
                    selected: !_carousel,
                    onTap: () => setState(() => _carousel = false),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- Vistas

  Widget _gridView(List<Notebook> list) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 90),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisSpacing: 18,
          crossAxisSpacing: 18,
          childAspectRatio: 0.62,
        ),
        itemCount: list.length + 1 + (widget.onExpenses == null ? 0 : 1),
        itemBuilder: (context, index) => LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            if (widget.onExpenses != null && index == 0) {
              return GestureDetector(
                onTap: widget.onExpenses,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BookCover(notebook: _expensesBook, width: w),
                    const SizedBox(height: 8),
                    const Text('Gastos', style: TextStyle(fontSize: 14, color: HomeColors.ink)),
                    const Text('Compras por categoría', style: TextStyle(fontSize: 11.5, color: Colors.black45)),
                  ],
                ),
              );
            }
            final i = index - (widget.onExpenses == null ? 0 : 1);
            if (i == list.length) {
              return _AddCard(width: w, height: w * 1.3, onTap: widget.onNewNotebook, small: true);
            }
            final nb = list[i];
            return GestureDetector(
              onTap: () => widget.onOpenNotebook(nb),
              onLongPress: () => widget.onNotebookOptions(nb),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BookCover(notebook: nb, width: w),
                  const SizedBox(height: 8),
                  Text(nb.name.isEmpty ? 'Sin nombre' : nb.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: HomeColors.ink)),
                  Text(_count(nb), style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
                ],
              ),
            );
          },
        ),
      );

  Widget _carouselView(List<Notebook> list) => LayoutBuilder(
        builder: (context, c) {
          final w = math.min(c.maxWidth * 0.62, (c.maxHeight - 120) / 1.32);
          final extra = widget.onExpenses == null ? 0 : 1;
          return PageView.builder(
            controller: _page,
            itemCount: list.length + 1 + extra,
            itemBuilder: (context, index) => index < extra
                ? Padding(
                    padding: const EdgeInsets.only(top: 26),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: widget.onExpenses,
                          child: BookCover(notebook: _expensesBook, width: w, big: true),
                        ),
                        const SizedBox(height: 14),
                        const Text('Gastos',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: HomeColors.ink)),
                        const Text('Compras por categoría', style: TextStyle(fontSize: 12.5, color: Colors.black45)),
                      ],
                    ),
                  )
                : Builder(builder: (context) {
                    final i = index - extra;
                    return Padding(
              padding: const EdgeInsets.only(top: 26),
              child: Column(
                children: [
                  if (i == list.length)
                    _AddCard(width: w, height: w * 1.32, onTap: widget.onNewNotebook)
                  else
                    GestureDetector(
                      onTap: () => widget.onOpenNotebook(list[i]),
                      onLongPress: () => widget.onNotebookOptions(list[i]),
                      child: BookCover(notebook: list[i], width: w, big: true),
                    ),
                  const SizedBox(height: 14),
                  if (i < list.length) ...[
                    Text(list[i].name.isEmpty ? 'Sin nombre' : list[i].name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: HomeColors.ink)),
                    Text(_count(list[i]), style: const TextStyle(fontSize: 12.5, color: Colors.black45)),
                  ],
                ],
              ),
            );
                  }),
          );
        },
      );

  String _count(Notebook nb) {
    final n = widget.counts[nb.id] ?? 0;
    return n == 1 ? '1 nota' : '$n notas';
  }

  // ----------------------------------------------------------- Barra inferior

  Widget _bottomBar() {
    Widget item(IconData icon, String label, bool selected, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 3,
                    margin: const EdgeInsets.only(bottom: 8),
                    color: selected ? HomeColors.ink : Colors.transparent,
                  ),
                  Icon(icon, color: selected ? HomeColors.terracotta : Colors.black54),
                  const SizedBox(height: 2),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: selected ? HomeColors.ink : Colors.black54,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                ],
              ),
            ),
          ),
        );
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x14000000)))),
          child: Row(
            children: [
              item(Icons.menu_book_rounded, 'Cuadernos', true, () {}),
              item(Icons.sticky_note_2_outlined, 'Notas·${widget.notesCount}', false, widget.onAllNotes),
              item(Icons.calendar_month_outlined, 'Semana', false, () => widget.onPlanner?.call()),
              item(Icons.school_outlined, 'Estudio', false, () => widget.onStudy?.call()),
              item(Icons.favorite_border, 'Diario', false, () => widget.onJournal?.call()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tapa del cuaderno fijo "Gastos".
const _expensesBook = Notebook(
  id: '__gastos',
  name: 'Gastos',
  color: 0xFFCDE5C0,
  style: CoverStyle(pattern: CoverPattern.gingham, sticker: '🧾', plate: 'GASTOS'),
);

/// Tapa de cuaderno tipo libro: lomo de color, dibujo, sticker y la etiqueta
/// "Pertenece a".
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.notebook, required this.width, this.big = false});
  final Notebook notebook;
  final double width;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final h = width * 1.32;
    final base = Color(notebook.color);
    final hsl = HSLColor.fromColor(base);
    final spine = hsl.withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0)).withSaturation(
        (hsl.saturation + 0.15).clamp(0.0, 1.0)).toColor();
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(blurRadius: 10, offset: Offset(3, 6), color: Color(0x33000000))],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(3), right: Radius.circular(8)),
        child: Stack(
          children: [
            NotebookCover(
              name: notebook.name,
              color: notebook.color,
              coverPath: notebook.coverPath,
              style: notebook.style,
              width: width,
              showLabel: notebook.style.hasPlate,
            ),
            // Lomo
            Positioned(left: 0, top: 0, bottom: 0, width: width * 0.075, child: ColoredBox(color: spine)),
            Positioned(
              left: width * 0.075,
              top: 0,
              bottom: 0,
              width: 2,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.12)),
            ),
            // Etiqueta "Pertenece a" (las portadas con placa ya llevan título)
            if (!(notebook.style.hasPlate && notebook.coverPath == null))
            Positioned(
              left: width * 0.2,
              right: width * 0.1,
              bottom: h * 0.08,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: big ? 8 : 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBF2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: HomeColors.ink.withValues(alpha: 0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Pertenece a',
                        style: fontStyle('Dancing Script', size: big ? 13 : 9)
                            .copyWith(color: HomeColors.ink.withValues(alpha: 0.7))),
                    Container(height: 1, color: HomeColors.ink.withValues(alpha: 0.35)),
                    const SizedBox(height: 2),
                    Text(
                      notebook.name.isEmpty ? 'Tu nombre aquí' : notebook.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: big ? 13 : 9.5, fontWeight: FontWeight.w600, color: HomeColors.ink),
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

class _AddCard extends StatelessWidget {
  const _AddCard({required this.width, required this.height, required this.onTap, this.small = false});
  final double width;
  final double height;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          painter: const _DashedRRect(),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xFFF6F4EF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: small ? 40 : 52,
                  height: small ? 40 : 52,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.add, color: HomeColors.terracottaDark),
                ),
                const SizedBox(height: 10),
                Text('Nuevo cuaderno',
                    style: TextStyle(fontSize: small ? 12 : 14, fontWeight: FontWeight.w600, color: HomeColors.ink)),
              ],
            ),
          ),
        ),
      );
}

class _DashedRRect extends CustomPainter {
  const _DashedRRect();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)));
    final p = Paint()
      ..color = const Color(0xFFCFC6B6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, d + 4), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) => false;
}

class _ViewDot extends StatelessWidget {
  const _ViewDot({required this.icon, required this.selected, required this.onTap});
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Icon(icon, size: 18, color: selected ? HomeColors.terracottaDark : Colors.black26),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HomeColors.terracotta, width: 1.4),
        ),
        child: Text(text,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: HomeColors.ink)),
      );
}


/// "z z Z" que sube y se desvanece sobre un gatito dormido.
class _Zzz extends StatefulWidget {
  const _Zzz();

  @override
  State<_Zzz> createState() => _ZzzState();
}

class _ZzzState extends State<_Zzz> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Opacity(
          opacity: 1 - _c.value,
          child: Transform.translate(
            offset: Offset(6 * _c.value, -14 * _c.value),
            child: const Text('z Z',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF6B5B95))),
          ),
        ),
      );
}
