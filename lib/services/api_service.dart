import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'image_compressor.dart';

/// Permesso dell'utente sul modulo segnalazioni, come arriva dal login.
///
/// * [none] – nessun accesso: il login viene rifiutato con un avviso.
/// * [read] – sola lettura: si vedono le proprie segnalazioni, non si
///   creano, modificano o eliminano.
/// * [readWrite] – accesso completo.
enum AppPermission { none, read, readWrite }

class ApiService {
  // Produzione
  static const String baseUrl = 'https://www.castellazzodestampi.org';
  // Sviluppo locale (decommentare per usare in locale). Da emulatore o
  // dispositivo fisico al posto di localhost va messo l'IP del pc.
  // static const String baseUrl = 'http://localhost/www.castellazzodestampi.org/public';

  /// URL assoluto di un'immagine indicata dall'API (foto, miniature, icone).
  /// L'API manda URL completi: qui si tiene il valore cosi' com'e'. I percorsi
  /// relativi ("/uploads/...") delle versioni precedenti restano validi e
  /// vengono risolti sul baseUrl corrente, che in locale comprende anche la
  /// sottocartella del sito.
  static String? mediaUrl(String? path) {
    final p = path?.trim();
    if (p == null || p.isEmpty) return null;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    return '$baseUrl/${p.replaceFirst(RegExp(r'^/+'), '')}';
  }

  static const String _tokenKey = 'auth_token';
  static const String _permissionKey = 'auth_permission';
  static String? token;

  /// Permesso dell'utente sulle segnalazioni: lo manda il login e resta
  /// salvato sul dispositivo, perche' al riavvio dell'app il login non
  /// viene rifatto (si riusa il token).
  static AppPermission permission = AppPermission.none;

  /// Puo' vedere le segnalazioni (sola lettura o lettura e scrittura).
  static bool get canRead => permission != AppPermission.none;

  /// Puo' creare, modificare ed eliminare segnalazioni e bozze.
  static bool get canWrite => permission == AppPermission.readWrite;

  static Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    'X-AUTH-TOKEN': token ?? '',
  };

  // ── Persistenza token e permesso ───────────────────────────────

  static Future<void> saveToken(String t, AppPermission p) async {
    token = t;
    permission = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, t);
    await prefs.setString(_permissionKey, p.name);
  }

  /// Restituisce true se esiste un token salvato con un permesso valido.
  /// Un token senza permesso (utente disabilitato dopo l'ultimo accesso,
  /// o dati vecchi) viene buttato via: si torna al login.
  static Future<bool> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_tokenKey);
    if (saved == null || saved.isEmpty) return false;
    final savedName = prefs.getString(_permissionKey);
    final savedPermission = AppPermission.values
        .where((p) => p.name == savedName)
        .fold<AppPermission?>(null, (_, p) => p);
    if (savedPermission == null || savedPermission == AppPermission.none) {
      await clearToken();
      return false;
    }
    token = saved;
    permission = savedPermission;
    return true;
  }

  static Future<void> clearToken() async {
    token = null;
    permission = AppPermission.none;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_permissionKey);
  }

  // ── Lettura del permesso dalla risposta di login ───────────────

  /// Chiavi con cui il backend puo' indicare il modulo segnalazioni
  /// dentro `user.permissions`.
  static const _reportsKeys = ['segnalazioni', 'reports', 'report'];

  /// Valori che valgono lettura e scrittura, e valori di sola lettura.
  static const _writeWords = [
    'rw',
    'w',
    'write',
    'readwrite',
    'read_write',
    'read-write',
    'scrittura',
    'lettura_scrittura',
    'full',
    'admin',
    'edit',
    '2',
  ];
  static const _readWords = [
    'r',
    'read',
    'readonly',
    'read_only',
    'read-only',
    'lettura',
    'view',
    'sola_lettura',
    '1',
  ];

  /// Permesso sulle segnalazioni ricavato dall'oggetto `user` del login.
  ///
  /// Sono accettate le forme piu' comuni, cosi' il backend puo' mandare
  /// il permesso in uno qualsiasi di questi modi:
  ///
  /// * `"permissions": {"segnalazioni": "rw"}` (oppure `"r"`, `""`, `true`,
  ///   `false`, o un oggetto `{"read": true, "write": true}`);
  /// * `"permissions": ["segnalazioni_write"]` / `["segnalazioni:r"]`;
  /// * `"roles": ["ROLE_SEGNALAZIONI_WRITE"]` o `"role": "ROLE_..."`.
  ///
  /// Se non c'e' nessuna informazione sui permessi si assume lettura e
  /// scrittura: e' il comportamento delle versioni precedenti dell'API,
  /// che non manda(va)no il campo, e senza questa scelta l'app si
  /// bloccherebbe per tutti al primo aggiornamento del backend.
  static AppPermission permissionFromUser(Map<String, dynamic>? user) {
    if (user == null) return AppPermission.readWrite;

    final permissions = user['permissions'] ?? user['permessi'];

    if (permissions is Map) {
      for (final key in permissions.keys) {
        if (!_isReportsKey(key.toString())) continue;
        return _permissionFromValue(permissions[key]);
      }
      // Oggetto permessi presente ma senza il modulo segnalazioni:
      // l'utente non ci puo' entrare.
      return AppPermission.none;
    }

    final roles = user['roles'];
    final flat = <String>[
      if (permissions is List) ...permissions.map((p) => p.toString()),
      if (roles is List) ...roles.map((r) => r.toString()),
      if (user['role'] is String) user['role'] as String,
    ];

    final found = _permissionFromEntries(flat);
    // Nessuna voce parla di segnalazioni: se l'elenco dei permessi c'e',
    // il modulo non e' concesso; se invece ci sono solo i ruoli Symfony
    // (`ROLE_USER`), e' l'API vecchia che i permessi non li manda e si
    // resta sul comportamento di prima.
    if (found == AppPermission.none && permissions == null) {
      return AppPermission.readWrite;
    }
    return found;
  }

  static AppPermission _permissionFromEntries(List<String> flat) {
    var found = AppPermission.none;
    for (final raw in flat) {
      final entry = raw.toLowerCase();
      if (!_reportsKeys.any(entry.contains)) continue;
      // "segnalazioni_write", "ROLE_SEGNALAZIONI_READ", "segnalazioni:rw".
      // Senza suffisso ("segnalazioni") vale come accesso pieno.
      final suffix = entry.split(RegExp(r'[^a-z0-9]+')).last;
      if (_readWords.contains(suffix)) {
        if (found == AppPermission.none) found = AppPermission.read;
      } else {
        return AppPermission.readWrite;
      }
    }
    return found;
  }

  static bool _isReportsKey(String key) {
    final k = key.toLowerCase();
    return _reportsKeys.any(k.contains);
  }

  static AppPermission _permissionFromValue(dynamic value) {
    if (value == null || value == false) return AppPermission.none;
    if (value == true) return AppPermission.readWrite;
    if (value is Map) {
      final write = value['write'] ?? value['scrittura'] ?? value['edit'];
      final read = value['read'] ?? value['lettura'] ?? value['view'];
      if (write == true) return AppPermission.readWrite;
      if (read == true) return AppPermission.read;
      return AppPermission.none;
    }
    if (value is List) {
      final words = value.map((v) => v.toString().toLowerCase()).toList();
      if (words.any(_writeWords.contains)) return AppPermission.readWrite;
      if (words.any(_readWords.contains)) return AppPermission.read;
      return AppPermission.none;
    }
    final word = value.toString().toLowerCase().trim();
    if (_writeWords.contains(word)) return AppPermission.readWrite;
    if (_readWords.contains(word)) return AppPermission.read;
    return AppPermission.none;
  }

  // ── Lettura delle risposte ─────────────────────────────────────

  /// Interpreta la risposta di un endpoint.
  ///
  /// Quando qualcosa va storto il server risponde con una pagina HTML
  /// invece che con JSON (404, 405, 500, redirect al login del sito):
  /// senza questo filtro `jsonDecode` lanciava e l'errore arrivava
  /// all'utente come un generico "Errore di connessione", nascondendo
  /// il codice HTTP. Qui il codice si vede, e il corpo della risposta
  /// finisce nel log di debug.
  static Map<String, dynamic> _decode(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) return body;
    } catch (_) {
      // Non e' JSON: si continua sotto con il messaggio di errore.
    }
    final request = response.request;
    final where = request == null
        ? 'richiesta sconosciuta'
        : '${request.method} ${request.url}';
    final preview = response.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    debugPrint(
      '[api] HTTP ${response.statusCode} su $where\n'
      '[api] ${_errorTitle(preview) ?? ''}'
      '${preview.length > 500 ? '${preview.substring(0, 500)}…' : preview}',
    );
    return {
      'success': false,
      'message': 'Errore del server (HTTP ${response.statusCode}).',
    };
  }

  /// Titolo della pagina di errore: nelle pagine di Symfony e' li' che
  /// finisce il messaggio dell'eccezione, ed e' la riga piu' utile del
  /// log quando il server risponde 500.
  static String? _errorTitle(String html) {
    final match =
        RegExp(r'<title>(.*?)</title>', caseSensitive: false).firstMatch(html);
    final title = match?.group(1)?.trim();
    return title == null || title.isEmpty ? null : '<$title> ';
  }

  /// Errore di rete: niente risposta dal server (host irraggiungibile,
  /// timeout, permesso INTERNET mancante, certificato non valido). Il
  /// motivo vero resta nel log di debug.
  static Map<String, dynamic> _connectionError(Object e) {
    debugPrint('[api] errore di rete: $e');
    return {'success': false, 'message': 'Errore di connessione.'};
  }

  /// Risposta di comodo per le chiamate in scrittura bloccate dal
  /// permesso: l'app la tratta come un errore qualsiasi e mostra il
  /// messaggio, senza aver toccato il server.
  static Map<String, dynamic> get _noWritePermission => {
    'success': false,
    'message': 'Non hai i permessi per modificare le segnalazioni.',
  };

  static bool isUnauthenticated(Map<String, dynamic> result) =>
      result['success'] == false &&
      (result['message'] as String? ?? '').contains('autenticato');

  // ── Auth ───────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));
      return _decode(response);
    } catch (e) {
      return _connectionError(e);
    }
  }

  static Future<void> logout() async {
    try {
      await http
          .post(Uri.parse('$baseUrl/api/logout'), headers: _authHeaders)
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
    await clearToken();
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/password-dimenticata'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));
      return _decode(response);
    } catch (e) {
      return _connectionError(e);
    }
  }

  // ── Tipi segnalazione ──────────────────────────────────────────

  static Future<Map<String, dynamic>> getReportTypes() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/tipi-segnalazione'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      return _decode(response);
    } catch (e) {
      return _connectionError(e);
    }
  }

  // ── Segnalazioni ───────────────────────────────────────────────

  static Future<Map<String, dynamic>> getMyReports() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/segnalazioni'), headers: _authHeaders)
          .timeout(const Duration(seconds: 15));
      return _decode(response);
    } catch (e) {
      return _connectionError(e);
    }
  }

  static Future<Map<String, dynamic>> getReportDetail(String id) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/segnalazioni/$id'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      return _decode(response);
    } catch (e) {
      return _connectionError(e);
    }
  }

  // ── Geocoding ──────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> autocompleteAddress(
    String query,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/api/autocomplete-indirizzo?q=${Uri.encodeComponent(query)}',
            ),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 10));
      final body = _decode(response);
      if (body['success'] == true) {
        return List<Map<String, dynamic>>.from(body['data'] as List);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Restituisce indirizzo e flag `in_corbetta` per le coordinate indicate.
  /// `null` se il servizio non risponde.
  static Future<Map<String, dynamic>?> reverseGeocode(
    double lat,
    double lon,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/reverse-geocode?lat=$lat&lon=$lon'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 10));
      final body = _decode(response);
      if (body['success'] == true && body['data'] != null) {
        return Map<String, dynamic>.from(body['data'] as Map);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Crea una segnalazione. Con [status] `in_creazione` resta una bozza
  /// modificabile; con `pending` viene inviata al Comune.
  static Future<Map<String, dynamic>> createReport({
    required String typeId,
    String? details,
    String? address,
    String? latitude,
    String? longitude,
    List<String> imagePaths = const [],
    String status = 'pending',
  }) async {
    if (!canWrite) return _noWritePermission;
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/segnalazioni'),
      );
      request.headers['X-AUTH-TOKEN'] = token ?? '';
      request.fields['type_id'] = typeId;
      request.fields['status'] = status;
      if (details != null && details.isNotEmpty) {
        request.fields['details'] = details;
      }
      if (address != null && address.isNotEmpty) {
        request.fields['address'] = address;
      }
      if (latitude != null) request.fields['latitude'] = latitude;
      if (longitude != null) request.fields['longitude'] = longitude;

      await _attachImages(request, imagePaths);

      final streamed = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } catch (e) {
      return _connectionError(e);
    }
  }

  /// Aggiorna una bozza o una segnalazione ancora in attesa.
  static Future<Map<String, dynamic>> updateReport({
    required String id,
    String? typeId,
    String? details,
    String? address,
    String? latitude,
    String? longitude,
    List<String> imagePaths = const [],
    String? status,
  }) async {
    if (!canWrite) return _noWritePermission;
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/segnalazioni/$id'),
      );
      request.headers['X-AUTH-TOKEN'] = token ?? '';
      if (typeId != null) request.fields['type_id'] = typeId;
      if (details != null) request.fields['details'] = details;
      if (address != null) request.fields['address'] = address;
      if (latitude != null) request.fields['latitude'] = latitude;
      if (longitude != null) request.fields['longitude'] = longitude;
      if (status != null) request.fields['status'] = status;

      await _attachImages(request, imagePaths);

      final streamed = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } catch (e) {
      return _connectionError(e);
    }
  }

  static Future<Map<String, dynamic>> deleteReport(String id) async {
    if (!canWrite) return _noWritePermission;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/segnalazioni/$id/elimina'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      return _decode(response);
    } catch (e) {
      return _connectionError(e);
    }
  }

  /// Comprime le foto (obiettivo 400 KB) e le allega alla richiesta multipart.
  static Future<void> _attachImages(
    http.MultipartRequest request,
    List<String> imagePaths,
  ) async {
    final compressed = await ImageCompressor.compressAll(imagePaths);
    for (final path in compressed) {
      request.files.add(
        await http.MultipartFile.fromPath('attachments[]', path),
      );
    }
  }
}
