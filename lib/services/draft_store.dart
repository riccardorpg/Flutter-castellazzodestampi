import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Bozze salvate solo su questo dispositivo.
///
/// Non vengono mai inviate al Comune: restano nell'app, visibili nel
/// filtro "In creazione" con colore grigio, finche' l'utente non le
/// invia dalla scheda (a quel punto diventano segnalazioni "In attesa"
/// sul server e la copia locale viene cancellata).
///
/// Ogni utente ha il suo contenitore, intestato all'id che manda il
/// server: su un telefono usato da piu' account, ognuno vede in elenco
/// solo le bozze che ha scritto lui. Prima erano in un unico elenco
/// condiviso e comparivano a chiunque entrasse.
class DraftStore {
  /// Elenco unico delle versioni precedenti, prima dei contenitori per
  /// utente. Vale ancora come contenitore di ripiego quando l'id
  /// dell'utente non si conosce (API che `user.id` non lo mandano).
  static const String _legacyKey = 'local_drafts';

  /// Contenitore dell'utente collegato.
  static String get _key {
    final id = ApiService.userId;
    return (id == null || id.isEmpty) ? _legacyKey : '${_legacyKey}_$id';
  }

  /// Riconosce una bozza locale da una segnalazione arrivata dal server.
  static bool isLocal(Map<String, dynamic> report) =>
      report['is_local'] == true;

  static Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacy(prefs);
    return _read(prefs, _key);
  }

  /// Sposta l'elenco condiviso delle versioni precedenti nel contenitore
  /// dell'utente collegato, e solo se questo e' ancora vuoto: cioe' al
  /// primo accesso dopo l'aggiornamento, cosi' chi aveva bozze in corso
  /// non le perde. Poi la chiave vecchia viene rimossa e da li' in avanti
  /// nessun altro account se le ritrova in elenco.
  static Future<void> _migrateLegacy(SharedPreferences prefs) async {
    final key = _key;
    // Utente sconosciuto: si sta ancora usando l'elenco vecchio.
    if (key == _legacyKey) return;
    final legacy = prefs.getString(_legacyKey);
    if (legacy == null || legacy.isEmpty) return;
    if ((prefs.getString(key) ?? '').isEmpty) {
      await prefs.setString(key, legacy);
    }
    await prefs.remove(_legacyKey);
  }

  static List<Map<String, dynamic>> _read(
    SharedPreferences prefs,
    String key,
  ) {
    final raw = prefs.getString(key);
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
    final previous = drafts.where((d) => d['id']?.toString() == id).toList();
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
