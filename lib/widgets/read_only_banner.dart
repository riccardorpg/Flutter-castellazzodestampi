import 'package:flutter/material.dart';

/// Avviso fisso per chi ha il permesso di sola lettura: spiega perche'
/// mancano i pulsanti per creare e modificare.
class ReadOnlyBanner extends StatelessWidget {
  final String message;

  const ReadOnlyBanner({
    super.key,
    this.message =
        'Accesso in sola lettura: puoi consultare le segnalazioni ma non '
        'crearle o modificarle.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.visibility_outlined,
            color: Color(0xFFB45309),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
