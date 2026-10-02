import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:castellazzodestampi/form.dart';
import 'package:castellazzodestampi/services/api_service.dart';

/// Una segnalazione gia' inviata, ancora modificabile, con una foto
/// caricata sul server.
const _report = {
  'id': '42',
  'type': {'id': 1, 'name': 'Illuminazione pubblica'},
  'details': 'Lampione spento.',
  'address': 'Via Roma 1, Corbetta',
  'latitude': '45.4680',
  'longitude': '8.9160',
  'status': 'pending',
  'can_edit': true,
  'attachments': [
    {
      'file_name': '66a1b2c3d4e5f.jpg',
      'file_path': '/uploads/reports/42/66a1b2c3d4e5f.jpg',
      'thumb_path': '/uploads/reports/42/thumb_66a1b2c3d4e5f.jpg',
    },
  ],
};

/// Raccoglie il valore con cui il form si e' chiuso: e' quello su cui la
/// scheda decide se rileggere la segnalazione dal server.
class _Host {
  final popped = <Object?>[];
}

Future<_Host> _openForm(WidgetTester tester) async {
  final host = _Host();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                host.popped.add(
                  await Navigator.push<Object?>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FormScreen(
                        reportType: {'id': 1, 'name': 'Illuminazione pubblica'},
                        report: _report,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('apri'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('apri'));
  await tester.pumpAndSettle();
  return host;
}

/// I test non devono uscire in rete: senza questo, la chiamata di
/// eliminazione parte davvero verso il sito del Comune.
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('rete disabilitata nei test');
}

void main() {
  setUpAll(() => HttpOverrides.global = _NoNetwork());
  tearDownAll(() => HttpOverrides.global = null);

  setUp(() => ApiService.permission = AppPermission.readWrite);
  tearDown(() => ApiService.permission = AppPermission.none);

  testWidgets('la foto gia\' caricata si vede e ha la x per toglierla', (
    tester,
  ) async {
    await _openForm(tester);
    expect(find.text('FOTO (opzionale)'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('il tasto indietro di sistema passa dalla conferma '
      'invece di uscire di colpo', (tester) async {
    final host = await _openForm(tester);

    await tester.enterText(
      find.byType(TextField).first,
      'Lampione spento da giorni.',
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Annullare le modifiche?'), findsOneWidget);
    expect(
      find.text('SALVA MODIFICHE'),
      findsOneWidget,
      reason: 'resta nel form',
    );
    expect(host.popped, isEmpty);

    await tester.tap(find.text('Continua a modificare'));
    await tester.pumpAndSettle();
    expect(find.text('SALVA MODIFICHE'), findsOneWidget);
  });

  testWidgets('la freccia in alto chiede la stessa conferma', (tester) async {
    await _openForm(tester);

    await tester.enterText(find.byType(TextField).first, 'Testo cambiato.');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    expect(find.text('Annullare le modifiche?'), findsOneWidget);
  });

  testWidgets('uscendo senza aver tolto foto la scheda non ricarica', (
    tester,
  ) async {
    final host = await _openForm(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('SALVA MODIFICHE'), findsNothing, reason: 'form chiuso');
    // false, non null: la scheda tiene i dati che ha.
    expect(host.popped, [false]);
  });

  testWidgets('se il server rifiuta la cancellazione la foto resta e '
      'compare l\'errore', (tester) async {
    // In test la rete non c'e': la chiamata fallisce, ed e' esattamente il
    // caso in cui l'app non deve far sparire la foto dall'elenco ne'
    // dire alla scheda che qualcosa e' cambiato.
    final host = await _openForm(tester);

    final x = find.byIcon(Icons.close);
    await tester.ensureVisible(x);
    await tester.pumpAndSettle();
    await tester.tap(x);
    await tester.pumpAndSettle();
    expect(find.text('Eliminare la foto?'), findsOneWidget);

    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close), findsOneWidget, reason: 'la foto resta');
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(host.popped, [false], reason: 'niente e\' stato eliminato');
  });
}
