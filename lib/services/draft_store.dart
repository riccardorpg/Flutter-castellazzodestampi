import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Bozze salvate solo su questo dispositivo.
///
/// Non vengono mai inviate al Comune: restano nell'app, visibili nel
/// filtro "In creazione" con colore grigio, finche' l'utente non le
/// invia dalla scheda (a quel punto diventano segnalazioni "In attesa"
/// sul server e la copia locale viene cancellata).
class DraftStore {
  static const String _key = 'local_drafts';

  /// Riconosce una bozza locale da una segnalazione arrivata dal server.
  static bool isLocal(Map<String, dynamic> report) => report['is_local'] == true;

  static Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      // dati corrotti: meglio ripartire da zero che bloccare la lista
      return [];
    }
  }

  /// Inserisce una nuova bozza o aggiorna quella con lo stesso [localId].
  /// Restituisce il record salvato.
  static Future<Map<String, dynamic>> save({
    required Map<String, dynamic> reportType,
    required String details,
    required String address,
    String? latitude,
    String? longitude,
    List<String> imagePaths = const [],
    String? localId,
  }) async {
    final drafts = await load();
    final now = DateTime.now();
    final id = localId ?? 'local_${now.microsecondsSinceEpoch}';

    // Modificando una bozza la data di creazione non cambia: l'elenco
    // resta in ordine di inserimento.
    final previous =
        drafts.where((d) => d['id']?.toString() == id).toList();
    final created = previous.isEmpty
        ? now.toIso8601String()
        : previous.first['datetime']?.toString() ?? now.toIso8601String();

    final draft = <String, dynamic>{
      'id': id,
      'is_local': true,
      'status': 'in_creazione',
      'status_label': 'In creazione',
      'type': reportType,
      'details': details,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'image_paths': imagePaths,
      'datetime': created,
      'updated_at': now.toIso8601String(),
    };
    drafts.removeWhere((d) => d['id']?.toString() == id);
    drafts.add(draft);
    await _persist(drafts);
    return draft;
  }

  static Future<void> delete(String id) async {
    final drafts = await load();
    drafts.removeWhere((d) => d['id']?.toString() == id);
    await _persist(drafts);
  }

  static Future<void> _persist(List<Map<String, dynamic>> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(drafts));
  }
}
