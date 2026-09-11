import 'package:flutter/material.dart';

import '../utils/responsive.dart';

/// Barra di navigazione in fondo alla schermata (una sola voce).
///
/// Il `bottomNavigationBar` dello `Scaffold` viene disegnato fino al
/// bordo fisico dello schermo: senza `SafeArea` la barra gesti di Android
/// e l'home indicator di iPhone ci finiscono sopra, e su alcuni telefoni
/// la voce spariva del tutto. Qui l'ingombro di sistema diventa padding,
/// e l'altezza non e' piu' fissa ma cresce con i caratteri di sistema,
/// cosi' la scritta non viene mai tagliata.
class BottomNavBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const BottomNavBar({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xFF666666);
    final iconSize = context.adaptive(22, tablet: 24);
    final fontSize = context.adaptive(14, tablet: 15);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          // top: false — in cima ci pensa gia' l'AppBar.
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: context.tapHeight(64)),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.sidePadding,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: foreground, size: iconSize),
                    const SizedBox(width: 10),
                    // Flexible: su un telefono stretto la scritta si
                    // accorcia invece di sfondare la riga.
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: fontSize,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
