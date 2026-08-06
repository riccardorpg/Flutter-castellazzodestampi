import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Comprime le foto prima dell'upload: le immagini scattate dal telefono
/// arrivano facilmente a 5-10 MB e rendono l'invio lentissimo su rete mobile.
/// Ogni foto viene ricompressa, anche quelle gia' sotto il megabyte: spesso
/// sono comunque da 4000px e alleggerirle riduce upload e spazio sul server.
/// Se la ricompressione non guadagna nulla si invia l'originale.
class ImageCompressor {
  /// Obiettivo: portare ogni foto sotto 1 MB.
  static const int thresholdBytes = 1024 * 1024;

  static const int _initialMinSide = 1600;
  static const int _initialQuality = 82;
  static const int _maxAttempts = 3;

  static int _counter = 0;

  /// Restituisce il percorso della versione compressa, oppure il percorso
  /// originale se la compressione fallisce o non riduce il peso del file.
  static Future<String> compressIfNeeded(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return path;

      final originalSize = await file.length();
      if (originalSize == 0) return path;

      final dir = await getTemporaryDirectory();
      var quality = _initialQuality;
      var minSide = _initialMinSide;
      String? best;
      var bestSize = originalSize;

      // Qualita' e dimensioni calano a ogni tentativo finche' il file
      // non scende sotto il megabyte.
      for (var attempt = 0; attempt < _maxAttempts; attempt++) {
        final target =
            '${dir.path}/cds_${DateTime.now().microsecondsSinceEpoch}_${_counter++}.jpg';

        final result = await FlutterImageCompress.compressAndGetFile(
          path,
          target,
          quality: quality,
          minWidth: minSide,
          minHeight: minSide,
          format: CompressFormat.jpeg,
          keepExif: false,
        );
        if (result == null) break;

        final size = await result.length();
        if (best == null || size < bestSize) {
          best = result.path;
          bestSize = size;
        }
        if (size <= thresholdBytes) break;

        quality = (quality - 15).clamp(40, 100);
        minSide = (minSide * 0.75).round();
      }

      // Foto gia' ottimizzate (o molto piccole) possono crescere se
      // ricodificate: in quel caso si tiene il file originale.
      if (best == null || bestSize >= originalSize) return path;
      return best;
    } catch (_) {
      // in caso di errore si invia l'originale: il server ricomprime comunque
      return path;
    }
  }

  /// Comprime in sequenza tutte le foto selezionate.
  static Future<List<String>> compressAll(List<String> paths) async {
    final out = <String>[];
    for (final p in paths) {
      out.add(await compressIfNeeded(p));
    }
    return out;
  }
}
