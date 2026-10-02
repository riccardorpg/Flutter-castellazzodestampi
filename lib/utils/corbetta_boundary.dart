import 'dart:convert';

import 'package:flutter/services.dart';

/// Confine reale del Comune di Corbetta (CAP 20011, frazioni comprese),
/// preso da OpenStreetMap (relazione 45011) e salvato in
/// `assets/corbetta_boundary.json` come lista di [lat, lng].
/// Lo stesso file sta sul server, che applica lo stesso controllo.
abstract final class CorbettaBoundary {
  static const String asset = 'assets/corbetta_boundary.json';

  static List<List<double>> _polygon = const [];
  static double _minLat = 0, _maxLat = 0, _minLon = 0, _maxLon = 0;

  /// Da chiamare una volta all'avvio, prima di `runApp`.
  static Future<void> load() async => parse(await rootBundle.loadString(asset));

  /// Carica il poligono da JSON: separato da [load] per i test.
  static void parse(String json) {
    _polygon = (jsonDecode(json) as List)
        .map((p) => [(p[0] as num).toDouble(), (p[1] as num).toDouble()])
        .toList();
    _minLat = _polygon.map((p) => p[0]).reduce((a, b) => a < b ? a : b);
    _maxLat = _polygon.map((p) => p[0]).reduce((a, b) => a > b ? a : b);
    _minLon = _polygon.map((p) => p[1]).reduce((a, b) => a < b ? a : b);
    _maxLon = _polygon.map((p) => p[1]).reduce((a, b) => a > b ? a : b);
  }

  /// true se il punto sta dentro il confine. Senza poligono caricato
  /// risponde sempre no: meglio rifiutare che accettare alla cieca.
  static bool contains(double lat, double lon) {
    if (_polygon.length < 3) return false;
    // Scarto veloce: fuori dal rettangolo che contiene il confine.
    if (lat < _minLat || lat > _maxLat || lon < _minLon || lon > _maxLon) {
      return false;
    }

    // Ray-Casting: si tira una linea dal punto verso est e si contano i
    // lati del confine che attraversa. Dispari = dentro, pari = fuori.
    var inside = false;
    for (var i = 0, j = _polygon.length - 1; i < _polygon.length; j = i++) {
      final latI = _polygon[i][0], lonI = _polygon[i][1];
      final latJ = _polygon[j][0], lonJ = _polygon[j][1];
      if ((latI > lat) != (latJ > lat) &&
          lon < (lonJ - lonI) * (lat - latI) / (latJ - latI) + lonI) {
        inside = !inside;
      }
    }
    return inside;
  }
}
