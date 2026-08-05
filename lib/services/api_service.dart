import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'image_compressor.dart';

class ApiService {
  // Produzione
  static const String baseUrl = 'https://www.castellazzodestampi.org';
  // Sviluppo locale (decommentare per usare in locale)
  // static const String baseUrl = 'http://localhost/S7-www.castellazzodestampi.org/public';

  static const String _tokenKey = 'auth_token';
  static String? token;

  static Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'X-AUTH-TOKEN': token ?? '',
      };

  // ── Persistenza token ──────────────────────────────────────────

  static Future<void> saveToken(String t) async {
    token = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, t);
  }

  /// Restituisce true se esiste un token salvato.
  static Future<bool> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_tokenKey);
    if (saved != null && saved.isNotEmpty) {
      token = saved;
      return true;
    }
    return false;
  }

  static Future<void> clearToken() async {
    token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  static bool isUnauthenticated(Map<String, dynamic> result) =>
      result['success'] == false &&
      (result['message'] as String? ?? '').contains('autenticato');

  // ── Auth ───────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Errore di connessione.'};
    }
  }

  static Future<void> logout() async {
    try {
      await http
          .post(
            Uri.parse('$baseUrl/api/logout'),
            headers: _authHeaders,
          )
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
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Errore di connessione.'};
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
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Errore di connessione.'};
    }
  }

  // ── Segnalazioni ───────────────────────────────────────────────

  static Future<Map<String, dynamic>> getMyReports() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/segnalazioni'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Errore di connessione.'};
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
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Errore di connessione.'};
    }
  }

  // ── Geocoding ──────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> autocompleteAddress(String query) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/autocomplete-indirizzo?q=${Uri.encodeComponent(query)}'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
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
      double lat, double lon) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/reverse-geocode?lat=$lat&lon=$lon'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
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

      final streamed =
          await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Errore di connessione.'};
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

      final streamed =
          await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Errore di connessione.'};
    }
  }

  static Future<Map<String, dynamic>> deleteReport(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/segnalazioni/$id/elimina'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Errore di connessione.'};
    }
  }

  /// Comprime le foto sopra 1 MB e le allega alla richiesta multipart.
  static Future<void> _attachImages(
      http.MultipartRequest request, List<String> imagePaths) async {
    final compressed = await ImageCompressor.compressAll(imagePaths);
    for (final path in compressed) {
      request.files.add(await http.MultipartFile.fromPath(
        'attachments[]',
        path,
      ));
    }
  }
}
