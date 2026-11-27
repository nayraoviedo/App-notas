import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/platform_info.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/cat_mascot.dart';
import '../../settings/settings.dart';
import '../domain/planner.dart';
import 'planner_screen.dart';

/// Tinta que se lee bien encima de un color (los colores de las materias son
/// pastel: tinta café oscura; si alguno es oscuro, blanco).
Color inkOn(Color bg) =>
    ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? Colors.white : AppTheme.ink;

/// Cuántos días mostrar: de lunes a viernes, o hasta sábado/domingo si hay clases.
int _daysShown(List<ClassSlot> classes) => classes.any((c) => c.weekday == 7)
    ? 7
    : classes.any((c) => c.weekday == 6)
        ? 6
        : 5;

(int, int) _hourRange(List<ClassSlot> classes) {
  if (classes.isEmpty) return (7, 18);
  final minH = (classes.map((c) => c.start).reduce((a, b) => a < b ? a : b) ~/ 60).clamp(0, 7);
  final maxH = ((classes.map((c) => c.end).reduce((a, b) => a > b ? a : b) + 59) ~/ 60).clamp(18, 24);
  return (minH, maxH);
}

String _duration(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m';
}

// ============================================================ Vista semana

/// Cuadrícula de la semana (días en columnas, horas en filas). Se usa en la
/// pantalla y también para la imagen PNG.
class WeekGrid extends StatelessWidget {
  const WeekGrid({super.key, required this.classes, this.now, this.onTap, this.hourHeight = 64});

  final List<ClassSlot> classes;

  /// Para marcar el día de hoy y la hora actual (null en la imagen).
  final DateTime? now;
  final void Function(ClassSlot)? onTap;
  final double hourHeight;

  static const leftW = 46.0;
  static const headerH = 36.0;

  /// Alto total (cabecera + horas), para armar la imagen.
  static double heightFor(List<ClassSlot> classes, double hourHeight) {
    final (minH, maxH) = _hourRange(classes);
    return headerH + (maxH - minH) * hourHeight + 8;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days = _daysShown(classes);
    final (minH, maxH) = _hourRange(classes);
    final hourH = hourHeight;
    final todayCol = now != null && now!.weekday <= days ? now!.weekday : null;
    final nowMin = now == null ? null : now!.hour * 60 + now!.minute;
    final labelStyle = TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: headerH,
          child: Row(
            children: [
              const SizedBox(width: leftW),
              for (var d = 1; d <= days; d++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: d == todayCol
                        ? BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12))
                        : null,
                    child: Text(weekNames[d - 1].substring(0, 3),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: d == todayCol ? cs.onPrimary : cs.onSurface,
                        )),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: (maxH - minH) * hourH + 8,
          child: LayoutBuilder(builder: (context, c) {
            final colW = (c.maxWidth - leftW) / days;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Columna de hoy, apenas marcada.
                if (todayCol != null)
                  Positioned(
                    left: leftW + (todayCol - 1) * colW,
                    width: colW,
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                for (var h = minH; h <= maxH; h++) ...[
                  Positioned(
                    top: (h - minH) * hourH + 4 - 8,
                    left: 0,
                    width: leftW - 8,
                    child: Text('$h:00', textAlign: TextAlign.right, style: labelStyle),
                  ),
                  Positioned(
                    top: (h - minH) * hourH + 4,
                    left: leftW,
                    right: 0,
                    child: Container(height: 1, color: cs.outlineVariant),
                  ),
                  // Media hora, más suave.
                  if (h < maxH)
                    Positioned(
                      top: (h - minH + 0.5) * hourH + 4,
                      left: leftW,
                      right: 0,
                      child: Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.35)),
                    ),
                ],
                for (final cl in classes)
                  if (cl.weekday <= days)
                    Positioned(
                      left: leftW + (cl.weekday - 1) * colW + 2,
                      width: colW - 4,
                      top: (cl.start / 60 - minH) * hourH + 4 + 1,
                      height: ((cl.end - cl.start) / 60 * hourH - 2).clamp(20, 2000),
                      child: _ClassBlock(cl: cl, onTap: onTap == null ? null : () => onTap!(cl)),
                    ),
                // Línea de "ahora".
                if (todayCol != null && nowMin! >= minH * 60 && nowMin < maxH * 60)
                  Positioned(
                    left: leftW + (todayCol - 1) * colW - 3,
                    width: colW + 3,
                    top: (nowMin / 60 - minH) * hourH + 4 - 4,
                    height: 8,
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle),
                        ),
                        Expanded(child: Container(height: 2, color: cs.error)),
                      ],
                    ),
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

class _ClassBlock extends StatelessWidget {
  const _ClassBlock({required this.cl, this.onTap});
  final ClassSlot cl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = Color(cl.color);
    final ink = inkOn(bg);
    final edge = Color.lerp(bg, Colors.black, 0.25)!;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: edge, width: 3))),
          padding: const EdgeInsets.fromLTRB(5, 4, 4, 4),
          child: LayoutBuilder(builder: (context, c) {
            // Lo que entre: materia, luego aula, luego horas.
            final tall = c.maxHeight > 58;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(cl.subject,
                      maxLines: tall ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, height: 1.1, fontWeight: FontWeight.bold, color: ink)),
                ),
                if (cl.room.isNotEmpty && c.maxHeight > 40)
                  Text(cl.room,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: ink.withValues(alpha: 0.8))),
                if (tall)
                  Text('${hhmm(cl.start)}–${hhmm(cl.end)}',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(fontSize: 10.5, color: ink.withValues(alpha: 0.7))),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ============================================================ Imagen PNG

/// La cuadrícula de la semana como imagen PNG (siempre en tema claro, que se
/// lee mejor impresa o de fondo de pantalla).
Future<Uint8List> scheduleToPng(List<ClassSlot> classes, ThemeData theme, {double pixelRatio = 2.5}) async {
  const width = 760.0;
  const hourH = 60.0;
  const titleH = 64.0;
  const pad = 20.0;
  final height = pad + titleH + WeekGrid.heightFor(classes, hourH) + 34 + pad;
  final child = Container(
    color: theme.scaffoldBackgroundColor,
    padding: const EdgeInsets.all(pad),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: titleH,
          child: Row(
            children: [
              Text('Mi horario',
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Icon(Icons.pets, color: theme.colorScheme.primary, size: 28),
            ],
          ),
        ),
        WeekGrid(classes: classes, hourHeight: hourH),
        SizedBox(
          height: 34,
          child: Align(
            alignment: Alignment.bottomRight,
            child: Text('hecho con Kumo',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ),
        ),
      ],
    ),
  );
  return widgetToPng(
    MediaQuery(
      data: const MediaQueryData(),
      child: Theme(
        data: theme,
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium ?? const TextStyle(),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    ),
    Size(width, height),
    pixelRatio: pixelRatio,
  );
}

/// Dibuja un widget fuera de la pantalla y lo devuelve en PNG.
Future<Uint8List> widgetToPng(Widget widget, Size size, {double pixelRatio = 2.5}) async {
  final boundary = RenderRepaintBoundary();
  final view = WidgetsBinding.instance.platformDispatcher.implicitView ??
      WidgetsBinding.instance.platformDispatcher.views.first;
  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
    configuration: ViewConfiguration(logicalConstraints: BoxConstraints.tight(size), devicePixelRatio: 1),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final buildOwner = BuildOwner(focusManager: FocusManager());
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: Directionality(textDirection: TextDirection.ltr, child: SizedBox.fromSize(size: size, child: widget)),
  ).attachToRenderTree(buildOwner);
  buildOwner
    ..buildScope(root)
    ..finalizeTree();
  pipeline
    ..flushLayout()
    ..flushCompositingBits()
    ..flushPaint();
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Botón "Guardar como imagen": en el celular se comparte (y se puede guardar
/// en la galería); en la compu se elige dónde guardar el PNG.
Future<void> exportScheduleImage(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final theme = AppTheme.light(ref.read(appFontProvider));
    final png = await scheduleToPng(ref.read(plannerProvider).classes, theme);
    if (isDesktop) {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar horario',
        fileName: 'Mi horario.png',
        type: FileType.custom,
        allowedExtensions: const ['png'],
      );
      if (path == null) return;
      final out = path.toLowerCase().endsWith('.png') ? path : '$path.png';
      await File(out).writeAsBytes(png);
      messenger.showSnackBar(SnackBar(content: Text('Horario guardado en $out')));
    } else {
      final f = File('${(await getTemporaryDirectory()).path}/Mi horario.png');
      await f.writeAsBytes(png);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'image/png')]));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo guardar la imagen: $e')));
  }
}

// ============================================================ Vista día

const _months = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

/// Colores de los pendientes en la vista de día.
Color _reminderColor(ReminderKind k) => switch (k) {
      ReminderKind.exam => const Color(0xFFF7C6D3),
      ReminderKind.homework => const Color(0xFFFFE3A3),
      ReminderKind.other => const Color(0xFFCFE3F5),
    };

/// Un día a la vez: tira con los días de la semana y, debajo, tarjetas con
/// las clases y los pendientes de ese día en orden de hora.
class DayAgenda extends ConsumerStatefulWidget {
  const DayAgenda({super.key, required this.now, this.header});
  final DateTime now;
  final Widget? header;

  @override
  ConsumerState<DayAgenda> createState() => _DayAgendaState();
}

class _DayAgendaState extends ConsumerState<DayAgenda> {
  late DateTime _day = DateTime(widget.now.year, widget.now.month, widget.now.day);

  DateTime get _monday => _day.subtract(Duration(days: _day.weekday - 1));

  void _shiftWeek(int weeks) => setState(() => _day = DateTime(_day.year, _day.month, _day.day + 7 * weeks));

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(plannerProvider);
    final cs = Theme.of(context).colorScheme;
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final isToday = _day == today;
    final nowMin = widget.now.hour * 60 + widget.now.minute;

    // Clases y pendientes de ese día, por hora.
    final items = <(int, Widget)>[
      for (final c in st.classesOn(_day.weekday))
        (c.start, _ClassCard(c: c, live: isToday && c.start <= nowMin && nowMin < c.end)),
      for (final r in st.reminders)
        if (DateUtils.isSameDay(r.due, _day)) (r.due.hour * 60 + r.due.minute, _ReminderCard(r: r)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    final rows = <Widget>[];
    var nowShown = !isToday;
    for (final (min, card) in items) {
      if (!nowShown && min > nowMin) {
        rows.add(_NowMark(now: nowMin));
        nowShown = true;
      }
      rows.add(_TimeRow(minutes: min, child: card));
    }
    if (!nowShown && items.isNotEmpty) rows.add(_NowMark(now: nowMin));

    final m = _monday;
    final sunday = m.add(const Duration(days: 6));
    final monthLabel = m.month == sunday.month
        ? '${_months[m.month - 1]} ${m.year}'
        : '${_months[m.month - 1].substring(0, 3)} – ${_months[sunday.month - 1].substring(0, 3)} ${sunday.year}';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
          children: [
            if (widget.header != null) widget.header!,
            Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: Text(monthLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (!isToday)
                  TextButton(onPressed: () => setState(() => _day = today), child: const Text('Hoy')),
                IconButton(
                    tooltip: 'Semana anterior', onPressed: () => _shiftWeek(-1), icon: const Icon(Icons.chevron_left)),
                IconButton(
                    tooltip: 'Semana siguiente', onPressed: () => _shiftWeek(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: _DayChip(
                      date: m.add(Duration(days: i)),
                      selected: m.add(Duration(days: i)) == _day,
                      today: m.add(Duration(days: i)) == today,
                      busy: st.classes.any((c) => c.weekday == i + 1) ||
                          st.reminders.any((r) => !r.done && DateUtils.isSameDay(r.due, m.add(Duration(days: i)))),
                      onTap: () => setState(() => _day = m.add(Duration(days: i))),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const CatMascot(kind: CatKind.gray, size: 80),
                    const SizedBox(height: 10),
                    Text('${weekNames[_day.weekday - 1]} libre',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('No hay clases ni pendientes este día.', style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              )
            else
              ...rows,
          ],
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.date,
    required this.selected,
    required this.today,
    required this.busy,
    required this.onTap,
  });
  final DateTime date;
  final bool selected, today, busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimary : (today ? cs.primary : cs.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected ? cs.primary : Colors.transparent,
        shape: StadiumBorder(side: today && !selected ? BorderSide(color: cs.primary, width: 1.5) : BorderSide.none),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Text(weekNames[date.weekday - 1].substring(0, 3).toUpperCase(),
                    style: TextStyle(fontSize: 11.5, color: selected ? fg : cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text('${date.day}', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: fg)),
                const SizedBox(height: 3),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: busy ? (selected ? cs.onPrimary : cs.primary) : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hora a la izquierda y tarjeta a la derecha.
class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.minutes, required this.child});
  final int minutes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 14, left: 4),
              child: Text(hhmm(minutes),
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _NowMark extends StatelessWidget {
  const _NowMark({required this.now});
  final int now;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(hhmm(now), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c)),
            ),
          ),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          Expanded(child: Container(height: 2, color: c)),
        ],
      ),
    );
  }
}

/// Píldora clarita con una palabra (aula, tipo de pendiente…).
class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.ink});
  final String text;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, color: ink.withValues(alpha: 0.75))),
      );
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.color, required this.child, this.onTap, this.highlight = false});
  final Color color;
  final Widget child;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: highlight
              ? BorderSide(color: Theme.of(context).colorScheme.error, width: 2)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 10, 12), child: child),
        ),
      );
}

class _ClassCard extends ConsumerWidget {
  const _ClassCard({required this.c, required this.live});
  final ClassSlot c;
  final bool live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = Color(c.color);
    final ink = inkOn(bg);
    return _CardShell(
      color: bg,
      highlight: live,
      onTap: () => classMenu(context, ref, c),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.subject,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: ink, height: 1.15)),
                const SizedBox(height: 2),
                Text(
                  '${hhmm(c.start)} – ${hhmm(c.end)} · ${_duration(c.end - c.start)}${live ? ' · ahora' : ''}',
                  style: TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          _Tag(c.room.isEmpty ? 'Clase' : c.room, ink: ink),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Grabar la clase',
            onPressed: () => recordClass(context, ref, c),
            style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.6)),
            icon: Icon(Icons.mic_none, color: ink, size: 20),
          ),
        ],
      ),
    );
  }
}

class _ReminderCard extends ConsumerWidget {
  const _ReminderCard({required this.r});
  final Reminder r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = _reminderColor(r.kind);
    final ink = inkOn(bg);
    return Opacity(
      opacity: r.done ? 0.6 : 1,
      child: _CardShell(
        color: bg,
        onTap: () => editReminder(context, ref, existing: r),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: ink,
                        height: 1.15,
                        decoration: r.done ? TextDecoration.lineThrough : null,
                      )),
                  if (r.subject.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(r.subject, style: TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.7))),
                  ],
                ],
              ),
            ),
            _Tag(r.kind.label, ink: ink),
            const SizedBox(width: 4),
            IconButton(
              tooltip: r.done ? 'Marcar sin hacer' : 'Marcar hecho',
              onPressed: () => ref.read(plannerProvider.notifier).saveReminder(r.copyWith(done: !r.done)),
              icon: Icon(r.done ? Icons.check_circle : Icons.radio_button_unchecked, color: ink, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}
