import 'dart:convert';

import 'package:flutter/services.dart';

/// Elenco delle vie di Corbetta preso da OpenStreetMap
/// (`assets/corbetta_streets.json`, rigenerato da `tools/genera_vie.php`).
///
/// Il geocoder cerca il nome quasi alla lettera: "Via Ghiaccio" non trova
/// "Vicolo del Ghiaccio", "Via Camillo Benso di Cavour" non trova "Via
/// Cavour". Qui il confronto ignora tipo di via, articoli, accenti e
/// piccoli errori di battitura.
abstract final class CorbettaStreets {
  static const String asset = 'assets/corbetta_streets.json';

  static List<_Street> _streets = const [];

  /// Da chiamare una volta all'avvio, prima di `runApp`.
  static Future<void> load() async => parse(await rootBundle.loadString(asset));

  /// Carica l'elenco da JSON: separato da [load] per i test.
  static void parse(String json) {
    _streets = (jsonDecode(json) as List)
        .whereType<Map>()
        .map(
          (s) => _Street(
            s['name'] as String,
            (s['lat'] as num).toDouble(),
            (s['lon'] as num).toDouble(),
          ),
        )
        .toList();
  }

  /// Vie che corrispondono a [query], migliori prima, nello stesso formato
  /// dei suggerimenti del geocoder (`display_name`, `lat`, `lon`).
  /// true se [a] e [b] sono la stessa via scritta in due modi, civico
  /// escluso: "Via Camillo Benso Conte di Cavour 10" e "Via Cavour" si',
  /// "Via Roma" e "Piazza Roma" no.
  static bool sameStreet(String a, String b) {
    final wa = _withoutCivico(_words(a)), wb = _withoutCivico(_words(b));
    final ka = wa.where((w) => !_ignored.contains(w)).toSet();
    final kb = wb.where((w) => !_ignored.contains(w)).toSet();
    if (ka.isEmpty || kb.isEmpty) return false;

    // Tipi diversi scritti entrambi = vie diverse.
    final ta = wa.firstWhere(_streetTypes.contains, orElse: () => '');
    final tb = wb.firstWhere(_streetTypes.contains, orElse: () => '');
    if (ta.isNotEmpty && tb.isNotEmpty && ta != tb) return false;

    // Un nome contiene l'altro: il nome completo e quello corto.
    return ka.containsAll(kb) || kb.containsAll(ka);
  }

  /// Toglie il civico in fondo: ['via', 'roma', '12', 'a'] → ['via', 'roma'].
  /// I numeri dentro il nome restano ("Via 4 Novembre").
  static List<String> _withoutCivico(List<String> words) {
    final w = [...words];
    if (w.length > 1 && w.last.length == 1 && !RegExp(r'\d').hasMatch(w.last)) {
      // "12/a" diventa ['12', 'a']: la lettera fa parte del civico.
      if (RegExp(r'^\d+$').hasMatch(w[w.length - 2])) w.removeLast();
    }
    if (w.length > 1 && RegExp(r'^\d+$').hasMatch(w.last)) w.removeLast();
    return w;
  }

  static List<Map<String, dynamic>> search(String query, {int limit = 5}) {
    final words = _words(query).where((w) => !_corbettaWords.contains(w));
    final typed = words.where((w) => !_ignored.contains(w)).toList();
    if (typed.isEmpty) return const [];
    final type = words.firstWhere(_streetTypes.contains, orElse: () => '');

    final scored = <(int, _Street)>[];
    for (final street in _streets) {
      final score = _score(typed, type, street);
      if (score > 0) scored.add((score, street));
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      return byScore != 0 ? byScore : a.$2.name.compareTo(b.$2.name);
    });

    return scored
        .take(limit)
        .map(
          (s) => <String, dynamic>{
            'display_name': '${s.$2.name}, Corbetta',
            'lat': s.$2.lat,
            'lon': s.$2.lon,
            'address': {'town': 'Corbetta'},
          },
        )
        .toList();
  }

  /// Quanto la via corrisponde, 0 = per niente. Due modi di corrispondere:
  /// - ogni parola scritta e' l'inizio di una parola della via (si sta
  ///   ancora scrivendo: "via gor" → Via Gorizia);
  /// - ogni parola della via e' tra quelle scritte (nome completo con
  ///   parole in piu': "camillo benso di cavour" → Via Cavour).
  static int _score(List<String> typed, String type, _Street street) {
    final key = street.keyWords;
    if (key.isEmpty) return 0;

    var score = 0;
    if (typed.every((t) => key.any((k) => _wordMatches(t, k)))) {
      score = 100 + 10 * typed.length;
    } else if (key.every((k) => typed.any((t) => _wordMatches(t, k)))) {
      score = 50 + 10 * key.length;
    } else {
      return 0;
    }

    // Parole identiche valgono piu' dei prefissi o degli errori.
    score += typed.where(key.contains).length * 5;
    // A parita', vince il tipo di via scritto (via, vicolo, piazza...).
    if (type.isNotEmpty && street.type == type) score += 3;
    return score;
  }

  /// [typed] corrisponde alla parola [word] della via: e' il suo inizio,
  /// oppure ha al massimo un errore (lettera sbagliata, in piu' o in meno)
  /// se e' lunga almeno 5 lettere.
  static bool _wordMatches(String typed, String word) {
    if (word.startsWith(typed)) return true;
    if (typed.length < 5 || word.length < 5) return false;
    if ((typed.length - word.length).abs() > 1) {
      // Si sta ancora scrivendo: si confronta con l'inizio della via.
      if (typed.length >= word.length) return false;
      return _oneEditAway(typed, word.substring(0, typed.length));
    }
    return _oneEditAway(typed, word);
  }

  static bool _oneEditAway(String a, String b) {
    if (a == b) return true;
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0, j = 0, edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length > b.length) {
        i++;
      } else if (a.length < b.length) {
        j++;
      } else {
        i++;
        j++;
      }
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
  }

  /// Parole minuscole senza accenti ne' punteggiatura:
  /// "Vicolo dell'Ospedale" → ['vicolo', 'dell', 'ospedale'].
  static List<String> _words(String text) {
    var t = text.toLowerCase();
    _accents.forEach((from, to) => t = t.replaceAll(from, to));
    return t.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
  }

  static const Map<String, String> _accents = {
    'à': 'a',
    'á': 'a',
    'è': 'e',
    'é': 'e',
    'ì': 'i',
    'í': 'i',
    'ò': 'o',
    'ó': 'o',
    'ù': 'u',
    'ú': 'u',
  };

  static const Set<String> _streetTypes = {
    'via',
    'viale',
    'vicolo',
    'piazza',
    'piazzale',
    'largo',
    'corso',
    'strada',
    'piazzetta',
    'vicoletto',
    'cascina',
    'contrada',
    'galleria',
    'passaggio',
    'ripa',
    'alzaia',
  };

  /// Parole che non aiutano a riconoscere la via: tipi, abbreviazioni,
  /// articoli e preposizioni.
  static const Set<String> _ignored = {
    ..._streetTypes,
    'v',
    'p',
    'pza',
    'pzza',
    'zza',
    'c',
    'so',
    'vle',
    'del',
    'dello',
    'della',
    'dei',
    'degli',
    'delle',
    'dell',
    'di',
    'de',
    'd',
    'da',
    'dal',
    'dalla',
    'al',
    'alla',
    'ai',
    'alle',
    'il',
    'lo',
    'la',
    'i',
    'gli',
    'le',
    'l',
    'e',
    'ed',
  };

  /// Comune e CAP scritti nella ricerca: non fanno parte della via.
  static const Set<String> _corbettaWords = {'corbetta', '20011', '20009'};
}

class _Street {
  _Street(this.name, this.lat, this.lon)
    : keyWords = CorbettaStreets._words(
        name,
      ).where((w) => !CorbettaStreets._ignored.contains(w)).toList(),
      type = CorbettaStreets._words(name).firstOrNull ?? '';

  final String name;
  final double lat;
  final double lon;

  /// Parole che identificano la via: "Vicolo del Ghiaccio" → ['ghiaccio'].
  final List<String> keyWords;

  /// Primo termine del nome, di solito il tipo: 'via', 'vicolo'...
  final String type;
}
