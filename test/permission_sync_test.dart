import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:segnalazioni_app/services/api_service.dart';

/// Blocco `user` come lo manda il server, con il permesso indicato.
Map<String, dynamic> _user(String reports) => {
  'id': 1,
  'email': 'mario@example.com',
  'permissions': {'segnalazioni': reports, 'reports': reports},
  'canManageReports': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.token = null;
    ApiService.userId = null;
    ApiService.permission = AppPermission.none;
  });

  group('nell\'app "r" e "rw" sono equivalenti', () {
    test('chi ha la sola lettura sul sito puo\' comunque segnalare', () {
      ApiService.permission = AppPermission.read;
      expect(ApiService.canRead, isTrue);
      expect(ApiService.canWrite, isTrue);
    });

    test('chi ha lettura e scrittura puo\' segnalare', () {
      ApiService.permission = AppPermission.readWrite;
      expect(ApiService.canWrite, isTrue);
    });

    test('senza permesso non si fa niente', () {
      ApiService.permission = AppPermission.none;
      expect(ApiService.canRead, isFalse);
      expect(ApiService.canWrite, isFalse);
    });
  });

  group('riallineamento del permesso senza rifare il login', () {
    test('il permesso tolto dal sito arriva con l\'elenco', () async {
      await ApiService.saveToken('tok', AppPermission.readWrite);
      expect(ApiService.canWrite, isTrue);

      await ApiService.syncPermissionFrom({
        'success': true,
        'data': [],
        'user': _user(''),
      });

      expect(ApiService.permission, AppPermission.none);
      expect(ApiService.canRead, isFalse);
    });

    test('il permesso dato dal sito arriva con l\'elenco', () async {
      await ApiService.saveToken('tok', AppPermission.read);

      await ApiService.syncPermissionFrom({
        'success': true,
        'data': [],
        'user': _user('rw'),
      });

      expect(ApiService.permission, AppPermission.readWrite);
    });

    test('il permesso aggiornato resta anche al riavvio dell\'app', () async {
      await ApiService.saveToken('tok', AppPermission.readWrite);
      await ApiService.syncPermissionFrom({'user': _user('r')});

      // Riavvio: le variabili in memoria si perdono, il token si rilegge.
      ApiService.token = null;
      ApiService.permission = AppPermission.none;
      expect(await ApiService.loadToken(), isTrue);
      expect(ApiService.permission, AppPermission.read);
    });

    test('revocato il permesso, al riavvio non si rientra', () async {
      await ApiService.saveToken('tok', AppPermission.readWrite);
      await ApiService.syncPermissionFrom({'user': _user('')});

      ApiService.token = null;
      ApiService.permission = AppPermission.none;
      expect(await ApiService.loadToken(), isFalse);
    });

    test('API senza blocco user: il permesso del login resta buono', () async {
      await ApiService.saveToken('tok', AppPermission.readWrite);

      await ApiService.syncPermissionFrom({'success': true, 'data': []});

      expect(ApiService.permission, AppPermission.readWrite);
    });

    test('permesso invariato: non si tocca niente', () async {
      await ApiService.saveToken('tok', AppPermission.readWrite);
      await ApiService.syncPermissionFrom({'user': _user('rw')});
      expect(ApiService.permission, AppPermission.readWrite);
    });
  });
}
