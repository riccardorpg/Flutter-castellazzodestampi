import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:castellazzodestampi/utils/corbetta_boundary.dart';
import 'package:castellazzodestampi/utils/corbetta_streets.dart';

void main() {
  setUpAll(() {
    CorbettaBoundary.parse(
      File('assets/corbetta_boundary.json').readAsStringSync(),
    );
    CorbettaStreets.parse(
      File('assets/corbetta_streets.json').readAsStringSync(),
    );
  });

  String? first(String query) {
    final results = CorbettaStreets.search(query);
    return results.isEmpty
        ? null
        : (results.first['display_name'] as String).split(',').first;
  }

  group('trova la via anche con il nome scritto diverso da OSM', () {
    const casi = {
      'Via Ghiaccio': 'Vicolo del Ghiaccio',
      'via ghiaccio, Corbetta': 'Vicolo del Ghiaccio',
      'Via Camillo Benso di Cavour': 'Via Cavour',
      'Via Cammillo Benso di Cavour': 'Via Cavour',
      'cavour': 'Via Cavour',
      'Via Gorizia': 'Via Gorizia',
      'via goriz': 'Via Gorizia',
      'Via Gorizzia': 'Via Gorizia',
      'corso garibaldi': 'Corso Giuseppe Garibaldi',
      'Via dei Mille': 'Via dei Mille',
    };
    casi.forEach((scritto, atteso) {
      test('"$scritto" → $atteso', () => expect(first(scritto), atteso));
    });
  });

  test('una via inventata non trova niente', () {
    expect(CorbettaStreets.search('Via Inesistentissima'), isEmpty);
  });

  test('solo "via" o solo "Corbetta" non suggerisce tutto l\'elenco', () {
    expect(CorbettaStreets.search('via'), isEmpty);
    expect(CorbettaStreets.search('Corbetta'), isEmpty);
  });

  group('tutte le vie dell\'elenco', () {
    final vie =
        (jsonDecode(File('assets/corbetta_streets.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();

    test('hanno il punto dentro il confine', () {
      for (final v in vie) {
        expect(
          CorbettaBoundary.contains(
            (v['lat'] as num).toDouble(),
            (v['lon'] as num).toDouble(),
          ),
          isTrue,
          reason: v['name'] as String,
        );
      }
    });

    test('si trovano scrivendo il loro nome', () {
      for (final v in vie) {
        final nomi = CorbettaStreets.search(
          v['name'] as String,
        ).map((s) => (s['display_name'] as String).split(',').first);
        expect(nomi, contains(v['name']), reason: v['name'] as String);
      }
    });
  });
}
