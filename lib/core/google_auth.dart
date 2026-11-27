import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_info.dart';

/// Inicio de sesión con Google para Drive y Calendar.
///
/// - Celular: google_sign_in (la ventana de cuentas de Android).
/// - Compu: se abre el navegador, eliges tu cuenta y Google vuelve a Kumo
///   por http://127.0.0.1 (así lo hacen las apps de escritorio). Necesita un
///   "ID de cliente de escritorio" del mismo proyecto de Google Cloud.
class GoogleAuth {
  GoogleAuth._();
  static final instance = GoogleAuth._();

  static const emailKey = 'google.email';
  static const webClientIdKey = 'drive.webClientId';
  static const desktopIdKey = 'google.desktopClientId';
  static const desktopSecretKey = 'google.desktopClientSecret';
  static const _scopesKey = 'google.scopes';
  static const _refreshKey = 'google.refresh';

  /// ID de cliente web del proyecto "Kumo" (es público, no es una clave).
  static const defaultWebClientId = '529008696542-89313m0rasquf8tp43nfa4h0kc6vnecb.apps.googleusercontent.com';

  final _secure = const FlutterSecureStorage();

  // ----------------------------------------------------------- Celular
  bool _ready = false;
  GoogleSignInAccount? _user;

  Future<void> _initPhone(SharedPreferences prefs) async {
    if (_ready) return;
    final saved = prefs.getString(webClientIdKey)?.trim();
    await GoogleSignIn.instance.initialize(
        serverClientId: saved == null || saved.isEmpty ? defaultWebClientId : saved);
    _ready = true;
  }

  // -------------------------------------------------------------- Compu
  String? _access;
  DateTime _expires = DateTime(2000);

  bool desktopConfigured(SharedPreferences prefs) =>
      (prefs.getString(desktopIdKey) ?? '').trim().isNotEmpty;

  /// Correo de la cuenta conectada (o null).
  String? email(SharedPreferences prefs) => prefs.getString(emailKey) ?? prefs.getString('drive.email');

  /// Inicia sesión pidiendo [scopes]. Devuelve el correo.
  Future<String> signIn(SharedPreferences prefs, List<String> scopes) async {
    if (isPhone) {
      await _initPhone(prefs);
      try {
        _user = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
      } on GoogleSignInException catch (e) {
        throw GoogleAuthException(e.code == GoogleSignInExceptionCode.canceled
            ? 'Se canceló. Si elegiste tu cuenta y igual sale esto, revisa en Google Cloud '
                'el nombre de paquete y la huella SHA-1.'
            : 'No se pudo iniciar sesión: ${e.description ?? e.code.name}');
      }
      final auth = await _user!.authorizationClient.authorizationForScopes(scopes) ??
          await _user!.authorizationClient.authorizeScopes(scopes);
      _access = auth.accessToken;
      await prefs.setString(emailKey, _user!.email);
      return _user!.email;
    }
    return _desktopSignIn(prefs, scopes);
  }

  Future<void> signOut(SharedPreferences prefs) async {
    if (isPhone) {
      try {
        await GoogleSignIn.instance.disconnect();
      } catch (_) {}
      _user = null;
    } else {
      await _secure.delete(key: _refreshKey);
      await prefs.remove(_scopesKey);
    }
    _access = null;
    await prefs.remove(emailKey);
    await prefs.remove('drive.email');
  }

  /// Un permiso de acceso para [scopes]. Si falta permiso y [interactive],
  /// lo pide (ventana de Google); si no, lanza [GoogleAuthException].
  Future<String> token(SharedPreferences prefs, List<String> scopes, {bool interactive = false}) async {
    if (isPhone) {
      await _initPhone(prefs);
      // Primero, sin mostrar nada: si ya diste permiso antes, Google entrega
      // el acceso en silencio. (Antes se usaba el "inicio rápido", que en
      // Android a veces abre la lista de cuentas al abrir la app.)
      try {
        final silent = await (_user?.authorizationClient ?? GoogleSignIn.instance.authorizationClient)
            .authorizationForScopes(scopes);
        if (silent != null) return silent.accessToken;
      } catch (_) {}
      if (!interactive) throw const GoogleAuthException('Falta dar permiso: toca "Conectar" en Ajustes.');
      var user = _user ?? await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (user == null) {
        if (!interactive) throw const GoogleAuthException('Conecta tu cuenta de Google en Ajustes.');
        await signIn(prefs, scopes);
        user = _user!;
      }
      _user = user;
      var auth = await user.authorizationClient.authorizationForScopes(scopes);
      if (auth == null) {
        if (!interactive) throw const GoogleAuthException('Falta dar permiso: toca "Conectar" en Ajustes.');
        auth = await user.authorizationClient.authorizeScopes(scopes);
      }
      return auth.accessToken;
    }

    final granted = (prefs.getStringList(_scopesKey) ?? const []).toSet();
    final missing = scopes.where((s) => !granted.contains(s)).toList();
    if (missing.isNotEmpty) {
      if (!interactive) throw const GoogleAuthException('Falta dar permiso: toca "Conectar" en Ajustes.');
      await _desktopSignIn(prefs, {...granted, ...scopes}.toList());
    }
    if (_access != null && DateTime.now().isBefore(_expires)) return _access!;
    final refresh = await _secure.read(key: _refreshKey);
    if (refresh == null) {
      if (!interactive) throw const GoogleAuthException('Conecta tu cuenta de Google en Ajustes.');
      await _desktopSignIn(prefs, {...granted, ...scopes}.toList());
      return _access!;
    }
    final res = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'client_id': prefs.getString(desktopIdKey)!.trim(),
      if ((prefs.getString(desktopSecretKey) ?? '').isNotEmpty) 'client_secret': prefs.getString(desktopSecretKey)!.trim(),
      'refresh_token': refresh,
      'grant_type': 'refresh_token',
    });
    if (res.statusCode != 200) {
      await _secure.delete(key: _refreshKey);
      throw const GoogleAuthException('Se venció el permiso de Google: vuelve a conectar en Ajustes. '
          '(Si tu proyecto de Google Cloud está "En prueba", Google lo vence cada 7 días.)');
    }
    final j = jsonDecode(res.body) as Map;
    _access = j['access_token'] as String;
    _expires = DateTime.now().add(Duration(seconds: (j['expires_in'] as num? ?? 3600).toInt() - 120));
    return _access!;
  }

  /// Compu: navegador + respuesta en http://127.0.0.1:puerto (con PKCE).
  Future<String> _desktopSignIn(SharedPreferences prefs, List<String> scopes) async {
    final clientId = (prefs.getString(desktopIdKey) ?? '').trim();
    if (clientId.isEmpty) {
      throw const GoogleAuthException('Primero pon el "ID de cliente de escritorio" en Ajustes → Google.');
    }
    final secret = (prefs.getString(desktopSecretKey) ?? '').trim();
    final rnd = Random.secure();
    final verifier = base64UrlEncode(List.generate(48, (_) => rnd.nextInt(256))).replaceAll('=', '');
    final challenge = base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = base64UrlEncode(List.generate(16, (_) => rnd.nextInt(256))).replaceAll('=', '');
    final all = {'openid', 'email', ...scopes}.toList();

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': all.join(' '),
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'consent',
      'include_granted_scopes': 'true',
      'state': state,
    });
    await openInBrowser(url.toString());

    String? code;
    try {
      await for (final req in server.timeout(const Duration(minutes: 5))) {
        final q = req.uri.queryParameters;
        if (q['state'] != state && q['code'] != null) {
          req.response.statusCode = 400;
          await req.response.close();
          continue;
        }
        code = q['code'];
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html><body style="font-family:sans-serif;text-align:center;padding:60px">'
            '<h2>${code != null ? '¡Listo! 🐱' : 'No se pudo conectar'}</h2>'
            '<p>${code != null ? 'Ya puedes cerrar esta pestaña y volver a Kumo.' : 'Vuelve a Kumo e inténtalo de nuevo.'}</p>'
            '</body></html>');
        await req.response.close();
        break;
      }
    } on TimeoutException {
      throw const GoogleAuthException('Se tardó demasiado en elegir la cuenta. Inténtalo de nuevo.');
    } finally {
      await server.close(force: true);
    }
    if (code == null) throw const GoogleAuthException('Se canceló el inicio de sesión.');

    final res = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'client_id': clientId,
      if (secret.isNotEmpty) 'client_secret': secret,
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': redirect,
      'grant_type': 'authorization_code',
    });
    if (res.statusCode != 200) {
      throw GoogleAuthException('Google no aceptó el inicio de sesión (${res.statusCode}). '
          'Revisa el ID y el secreto de cliente de escritorio.');
    }
    final j = jsonDecode(res.body) as Map;
    _access = j['access_token'] as String;
    _expires = DateTime.now().add(Duration(seconds: (j['expires_in'] as num? ?? 3600).toInt() - 120));
    final refresh = j['refresh_token'] as String?;
    if (refresh != null) await _secure.write(key: _refreshKey, value: refresh);
    final grantedNow = (j['scope'] as String? ?? all.join(' ')).split(' ');
    await prefs.setStringList(_scopesKey, grantedNow);
    final email = _emailFromIdToken(j['id_token'] as String?) ?? 'Cuenta de Google';
    await prefs.setString(emailKey, email);
    return email;
  }

  static String? _emailFromIdToken(String? jwt) {
    if (jwt == null) return null;
    try {
      final part = jwt.split('.')[1];
      final json = utf8.decode(base64Url.decode(base64Url.normalize(part)));
      return (jsonDecode(json) as Map)['email'] as String?;
    } catch (_) {
      return null;
    }
  }
}

/// Abre un enlace en el navegador de la compu.
Future<void> openInBrowser(String url) async {
  if (Platform.isWindows) {
    await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [url]);
  } else {
    await Process.run('xdg-open', [url]);
  }
}

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
