import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/cat_mascot.dart';
import '../../notebooks/domain/notebook.dart';
import '../../settings/settings.dart';
import '../data/reminder_notifications.dart';
import '../../../core/home_widget.dart';
import '../data/calendar_sync.dart';
import '../domain/planner.dart';
import '../../../core/widgets/doodle_icon.dart';

class PlannerController extends Notifier<PlannerState> {
  static const _key = 'planner.data';

  @override
  PlannerState build() => PlannerState.decode(ref.watch(sharedPreferencesProvider).getString(_key));

  void _save(PlannerState s) {
    state = s;
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(_key, s.encode()).then((_) => HomeWidget.refresh());
    // Y a Google Calendar, si está activado (en segundo plano).
    if (CalendarSync.instance.isOn(prefs)) {
      CalendarSync.instance.sync(prefs, s.reminders).catchError((_) => 0);
    }
  }

  void saveClass(ClassSlot c) => _save(state.copyWith(classes: [
        for (final x in state.classes)
          if (x.id != c.id) x,
        c,
      ]));

  void deleteClass(ClassSlot c) =>
      _save(state.copyWith(classes: [for (final x in state.classes) if (x.id != c.id) x]));

  Future<void> saveReminder(Reminder r) async {
    _save(state.copyWith(reminders: [
      for (final x in state.reminders)
        if (x.id != r.id) x,
      r,
    ]));
    await ReminderNotifications.instance.schedule(r);
  }

  Future<void> deleteReminder(Reminder r) async {
    _save(state.copyWith(reminders: [for (final x in state.reminders) if (x.id != r.id) x]));
    await ReminderNotifications.instance.cancel(r);
  }
}

final plannerProvider = NotifierProvider<PlannerController, PlannerState>(PlannerController.new);

const _weekNames = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
const _subjectColors = [
  0xFFF4A7B9, 0xFFF9D5A7, 0xFFFFE699, 0xFFB8E0D2, 0xFFA7C7E7, 0xFFD5B8F0, 0xFFC5E1A5, 0xFFFFCCBC,
];

/// Horario de clases y pendientes (exámenes, entregas) con avisos.
class PlannerScreen extends StatelessWidget {
  const PlannerScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mi semana'),
          actions: [
            TextButton.icon(
              onPressed: () => context.push('/week'),
              icon: const Icon(Icons.insights_outlined),
              label: const Text('Resumen'),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Horario'), Tab(text: 'Pendientes')]),
        ),
        body: const TabBarView(children: [ScheduleView(), RemindersView()]),
      ),
    );
  }
}

// ------------------------------------------------------------------ Horario

class ScheduleView extends ConsumerWidget {
  const ScheduleView({super.key, this.now});
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(plannerProvider);
    final today = now ?? DateTime.now();
    final days = st.classes.any((c) => c.weekday == 7)
        ? 7
        : st.classes.any((c) => c.weekday == 6)
            ? 6
            : 5;
    final minH = st.classes.isEmpty
        ? 7
        : (st.classes.map((c) => c.start).reduce((a, b) => a < b ? a : b) ~/ 60).clamp(0, 7);
    final maxH = st.classes.isEmpty
        ? 18
        : ((st.classes.map((c) => c.end).reduce((a, b) => a > b ? a : b) + 59) ~/ 60).clamp(18, 24);
    const hourH = 56.0;
    const leftW = 38.0;
    final next = st.currentOrNext(today);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'clase',
        onPressed: () => editClass(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Clase'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
        children: [
          if (next != null)
            Card(
              color: Color(next.color),
              child: ListTile(
                leading: const CatMascot(kind: CatKind.orange, size: 40),
                title: Text(next.subject, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${next.start <= today.hour * 60 + today.minute ? 'Ahora' : 'Hoy'} · ${hhmm(next.start)}–${hhmm(next.end)}'
                    '${next.room.isEmpty ? '' : ' · ${next.room}'}'),
                trailing: FilledButton.tonalIcon(
                  onPressed: () => recordClass(context, ref, next),
                  icon: const Icon(Icons.mic, size: 18),
                  label: const Text('Grabar'),
                ),
              ),
            )
          else if (st.classes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  CatMascot(kind: CatKind.gray, size: 56),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Agrega tus clases con el botón + y toca una para abrir su cuaderno '
                        'o grabar la clase.'),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              const SizedBox(width: leftW),
              for (var d = 1; d <= days; d++)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    alignment: Alignment.center,
                    decoration: d == today.weekday
                        ? BoxDecoration(
                            color: const Color(0xFFE07B55).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          )
                        : null,
                    child: Text(_weekNames[d - 1].substring(0, 3),
                        style: TextStyle(
                          fontWeight: d == today.weekday ? FontWeight.bold : FontWeight.w500,
                          color: d == today.weekday ? const Color(0xFFE07B55) : null,
                        )),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: (maxH - minH) * hourH,
            child: LayoutBuilder(builder: (context, c) {
              final colW = (c.maxWidth - leftW) / days;
              return Stack(
                children: [
                  for (var h = minH; h <= maxH; h++) ...[
                    Positioned(
                      top: (h - minH) * hourH - 7,
                      left: 0,
                      width: leftW - 4,
                      child: Text('$h:00',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 10, color: Colors.black45)),
                    ),
                    Positioned(
                      top: (h - minH) * hourH,
                      left: leftW,
                      right: 0,
                      child: Container(height: 1, color: Colors.black12),
                    ),
                  ],
                  for (final cl in st.classes)
                    if (cl.weekday <= days)
                      Positioned(
                        left: leftW + (cl.weekday - 1) * colW + 2,
                        width: colW - 4,
                        top: (cl.start / 60 - minH) * hourH + 1,
                        height: ((cl.end - cl.start) / 60 * hourH - 2).clamp(18, 2000),
                        child: Material(
                          color: Color(cl.color),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _classMenu(context, ref, cl),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(cl.subject,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  if (cl.room.isNotEmpty)
                                    Text(cl.room,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 9.5)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Future<void> _classMenu(BuildContext context, WidgetRef ref, ClassSlot c) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(c.subject, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${_weekNames[c.weekday - 1]} · ${hhmm(c.start)}–${hhmm(c.end)}'
                  '${c.room.isEmpty ? '' : ' · ${c.room}'}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.mic_none),
              title: const Text('Grabar la clase ahora'),
              onTap: () => Navigator.pop(context, 'record'),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(c.notebookId == null ? 'Elegir su cuaderno' : 'Abrir su cuaderno'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
            ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('Agregar examen o entrega'),
              onTap: () => Navigator.pop(context, 'reminder'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Quitar del horario'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'record':
        await recordClass(context, ref, c);
      case 'open':
        if (c.notebookId == null) {
          await editClass(context, ref, c);
        } else {
          context.push('/notebooks/${c.notebookId}');
        }
      case 'reminder':
        await editReminder(context, ref, subject: c.subject);
      case 'edit':
        await editClass(context, ref, c);
      case 'delete':
        ref.read(plannerProvider.notifier).deleteClass(c);
    }
  }
}

/// Crea una nota "Materia 25/11" en el cuaderno de la materia y empieza a grabar.
Future<void> recordClass(BuildContext context, WidgetRef ref, ClassSlot c) async {
  final now = DateTime.now();
  final id = await ref.read(notesRepositoryProvider).createNote(
        title: '${c.subject} ${now.day}/${now.month}',
        notebookId: c.notebookId,
        tags: [c.subject],
      );
  if (!context.mounted) return;
  context.push('/notes/$id');
  context.push('/notes/$id/record');
}

Future<void> editClass(BuildContext context, WidgetRef ref, [ClassSlot? c]) async {
  final notebooks = ref.read(notebooksProvider).valueOrNull ?? const <Notebook>[];
  final subject = TextEditingController(text: c?.subject ?? '');
  final room = TextEditingController(text: c?.room ?? '');
  var weekday = c?.weekday ?? DateTime.now().weekday.clamp(1, 6);
  var start = c?.start ?? 8 * 60;
  var end = c?.end ?? 10 * 60;
  var color = c?.color ?? _subjectColors[ref.read(plannerProvider).classes.length % _subjectColors.length];
  var notebookId = c?.notebookId;
  // Materias y aulas que ya usaste (una por nombre).
  final all = ref.read(plannerProvider).classes;
  final known = {for (final x in all) x.subject: x}.values.toList()
    ..sort((a, b) => a.subject.compareTo(b.subject));
  final rooms = {for (final x in all) if (x.room.isNotEmpty) x.room}.toList()..sort();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, set) {
        Future<void> pickTime(bool isStart) async {
          final v = isStart ? start : end;
          final t = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: v ~/ 60, minute: v % 60),
          );
          if (t == null) return;
          set(() {
            final m = t.hour * 60 + t.minute;
            if (isStart) {
              final len = end - start;
              start = m;
              end = (m + (len > 0 ? len : 90)).clamp(m + 15, 24 * 60);
            } else {
              end = m > start ? m : start + 15;
            }
          });
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(c == null ? 'Nueva clase' : 'Editar clase', style: Theme.of(context).textTheme.titleLarge),
                TextField(
                  controller: subject,
                  autofocus: c == null && known.isEmpty,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Materia'),
                ),
                // Materias que ya tienes: tocar una la elige (con su color y cuaderno).
                if (known.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final k in known)
                          ChoiceChip(
                            label: Text(k.subject),
                            avatar: CircleAvatar(backgroundColor: Color(k.color), radius: 7),
                            selected: subject.text.trim() == k.subject,
                            onSelected: (_) => set(() {
                              subject.text = k.subject;
                              color = k.color;
                              notebookId = k.notebookId ?? notebookId;
                              if (room.text.isEmpty) room.text = k.room;
                            }),
                          ),
                      ],
                    ),
                  ),
                TextField(
                  controller: room,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Aula', hintText: 'A-12, Lab 3…'),
                ),
                if (rooms.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final r in rooms)
                          ActionChip(label: Text(r), onPressed: () => set(() => room.text = r)),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      ChoiceChip(
                        label: Text(_weekNames[d - 1].substring(0, 3)),
                        selected: weekday == d,
                        onSelected: (_) => set(() => weekday = d),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => pickTime(true),
                        icon: const Icon(Icons.schedule),
                        label: Text('De ${hhmm(start)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pickTime(false),
                        child: Text('a ${hhmm(end)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final col in _subjectColors)
                      GestureDetector(
                        onTap: () => set(() => color = col),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(col),
                          child: col == color ? const Icon(Icons.check, size: 16, color: Colors.black54) : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: notebooks.any((n) => n.id == notebookId) ? notebookId : null,
                  decoration: const InputDecoration(labelText: 'Cuaderno de la materia'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Ninguno')),
                    for (final n in notebooks) DropdownMenuItem(value: n.id, child: Text(n.name)),
                  ],
                  onChanged: (v) => set(() => notebookId = v),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
              ],
            ),
          ),
        );
      },
    ),
  );
  if (ok != true || subject.text.trim().isEmpty) return;
  final slot = ClassSlot(
    id: c?.id ?? const Uuid().v4(),
    subject: subject.text.trim(),
    weekday: weekday,
    start: start,
    end: end,
    color: color,
    room: room.text.trim(),
    notebookId: notebookId,
  );
  ref.read(plannerProvider.notifier).saveClass(slot);
}

// --------------------------------------------------------------- Pendientes

class RemindersView extends ConsumerWidget {
  const RemindersView({super.key, this.now});
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(plannerProvider);
    final today = now ?? DateTime.now();
    final list = st.upcoming;
    final done = st.reminders.where((r) => r.done).toList()..sort((a, b) => b.due.compareTo(a.due));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'pendiente',
        onPressed: () => editReminder(context, ref),
        icon: const Icon(Icons.add_alert_outlined),
        label: const Text('Pendiente'),
      ),
      body: list.isEmpty && done.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CatMascot(kind: CatKind.orange, size: 90),
                    SizedBox(height: 12),
                    DoodleText('Anota tus exámenes y entregas.\nTe aviso un día antes y 2 horas antes 🔔',
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                for (final r in list) _ReminderTile(r: r, now: today),
                if (done.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 16, 8, 4),
                    child: Text('Hechos', style: TextStyle(color: Colors.black45)),
                  ),
                  for (final r in done.take(20)) _ReminderTile(r: r, now: today),
                ],
              ],
            ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.r, required this.now});
  final Reminder r;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final soon = !r.done && r.due.difference(now).inDays < 2;
    final late = !r.done && r.due.isBefore(now);
    return Card(
      color: r.done
          ? null
          : late
              ? const Color(0xFFFFE0E0)
              : soon
                  ? const Color(0xFFFFF1D6)
                  : Colors.white,
      child: ListTile(
        leading: Checkbox(
          value: r.done,
          onChanged: (v) => ref.read(plannerProvider.notifier).saveReminder(r.copyWith(done: v ?? false)),
        ),
        title: DoodleText('${r.kind.emoji} ${r.title}',
            style: TextStyle(decoration: r.done ? TextDecoration.lineThrough : null)),
        subtitle: Text([
          if (r.subject.isNotEmpty) r.subject,
          '${r.due.day}/${r.due.month} ${hhmm(r.due.hour * 60 + r.due.minute)}',
        ].join(' · ')),
        trailing: Text(
          dueLabel(r.due, now),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: late ? Colors.red.shade700 : soon ? const Color(0xFFB26A00) : Colors.black54,
          ),
        ),
        onTap: () => editReminder(context, ref, existing: r),
      ),
    );
  }
}

const _beforeOptions = <(String, Duration)>[
  ('1 semana antes', Duration(days: 7)),
  ('3 días antes', Duration(days: 3)),
  ('1 día antes', Duration(days: 1)),
  ('2 horas antes', Duration(hours: 2)),
  ('30 min antes', Duration(minutes: 30)),
  ('A la hora', Duration.zero),
];

Future<void> editReminder(BuildContext context, WidgetRef ref, {Reminder? existing, String? subject}) async {
  final r = existing;
  final title = TextEditingController(text: r?.title ?? '');
  final subjects = ref.read(plannerProvider).subjects;
  var subj = r?.subject ?? subject ?? '';
  var kind = r?.kind ?? ReminderKind.exam;
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  var due = r?.due ?? DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8);
  final before = {...(r?.notifyBefore ?? const [Duration(days: 1), Duration(hours: 2)])};
  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                children: [
                  for (final k in ReminderKind.values)
                    ChoiceChip(
                      label: DoodleText('${k.emoji} ${k.label}'),
                      selected: kind == k,
                      onSelected: (_) => set(() => kind = k),
                    ),
                ],
              ),
              TextField(
                controller: title,
                autofocus: r == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: '¿Qué es?', hintText: 'Parcial de Biología'),
              ),
              if (subjects.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final s in subjects)
                      ChoiceChip(
                        label: Text(s),
                        selected: subj == s,
                        onSelected: (v) => set(() => subj = v ? s : ''),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text('${due.day}/${due.month}/${due.year}'),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: due,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (d != null) set(() => due = DateTime(d.year, d.month, d.day, due.hour, due.minute));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule),
                      label: Text(hhmm(due.hour * 60 + due.minute)),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: context, initialTime: TimeOfDay.fromDateTime(due));
                        if (t != null) set(() => due = DateTime(due.year, due.month, due.day, t.hour, t.minute));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Avisarme'),
              Wrap(
                spacing: 6,
                children: [
                  for (final (label, d) in _beforeOptions)
                    FilterChip(
                      label: Text(label),
                      selected: before.contains(d),
                      onSelected: (v) => set(() => v ? before.add(d) : before.remove(d)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (r != null)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context, 'delete'),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Borrar'),
                    ),
                  const Spacer(),
                  FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Guardar')),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  final ctl = ref.read(plannerProvider.notifier);
  if (action == 'delete' && r != null) await ctl.deleteReminder(r);
  if (action != 'save' || title.text.trim().isEmpty) return;
  final rem = Reminder(
    id: r?.id ?? const Uuid().v4(),
    title: title.text.trim(),
    due: due,
    kind: kind,
    subject: subj,
    notifyBefore: before.toList()..sort((a, b) => b.compareTo(a)),
    done: r?.done ?? false,
  );
  await ReminderNotifications.instance.requestPermission();
  await ctl.saveReminder(rem);
  if (context.mounted && before.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: DoodleText('Te aviso ${rem.alertTimes(DateTime.now()).length} veces antes 🔔')));
  }
}
