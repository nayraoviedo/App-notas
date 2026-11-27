import 'dart:io';

import 'package:flutter/material.dart';

import '../drawing/application/handwriting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/fonts.dart';
import '../../core/theme.dart';
import '../backup/backup_service.dart';
import '../backup/drive_sync.dart';
import '../planner/data/reminder_notifications.dart';
import 'settings.dart';
import '../../core/google_auth.dart';
import '../../core/platform_info.dart';
import '../planner/data/calendar_sync.dart';
import '../planner/presentation/planner_screen.dart';
import '../../core/widgets/doodle_icon.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Preparando la copia…')));
    try {
      final path = await BackupService.create(ref.read(sharedPreferencesProvider));
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path)],
        text: 'Copia de seguridad de Kumo',
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo crear la copia: $e')));
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Restaurar una copia?'),
        content: const Text('Lo que tienes ahora se reemplaza por lo que trae la copia. '
            'Si quieres, primero crea una copia de lo actual.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Elegir archivo')),
        ],
      ),
    );
    if (ok != true) return;
    final picked = await FilePicker.platform.pickFiles();
    final path = picked?.files.single.path;
    if (path == null || !context.mounted) return;
    try {
      final n = await BackupService.prepareRestore(path, ref.read(sharedPreferencesProvider));
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Copia lista ✓'),
          content: Text('Se recuperaron $n archivos. Cierra la app por completo y vuelve a abrirla '
              'para terminar.'),
          actions: [
            FilledButton(onPressed: () => SystemNavigator.pop(), child: const Text('Cerrar la app')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo restaurar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const _Header('Tú'),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Tu nombre'),
            subtitle: Text(ref.read(sharedPreferencesProvider).getString('user.name')?.isNotEmpty == true
                ? 'Los gatitos te saludan como "${ref.read(sharedPreferencesProvider).getString('user.name')}"'
                : 'Para que los gatitos te saluden'),
            onTap: () async {
              final prefs = ref.read(sharedPreferencesProvider);
              final c = TextEditingController(text: prefs.getString('user.name') ?? '');
              final name = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('¿Cómo te llamas?'),
                  content: TextField(
                    controller: c,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Guardar')),
                  ],
                ),
              );
              if (name == null) return;
              await prefs.setString('user.name', name);
              ref.invalidate(settingsProvider); // refrescar el subtítulo
            },
          ),
          const _Header('Apariencia'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Auto')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Claro')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Oscuro')),
              ],
              selected: {ref.watch(themeModeProvider)},
              onSelectionChanged: (v) => setThemeMode(ref, v.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.font_download_outlined),
            title: const Text('Letra de la app'),
            subtitle: Text(uiFonts[ref.watch(appFontProvider)] ?? ref.watch(appFontProvider)),
            onTap: () async {
              final f = await showModalBottomSheet<String>(
                context: context,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in uiFonts.entries)
                        ListTile(
                          title: Text(e.value,
                              style: e.key == 'Normal' ? null : fontStyle(e.key, size: 20)),
                          subtitle: DoodleText(e.key == 'Normal' ? 'La letra del sistema' : 'Hoy aprendí algo nuevo ✏️',
                              style: e.key == 'Normal' ? null : fontStyle(e.key, size: 16)),
                          trailing: ref.read(appFontProvider) == e.key ? const Icon(Icons.check) : null,
                          onTap: () => Navigator.pop(context, e.key),
                        ),
                    ],
                  ),
                ),
              );
              if (f != null) await setAppFont(ref, f);
            },
          ),
          const _Header('Hojas'),
          ListTile(
            leading: const Icon(Icons.swap_vert),
            title: const Text('Pasar de hoja'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'vertical', icon: Icon(Icons.swap_vert), label: Text('Tirar ↑↓')),
                  ButtonSegment(value: 'horizontal', icon: Icon(Icons.swap_horiz), label: Text('Deslizar ←→')),
                ],
                selected: {ref.read(sharedPreferencesProvider).getString('pages.mode') ?? 'vertical'},
                onSelectionChanged: (v) async {
                  await ref.read(sharedPreferencesProvider).setString('pages.mode', v.first);
                  ref.invalidate(settingsProvider); // redibujar
                },
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: Text(
              'Tirar: en la última hoja, tira hacia arriba para agregar otra. '
              'Se hace con el dedo en el fondo gris, en modo mano o con "solo lápiz".',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          const _Header('Letra a mano'),
          const _HandwritingTile(),
          const _Header('Avisos'),
          StatefulBuilder(builder: (context, setState) {
            final prefs = ref.watch(sharedPreferencesProvider);
            return SwitchListTile(
              secondary: const Icon(Icons.insights_outlined),
              title: const Text('Resumen de la semana'),
              subtitle: const Text('Cada domingo a las 19:00, lo que hiciste y lo que viene'),
              value: prefs.getBool('week.notify') ?? true,
              onChanged: (v) async {
                await prefs.setBool('week.notify', v);
                setState(() {});
                await ReminderNotifications.instance.scheduleWeeklySummary(on: v);
              },
            );
          }),
          const _Header('Google: Drive y Calendar'),
          const _DriveTiles(),
          const _Header('Copia de seguridad'),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Crear copia y guardarla'),
            subtitle: const Text('Un archivo con todo: cuadernos, audios, fotos y ajustes. '
                'Guárdalo en Google Drive desde el menú de compartir.'),
            onTap: () => _backup(context, ref),
          ),
          const _AutoBackupTiles(),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restaurar una copia'),
            subtitle: const Text('Reemplaza lo que hay ahora por lo de la copia'),
            onTap: () => _restore(context, ref),
          ),
          const _Header('Inteligencia artificial (resúmenes)'),
          ListTile(
            title: const Text('Servicio'),
            trailing: DropdownButton<AiProvider>(
              value: s.aiProvider,
              underline: const SizedBox.shrink(),
              items: [
                for (final p in AiProvider.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (p) => ctl.update(s.copyWith(aiProvider: p)),
            ),
          ),
          const _ApiKeyTile(
            provider: AiProvider.gemini,
            help: 'Clave gratis en aistudio.google.com → "Get API key"',
          ),
          _TextSettingTile(
            label: 'Modelo de Gemini',
            value: s.geminiModel,
            onSaved: (v) => ctl.update(s.copyWith(
                geminiModel: v.isEmpty ? AppSettings.defaultGeminiModel : v)),
          ),
          const _ApiKeyTile(
            provider: AiProvider.groq,
            help: 'Gratis en console.groq.com → "API Keys". Sirve para resúmenes y para '
                'transcribir rápido sin descargar nada (el audio se envía a Groq).',
          ),
          _TextSettingTile(
            label: 'Modelo de Groq',
            value: s.groqModel,
            onSaved: (v) => ctl.update(
                s.copyWith(groqModel: v.isEmpty ? AppSettings.defaultGroqModel : v)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Los planes gratis tienen límites diarios. Si se alcanza el límite '
              'de un servicio, la app prueba con el otro si tiene clave. '
              'Las claves se guardan cifradas solo en este teléfono.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const _Header('Grabación'),
          StatefulBuilder(builder: (context, setState) {
            final prefs = ref.watch(sharedPreferencesProvider);
            return SwitchListTile(
              secondary: const Icon(Icons.high_quality_outlined),
              title: const Text('Grabar en alta calidad'),
              subtitle: const Text('Sonido más claro (48 kHz) para escucharlo o compartirlo. '
                  'Ocupa unas 3 veces más espacio. La transcripción funciona igual.'),
              value: prefs.getBool('record.hq') ?? false,
              onChanged: (v) async {
                await prefs.setBool('record.hq', v);
                setState(() {});
              },
            );
          }),
          SwitchListTile(
            title: const Text('Transcripción en vivo'),
            subtitle: const Text('Apágala si el teléfono se pone lento'),
            value: s.liveTranscription,
            onChanged: (v) => ctl.update(s.copyWith(liveTranscription: v)),
          ),
          SwitchListTile(
            title: const Text('Detectar cambio de voz'),
            subtitle: const Text('Pregunta "¿Habla otra persona?"'),
            value: s.autoSpeakerDetection,
            onChanged: (v) => ctl.update(s.copyWith(autoSpeakerDetection: v)),
          ),
          ListTile(
            title: const Text('Idioma'),
            trailing: DropdownButton<String>(
              value: s.language,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'es', child: Text('Español')),
                DropdownMenuItem(value: 'en', child: Text('Inglés')),
                DropdownMenuItem(value: 'pt', child: Text('Portugués')),
                DropdownMenuItem(value: 'auto', child: Text('Detectar')),
              ],
              onChanged: (v) => ctl.update(s.copyWith(language: v)),
            ),
          ),
          const _Header('Escritura a mano'),
          SwitchListTile(
            title: const Text('Solo lápiz óptico'),
            subtitle: const Text('El dedo mueve la hoja; el lápiz escribe'),
            value: s.stylusOnly,
            onChanged: (v) => ctl.update(s.copyWith(stylusOnly: v)),
          ),
          SwitchListTile(
            title: const Text('Ajuste de figura'),
            subtitle: const Text(
                'Al terminar un trazo, mantén quieto el lápiz y se vuelve línea, '
                'círculo, rectángulo o triángulo perfecto'),
            value: s.shapeSnap,
            onChanged: (v) => ctl.update(s.copyWith(shapeSnap: v)),
          ),
          SwitchListTile(
            title: const Text('El grosor se ajusta con el zoom'),
            subtitle: const Text('Con zoom alto el trazo sale más fino, para letra pequeña'),
            value: s.scaleWithZoom,
            onChanged: (v) => ctl.update(s.copyWith(scaleWithZoom: v)),
          ),
          ListTile(
            title: const Text('Mezcla del resaltador'),
            trailing: DropdownButton<HighlighterBlend>(
              value: s.highlighterBlend,
              underline: const SizedBox.shrink(),
              items: [
                for (final b in HighlighterBlend.values)
                  DropdownMenuItem(value: b, child: Text(b.label)),
              ],
              onChanged: (b) => ctl.update(s.copyWith(highlighterBlend: b)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _ApiKeyTile extends ConsumerStatefulWidget {
  const _ApiKeyTile({required this.provider, required this.help});
  final AiProvider provider;
  final String help;

  @override
  ConsumerState<_ApiKeyTile> createState() => _ApiKeyTileState();
}

class _ApiKeyTileState extends ConsumerState<_ApiKeyTile> {
  bool? _hasKey;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final k = await ref.read(apiKeysProvider).read(widget.provider);
    if (mounted) setState(() => _hasKey = k != null && k.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.key_outlined),
      title: Text('Clave de ${widget.provider.label}'),
      subtitle: Text(_hasKey == true ? 'Guardada ✓' : widget.help),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final c = TextEditingController();
        final value = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Clave de ${widget.provider.label}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.help, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: c,
                  obscureText: true,
                  autocorrect: false,
                  decoration: const InputDecoration(hintText: 'Pega la clave aquí'),
                ),
              ],
            ),
            actions: [
              if (_hasKey == true)
                TextButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: const Text('Borrar clave')),
              TextButton(
                  onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, c.text),
                  child: const Text('Guardar')),
            ],
          ),
        );
        if (value == null) return;
        await ref.read(apiKeysProvider).write(widget.provider, value);
        await _refresh();
      },
    );
  }
}

class _TextSettingTile extends StatelessWidget {
  const _TextSettingTile({required this.label, required this.value, required this.onSaved});
  final String label;
  final String value;
  final ValueChanged<String> onSaved;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(label),
        subtitle: Text(value),
        trailing: const Icon(Icons.edit_outlined, size: 20),
        onTap: () async {
          final c = TextEditingController(text: value);
          final v = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(label),
              content: TextField(controller: c, autocorrect: false),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, c.text.trim()),
                    child: const Text('Guardar')),
              ],
            ),
          );
          if (v != null) onSaved(v);
        },
      );
}

/// Copia automática semanal: activarla y compartir la última.
class _AutoBackupTiles extends ConsumerStatefulWidget {
  const _AutoBackupTiles();

  @override
  ConsumerState<_AutoBackupTiles> createState() => _AutoBackupTilesState();
}

class _AutoBackupTilesState extends ConsumerState<_AutoBackupTiles> {
  List<File> _copies = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await BackupService.autoCopies();
      if (mounted) setState(() => _copies = l);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final on = prefs.getBool(BackupService.autoKey) ?? true;
    final last = prefs.getInt(BackupService.lastAutoKey);
    final d = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.autorenew),
          title: const Text('Copia automática cada semana'),
          subtitle: Text(d == null
              ? 'Se guarda en el teléfono (las 3 más recientes)'
              : 'Última: ${d.day}/${d.month}/${d.year} · se guardan las 3 más recientes'),
          value: on,
          onChanged: (v) async {
            await prefs.setBool(BackupService.autoKey, v);
            setState(() {});
          },
        ),
        ListTile(
          leading: const Icon(Icons.add_to_drive_outlined),
          title: const Text('Hacer copia automática ahora'),
          subtitle: const Text('Y luego compártela a Drive: si desinstalas la app, las del teléfono se borran.'),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            messenger.showSnackBar(const SnackBar(content: Text('Haciendo la copia…')));
            try {
              await prefs.remove(BackupService.lastAutoKey);
              final path = await BackupService.autoBackupIfDue(prefs);
              await _load();
              if (path != null) {
                await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: 'Copia de seguridad de Kumo'));
              }
            } catch (e) {
              messenger.showSnackBar(SnackBar(content: Text('No se pudo: $e')));
            }
          },
        ),
        if (_copies.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text('${_copies.length} ${_copies.length == 1 ? 'copia guardada' : 'copias guardadas'} en el teléfono'),
            subtitle: Text(_copies.map((f) => f.uri.pathSegments.last.replaceAll('.appnotas', '')).join(' · ')),
          ),
      ],
    );
  }
}

/// Conectar Google Drive y guardar/restaurar la copia de toda la app.
class _DriveTiles extends ConsumerStatefulWidget {
  const _DriveTiles();

  @override
  ConsumerState<_DriveTiles> createState() => _DriveTilesState();
}

class _DriveTilesState extends ConsumerState<_DriveTiles> {
  String? _busy;

  Future<void> _run(Future<void> Function(void Function(String)) job) async {
    setState(() => _busy = 'Un momento…');
    try {
      await job((m) {
        if (mounted) setState(() => _busy = m);
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _restartNotice(int n) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Listo ✓'),
          content: Text('Se trajeron $n archivos. Kumo se tiene que cerrar para terminar: '
              'vuelve a abrirlo y verás todo al día.'),
          actions: [
            FilledButton(
              onPressed: () => isDesktop ? exit(0) : SystemNavigator.pop(),
              child: const Text('Cerrar Kumo'),
            ),
          ],
        ),
      );

  /// Compu: ID y secreto del cliente "App de escritorio" de Google Cloud.
  Future<void> _setDesktopClient() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final id = TextEditingController(text: prefs.getString(GoogleAuth.desktopIdKey) ?? '');
    final secret = TextEditingController(text: prefs.getString(GoogleAuth.desktopSecretKey) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cliente de escritorio'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('En Google Cloud (el mismo proyecto de Kumo): APIs y servicios → Credenciales → '
                  'Crear credenciales → ID de cliente de OAuth → tipo "App de escritorio". '
                  'Copia aquí el ID y el secreto que te muestra.'),
              const SizedBox(height: 12),
              TextField(
                controller: id,
                decoration: const InputDecoration(labelText: 'ID de cliente', hintText: '…apps.googleusercontent.com'),
              ),
              TextField(
                controller: secret,
                decoration: const InputDecoration(labelText: 'Secreto de cliente', hintText: 'GOCSPX-…'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    await prefs.setString(GoogleAuth.desktopIdKey, id.text.trim());
    await prefs.setString(GoogleAuth.desktopSecretKey, secret.text.trim());
    setState(() {});
  }

  Future<void> _setClientId() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final c = TextEditingController(text: prefs.getString(DriveSync.clientIdKey) ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ID de cliente web'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Cópialo de Google Cloud → APIs y servicios → Credenciales → '
                'el cliente de tipo "Aplicación web". Termina en .apps.googleusercontent.com'),
            TextField(
              controller: c,
              decoration: const InputDecoration(hintText: '1234…apps.googleusercontent.com'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Guardar')),
        ],
      ),
    );
    if (v == null) return;
    await prefs.setString(DriveSync.clientIdKey, v);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final email = prefs.getString(DriveSync.emailKey);
    final clientId = prefs.getString(DriveSync.clientIdKey);
    final last = prefs.getInt(DriveSync.lastKey);
    final d = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
    final drive = DriveSync.instance;
    return Column(
      children: [
        if (_busy != null)
          ListTile(
            leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            title: Text(_busy!),
          ),
        if (isPhone)
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('ID de cliente web (Google Cloud)'),
            subtitle: Text(clientId == null || clientId.isEmpty ? 'El de Kumo (ya viene puesto)' : clientId,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: _setClientId,
          )
        else
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Cliente de escritorio (Google Cloud)'),
            subtitle: Text(
              GoogleAuth.instance.desktopConfigured(prefs)
                  ? prefs.getString(GoogleAuth.desktopIdKey)!
                  : 'Falta: en la compu Google pide un cliente "App de escritorio". Toca para ponerlo.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: _setDesktopClient,
          ),
        if (email == null)
          ListTile(
            leading: const Icon(Icons.add_to_drive),
            title: const Text('Conectar con Google'),
            subtitle: const Text('Guarda y sincroniza todo entre tu celular y tu compu, en una carpeta '
                'privada de tu Drive (15 GB gratis)'),
            enabled: _busy == null,
            onTap: () => _run((_) async {
              final e = await drive.connect(prefs);
              if (!mounted) return;
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Conectado: $e ✓')));
            }),
          )
        else ...[
          ListTile(
            leading: const Icon(Icons.cloud_done_outlined),
            title: Text(email),
            subtitle: Text(d == null
                ? 'Todavía no hay copia en Drive'
                : 'Última copia: ${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.sync),
            title: const Text('Sincronizar celular y compu'),
            subtitle: const Text('Sube tus cambios cada 30 min (y al salir de la app). Al abrir, avisa si '
                'hay cambios más nuevos del otro aparato para traerlos.'),
            value: prefs.getBool(DriveSync.autoKey) ?? true,
            onChanged: (v) async {
              await prefs.setBool(DriveSync.autoKey, v);
              setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.sync_alt),
            title: const Text('Sincronizar ahora'),
            subtitle: const Text('Trae lo del otro aparato si es más nuevo; si no, sube lo de aquí'),
            enabled: _busy == null,
            onTap: () => _run((status) async {
              status('Revisando Drive…');
              final newer = await drive.newerFromOtherDevice(prefs);
              if (!mounted) return;
              if (newer == null) {
                await drive.upload(prefs, onStatus: status);
                if (!mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Todo al día ✓ Tus cambios están en Drive')));
                return;
              }
              final (at, from) = newer;
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Hay cambios más nuevos'),
                  content: Text('Tu $from guardó cambios el ${at.day}/${at.month} a las '
                      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}. '
                      '¿Traerlos? Lo de aquí se reemplaza (antes se guarda una copia de seguridad).'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Traer')),
                  ],
                ),
              );
              if (ok != true) return;
              final n = await drive.restoreLatest(prefs, onStatus: status);
              if (!mounted) return;
              await _restartNotice(n);
            }),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Guardar en Drive ahora'),
            enabled: _busy == null,
            onTap: () => _run((status) async {
              await drive.upload(prefs, onStatus: status);
              if (!mounted) return;
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copia guardada en Drive ✓')));
            }),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Restaurar desde Drive'),
            subtitle: const Text('Trae la copia más reciente (reemplaza lo de ahora)'),
            enabled: _busy == null,
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('¿Restaurar desde Drive?'),
                  content: const Text('Lo que hay ahora en este celular se reemplaza por la copia de Drive.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restaurar')),
                  ],
                ),
              );
              if (ok != true) return;
              await _run((status) async {
                final n = await drive.restoreLatest(prefs, onStatus: status);
                if (!mounted) return;
                await _restartNotice(n);
              });
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.event_outlined),
            title: const Text('Pasar pendientes a Google Calendar'),
            subtitle: const Text('Exámenes y entregas aparecen en tu calendario, con sus avisos. '
                'Si los cambias o borras en Kumo, también allá.'),
            value: CalendarSync.instance.isOn(prefs),
            onChanged: _busy != null
                ? null
                : (v) => _run((status) async {
                      if (v) {
                        status('Pasando tus pendientes a Calendar…');
                        final n = await CalendarSync.instance.enable(prefs, ref.read(plannerProvider).reminders);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Listo ✓ $n ${n == 1 ? 'pendiente' : 'pendientes'} en tu calendario')));
                      } else {
                        await CalendarSync.instance.disable(prefs);
                      }
                      if (mounted) setState(() {});
                    }),
          ),
          ListTile(
            leading: const Icon(Icons.link_off),
            title: const Text('Desconectar cuenta'),
            onTap: () async {
              await drive.disconnect(prefs);
              setState(() {});
            },
          ),
        ],
      ],
    );
  }
}


/// Reconocer letra a mano: buscar lo escrito y pasarlo a texto.
class _HandwritingTile extends ConsumerStatefulWidget {
  const _HandwritingTile();

  @override
  ConsumerState<_HandwritingTile> createState() => _HandwritingTileState();
}

class _HandwritingTileState extends ConsumerState<_HandwritingTile> {
  bool? _ready;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Handwriting.instance.isReady().then((v) {
      if (mounted) setState(() => _ready = v);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (!isPhone) {
      return const ListTile(
        leading: Icon(Icons.draw_outlined),
        title: Text('Buscar y pasar a texto tu letra'),
        subtitle: Text('Por ahora solo en el celular. Lo que se reconoce allá también se encuentra aquí '
            'al sincronizar.'),
      );
    }
    final prefs = ref.watch(sharedPreferencesProvider);
    final on = prefs.getBool('hw.enabled') ?? true;
    return Column(children: [
      SwitchListTile(
        secondary: const Icon(Icons.draw_outlined),
        title: const Text('Buscar en lo que escribo a mano'),
        subtitle: Text(_busy
            ? 'Bajando el lector de letra (~20 MB)…'
            : _ready == true
                ? 'Listo ✓ · El buscador también encuentra tu letra'
                : 'Hay que bajar el lector de letra una vez (~20 MB)'),
        value: on,
        onChanged: (v) async {
          await prefs.setBool('hw.enabled', v);
          setState(() {});
          if (v && _ready != true) _download();
        },
      ),
      if (_ready != true && !_busy)
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _download,
              icon: const Icon(Icons.download),
              label: const Text('Bajar lector de letra'),
            ),
          ),
        ),
      const Padding(
        padding: EdgeInsets.fromLTRB(72, 0, 16, 8),
        child: Text(
          'Para pasar tu letra a texto: usa el lazo, rodea lo escrito y toca "A texto".',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
      ),
    ]);
  }

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      await Handwriting.instance.ensureModel();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
