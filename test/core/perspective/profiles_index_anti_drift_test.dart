// Test anti-dérive : `assets/profiles/index.json` est un artefact
// GÉNÉRÉ (par `tools/dxf_pipeline/build_profiles_index.py` depuis
// `gate_sanite_rapport.csv`), pas une source de vérité indépendante.
//
// Risque couvert : le gate (`gate_sanite.py`) est rerun un jour avec un
// jeu de données différent (nouveau batch, critères durcis/assouplis),
// changeant l'ensemble des SKU `statut_gate == "OK"` -- mais
// `build_profiles_index.py` n'est pas relancé, ou l'est mais son
// résultat n'est pas recommité. `index.json`, embarqué dans le binaire
// de l'app, reste alors PÉRIMÉ par rapport au CSV -- silencieusement :
// rien dans l'app ni dans les tests qui ne lisent que l'un OU l'autre
// fichier ne peut détecter cette désynchronisation.
//
// Ce test lit les DEUX fichiers indépendamment et vérifie l'égalité
// stricte des ensembles de refs -- il échoue si `index.json` n'a pas
// été régénéré après une modification du CSV (ou vice-versa).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Découpage minimal d'une ligne CSV, suffisant pour les colonnes lues
/// ici (`sku`, `statut_gate`) -- voir la même remarque dans
/// `profile_dims_cache_coverage_31_test.dart`.
List<Map<String, String>> _readGateCsvRows() {
  final lines = File('tools/dxf_pipeline/gate_sanite_rapport.csv')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();
  final headers = lines.first.split(',');
  final rows = <Map<String, String>>[];
  for (final line in lines.skip(1)) {
    final cells = line.split(',');
    final row = <String, String>{};
    for (var i = 0; i < headers.length && i < cells.length; i++) {
      row[headers[i]] = cells[i];
    }
    rows.add(row);
  }
  return rows;
}

Set<String> _readGateOkRefsFromCsv() {
  return _readGateCsvRows()
      .where((row) => row['statut_gate'] == 'OK')
      .map((row) => row['sku']!)
      .toSet();
}

Set<String> _readIndexRefsFromJson() {
  final raw = File('assets/profiles/index.json').readAsStringSync();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return (decoded['refs'] as List).cast<String>().toSet();
}

void main() {
  test(
    'anti-derive : assets/profiles/index.json (genere) doit contenir '
    'EXACTEMENT le meme ensemble de refs que gate_sanite_rapport.csv '
    '(source, statut_gate == "OK") -- si ce test echoue, '
    'build_profiles_index.py doit etre relance et son resultat recommite '
    'avant tout autre travail sur le rendu en cotes reelles',
    () {
      final fromCsv = _readGateOkRefsFromCsv();
      final fromIndex = _readIndexRefsFromJson();

      final onlyInCsv = fromCsv.difference(fromIndex);
      final onlyInIndex = fromIndex.difference(fromCsv);

      expect(
        onlyInCsv,
        isEmpty,
        reason:
            'Refs gate-OK dans le CSV mais ABSENTES de index.json -- '
            'index.json est perime (trop restrictif), regenerer via '
            'build_profiles_index.py : $onlyInCsv',
      );
      expect(
        onlyInIndex,
        isEmpty,
        reason:
            'Refs presentes dans index.json mais dont le CSV ne dit plus '
            'statut_gate == "OK" -- index.json est perime (trop '
            'permissif, contient des refs que le gate a depuis rejetees), '
            'regenerer via build_profiles_index.py : $onlyInIndex',
      );

      // Egalite stricte des ensembles, redondant avec les deux
      // assertions ci-dessus mais explicite sur l'intention du test.
      expect(fromIndex, fromCsv);
    },
  );

  test(
    'garde-fou : le CSV contient au moins une ref OK et au moins une '
    'ref non-OK -- sinon ce test anti-derive serait vide de sens '
    '(comparerait deux ensembles vides ou deux ensembles identiques par '
    'construction, sans jamais avoir exerce la logique de filtrage)',
    () {
      final rows = _readGateCsvRows();
      final okCount = rows.where((r) => r['statut_gate'] == 'OK').length;
      final notOkCount = rows.length - okCount;

      expect(okCount, greaterThan(0));
      expect(notOkCount, greaterThan(0));
    },
  );
}
