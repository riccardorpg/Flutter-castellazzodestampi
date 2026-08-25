import 'package:flutter/material.dart';

/// Priorita' di una segnalazione.
///
/// Non viene chiesta nel form: il backend la eredita dal tipo scelto, che sul
/// database porta la graduatoria decisa dal Comune. Qui si legge soltanto
/// l'etichetta gia' calcolata da `priority_label`.

/// Etichetta della priorita', o null se il dato non c'e' (bozze locali e
/// segnalazioni salvate prima di questa modifica).
String? priorityLabel(Map<String, dynamic> report) {
  final label = report['priority_label'];
  if (label is String && label.trim().isNotEmpty) return label.trim();
  return null;
}

/// Rosso, ambra, verde. Le etichette non previste restano grigie.
Color priorityColor(String label) {
  switch (label.toLowerCase()) {
    case 'alta':
      return const Color(0xFFDC2626);
    case 'media':
      return const Color(0xFFD97706);
    case 'bassa':
      return const Color(0xFF7BA566);
    default:
      return const Color(0xFF9CA3AF);
  }
}

/// Badge priorita'. In [compact] mostra la sola etichetta, per stare nelle
/// card dell'elenco accanto alla data.
class PriorityBadge extends StatelessWidget {
  final String label;
  final bool compact;

  const PriorityBadge({super.key, required this.label, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(label);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 2 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_outlined, size: compact ? 10 : 13, color: color),
          SizedBox(width: compact ? 3 : 5),
          Text(
            compact ? label.toUpperCase() : 'Priorita\' ${label.toLowerCase()}',
            style: TextStyle(
              color: color,
              fontSize: compact ? 10 : 12,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
