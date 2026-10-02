import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:castellazzodestampi/form.dart';
import 'package:castellazzodestampi/scheda.dart';
import 'package:castellazzodestampi/services/api_service.dart';
import 'package:castellazzodestampi/utils/responsive.dart';
import 'package:castellazzodestampi/widgets/action_bar.dart';
import 'package:castellazzodestampi/widgets/bottom_nav_bar.dart';

/// Un formato di schermo reale su cui l'app deve funzionare.
class _Device {
  final String name;

  /// Dimensioni in dp logici.
  final Size size;

  /// Ingombro di sistema in basso: barra gesti Android, home indicator
  /// iPhone, 0 sui tre tasti classici.
  final double bottomInset;

  final double topInset;

  const _Device(
    this.name,
    this.size, {
    this.bottomInset = 0,
    this.topInset = 0,
  });
}

/// Il formato con questo nome. Cercarlo per nome e non per posizione:
/// aggiungendo un device in mezzo alla lista, gli indici slittavano.
_Device _dev(String name) => _devices.firstWhere((d) => d.name == name);

const _devices = [
  // Android piccolo coi tre tasti: nessun ingombro sotto.
  _Device('Android compatto', Size(320, 568)),
  // Android con barra gesti: e' il caso in cui la barra spariva.
  _Device('Android gesti', Size(411, 915), bottomInset: 48, topInset: 24),
  // Android con i tre tasti a schermo.
  _Device('Android 3 tasti', Size(411, 823), bottomInset: 24, topInset: 24),
  _Device('iPhone SE', Size(375, 667), topInset: 20),
  _Device('iPhone Pro Max', Size(430, 932), bottomInset: 34, topInset: 59),
  _Device('Android coricato', Size(915, 411), bottomInset: 24, topInset: 0),
  _Device('iPhone coricato', Size(932, 430), bottomInset: 21, topInset: 0),
  _Device('iPad verticale', Size(768, 1024), bottomInset: 20, topInset: 24),
  _Device('iPad Pro orizzontale', Size(1366, 1024), bottomInset: 20),
];

/// Applica il formato del device alla finestra di test.
Future<void> _useDevice(WidgetTester tester, _Device device) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = device.size;
  tester.view.viewPadding = FakeViewPadding(
    top: device.topInset,
    bottom: device.bottomInset,
  );
  tester.view.padding = FakeViewPadding(
    top: device.topInset,
    bottom: device.bottomInset,
  );
  addTearDown(tester.view.reset);
}

void main() {
  group('BottomNavBar', () {
    for (final device in _devices) {
      testWidgets('resta visibile sopra l\'ingombro di sistema — '
          '${device.name}', (tester) async {
        await _useDevice(tester, device);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: BottomNavBar(
                icon: Icons.list_alt,
                label: 'Le mie segnalazioni',
                onTap: () {},
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull, reason: 'nessun overflow');

        // Il cuore del bug: la scritta finiva sotto la barra gesti.
        final label = tester.getRect(find.text('Le mie segnalazioni'));
        final safeBottom = device.size.height - device.bottomInset;
        expect(
          label.bottom,
          lessThanOrEqualTo(safeBottom),
          reason: 'la voce non deve finire sotto la barra di sistema',
        );
        expect(label.left, greaterThanOrEqualTo(0));
        expect(label.right, lessThanOrEqualTo(device.size.width));
      });
    }

    testWidgets('coi caratteri di sistema ingranditi la barra cresce '
        'invece di tagliare la scritta', (tester) async {
      await _useDevice(tester, _dev('Android gesti'));

      Future<double> barHeight(double scale) async {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: BottomNavBar(
                icon: Icons.add_circle_outline,
                label: 'Nuova',
                onTap: () {},
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        return tester.getSize(find.byType(BottomNavBar)).height;
      }

      final normale = await barHeight(1.0);
      final grande = await barHeight(1.35);
      expect(grande, greaterThan(normale));
    });
  });

  group('FormScreen', _formScreenTests);

  group('SchedaScreen', _schedaScreenTests);

  group('misure responsive', () {
    /// Legge i valori dell'estensione con il formato del device attivo.
    Future<T> read<T>(
      WidgetTester tester,
      _Device device,
      T Function(BuildContext) get,
    ) async {
      await _useDevice(tester, device);
      late T value;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              value = get(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return value;
    }

    testWidgets('classifica telefoni, tablet e iPad', (tester) async {
      expect(
        await read(tester, _dev('Android compatto'), (c) => c.screenClass),
        ScreenClass.phone,
      );
      expect(
        await read(tester, _dev('iPhone Pro Max'), (c) => c.screenClass),
        ScreenClass.phone,
      );
      expect(
        await read(tester, _dev('iPad verticale'), (c) => c.screenClass),
        ScreenClass.tablet,
      );
      expect(
        await read(tester, _dev('iPad Pro orizzontale'), (c) => c.screenClass),
        ScreenClass.desktop,
      );
    });

    testWidgets('sul telefono il padding resta quello di prima, '
        'sull\'iPad centra il contenuto', (tester) async {
      final phone = await read(
        tester,
        _dev('iPhone SE'),
        (c) => c.centeredPadding(horizontal: 24),
      );
      expect(phone.left, 24);
      expect(phone.right, 24);

      // iPad Pro orizzontale: 1366dp, colonna da 760 → 303 per lato.
      final tablet = await read(
        tester,
        _dev('iPad Pro orizzontale'),
        (c) => c.centeredPadding(horizontal: 24),
      );
      expect(tablet.left, greaterThan(24));
      expect(tablet.left, tablet.right);
      expect(1366 - tablet.left - tablet.right, closeTo(760, 0.5));
    });

    testWidgets('le colonne delle miniature crescono col formato', (
      tester,
    ) async {
      expect(
        await read(tester, _dev('Android gesti'), (c) => c.thumbColumns),
        3,
      );
      expect(
        await read(tester, _dev('iPad verticale'), (c) => c.thumbColumns),
        4,
      );
      expect(
        await read(tester, _dev('iPad Pro orizzontale'), (c) => c.thumbColumns),
        5,
      );
    });

    testWidgets('tapHeight cresce coi caratteri ma si ferma', (tester) async {
      await _useDevice(tester, _dev('Android gesti'));
      late double h;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              h = context.tapHeight(54);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(h, closeTo(54 * 1.35, 0.01));
    });
  });
}

/// Il form e' la schermata piu' fitta: se una misura fissa e' rimasta in
/// giro, e' qui che si vede per prima.
void _formScreenTests() {
  for (final device in _devices) {
    testWidgets('il form non sfonda su ${device.name}', (tester) async {
      await _useDevice(tester, device);

      await tester.pumpWidget(
        const MaterialApp(
          home: FormScreen(
            reportType: {'id': 1, 'name': 'Illuminazione pubblica'},
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'nessun overflow');

      // La barra dei pulsanti deve restare sopra l'ingombro di sistema.
      final invia = tester.getRect(find.text('INVIA'));
      expect(
        invia.bottom,
        lessThanOrEqualTo(device.size.height - device.bottomInset),
      );
    });

    testWidgets('il form non sfonda coi caratteri ingranditi su '
        '${device.name}', (tester) async {
      await _useDevice(tester, device);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.35)),
            child: child!,
          ),
          home: const FormScreen(
            reportType: {'id': 1, 'name': 'Illuminazione pubblica'},
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'nessun overflow');
    });
  }
}

/// La scheda di una bozza: qui convivono banner di stato, testi lunghi,
/// griglia foto e barra con tre pulsanti.
void _schedaScreenTests() {
  const draft = {
    'id': 'local_1',
    'is_local': true,
    'type': {'id': 1, 'name': 'Illuminazione pubblica'},
    'details':
        'Il lampione all\'incrocio e\' spento da diversi giorni e la sera '
        'la strada resta completamente al buio.',
    'address': 'Via Giuseppe Garibaldi 128, Corbetta (MI)',
    'status': 'in_creazione',
    'datetime': '2026-09-01T10:30:00',
    'image_paths': <String>[],
  };

  for (final device in _devices) {
    testWidgets('la scheda non sfonda su ${device.name}', (tester) async {
      await _useDevice(tester, device);
      ApiService.permission = AppPermission.readWrite;
      addTearDown(() => ApiService.permission = AppPermission.none);

      await tester.pumpWidget(
        const MaterialApp(home: SchedaScreen(report: draft)),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'nessun overflow');

      // I tre pulsanti restano sopra l'ingombro di sistema.
      final invia = tester.getRect(find.text('INVIA'));
      expect(
        invia.bottom,
        lessThanOrEqualTo(device.size.height - device.bottomInset),
      );

      // La barra sta in fondo e occupa solo lo spazio dei suoi pulsanti.
      // Non e' una prova per il gusto di farla: l'Align che centra il
      // contenuto sui formati grandi si prendeva tutta l'altezza dello
      // schermo, la barra copriva appbar e scheda col suo fondo bianco e
      // i pulsanti finivano in cima alla pagina. La prova qui sopra
      // passava comunque, perche' un pulsante in cima e' sopra
      // l'ingombro di sistema.
      final bar = tester.getRect(find.byType(BottomActionBar));
      expect(bar.bottom, device.size.height, reason: 'barra in fondo');
      expect(
        bar.height,
        lessThan(device.size.height / 2),
        reason: 'la barra non copre la pagina',
      );
      // Il titolo dell'appbar resta visibile, non ci finisce niente sopra.
      expect(
        tester.getRect(find.text('Dettaglio segnalazione')).bottom,
        lessThan(bar.top),
      );
    });

    testWidgets('la scheda non sfonda coi caratteri ingranditi su '
        '${device.name}', (tester) async {
      await _useDevice(tester, device);
      ApiService.permission = AppPermission.readWrite;
      addTearDown(() => ApiService.permission = AppPermission.none);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.35)),
            child: child!,
          ),
          home: const SchedaScreen(report: draft),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'nessun overflow');
    });
  }
}
