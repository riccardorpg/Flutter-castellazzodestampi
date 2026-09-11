import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Soglie di larghezza in dp logici (non pixel fisici): sono le stesse
/// per Android e iOS, quindi un telefono resta un telefono a prescindere
/// dalla densita' dello schermo.
abstract final class AppBreakpoints {
  /// Sotto: telefono (iPhone SE 320dp … iPhone Pro Max 430dp,
  /// Android compatti e non).
  static const double phone = 600;

  /// Sotto: tablet in verticale (iPad 768dp, tablet Android 600-900dp).
  static const double tablet = 900;
}

enum ScreenClass { phone, tablet, desktop }

/// Misure che si adattano allo schermo, ricavate una volta sola e usate
/// da tutte le schermate: cosi' un telefono stretto, un iPhone col notch,
/// un Android con la barra gesti e un iPad si comportano allo stesso modo.
extension Responsive on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;

  ScreenClass get screenClass {
    final w = screenWidth;
    if (w < AppBreakpoints.phone) return ScreenClass.phone;
    if (w < AppBreakpoints.tablet) return ScreenClass.tablet;
    return ScreenClass.desktop;
  }

  bool get isPhone => screenClass == ScreenClass.phone;
  bool get isTablet => screenClass == ScreenClass.tablet;
  bool get isDesktop => screenClass == ScreenClass.desktop;

  /// Vero da tablet in su: comodo per decidere se ingrandire un elemento.
  bool get isLargeScreen => !isPhone;

  bool get isLandscape => screenWidth > screenHeight;

  /// Telefoni bassi (SE, Android piccoli) o telefono coricato: qui gli
  /// spazi verticali generosi vanno accorciati o non ci sta niente.
  bool get isShortScreen => screenHeight < 700;

  /// Telefoni molto stretti (320dp): le scritte lunghe vanno accorciate.
  bool get isNarrowScreen => screenWidth < 360;

  /// Ingombro di sistema in basso: barra gesti Android, home indicator
  /// iPhone. Vale anche quando la tastiera copre il bordo, al contrario
  /// di `MediaQuery.padding`.
  double get systemBottomInset => MediaQuery.viewPaddingOf(this).bottom;

  /// Quanto l'utente ha ingrandito i caratteri nelle impostazioni.
  double get textScale => MediaQuery.textScalerOf(this).scale(1);

  /// Larghezza massima leggibile del contenuto. Su telefono non fa
  /// niente, su tablet e iPad evita righe lunghissime da bordo a bordo.
  double get maxContentWidth => switch (screenClass) {
    ScreenClass.phone => double.infinity,
    ScreenClass.tablet => 640,
    ScreenClass.desktop => 760,
  };

  /// Margine laterale di base della pagina.
  double get sidePadding => switch (screenClass) {
    ScreenClass.phone => isNarrowScreen ? 14 : 16,
    ScreenClass.tablet => 24,
    ScreenClass.desktop => 32,
  };

  /// Padding che centra il contenuto entro [maxContentWidth] senza
  /// avvolgere la lista in un widget in piu': la `ListView` resta lazy e
  /// la barra di scorrimento resta sul bordo dello schermo.
  EdgeInsets centeredPadding({
    double? horizontal,
    double top = 0,
    double bottom = 0,
  }) {
    final base = horizontal ?? sidePadding;
    final max = maxContentWidth;
    final side = max.isFinite ? math.max(base, (screenWidth - max) / 2) : base;
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }

  /// Valore che cresce sui formati grandi: [phone] e' il riferimento,
  /// gli altri due sono facoltativi e derivano da una scala fissa.
  double adaptive(double phone, {double? tablet, double? desktop}) =>
      switch (screenClass) {
        ScreenClass.phone => phone,
        ScreenClass.tablet => tablet ?? phone * 1.15,
        ScreenClass.desktop => desktop ?? tablet ?? phone * 1.25,
      };

  /// Colonne di una griglia di miniature. Sul telefono restano tre, come
  /// prima; su tablet e iPad se ne aggiungono invece di ingrandire a
  /// dismisura ogni foto.
  int get thumbColumns => switch (screenClass) {
    ScreenClass.phone => 3,
    ScreenClass.tablet => 4,
    ScreenClass.desktop => 5,
  };

  /// Altezza di un elemento tappabile che deve restare leggibile anche
  /// con i caratteri di sistema ingranditi, senza crescere all'infinito.
  double tapHeight(double base, {double maxFactor = 1.35}) =>
      base * textScale.clamp(1.0, maxFactor);
}

/// Centra e limita il contenuto entro [Responsive.maxContentWidth].
/// Da usare su form e schede, dove il testo a tutta larghezza di un iPad
/// diventa illeggibile; su telefono e' trasparente.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? maxWidth;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      // heightFactor: senza questo l'Align si prende tutta l'altezza che
      // i vincoli gli concedono, non quella del contenuto. In fondo a uno
      // Scaffold (la barra azioni di scheda e form) i vincoli sono quelli
      // dello schermo intero: la barra diventava alta come la pagina, il
      // suo fondo bianco copriva appbar e contenuto e i pulsanti
      // comparivano in cima. In larghezza non cambia niente.
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? context.maxContentWidth,
        ),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }
}
