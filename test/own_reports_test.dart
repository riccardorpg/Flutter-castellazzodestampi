import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:castellazzodestampi/services/api_service.dart';
import 'package:castellazzodestampi/services/draft_store.dart';

/// Blocco `user` come lo manda il server, per l'id indicato.
Map<String, dynamic> _user(int id) => {
  'id': id,
  'email': 'utente$id@example.com',
  'permissions': {'segnalazioni': 'rw', 'reports': 'rw'},
  'canManageReports': false,
};

/// Segnalazione in elenco, come la serializza l'API.
Map<String, dynamic> _report(String id, {bool? isOwner}) => {
  'id': id,
  'status': 'pending',
  'is_owner': ?isOwner,
};

/// Salva una bozza minima, quel tanto che basta a ritrovarla in elenco.
Future<Map<String, dynamic>> _saveDraft(String details) => DraftStore.save(
  reportType: {'id': 1, 'name': 'Illuminazione'},
  details: details,
  address: 'Via Roma 12',
);

Future<void> _login(int id) =>
    ApiService.saveToken('tok$id', AppPermission.readWrite, id: '$id');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.token = null;
    ApiService.userId = null;
    ApiService.permission = AppPermission.none;
  });

  group('in elenco vanno solo le proprie segnalazioni', () {
    test('quelle di altri vengono scartate', () {
      final kept = ApiService.onlyMine([
        _report('1', isOwner: true),
        _report('2', isOwner: false),
        _report('3', isOwner: true),
      ]);
      expect(kept.map((r) => r['id']), ['1', '3']);
    });

    test('senza is_owner non si scarta niente (API precedenti)', () {
      final kept = ApiService.onlyMine([_report('1'), _report('2')]);
      expect(kept.length, 2);
    });
  });

  group('id dell\'utente collegato', () {
    test('arriva col login e resta al riavvio dell\'app', () async {
      await _login(7);
      expect(ApiService.userId, '7');

      ApiService.token = null;
      ApiService.userId = null;
      expect(await ApiService.loadToken(), isTrue);
      expect(ApiService.userId, '7');
    });

    test('un\'installazione senza id lo ritrova con l\'elenco', () async {
      await ApiService.saveToken('tok', AppPermission.readWrite);
      expect(ApiService.userId, isNull);

      await ApiService.syncPermissionFrom({'user': _user(7)});
      expect(ApiService.userId, '7');
    });

    test('uscendo non resta niente addosso al dispositivo', () async {
      await _login(7);
      await ApiService.clearToken();
      expect(ApiService.userId, isNull);
    });
  });

  group('le bozze locali sono di chi le ha scritte', () {
    test('un altro account non se le ritrova in elenco', () async {
      await _login(1);
      await _saveDraft('bozza di uno');
      expect(await DraftStore.load(), hasLength(1));

      // Cambio account sullo stesso telefono.
      await ApiService.clearToken();
      await _login(2);
      expect(await DraftStore.load(), isEmpty);

      // E chi l'ha scritta la ritrova dov'era.
      await ApiService.clearToken();
      await _login(1);
      final drafts = await DraftStore.load();
      expect(drafts, hasLength(1));
      expect(drafts.first['details'], 'bozza di uno');
    });

    test('eliminare una bozza non tocca quelle dell\'altro', () async {
      await _login(1);
      final mia = await _saveDraft('bozza di uno');
      await ApiService.clearToken();
      await _login(2);
      await _saveDraft('bozza di due');

      await DraftStore.delete(mia['id'].toString());

      expect(await DraftStore.load(), hasLength(1));
      await ApiService.clearToken();
      await _login(1);
      expect(await DraftStore.load(), hasLength(1));
    });

    test('le bozze della versione precedente non si perdono', () async {
      // Elenco condiviso salvato da una versione senza contenitori.
      SharedPreferences.setMockInitialValues({
        'local_drafts': jsonEncode([
          {'id': 'local_1', 'is_local': true, 'details': 'bozza vecchia'},
        ]),
      });

      await _login(1);
      final drafts = await DraftStore.load();
      expect(drafts, hasLength(1));
      expect(drafts.first['details'], 'bozza vecchia');

      // Recuperate una volta sola: al secondo account non ricompaiono.
      await ApiService.clearToken();
      await _login(2);
      expect(await DraftStore.load(), isEmpty);
    });
  });
}
