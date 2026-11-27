import 'dart:convert';

/// Una clase del horario semanal.
class ClassSlot {
  const ClassSlot({
    required this.id,
    required this.subject,
    required this.weekday,
    required this.start,
    required this.end,
    this.color = 0xFFF4A7B9,
    this.room = '',
    this.notebookId,
  });

  final String id;
  final String subject;

  /// 1 = lunes … 7 = domingo.
  final int weekday;

  /// Minutos desde las 00:00.
  final int start;
  final int end;
  final int color;
  final String room;

  /// Cuaderno de la materia (para abrirlo o grabar ahí).
  final String? notebookId;

  ClassSlot copyWith({
    String? subject,
    int? weekday,
    int? start,
    int? end,
    int? color,
    String? room,
    String? notebookId,
    bool clearNotebook = false,
  }) =>
      ClassSlot(
        id: id,
        subject: subject ?? this.subject,
        weekday: weekday ?? this.weekday,
        start: start ?? this.start,
        end: end ?? this.end,
        color: color ?? this.color,
        room: room ?? this.room,
        notebookId: clearNotebook ? null : (notebookId ?? this.notebookId),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'subject': subject,
        'weekday': weekday,
        'start': start,
        'end': end,
        'color': color,
        if (room.isNotEmpty) 'room': room,
        if (notebookId != null) 'notebookId': notebookId,
      };

  factory ClassSlot.fromJson(Map<String, Object?> j) => ClassSlot(
        id: j['id'] as String,
        subject: j['subject'] as String? ?? '',
        weekday: j['weekday'] as int? ?? 1,
        start: j['start'] as int? ?? 8 * 60,
        end: j['end'] as int? ?? 10 * 60,
        color: j['color'] as int? ?? 0xFFF4A7B9,
        room: j['room'] as String? ?? '',
        notebookId: j['notebookId'] as String?,
      );
}

enum ReminderKind {
  exam('Examen', '📝'),
  homework('Entrega', '📚'),
  other('Otro', '⏰');

  const ReminderKind(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// Un examen, una entrega o cualquier pendiente con fecha.
class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.due,
    this.kind = ReminderKind.exam,
    this.subject = '',
    this.notifyBefore = const [Duration(days: 1), Duration(hours: 2)],
    this.done = false,
  });

  final String id;
  final String title;
  final DateTime due;
  final ReminderKind kind;
  final String subject;

  /// Cuánto antes avisar (puede haber varios avisos).
  final List<Duration> notifyBefore;
  final bool done;

  /// Momentos de aviso que todavía no pasaron.
  List<DateTime> alertTimes(DateTime now) => [
        for (final b in notifyBefore)
          if (due.subtract(b).isAfter(now)) due.subtract(b),
        if (notifyBefore.isEmpty && due.isAfter(now)) due,
      ];

  /// Número estable para los avisos del sistema (id base; +i por aviso).
  int get notificationBase => (id.hashCode & 0x0FFFFFFF) * 8;

  Reminder copyWith({
    String? title,
    DateTime? due,
    ReminderKind? kind,
    String? subject,
    List<Duration>? notifyBefore,
    bool? done,
  }) =>
      Reminder(
        id: id,
        title: title ?? this.title,
        due: due ?? this.due,
        kind: kind ?? this.kind,
        subject: subject ?? this.subject,
        notifyBefore: notifyBefore ?? this.notifyBefore,
        done: done ?? this.done,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'due': due.millisecondsSinceEpoch,
        'kind': kind.name,
        if (subject.isNotEmpty) 'subject': subject,
        'before': [for (final b in notifyBefore) b.inMinutes],
        if (done) 'done': true,
      };

  factory Reminder.fromJson(Map<String, Object?> j) => Reminder(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        due: DateTime.fromMillisecondsSinceEpoch(j['due'] as int? ?? 0),
        kind: ReminderKind.values.where((k) => k.name == j['kind']).firstOrNull ?? ReminderKind.other,
        subject: j['subject'] as String? ?? '',
        notifyBefore: [for (final m in (j['before'] as List? ?? const [])) Duration(minutes: m as int)],
        done: j['done'] as bool? ?? false,
      );
}

/// "en 3 días", "mañana", "hoy 14:30", "hace 2 días".
String dueLabel(DateTime due, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final days = day.difference(today).inDays;
  final hm = '${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';
  if (days == 0) return 'hoy $hm';
  if (days == 1) return 'mañana $hm';
  if (days == -1) return 'ayer';
  if (days < 0) return 'hace ${-days} días';
  if (days < 7) return 'en $days días';
  final w = days ~/ 7;
  return w == 1 ? 'en 1 semana' : 'en $w semanas';
}

String hhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

class PlannerState {
  const PlannerState({this.classes = const [], this.reminders = const []});
  final List<ClassSlot> classes;
  final List<Reminder> reminders;

  /// Clases de un día, en orden.
  List<ClassSlot> classesOn(int weekday) =>
      classes.where((c) => c.weekday == weekday).toList()..sort((a, b) => a.start.compareTo(b.start));

  /// La clase que está pasando ahora o la siguiente de hoy.
  ClassSlot? currentOrNext(DateTime now) {
    final m = now.hour * 60 + now.minute;
    for (final c in classesOn(now.weekday)) {
      if (c.end > m) return c;
    }
    return null;
  }

  /// Pendientes sin hacer, del más cercano al más lejano.
  List<Reminder> get upcoming =>
      reminders.where((r) => !r.done).toList()..sort((a, b) => a.due.compareTo(b.due));

  /// Nombres de materias (del horario), sin repetir.
  List<String> get subjects => {for (final c in classes) c.subject}.toList()..sort();

  PlannerState copyWith({List<ClassSlot>? classes, List<Reminder>? reminders}) =>
      PlannerState(classes: classes ?? this.classes, reminders: reminders ?? this.reminders);

  String encode() => jsonEncode({
        'classes': [for (final c in classes) c.toJson()],
        'reminders': [for (final r in reminders) r.toJson()],
      });

  factory PlannerState.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const PlannerState();
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      return PlannerState(
        classes: [
          for (final c in (j['classes'] as List? ?? const []))
            ClassSlot.fromJson((c as Map).cast<String, Object?>()),
        ],
        reminders: [
          for (final r in (j['reminders'] as List? ?? const []))
            Reminder.fromJson((r as Map).cast<String, Object?>()),
        ],
      );
    } catch (_) {
      return const PlannerState();
    }
  }
}
