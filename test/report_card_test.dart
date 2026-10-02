import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:castellazzodestampi/segnalazioni.dart';

Map<String, dynamic> _report({
  String typeName = 'Illuminazione pubblica',
  String statusLabel = 'In lavorazione',
  String status = 'in_progress',
}) => {
  'id': '42',
  'type': {'id': 1, 'name': typeName},
  'address': 'Via Giuseppe Garibaldi 128, Corbetta (MI)',
  'status': status,
  'status_label': statusLabel,
  'datetime': '2026-09-01T10:30:00',
};

Future<void> _pump(
  WidgetTester tester,
  Map<String, dynamic> report, {
  Size size = const Size(411, 915),
  double textScale = 1.0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ReportCard(report: report, onChanged: () async {}),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Quanto spazio resta fra il badge e il bordo destro della card.
/// Deve valere solo i padding fissi (bordo 1 + padding card 14 + padding
/// interno del badge 8): se cresce, il badge non e' piu' appoggiato a
/// destra ma e' scivolato verso il centro.
double _gapADestra(WidgetTester tester, String label) {
  final card = tester.getRect(find.byType(ReportCard));
  final badge = tester.getRect(find.text(label.toUpperCase()));
  return card.right - badge.right;
}

void main() {
  // Con un'etichetta corta il divario e' enorme se il badge prende flex:
  // e' il caso che smaschera la regressione.
  for (final label in ['In attesa', 'Risolte', 'In lavorazione']) {
    testWidgets('il badge "$label" resta appoggiato al bordo destro', (
      tester,
    ) async {
      await _pump(tester, _report(statusLabel: label));

      expect(
        _gapADestra(tester, label),
        lessThan(30),
        reason: 'il badge deve stare a destra, non in mezzo alla card',
      );

      final card = tester.getRect(find.byType(ReportCard));
      final badge = tester.getRect(find.text(label.toUpperCase()));
      final typeName = tester.getRect(find.text('Illuminazione pubblica'));
      // Il nome del tipo parte da sinistra e non tocca il badge.
      expect(typeName.left, lessThan(card.center.dx));
      expect(typeName.right, lessThanOrEqualTo(badge.left));
    });
  }

  testWidgets('resta a destra anche con la dicitura di stato piu\' lunga', (
    tester,
  ) async {
    const label = 'In attesa di presa in carico';
    await _pump(tester, _report(statusLabel: label));
    expect(_gapADestra(tester, label), lessThan(30));
  });

  testWidgets('non sfonda su telefono stretto coi caratteri ingranditi', (
    tester,
  ) async {
    await _pump(
      tester,
      _report(typeName: 'Segnalazione di illuminazione pubblica guasta'),
      size: const Size(320, 568),
      textScale: 1.35,
    );
    expect(tester.takeException(), isNull);

    final card = tester.getRect(find.byType(ReportCard));
    final badge = tester.getRect(find.text('IN LAVORAZIONE'));
    expect(badge.right, lessThanOrEqualTo(card.right));
    expect(_gapADestra(tester, 'In lavorazione'), lessThan(30));
  });

  testWidgets('una bozza locale dice "In creazione"', (tester) async {
    final draft = _report()
      ..['is_local'] = true
      ..['status'] = 'in_creazione';
    await _pump(tester, draft);

    expect(find.text('IN CREAZIONE'), findsOneWidget);
  });
}
