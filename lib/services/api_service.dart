import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'image_compressor.dart';

/// Permesso dell'utente sul modulo segnalazioni, come arriva dal server.
///
/// * [none] – nessun accesso: il login viene rifiutato con un avviso.
/// * [read] – permesso "r" sul sito.
/// * [readWrite] – permesso "rw" sul sito.
///
/// Dentro l'app [read] e [readWrite] si comportano allo stesso modo: chi
/// entra puo' sempre creare e modificare le proprie segnalazioni (vedi
/// [ApiService.canWrite]). La distinzione si conserva perche' e' il valore
/// vero del sito, dove invece separa chi consulta da chi scrive.
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
  static const String _userIdKey = 'auth_user_id';
  static String? token;

  /// Id dell'utente collegato, come arriva dal server (`user.id`).
  ///
  /// Serve a tenere separato quello che l'app salva sul dispositivo: le
  /// bozze locali stanno in un contenitore per utente, cosi' su un
  /// telefono usato da piu' account nessuno vede le bozze di un altro
  /// (vedi DraftStore). Resta salvato insieme al token, perche' al
  /// riavvio il login non viene rifatto.
  static String? userId;

  /// Permesso dell'utente sulle segnalazioni: lo manda il login e resta
  /// salvato sul dispositivo, perche' al riavvio dell'app il login non
  /// viene rifatto (si riusa il token).
  static AppPermission permission = AppPermission.none;

  /// Puo' usare l'app.
  static bool get canRead => permission != AppPermission.none;

  /// Puo' creare, modificare ed eliminare le PROPRIE segnalazioni e bozze.
  ///
  /// Nell'app "r" e "rw" sono la stessa cosa: il permesso "Invio segnalazioni
  /// (app)" decide chi entra, non cosa puo' fare una volta dentro. Chi ha un
  /// accesso e' un cittadino che segnala, quindi scrive sempre. La differenza
  /// fra consultazione e scrittura resta valida sul sito.
  ///
  /// Restano comunque le sole proprie: quali schede aprano Modifica ed
  /// Elimina lo dice il campo `can_edit` che il server manda con ognuna.
  static bool get canWrite => canRead;

  static Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    'X-AUTH-TOKEN': token ?? '',
  };

  // ── Persistenza token e permesso ───────────────────────────────

  static Future<void> saveToken(
    String t,
    AppPermission p, {
    String? id,
  }) async {
    token = t;
    permission = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, t);
    await prefs.setString(_permissionKey, p.name);
    await _saveUserId(id);
  }

  /// Salva l'id dell'utente collegato. Con [id] nullo o vuoto (API vecchie,
  /// che `user.id` non lo mandano) il valore salvato viene rimosso: meglio
  /// non saperlo che tenersi quello di un altro accesso.
  static Future<void> _saveUserId(String? id) async {
    userId = (id == null || id.isEmpty) ? null : id;
    final prefs = await SharedPreferences.getInstance();
    if (userId == null) {
      await prefs.remove(_userIdKey);
    } else {
      await prefs.setString(_userIdKey, userId!);
    }
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
    userId = prefs.getString(_userIdKey);
    return true;
  }

  static Future<void> clearToken() async {
    token = null;
    permission = AppPermission.none;
    userId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_permissionKey);
    await prefs.remove(_userIdKey);
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
      // Confronto esatto, non "la chiave contiene segnalazioni/reports":
      // sul sito esiste anche il permesso "reports_manage" (gestione in area
      // riservata), che contiene "reports" ma NON e' il permesso dell'app.
      // Cercandolo per sottostringa si rischiava di leggere quello.
      for (final wanted in _reportsKeys) {
        for (final key in permissions.keys) {
          if (key.toString().toLowerCase().trim() != wanted) continue;
          return _permissionFromValue(permissions[key]);
        }
      }
      // Nessuna chiave esatta: si ricade sul confronto larga maniera, per i
      // backend che il modulo lo chiamano in un altro modo. Le chiavi della
      // gestione restano fuori.
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
    // "reports_manage"/"gestione_segnalazioni" sono la gestione in area
    // riservata, non il permesso dell'app: qui non devono passare.
    if (_manageWords.any(k.contains)) return false;
    return _reportsKeys.any(k.contains);
  }

  /// Parole che identificano il permesso di gestione, non quello dell'app.
  static const _manageWords = ['manage', 'gestione', 'gestisci'];

  // Il backend manda anche `user.canManageReports` ("Gestione segnalazioni"
  // sul sito). L'app non lo legge: da qui ognuno vede e gestisce le proprie,
  // chiunque sia, e vedere tutte le segnalazioni resta un lavoro da area
  // riservata.

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
    final match = RegExp(
      r'<title>(.*?)</title>',
      caseSensitive: false,
    ).firstMatch(html);
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
      final result = _decode(response);
      await syncPermissionFrom(result);
      return result;
    } catch (e) {
      return _connectionError(e);
    }
  }

  /// Tiene dell'elenco le sole segnalazioni inserite dall'utente collegato.
  ///
  /// L'API manda gia' solo le proprie, e con ognuna il campo `is_owner`:
  /// questo filtro e' la rete di sicurezza. Se il server in elenco rimanda
  /// anche quelle di altri — un backend non ancora aggiornato, o il
  /// permesso di gestione che sul sito fa vedere tutto — dall'app non si
  /// vedono comunque. Le segnalazioni senza `is_owner` (API precedenti,
  /// che il campo non lo mandano) restano: non c'e' modo di distinguerle.
  static List<Map<String, dynamic>> onlyMine(
    List<Map<String, dynamic>> reports,
  ) => reports.where((r) => r['is_owner'] != false).toList();

  /// Riallinea il permesso salvato a quello che il server manda insieme
  /// all'elenco, nel blocco `user`.
  ///
  /// Il permesso arriva col login e resta sul dispositivo finche' non si
  /// esce: cambiandolo dal sito, l'app non se ne accorgeva fino al logout.
  /// L'elenco viene ricaricato all'apertura, col pull-to-refresh e tornando
  /// da ogni schermata, quindi e' il punto giusto dove riallinearsi senza
  /// aggiungere chiamate.
  ///
  /// Le API precedenti il blocco `user` non lo mandano: in quel caso non si
  /// tocca niente e resta valido il permesso del login.
  static Future<void> syncPermissionFrom(Map<String, dynamic> result) async {
    final user = result['user'];
    if (user is! Map) return;
    final data = Map<String, dynamic>.from(user);

    // Anche l'id viaggia col blocco utente: qui si riallinea insieme al
    // permesso, cosi' un'installazione aggiornata da una versione che non
    // lo salvava lo ritrova al primo caricamento dell'elenco, senza
    // rifare l'accesso.
    final freshId = data['id']?.toString();
    if (freshId != null && freshId.isNotEmpty && freshId != userId) {
      await _saveUserId(freshId);
    }

    final fresh = permissionFromUser(data);
    if (fresh == permission) return;

    permission = fresh;
    final prefs = await SharedPreferences.getInstance();
    if (fresh == AppPermission.none) {
      // Permesso revocato: il token non serve piu' a niente. Chi chiama se
      // ne accorge da `canRead` e riporta al login.
      await prefs.remove(_permissionKey);
    } else {
      await prefs.setString(_permissionKey, fresh.name);
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

  /// Elimina una foto gia' caricata sul server.
  ///
  /// [fileName] e' il campo `file_name` dell'allegato, come arriva dall'API.
  /// Il server la accetta solo sulle proprie segnalazioni ancora modificabili
  /// (bozza o in attesa) e nella risposta rimanda la segnalazione aggiornata,
  /// senza quella foto.
  static Future<Map<String, dynamic>> deleteAttachment(
    String id,
    String fileName,
  ) async {
    if (!canWrite) return _noWritePermission;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/segnalazioni/$id/allegati/elimina'),
            headers: _authHeaders,
            body: jsonEncode({'file_name': fileName}),
          )
          .timeout(const Duration(seconds: 15));
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
