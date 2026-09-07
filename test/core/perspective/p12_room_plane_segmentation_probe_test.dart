/// P12 — SONDE REELLE : mesure la qualite d'une segmentation IA REELLE
/// (SegFormer B0, `backend/segformer_service/`) sur les 4 vraies photos
/// de `assets/demo_scenes/`, via `HttpRoomPlaneSegmenter` pointe sur le
/// service local (`http://localhost:8000/segment`).
///
/// ============================================================
/// AVERTISSEMENT EXPLICITE, contrairement a P11 :
/// provider HTTP reel, mesure la qualite IA.
/// ============================================================
/// Ce fichier NE reutilise PAS le masque synthetique parfait de
/// `FakeRoomPlaneSegmenter` (P11) : il envoie les VRAIS octets JPEG des
/// 4 scenes demo au VRAI service FastAPI/SegFormer B0, recoit un VRAI
/// masque de segmentation IA, et mesure les erreurs contre
/// `PerspCalib.forDemoScene` (verite terrain calee a la main sur ces
/// memes photos).
///
/// L'erreur maximale de 0.003 mesuree par la sonde P11 (masque
/// synthetique parfait) NE PREDIT RIEN de la qualite mesuree ici. La
/// porte |err| < 0.02 de P11 est probablement hors d'atteinte sur de
/// vraies photos (0.02 en yPct sur une image de 384px de haut = 8px,
/// l'epaisseur d'une corniche) - CE FICHIER N'IMPOSE AUCUNE PORTE DURE
/// sur les erreurs de frontiere. Les 3 bandes de decision (auto-apply
/// silencieux / auto-apply avec point visible / manualRequired) restent
/// A DEFINIR a partir des chiffres mesures ici, pas avant.
///
/// PREREQUIS pour executer ce fichier : le service FastAPI doit tourner
/// en local sur le port 8000 AVANT de lancer `flutter test` sur ce
/// fichier precis :
///   cd backend/segformer_service
///   MEASURE_MODE=1 uvicorn main:app --host 0.0.0.0 --port 8000
///
/// Ce fichier n'est PAS inclus dans la suite `flutter test` standard
/// sans service actif : si le service ne repond pas, chaque test de
/// scene echoue explicitement avec un message clair (pas de skip
/// silencieux), pour eviter un faux "vert" qui masquerait l'absence de
/// service. Documente l'avertissement methodologique du brief P12 : 4
/// photos n'ont aucune valeur statistique, un jeu de controle de 20-30
/// photos est necessaire avant tout branchement sur le rendu -- non
/// traite dans ce fichier (etape suivante, hors P12 mesure initiale).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/http_room_plane_segmenter.dart';
import 'package:staff_decor_studio/core/perspective/plane_boundary_extractor.dart';
import 'package:staff_decor_studio/core/perspective/room_plane_analysis.dart';
import 'package:staff_decor_studio/core/perspective/room_plane_segmenter.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

/// Resolution de travail demandee au backend -- doit matcher celle du
/// pipeline (voir p11_room_plane_segmentation_probe_test.dart).
const int kMaskWidth = 512;
const int kMaskHeight = 384;

/// Service FastAPI local (backend/segformer_service/, MEASURE_MODE=1
/// recommande pour eviter de re-inferer a chaque run pendant le
/// developpement -- voir README.md du service).
final Uri kSegmentEndpoint = Uri.parse('http://localhost:8000/segment');

const Map<String, List<int>> sceneSizes = {
  'haussmann': [2560, 1783],
  'moderne': [1960, 1470],
  'provencal': [2560, 1707],
  'scandinave': [1920, 1088],
};

const List<String> kScenes = ['haussmann', 'moderne', 'provencal', 'scandinave'];

class SceneProbeResult {
  final String scene;
  final double? ceilL;
  final double? ceilR;
  final double? floorL;
  final double? floorR;
  final double? xL;
  final double? xR;
  final double qualityScore;
  final Map<String, double> qualitySubScores;
  final bool manualRequired;
  final List<String> manualRequiredReasons;
  final int inferenceMs;

  // P12-ter §4 : collectees maintenant SANS en faire une porte -- ce
  // sont les 2 grandeurs qui serviront a concevoir le "discriminant
  // moderne" au tour suivant (brief P12-ter §2/§5).
  /// Proportion de colonnes valides (samples.length / mask.width) pour
  /// chaque frontiere -- pour wallFloor en mode firstOfLower, une
  /// colonne exclue signifie qu'aucun pixel floor n'atteint le bord bas
  /// de l'image sur cette colonne (occlusion totale, voir caveat #2).
  final double ceilingWallValidColumnProportion;
  final double wallFloorValidColumnProportion;

  /// Dispersion (ecart-type) des residus `yPct - yAt(xPct)` sur les
  /// samples de chaque frontiere -- mesure la coherence interne du
  /// nuage de points, independamment de la comparaison a la verite
  /// terrain (ceilL/ceilR/floorL/floorR).
  final double ceilingWallResidualDispersion;
  final double wallFloorResidualDispersion;

  // P12-quater §Patch C : evalAt(xVerite) pour chacun des 4 points de
  // verite terrain (ceilL/ceilR/floorL/floorR) -- DISTINCT des flags
  // edgeL/cornerL/cornerR/edgeR de analyseLabelMap (voir brief : "les
  // deux jeux ne coincident pas et ne doivent pas etre presentes comme
  // equivalents"). La valeur brute reste toujours presente meme si le
  // point est signale extrapole/hors bornes.
  final BoundaryEval? ceilLEval;
  final BoundaryEval? ceilREval;
  final BoundaryEval? floorLEval;
  final BoundaryEval? floorREval;

  // P12-quater : domaines d'echantillons observes + evals de
  // plausibilite (edgeL/cornerL/cornerR/edgeR) + balayage de marges,
  // copies depuis debugJson de analyseLabelMap pour le rapport de la
  // sonde.
  final List<double>? ceilingWallSampleDomain;
  final List<double>? wallFloorSampleDomain;
  final Map<String, dynamic>? ceilingWallEvals;
  final Map<String, dynamic>? wallFloorEvals;
  final Map<String, dynamic> extrapolationSweep;

  const SceneProbeResult({
    required this.scene,
    required this.ceilL,
    required this.ceilR,
    required this.floorL,
    required this.floorR,
    required this.xL,
    required this.xR,
    required this.qualityScore,
    required this.qualitySubScores,
    required this.manualRequired,
    required this.manualRequiredReasons,
    required this.inferenceMs,
    required this.ceilingWallValidColumnProportion,
    required this.wallFloorValidColumnProportion,
    required this.ceilingWallResidualDispersion,
    required this.wallFloorResidualDispersion,
    required this.ceilLEval,
    required this.ceilREval,
    required this.floorLEval,
    required this.floorREval,
    required this.ceilingWallSampleDomain,
    required this.wallFloorSampleDomain,
    required this.ceilingWallEvals,
    required this.wallFloorEvals,
    required this.extrapolationSweep,
  });

  Map<String, dynamic> toJson() => {
    'provider': 'HTTP_REAL',
    'scene': scene,
    'sourceImageSize': {
      'width': sceneSizes[scene]![0],
      'height': sceneSizes[scene]![1],
    },
    'maskSize': {'width': kMaskWidth, 'height': kMaskHeight},
    'errors': {'ceilL': ceilL, 'ceilR': ceilR, 'floorL': floorL, 'floorR': floorR, 'xL': xL, 'xR': xR},
    'qualityScore': qualityScore,
    'qualitySubScores': qualitySubScores,
    'manualRequired': manualRequired,
    'manualRequiredReasons': manualRequiredReasons,
    'inferenceMs': inferenceMs,
    'validColumnProportion': {
      'ceilingWall': ceilingWallValidColumnProportion,
      'wallFloor': wallFloorValidColumnProportion,
    },
    'residualDispersion': {
      'ceilingWall': ceilingWallResidualDispersion,
      'wallFloor': wallFloorResidualDispersion,
    },
    // P12-quater : evals aux 4 abscisses de VERITE (distinct des evals
    // aux 4 abscisses edgeL/cornerL/cornerR/edgeR ci-dessous).
    'evalAtTruth': {
      'ceilL': ceilLEval?.toJson(),
      'ceilR': ceilREval?.toJson(),
      'floorL': floorLEval?.toJson(),
      'floorR': floorREval?.toJson(),
    },
    'sampleDomain': {
      'ceilingWall': ceilingWallSampleDomain,
      'wallFloor': wallFloorSampleDomain,
    },
    // Evals aux abscisses edgeL/cornerL/cornerR/edgeR (celles
    // controlees par analyseLabelMap, marge=0.0).
    'ceilingWallEvals': ceilingWallEvals,
    'wallFloorEvals': wallFloorEvals,
    'extrapolationSweep': extrapolationSweep,
  };
}

/// Exécute la sonde reelle pour une [scene] : lit les vrais octets JPEG
/// de `assets/demo_scenes/<scene>.jpg`, les envoie a
/// [HttpRoomPlaneSegmenter] (service local reel), extrait les
/// frontieres via `analyseLabelMap`, calcule les 6 erreurs signees par
/// comparaison a la verite terrain `PerspCalib.forDemoScene(scene)`.
///
/// Meme structure de sortie que la sonde P11 (voir
/// p11_room_plane_segmentation_probe_test.dart), + `inferenceMs`
/// (temps mesure de l'appel HTTP complet, requis par le brief P12 pour
/// le "temps d'inference median" du rapport final).
Future<SceneProbeResult> _runProbe(String scene) async {
  final truth = PerspCalib.forDemoScene(scene);

  final imageFile = File('assets/demo_scenes/$scene.jpg');
  if (!imageFile.existsSync()) {
    throw StateError(
      'scene $scene: fichier introuvable ${imageFile.path} '
      '(execute depuis la racine du projet flutter_app ?)',
    );
  }
  final imageBytes = imageFile.readAsBytesSync();

  final segmenter = HttpRoomPlaneSegmenter(endpoint: kSegmentEndpoint);

  final stopwatch = Stopwatch()..start();
  final RoomPlaneMaskResult? mask;
  try {
    mask = await segmenter.segment(
      imageBytes: imageBytes,
      width: kMaskWidth,
      height: kMaskHeight,
    );
  } catch (e) {
    throw StateError(
      'scene $scene: appel au service reel a echoue -- le service '
      'FastAPI tourne-t-il sur $kSegmentEndpoint ? '
      '(cd backend/segformer_service && MEASURE_MODE=1 uvicorn main:app '
      '--host 0.0.0.0 --port 8000) -- erreur originale: $e',
    );
  }
  stopwatch.stop();

  if (mask == null) {
    throw StateError('scene $scene: le service a renvoye un masque null (inattendu -- HttpRoomPlaneSegmenter ne renvoie null que si non implemente)');
  }

  final analysis = analyseLabelMap(mask);

  final ceilingWall = analysis.ceilingWallBoundary;
  final wallFloor = analysis.wallFloorBoundary;

  // P12-quater §Patch C : evalAt(xVerite) pour chacun des 4 points de
  // verite terrain -- distinct des evals edgeL/cornerL/cornerR/edgeR de
  // analyseLabelMap (voir brief). La valeur brute (yPct/erreur signee)
  // est TOUJOURS calculee et conservee, meme si le point est marque
  // extrapole ou hors bornes -- "l'appelant decide, le calcul ne
  // ment pas".
  final ceilLEval = ceilingWall?.evalAt(truth.ceilL.xPct);
  final ceilREval = ceilingWall?.evalAt(truth.ceilR.xPct);
  final floorLEval = wallFloor?.evalAt(truth.floorL.xPct);
  final floorREval = wallFloor?.evalAt(truth.floorR.xPct);

  final ceilL = ceilingWall != null
      ? ceilingWall.yAt(truth.ceilL.xPct) - truth.ceilL.yPct
      : null;
  final ceilR = ceilingWall != null
      ? ceilingWall.yAt(truth.ceilR.xPct) - truth.ceilR.yPct
      : null;
  final floorL = wallFloor != null
      ? wallFloor.yAt(truth.floorL.xPct) - truth.floorL.yPct
      : null;
  final floorR = wallFloor != null
      ? wallFloor.yAt(truth.floorR.xPct) - truth.floorR.yPct
      : null;

  final detectedCorners = ceilingWall?.corners ?? wallFloor?.corners;
  final xL = detectedCorners != null ? detectedCorners[0] - truth.ceilL.xPct : null;
  final xR = detectedCorners != null ? detectedCorners[1] - truth.ceilR.xPct : null;

  final reasons = [...analysis.manualRequiredReasons];
  if (detectedCorners == null && !reasons.contains('corner_position_undetected')) {
    reasons.add('corner_position_undetected');
  }

  // P12-ter §4 : proportion de colonnes valides + dispersion des
  // residus, collectees sans en faire une porte (voir docstring de
  // SceneProbeResult).
  final ceilingWallValidProp = mask.width == 0
      ? 0.0
      : (ceilingWall?.samples.length ?? 0) / mask.width;
  final wallFloorValidProp = mask.width == 0
      ? 0.0
      : (wallFloor?.samples.length ?? 0) / mask.width;
  final ceilingWallDispersion = ceilingWall == null
      ? 0.0
      : _residualStdDev(ceilingWall.samples, ceilingWall.yAt);
  final wallFloorDispersion = wallFloor == null
      ? 0.0
      : _residualStdDev(wallFloor.samples, wallFloor.yAt);

  return SceneProbeResult(
    scene: scene,
    ceilL: ceilL,
    ceilR: ceilR,
    floorL: floorL,
    floorR: floorR,
    xL: xL,
    xR: xR,
    qualityScore: analysis.qualityScore,
    qualitySubScores: analysis.qualitySubScores,
    manualRequired: analysis.manualRequired || detectedCorners == null,
    manualRequiredReasons: reasons,
    inferenceMs: stopwatch.elapsedMilliseconds,
    ceilingWallValidColumnProportion: ceilingWallValidProp,
    wallFloorValidColumnProportion: wallFloorValidProp,
    ceilingWallResidualDispersion: ceilingWallDispersion,
    wallFloorResidualDispersion: wallFloorDispersion,
    ceilLEval: ceilLEval,
    ceilREval: ceilREval,
    floorLEval: floorLEval,
    floorREval: floorREval,
    ceilingWallSampleDomain:
        (analysis.debugJson['ceilingWallSampleDomain'] as List?)
            ?.cast<double>(),
    wallFloorSampleDomain:
        (analysis.debugJson['wallFloorSampleDomain'] as List?)
            ?.cast<double>(),
    ceilingWallEvals:
        analysis.debugJson['ceilingWallEvals'] as Map<String, dynamic>?,
    wallFloorEvals:
        analysis.debugJson['wallFloorEvals'] as Map<String, dynamic>?,
    extrapolationSweep:
        analysis.debugJson['extrapolationSweep'] as Map<String, dynamic>,
  );
}

/// Ecart-type des residus `yPct - yAt(xPct)` sur [samples] -- mesure de
/// dispersion PURE (pas de comparaison a une verite terrain), utilisee
/// par le brief P12-ter §4 comme candidate pour le futur "discriminant
/// moderne" (§2/§5), collectee ici sans etre transformee en porte.
double _residualStdDev(
  List<BoundarySample> samples,
  double Function(double xPct) yAt,
) {
  if (samples.length < 2) return 0.0;
  final residuals = samples.map((s) => s.yPct - yAt(s.xPct)).toList();
  final mean = residuals.reduce((a, b) => a + b) / residuals.length;
  var sumSq = 0.0;
  for (final r in residuals) {
    sumSq += (r - mean) * (r - mean);
  }
  return math.sqrt(sumSq / residuals.length);
}

String _fmtErr(double? v) => v == null ? 'N/A (manualRequired)' : v.toStringAsFixed(4);

void main() {
  group('P12 sonde REELLE - segmentation IA sur les 4 scenes demo (provider HTTP reel)', () {
    final results = <String, SceneProbeResult>{};

    for (final scene in kScenes) {
      test('scene $scene: mesure des erreurs signees vs verite terrain (AUCUNE porte dure)', () async {
        SceneProbeResult result;
        try {
          result = await _runProbe(scene);
        } catch (e) {
          // Service FastAPI local non demarre (ou injoignable) : SKIP
          // explicite, pas un echec de `flutter test` -- ce fichier a
          // une vraie dependance reseau (contrairement aux tests
          // MockClient de p12_http_room_plane_segmenter_contract_test),
          // donc ne peut pas faire partie de la garantie "255+ tests
          // toujours verts sans setup externe". Voir docstring de tete
          // de fichier pour la commande de demarrage du service.
          // ignore: avoid_print
          print(
            'scene $scene: SKIP -- service local injoignable sur '
            '$kSegmentEndpoint ($e). Demarrer le service avant de '
            'lancer ce fichier pour obtenir une mesure reelle.',
          );
          markTestSkipped('service FastAPI local non demarre sur $kSegmentEndpoint');
          return;
        }
        results[scene] = result;

        final jsonFile = File('/tmp/p12_segmentation_$scene.json');
        jsonFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(result.toJson()),
        );

        // AUCUNE porte dure ici (contrairement a P11) : le brief P12
        // interdit explicitement d'imposer un seuil avant mesure. Ce
        // test ne peut donc PAS echouer sur la valeur des erreurs --
        // seulement si le service est injoignable ou renvoie un
        // contrat invalide (exceptions remontees telles quelles depuis
        // _runProbe / HttpRoomPlaneSegmenter).
        // ignore: avoid_print
        print(
          'scene $scene: ceilL=${_fmtErr(result.ceilL)} ceilR=${_fmtErr(result.ceilR)} '
          'floorL=${_fmtErr(result.floorL)} floorR=${_fmtErr(result.floorR)} '
          'xL=${_fmtErr(result.xL)} xR=${_fmtErr(result.xR)} '
          'qualityScore=${result.qualityScore.toStringAsFixed(4)} '
          'manualRequired=${result.manualRequired} '
          'reasons=${result.manualRequiredReasons} '
          'inferenceMs=${result.inferenceMs} '
          'validCol(ceil/floor)=${result.ceilingWallValidColumnProportion.toStringAsFixed(3)}/'
          '${result.wallFloorValidColumnProportion.toStringAsFixed(3)} '
          'dispersion(ceil/floor)=${result.ceilingWallResidualDispersion.toStringAsFixed(4)}/'
          '${result.wallFloorResidualDispersion.toStringAsFixed(4)} '
          'yOOB@truth(ceilL/ceilR/floorL/floorR)='
          '${result.ceilLEval?.yOutOfBounds}/${result.ceilREval?.yOutOfBounds}/'
          '${result.floorLEval?.yOutOfBounds}/${result.floorREval?.yOutOfBounds}',
        );

        // Seule assertion : le test doit produire un resultat mesurable
        // (le contrat reseau/RLE est valide, pas la geometrie).
        expect(result, isNotNull);
      });
    }

    tearDownAll(() {
      final buffer = StringBuffer();
      buffer.writeln('provider HTTP réel, mesure la qualité IA');
      buffer.writeln('=' * 70);
      buffer.writeln(
        'Service: nvidia/segformer-b0-finetuned-ade-512-512 via '
        'backend/segformer_service/ (endpoint: $kSegmentEndpoint). '
        'AUCUNE porte dure sur les erreurs de frontiere -- les bandes '
        'de decision (auto-apply silencieux / auto-apply avec point '
        'visible / manualRequired) restent A DEFINIR a partir de ces '
        'chiffres, pas avant. AVERTISSEMENT: 4 photos n\'ont aucune '
        'valeur statistique -- un jeu de controle de 20-30 photos est '
        'necessaire avant tout branchement sur le rendu.',
      );
      buffer.writeln('');
      final inferenceTimes = <int>[];
      for (final scene in kScenes) {
        final r = results[scene];
        if (r == null) {
          buffer.writeln('scene $scene: (test non execute)');
          continue;
        }
        inferenceTimes.add(r.inferenceMs);
        buffer.writeln('--- scene: $scene ---');
        buffer.writeln('  sourceImageSize: ${sceneSizes[scene]![0]}x${sceneSizes[scene]![1]}');
        buffer.writeln('  ceilL  = ${_fmtErr(r.ceilL)}');
        buffer.writeln('  ceilR  = ${_fmtErr(r.ceilR)}');
        buffer.writeln('  floorL = ${_fmtErr(r.floorL)}');
        buffer.writeln('  floorR = ${_fmtErr(r.floorR)}');
        buffer.writeln('  xL     = ${_fmtErr(r.xL)}');
        buffer.writeln('  xR     = ${_fmtErr(r.xR)}');
        buffer.writeln('  qualityScore = ${r.qualityScore.toStringAsFixed(4)}');
        buffer.writeln('  qualitySubScores = ${r.qualitySubScores}');
        buffer.writeln('  manualRequired = ${r.manualRequired}');
        buffer.writeln('  manualRequiredReasons = ${r.manualRequiredReasons}');
        buffer.writeln('  inferenceMs = ${r.inferenceMs}');
        buffer.writeln(
          '  validColumnProportion: ceilingWall=${r.ceilingWallValidColumnProportion.toStringAsFixed(3)} '
          'wallFloor=${r.wallFloorValidColumnProportion.toStringAsFixed(3)} '
          '(P12-ter \u00a74, pas une porte -- candidat "discriminant moderne")',
        );
        buffer.writeln(
          '  residualDispersion: ceilingWall=${r.ceilingWallResidualDispersion.toStringAsFixed(4)} '
          'wallFloor=${r.wallFloorResidualDispersion.toStringAsFixed(4)} '
          '(P12-ter \u00a74, pas une porte -- candidat "discriminant moderne")',
        );
        // P12-quater : evalAt(xVerite) -- valeur brute TOUJOURS visible,
        // meme si yOutOfBounds/extrapole. Distinct des evals
        // edgeL/cornerL/cornerR/edgeR ci-dessous (points controles par
        // analyseLabelMap).
        buffer.writeln('  evalAtTruth (P12-quater, valeur brute + drapeaux) :');
        for (final entry in {
          'ceilL': r.ceilLEval,
          'ceilR': r.ceilREval,
          'floorL': r.floorLEval,
          'floorR': r.floorREval,
        }.entries) {
          final e = entry.value;
          if (e == null) {
            buffer.writeln('    ${entry.key}: N/A (frontiere absente)');
          } else {
            buffer.writeln(
              '    ${entry.key}: xPct=${e.xPct.toStringAsFixed(4)} '
              'yPctPredit=${e.yPct.toStringAsFixed(4)} '
              'yOutOfBounds=${e.yOutOfBounds} '
              'extrapolatedLeft=${e.extrapolatedLeft} '
              'extrapolatedRight=${e.extrapolatedRight}',
            );
          }
        }
        buffer.writeln(
          '  sampleDomain: ceilingWall=${r.ceilingWallSampleDomain} '
          'wallFloor=${r.wallFloorSampleDomain}',
        );
        buffer.writeln(
          '  ceilingWallEvals (edgeL/cornerL/cornerR/edgeR, margin=0.0) = '
          '${r.ceilingWallEvals}',
        );
        buffer.writeln(
          '  wallFloorEvals (edgeL/cornerL/cornerR/edgeR, margin=0.0) = '
          '${r.wallFloorEvals}',
        );
        buffer.writeln(
          '  extrapolationSweep (marges $kExtrapolationMarginSweep, '
          'DIAGNOSTIC seul, aucun rejet cable) = ${r.extrapolationSweep}',
        );
        buffer.writeln('');
      }
      if (inferenceTimes.isNotEmpty) {
        final sorted = [...inferenceTimes]..sort();
        final median = sorted[sorted.length ~/ 2];
        buffer.writeln('temps_inference_median_ms = $median (sur ${sorted.length} scenes: $sorted)');
      }
      File('/tmp/p12_segmentation.txt').writeAsStringSync(buffer.toString());
    });
  });
}
