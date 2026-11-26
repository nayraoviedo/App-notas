import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/fonts.dart';
import '../../core/theme.dart';
import '../backup/backup_service.dart';
import 'settings.dart';

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
            subtitle: Text(appFonts[ref.watch(appFontProvider)] ?? ref.watch(appFontProvider)),
            onTap: () async {
              final f = await showModalBottomSheet<String>(
                context: context,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in appFonts.entries)
                        ListTile(
                          title: Text(e.value,
                              style: e.key == 'Normal' ? null : fontStyle(e.key, size: 20)),
                          subtitle: Text(e.key == 'Normal' ? 'La letra del sistema' : 'Hoy aprendí algo nuevo ✏️',
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
