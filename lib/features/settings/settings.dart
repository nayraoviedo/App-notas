import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AiProvider {
  gemini('Gemini (Google)'),
  groq('Groq');

  const AiProvider(this.label);
  final String label;
}

/// Cómo se mezcla el resaltador con lo que hay debajo.
enum HighlighterBlend {
  multiply('Automático (multiplicar)'),
  darken('Oscurecer'),
  normal('Normal');

  const HighlighterBlend(this.label);
  final String label;
}

class AppSettings {
  const AppSettings({
    this.aiProvider = AiProvider.gemini,
    this.geminiModel = defaultGeminiModel,
    this.groqModel = defaultGroqModel,
    this.language = 'es',
    this.liveTranscription = true,
    this.autoSpeakerDetection = true,
    this.stylusOnly = false,
    this.shapeSnap = true,
    this.scaleWithZoom = true,
    this.highlighterBlend = HighlighterBlend.multiply,
  });

  /// Los nombres de modelo cambian seguido; se pueden cambiar en Ajustes.
  static const defaultGeminiModel = 'gemini-3.6-flash';
  static const defaultGroqModel = 'openai/gpt-oss-120b';

  final AiProvider aiProvider;
  final String geminiModel;
  final String groqModel;

  /// Idioma de transcripción y resúmenes.
  final String language;

  final bool liveTranscription;
  final bool autoSpeakerDetection;

  // Escritura
  final bool stylusOnly;

  /// Mantener el lápiz quieto al final de un trazo lo convierte en figura.
  final bool shapeSnap;

  /// El grosor se ajusta al zoom (con zoom alto se escribe más fino).
  final bool scaleWithZoom;
  final HighlighterBlend highlighterBlend;

  AppSettings copyWith({
    AiProvider? aiProvider,
    String? geminiModel,
    String? groqModel,
    String? language,
    bool? liveTranscription,
    bool? autoSpeakerDetection,
    bool? stylusOnly,
    bool? shapeSnap,
    bool? scaleWithZoom,
    HighlighterBlend? highlighterBlend,
  }) =>
      AppSettings(
        aiProvider: aiProvider ?? this.aiProvider,
        geminiModel: geminiModel ?? this.geminiModel,
        groqModel: groqModel ?? this.groqModel,
        language: language ?? this.language,
        liveTranscription: liveTranscription ?? this.liveTranscription,
        autoSpeakerDetection: autoSpeakerDetection ?? this.autoSpeakerDetection,
        stylusOnly: stylusOnly ?? this.stylusOnly,
        shapeSnap: shapeSnap ?? this.shapeSnap,
        scaleWithZoom: scaleWithZoom ?? this.scaleWithZoom,
        highlighterBlend: highlighterBlend ?? this.highlighterBlend,
      );
}

/// Se reemplaza en main() con la instancia ya cargada.
final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

class SettingsController extends Notifier<AppSettings> {
  SharedPreferences get _p => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final p = ref.watch(sharedPreferencesProvider);
    const d = AppSettings();
    T enumOr<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((v) => v.name == p.getString(key)).firstOrNull ?? fallback;
    return AppSettings(
      aiProvider: enumOr(AiProvider.values, 'aiProvider', d.aiProvider),
      geminiModel: p.getString('geminiModel') ?? d.geminiModel,
      groqModel: p.getString('groqModel') ?? d.groqModel,
      language: p.getString('language') ?? d.language,
      liveTranscription: p.getBool('liveTranscription') ?? d.liveTranscription,
      autoSpeakerDetection: p.getBool('autoSpeakerDetection') ?? d.autoSpeakerDetection,
      stylusOnly: p.getBool('stylusOnly') ?? d.stylusOnly,
      shapeSnap: p.getBool('shapeSnap') ?? d.shapeSnap,
      scaleWithZoom: p.getBool('scaleWithZoom') ?? d.scaleWithZoom,
      highlighterBlend:
          enumOr(HighlighterBlend.values, 'highlighterBlend', d.highlighterBlend),
    );
  }

  Future<void> update(AppSettings s) async {
    state = s;
    await Future.wait([
      _p.setString('aiProvider', s.aiProvider.name),
      _p.setString('geminiModel', s.geminiModel),
      _p.setString('groqModel', s.groqModel),
      _p.setString('language', s.language),
      _p.setBool('liveTranscription', s.liveTranscription),
      _p.setBool('autoSpeakerDetection', s.autoSpeakerDetection),
      _p.setBool('stylusOnly', s.stylusOnly),
      _p.setBool('shapeSnap', s.shapeSnap),
      _p.setBool('scaleWithZoom', s.scaleWithZoom),
      _p.setString('highlighterBlend', s.highlighterBlend.name),
    ]);
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Tema: según el teléfono, claro u oscuro.
final themeModeProvider = StateProvider<ThemeMode>((ref) {
  final v = ref.watch(sharedPreferencesProvider).getString('app.themeMode');
  // Claro por defecto: varias pantallas tienen fondo crema de cuaderno.
  return ThemeMode.values.where((m) => m.name == v).firstOrNull ?? ThemeMode.light;
});

/// Letra de toda la app (ver appFonts en core/theme.dart).
final appFontProvider = StateProvider<String>(
    (ref) => ref.watch(sharedPreferencesProvider).getString('app.font') ?? 'Patrick Hand');

Future<void> setAppFont(WidgetRef ref, String font) async {
  ref.read(appFontProvider.notifier).state = font;
  await ref.read(sharedPreferencesProvider).setString('app.font', font);
}

Future<void> setThemeMode(WidgetRef ref, ThemeMode m) async {
  ref.read(themeModeProvider.notifier).state = m;
  await ref.read(sharedPreferencesProvider).setString('app.themeMode', m.name);
}

/// Claves de API guardadas de forma cifrada en el teléfono (nunca en el código).
class ApiKeys {
  const ApiKeys(this._storage);
  final FlutterSecureStorage _storage;

  Future<String?> read(AiProvider p) => _storage.read(key: 'apikey_${p.name}');

  Future<void> write(AiProvider p, String? value) => value == null || value.trim().isEmpty
      ? _storage.delete(key: 'apikey_${p.name}')
      : _storage.write(key: 'apikey_${p.name}', value: value.trim());
}

final apiKeysProvider = Provider<ApiKeys>((ref) => const ApiKeys(FlutterSecureStorage()));
