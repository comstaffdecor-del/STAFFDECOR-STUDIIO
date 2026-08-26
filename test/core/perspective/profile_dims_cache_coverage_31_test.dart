// Étape 1 du brief de câblage (« Câblage du rendu en cotes réelles mm ») :
// vérification EXHAUSTIVE, pas seulement échantillonnée, que le cache réel
// (`ProfileDimsCache.ensureLoading`/`getIfLoaded`, PAS un script Python
// séparé qui ne prouverait rien du comportement Dart) retourne des
// dimensions non-null pour les 31 SKU gate-OK, avec ZÉRO exception — et
// que la couverture reste correctement fermée (fail-closed) pour les 25
// SKU hors gate qui ont pourtant un fichier `<ref>.json` sur disque avec
// `statut: "OK"` (25 = 16 profils à risque de crash sous l'ancien
// `assert()` + 9 profils "subtils" passant l'assert mais rejetés par le
// gate pour d'autres critères).
//
// Règle du brief, rappelée : « si à l'étape 1 le cache ne renvoie pas les
// 31, on s'arrête et on remonte l'écart avant de toucher au painter ».
// Ce fichier EST ce point d'arrêt/rapport, exécuté avant toute étape 3/4.
//
// Livrable "log hit/miss" (brief, réponse (b) de l'utilisateur) : les
// deux derniers tests consultent `loadedCountForLogging` /
// `failedCountForLogging` après la boucle des 31 + la boucle des 25, et
// vérifient les cardinalités exactes 31/25 — preuve que ces compteurs
// reflètent fidèlement l'état réel du cache, prêts pour un usage log à la
// demande (bouton debug, log manuel), sans jamais avoir déclenché de
// second canal de notification.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/profile_dims.dart';
import 'package:staff_decor_studio/core/perspective/profile_dims_cache.dart';

/// Découpage minimal d'une ligne CSV : suffisant ici car
/// `gate_sanite_rapport.csv` ne contient aucune virgule ni guillemet à
/// l'intérieur d'un champ sur les colonnes lues (`sku`, `statut_gate`,
/// `motifs`) — vérifié par lecture directe du fichier. Un vrai parseur
/// CSV serait nécessaire si ce fichier évoluait pour citer des champs.
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

/// Les refs "à risque de crash sous l'ancien `assert()`" -- c'est-à-dire
/// `statut_gate == "SUSPECT_GEOMETRIE"` pour un motif de type
/// `DEBORD_PLAN_*` (débord bbox_mm/profil_mm), À L'EXCLUSION des refs
/// rejetées plus tôt par le loader pour indices de face de pose
/// vides/absents (`CONTRAT_LOADER_*_VIDE`, `STATUT_NON_OK`,
/// `PROFIL_INSUFFISANT`) -- celles-ci ne passaient déjà jamais le
/// contrôle bbox_mm puisqu'elles n'atteignaient jamais ce code (voir
/// `loadProfileDims`, rejet avant même le calcul de `maxAbsDx/Dy`).
///
/// Dérivé du CSV plutôt que recopié en dur (correction demandée : un
/// `expect(rejectedByContractCount, 16)` codé en dur devient
/// incompréhensible et cassant le jour où le batch d'extraction tourne
/// à nouveau avec un jeu de données différent -- ce test doit rester
/// vrai vis-à-vis de la SOURCE, pas d'un instantané recopié).
List<String> _readCrashRiskRefsFromCsv() {
  final rows = _readGateCsvRows();
  final refs = <String>[];
  for (final row in rows) {
    if (row['statut_gate'] != 'SUSPECT_GEOMETRIE') continue;
    final motifs = row['motifs'] ?? '';
    final isDebordBbox = motifs.contains('DEBORD_PLAN');
    final isExcludedEarlyByLoader = motifs.contains('VIDE') ||
        motifs.contains('STATUT_NON_OK') ||
        motifs.contains('PROFIL_INSUFFISANT');
    if (isDebordBbox && !isExcludedEarlyByLoader) {
      refs.add(row['sku']!);
    }
  }
  refs.sort();
  return refs;
}

/// Les 31 SKU `statut_gate == "OK"` (`gate_sanite_rapport.csv`), lus
/// directement depuis `assets/profiles/index.json` généré par
/// `tools/dxf_pipeline/build_profiles_index.py` — pas une liste recopiée à
/// la main, pour que ce test échoue si le générateur ou le fichier
/// divergent un jour, plutôt que de vérifier une liste figée qui pourrait
/// silencieusement désynchroniser du fichier réel.
List<String> _readIndexRefsFromDisk() {
  final raw = File('assets/profiles/index.json').readAsStringSync();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return (decoded['refs'] as List).cast<String>();
}

/// Les 25 SKU dont le fichier `assets/profiles/<ref>.json` existe avec
/// `statut: "OK"`, mais qui sont ABSENTS de `index.json` (donc
/// `statut_gate != "OK"`) — calculé depuis les fichiers réellement présents
/// sur disque, pas recopié depuis le rapport CSV (qui n'est pas packagé
/// comme asset et n'a donc aucune raison d'être lu par le code de
/// production ; seul `index.json` doit l'être).
List<String> _readHorsGateButFileExistsRefsFromDisk(List<String> covered) {
  final dir = Directory('assets/profiles');
  final result = <String>[];
  for (final entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final name = entity.path.split('/').last;
    if (name == 'index.json') continue;
    final ref = name.substring(0, name.length - '.json'.length);
    if (covered.contains(ref)) continue;
    final raw = entity.readAsStringSync();
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['statut'] == 'OK') {
      result.add(ref);
    }
  }
  result.sort();
  return result;
}

Future<void> _ensureLoadedOrFailed(String ref) async {
  if (ProfileDimsCache.instance.getIfLoaded(ref) != null ||
      ProfileDimsCache.instance.hasFailed(ref)) {
    return;
  }
  final completer = Completer<void>();
  void cb() {
    if ((ProfileDimsCache.instance.getIfLoaded(ref) != null ||
            ProfileDimsCache.instance.hasFailed(ref)) &&
        !completer.isCompleted) {
      completer.complete();
    }
  }

  ProfileDimsCache.instance.addListener(cb);
  ProfileDimsCache.instance.ensureLoading(ref);
  await completer.future.timeout(const Duration(seconds: 10));
  ProfileDimsCache.instance.removeListener(cb);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ProfileDimsCache.instance.resetForTesting();
    resetRejectedByContractCountForTesting();
  });

  final coveredRefs = _readIndexRefsFromDisk();
  final horsGateButFileExists =
      _readHorsGateButFileExistsRefsFromDisk(coveredRefs);

  test(
    'garde-fou de comptage : exactement 31 refs couvertes et 25 refs '
    'hors-gate-mais-fichier-existant sur le jeu de donnees actuel -- si '
    'ces nombres bougent, les tests suivants ne verifient plus ce que '
    'leur nom promet',
    () {
      expect(coveredRefs.length, 31);
      expect(horsGateButFileExists.length, 25);
      // Aucune intersection possible par construction (l'un est defini
      // comme l'exclusion de l'autre), verifie neanmoins explicitement.
      expect(
        coveredRefs.toSet().intersection(horsGateButFileExists.toSet()),
        isEmpty,
      );
    },
  );

  test(
    'ETAPE 1 -- les 31 SKU gate-OK chargent TOUS reellement via le cache '
    '(ProfileDimsCache.ensureLoading/getIfLoaded), zero exception, zero '
    'echec -- point d\'arret du brief : si un seul echoue ici, on s\'arrete '
    'et on remonte l\'ecart avant de toucher au painter',
    () async {
      final failures = <String>[];
      for (final ref in coveredRefs) {
        await _ensureLoadedOrFailed(ref);
        final dims = ProfileDimsCache.instance.getIfLoaded(ref);
        if (dims == null) {
          failures.add(ref);
          continue;
        }
        // Dimensions plausibles : strictement positives et finies (le
        // meme garde que stripPxFromDims impose en aval, verifie ici en
        // amont sur les 31 refs reelles, pas seulement en test unitaire
        // sur des valeurs synthetiques).
        expect(
          dims.retombeeMm > 0 && dims.retombeeMm.isFinite,
          isTrue,
          reason: '$ref: retombeeMm=${dims.retombeeMm} implausible',
        );
        expect(
          dims.projectionMm > 0 && dims.projectionMm.isFinite,
          isTrue,
          reason: '$ref: projectionMm=${dims.projectionMm} implausible',
        );
        expect(dims.ref, ref);
      }

      expect(
        failures,
        isEmpty,
        reason:
            'Refs gate-OK n\'ayant pas charge de dimensions via le cache : '
            '$failures -- ARRET REQUIS, ne pas poursuivre vers l\'etape 3 '
            'tant que cet ecart n\'est pas explique et corrige.',
      );

      // Livrable log (brief, reponse (b)) : les 31 refs sont bien
      // comptees comme chargees, aucune comme echouee, sans qu'aucun
      // compteur n'ait declenche de repaint (verifie separement dans
      // profile_dims_cache_test.dart -- "aucune notification synchrone").
      expect(ProfileDimsCache.instance.loadedCountForLogging, 31);
      expect(ProfileDimsCache.instance.failedCountForLogging, 0);
    },
  );

  test(
    'ETAPE 1 (complement securite) -- les 25 SKU hors-gate dont le '
    'fichier <ref>.json existe pourtant sur disque (statut: OK) ne '
    'chargent JAMAIS via le cache -- zero exception, hasFailed==true '
    'pour les 25, y compris les 16 qui auraient fait lever l\'ancien '
    'assert() (verification qu\'ils sont maintenant neutralises par le '
    'filtre index.json, avant meme d\'atteindre loadProfileDims)',
    () async {
      final unexpectedlyLoaded = <String>[];
      for (final ref in horsGateButFileExists) {
        await _ensureLoadedOrFailed(ref);
        if (ProfileDimsCache.instance.getIfLoaded(ref) != null) {
          unexpectedlyLoaded.add(ref);
        }
        expect(
          ProfileDimsCache.instance.hasFailed(ref),
          isTrue,
          reason: '$ref: attendu hasFailed==true (exclu par index.json)',
        );
      }

      expect(
        unexpectedlyLoaded,
        isEmpty,
        reason:
            'Refs hors gate mais chargees quand meme -- fuite du filtre '
            'index.json : $unexpectedlyLoaded',
      );

      // Livrable log : les 25 sont comptees comme echouees (exclusion
      // par index.json), zero chargee -- cardinalites exactes,
      // demontrant que loadedCountForLogging/failedCountForLogging
      // reflete fidelement get etat reel apres cette boucle.
      expect(ProfileDimsCache.instance.loadedCountForLogging, 0);
      expect(ProfileDimsCache.instance.failedCountForLogging, 25);

      // Le rejet a eu lieu au niveau de la couverture (index.json), PAS
      // au niveau du controle de coherence bbox_mm de loadProfileDims --
      // ce compteur ne doit donc PAS avoir bouge via ce chemin (le cache
      // n'a jamais appele loadProfileDims pour ces refs).
      expect(rejectedByContractCount, 0);
    },
  );

  test(
    'ETAPE 1 (bout-en-bout, meme test) -- chargement des 31 gate-OK PUIS '
    'des 25 hors-gate dans le MEME cache (ordre realiste : un catalogue '
    'affiche un melange de refs) -- les cardinalites finales du livrable '
    'log sont exactement 31 charges / 25 echoues, sans interference entre '
    'les deux groupes',
    () async {
      for (final ref in coveredRefs) {
        await _ensureLoadedOrFailed(ref);
      }
      for (final ref in horsGateButFileExists) {
        await _ensureLoadedOrFailed(ref);
      }

      expect(ProfileDimsCache.instance.loadedCountForLogging, 31);
      expect(ProfileDimsCache.instance.failedCountForLogging, 25);

      for (final ref in coveredRefs) {
        expect(ProfileDimsCache.instance.getIfLoaded(ref), isNotNull);
      }
      for (final ref in horsGateButFileExists) {
        expect(ProfileDimsCache.instance.hasFailed(ref), isTrue);
      }
    },
  );

  test(
    'verification directe (hors cache, appel loadProfileDims explicite) : '
    'les profils a risque de crash sous l\'ancien assert() -- derives du '
    'CSV (statut_gate == SUSPECT_GEOMETRIE, motif DEBORD_PLAN_*, hors '
    'exclusion precoce par indices de face de pose vides), PAS une liste '
    'recopiee a la main -- retournent desormais null et incrementent '
    'rejectedByContractCount, zero exception -- verrouille l\'invariant '
    '"plus jamais de crash" independamment du filtrage index.json '
    '(defense en profondeur : meme si index.json etait un jour mal '
    'genere et laissait passer une de ces refs, loadProfileDims la '
    'rejetterait quand meme silencieusement)',
    () async {
      final crashRiskRefs = _readCrashRiskRefsFromCsv();

      // Le nombre exact depend des donnees du batch d'extraction (16 sur
      // le jeu de donnees actuel, verifie le 2026-08-XX lors de cette
      // session) -- ce test ne verrouille PAS ce chiffre : il verrouille
      // le COMPORTEMENT (rejet + comptage cumulatif) pour la liste telle
      // qu'elle est aujourd'hui, quelle que soit sa taille demain.
      expect(
        crashRiskRefs,
        isNotEmpty,
        reason:
            'Aucun profil a risque de crash trouve dans le CSV -- soit le '
            'jeu de donnees a change (bien), soit le parsing CSV de ce '
            'test est casse (mauvais) : a distinguer avant de continuer.',
      );

      var rejectedCount = 0;
      for (final ref in crashRiskRefs) {
        final dims = await loadProfileDims(ref);
        expect(dims, isNull, reason: '$ref devrait etre rejete (debord bbox_mm)');
        rejectedCount++;
        expect(
          rejectedByContractCount,
          rejectedCount,
          reason:
              '$ref: le compteur devrait s\'incrementer de 1 exactement '
              'a chaque rejet, cumulatif.',
        );
      }

      // Bilan cumulatif final = nombre de refs testees, PAS un nombre
      // magique fixe -- coherent par construction avec la boucle
      // ci-dessus, mais verifie explicitement pour capter toute
      // desynchronisation future entre le compteur et la liste source.
      expect(rejectedByContractCount, crashRiskRefs.length);
    },
  );
}
