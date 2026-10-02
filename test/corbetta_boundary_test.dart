import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:castellazzodestampi/utils/corbetta_boundary.dart';

void main() {
  setUpAll(() {
    CorbettaBoundary.parse(
      File('assets/corbetta_boundary.json').readAsStringSync(),
    );
  });

  group('dentro Corbetta', () {
    const punti = {
      'municipio, piazza Repubblica': [45.4686, 8.9196],
      'Castellazzo de\' Stampi': [45.4732, 8.9444],
      'Cerello': [45.4464, 8.9267],
      'Soriano': [45.4593, 8.9401],
      'Battuello': [45.4478, 8.9358],
      'via della Marzorata': [45.4631, 8.9599],
      'via Zara, Pobbia': [45.4778, 8.9443],
    };
    punti.forEach((nome, p) {
      test(nome, () => expect(CorbettaBoundary.contains(p[0], p[1]), isTrue));
    });
  });

  group('fuori Corbetta', () {
    const punti = {
      'Vittuone': [45.4880, 8.9524],
      // Primo risultato di "Via Corbetta, Vittuone": dentro il vecchio
      // rettangolo, ma e' Vittuone.
      'SS11, Vittuone': [45.4804, 8.9418],
      'Magenta': [45.4654, 8.8838],
      'Albairate': [45.4211, 8.9381],
      'Santo Stefano Ticino': [45.4873, 8.9186],
      'Milano': [45.4642, 9.1900],
    };
    punti.forEach((nome, p) {
      test(nome, () => expect(CorbettaBoundary.contains(p[0], p[1]), isFalse));
    });
  });
}
