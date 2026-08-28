import 'package:flutter_test/flutter_test.dart';
import 'package:segnalazioni_app/services/api_service.dart';

void main() {
  AppPermission p(Map<String, dynamic>? user) =>
      ApiService.permissionFromUser(user);

  test('permessi a oggetto', () {
    expect(
      p({
        'permissions': {'segnalazioni': 'rw'},
      }),
      AppPermission.readWrite,
    );
    expect(
      p({
        'permissions': {'segnalazioni': 'r'},
      }),
      AppPermission.read,
    );
    expect(
      p({
        'permissions': {'segnalazioni': 'lettura'},
      }),
      AppPermission.read,
    );
    expect(
      p({
        'permissions': {'segnalazioni': ''},
      }),
      AppPermission.none,
    );
    expect(
      p({
        'permissions': {'segnalazioni': null},
      }),
      AppPermission.none,
    );
    expect(
      p({
        'permissions': {'segnalazioni': true},
      }),
      AppPermission.readWrite,
    );
    expect(
      p({
        'permissions': {'segnalazioni': false},
      }),
      AppPermission.none,
    );
    expect(
      p({
        'permissions': {'altro': 'rw'},
      }),
      AppPermission.none,
    );
    expect(
      p({
        'permissions': {
          'segnalazioni': {'read': true, 'write': true},
        },
      }),
      AppPermission.readWrite,
    );
    expect(
      p({
        'permissions': {
          'segnalazioni': {'read': true, 'write': false},
        },
      }),
      AppPermission.read,
    );
  });

  test('permessi a lista e ruoli', () {
    expect(
      p({
        'permissions': ['segnalazioni_write'],
      }),
      AppPermission.readWrite,
    );
    expect(
      p({
        'permissions': ['segnalazioni:r'],
      }),
      AppPermission.read,
    );
    expect(
      p({
        'permissions': ['altro_write'],
      }),
      AppPermission.none,
    );
    expect(
      p({
        'roles': ['ROLE_USER', 'ROLE_SEGNALAZIONI_READ'],
      }),
      AppPermission.read,
    );
    expect(
      p({
        'roles': ['ROLE_SEGNALAZIONI_WRITE'],
      }),
      AppPermission.readWrite,
    );
    expect(
      p({
        'permissions': ['segnalazioni_read', 'segnalazioni_write'],
      }),
      AppPermission.readWrite,
    );
  });

  test('API vecchia senza permessi: accesso pieno', () {
    expect(p({'role': 'ROLE_USER'}), AppPermission.readWrite);
    expect(p({'id': '1', 'email': 'a@b.c'}), AppPermission.readWrite);
    expect(p(null), AppPermission.readWrite);
  });
}
