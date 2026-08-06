import 'package:flutter/material.dart';

/// Barra azioni fissa in fondo alla pagina: sfondo bianco, bordo e ombra
/// per staccarla dal contenuto che scorre sotto.
class BottomActionBar extends StatelessWidget {
  final List<Widget> children;
  const BottomActionBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// Azione principale della barra: verde piena, a tutta larghezza.
class PrimaryBarButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const PrimaryBarButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7BA566),
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              const Color(0xFF7BA566).withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Inter',
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}

/// Azione secondaria: altezza generosa e testo che si rimpicciolisce
/// invece di andare a capo sui telefoni stretti.
class SecondaryBarButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color foreground;
  final Color borderColor;
  final Color background;

  const SecondaryBarButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.foreground,
    required this.borderColor,
    required this.background,
  });

  /// Grigio neutro (Annulla, Modifica).
  const SecondaryBarButton.neutral({
    super.key,
    required this.label,
    required this.onPressed,
  })  : foreground = const Color(0xFF4B5563),
        borderColor = const Color(0xFF9CA3AF),
        background = Colors.white;

  /// Verde tenue (Salva bozza).
  const SecondaryBarButton.green({
    super.key,
    required this.label,
    required this.onPressed,
  })  : foreground = const Color(0xFF4F7A3B),
        borderColor = const Color(0xFF7BA566),
        background = const Color(0xFFEDF5E9);

  /// Rosso tenue (Elimina).
  const SecondaryBarButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
  })  : foreground = const Color(0xFFB91C1C),
        borderColor = const Color(0xFFEF4444),
        background = const Color(0xFFFEF2F2);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: background,
          side: BorderSide(color: borderColor, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ),
    );
  }
}
