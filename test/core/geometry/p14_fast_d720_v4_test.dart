// ══════════════════════════════════════════════════════════════════════
// P14-FAST v4 — rectification de cible (pH recalculé sur la calibration
// manuelle mur-miroir de v3, PAS l'ancien pH du preset large) + comparateur
// visuel d'échelle (override 1.0 vs 1.134), UNE seule passe.
//
// Base : v3 FIGÉE (calibration manuelle, axes, floorR, matériau,
// éclairage, bornes x) — repris ICI À L'IDENTIQUE, rien retouché.
//
// Cible périmée (112.8px) abandonnée : elle venait de pxParMm=0.556296,
// calculé sur le pH du PRESET LARGE (sol à yPct≈0.86), invalidé en
// P14-FAST v3. Avec la calibration manuelle (ceilL.yPct=0.090,
// floorL.yPct=0.685) :
//   pH = (0.685 - 0.090) * 1783 ≈ 1060.885 px (pour roomHeightM=2.5m)
//   pxParMm = pH / 2500 ≈ 0.424354
//   cible corrigée = 202.87 * 0.424354 * 1.1606 ≈ 99.9 px
// Mesure v3 = 99.47px, écart 0.4% -> AUCUNE correction de hauteur n'est
// géométriquement justifiée à partir de cette cible corrigée.
//
// `visualScaleOverride` : paramètre EXPOSÉ ICI, DANS CE TEST UNIQUEMENT —
// jamais lu par le code de production (`app_state.dart`,
// `cornice_plinth_painter.dart`, `RoomPainter`, etc.), jamais une
// constante en dur ailleurs que la valeur d'appel locale ci-dessous
// (1.0 / 1.134). Implémenté par un helper 100% test-local
// (`scaleMeshAboutEdge`) qui redimensionne les sommets du [Mesh] autour de
// la droite d'ancrage mur∩plafond (`ceilLOnEdge`->`ceilROnEdge`) — les
// points SUR cette droite (donc les bornes gauche/droite du trajet) ne
// sont PAS déplacés par construction (`d = p - closest; scaled = closest +
// d*factor` — si `p` est déjà sur la droite, `d=0`, `scaled=p`), ce qui
// préserve les bornes x du mesh, conformément à l'interdiction "pas de
// retour sur floorR / bornes x".
//
// 1.134 est une EXAGÉRATION VISUELLE DE COMPARAISON, PAS un facteur de
// correction retenu — la version de référence reste 1.0. Ne déclare PAS
// "D720 renderable".
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:staff_decor_studio/core/geometry/calib_to_camera.dart';
import 'package:staff_decor_studio/core/geometry/camera.dart';
import 'package:staff_decor_studio/core/geometry/sweep.dart';
import 'package:staff_decor_studio/core/perspective/mesh_painter.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

const double roomHeightMInjectable = 2.5;

MoulureProfile loadProfileFromJson(Map<String, dynamic> json) {
  final rawPts = (json['profil_mm'] as List)
      .map((p) => vm.Vector2((p[0] as num).toDouble(), (p[1] as num).toDouble()))
      .toList();
  var pts = rawPts;
  if (rawPts.length > 1 && rawPts.first.distanceTo(rawPts.last) < 1e-6) {
    pts = rawPts.sublist(0, rawPts.length - 1);
  }
  final wallIdx = (json['face_pose_mur']['indices'] as List).map((i) => i as int).toList();
  final ceilIdx = (json['face_pose_plafond']['indices'] as List).map((i) => i as int).toList();
  return MoulureProfile(pointsMm: pts, wallIndices: wallIdx, ceilingIndices: ceilIdx);
}

int _bottomIdxOf(MoulureProfile p) {
  var bottomIdx = 0;
  var minY = p.pointsMm[0].y;
  for (var i = 1; i < p.pointsMm.length; i++) {
    if (p.pointsMm[i].y < minY) {
      minY = p.pointsMm[i].y;
      bottomIdx = i;
    }
  }
  return bottomIdx;
}

Future<ui.Image> decodeImageFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<Uint8List> encodePng(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

void paintMeshWireframe(
  ui.Canvas canvas,
  Mesh mesh,
  Camera3D camera, {
  ui.Color color = const ui.Color(0xFF00C800),
  double strokeWidth = 1.0,
}) {
  final vertexCount = mesh.vertexCount;
  if (vertexCount == 0) return;
  final screenPos = List<ui.Offset>.filled(vertexCount, ui.Offset.zero);
  for (var i = 0; i < vertexCount; i++) {
    final proj = camera.project(mesh.positionAt(i));
    screenPos[i] = ui.Offset(proj.pixel.x, proj.pixel.y);
  }
  final paint = ui.Paint()
    ..color = color
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = strokeWidth;
  final triangleCount = mesh.triangleCount;
  for (var t = 0; t < triangleCount; t++) {
    final i0 = mesh.indices[t * 3];
    final i1 = mesh.indices[t * 3 + 1];
    final i2 = mesh.indices[t * 3 + 2];
    final path = ui.Path()
      ..moveTo(screenPos[i0].dx, screenPos[i0].dy)
      ..lineTo(screenPos[i1].dx, screenPos[i1].dy)
      ..lineTo(screenPos[i2].dx, screenPos[i2].dy)
      ..close();
    canvas.drawPath(path, paint);
  }
}

/// Redimensionne un point [p] autour de la droite (monde) définie par
/// [linePoint]/[lineDirUnit] (unitaire), par le facteur [factor] —
/// helper 100% test-local, voir docstring de tête de fichier. Un point
/// déjà sur la droite reste fixe (`d=0`).
vm.Vector3 scalePointAboutEdge(
  vm.Vector3 p,
  vm.Vector3 linePoint,
  vm.Vector3 lineDirUnit,
  double factor,
) {
  final t = (p - linePoint).dot(lineDirUnit);
  final closest = linePoint + lineDirUnit * t;
  final d = p - closest;
  return closest + d * factor;
}

/// Applique [scalePointAboutEdge] à tous les sommets d'un [Mesh] — nouveau
/// [Mesh] indépendant, mêmes indices/normales/UVs (approximation
/// acceptable : comparateur visuel d'exagération, pas un recalcul de
/// normales exact). Utilisé UNIQUEMENT par ce test.
Mesh scaleMeshAboutEdge(
  Mesh mesh,
  vm.Vector3 linePoint,
  vm.Vector3 lineDirUnit,
  double factor,
) {
  final n = mesh.vertexCount;
  final newPositions = Float32List(mesh.positions.length);
  for (var i = 0; i < n; i++) {
    final scaled = scalePointAboutEdge(
      mesh.positionAt(i),
      linePoint,
      lineDirUnit,
      factor,
    );
    newPositions[i * 3] = scaled.x;
    newPositions[i * 3 + 1] = scaled.y;
    newPositions[i * 3 + 2] = scaled.z;
  }
  return Mesh(
    positions: newPositions,
    indices: mesh.indices,
    normals: mesh.normals,
    uvs: mesh.uvs,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P14-FAST v4 — cible rectifiée (pH manuel) + comparateur visualScaleOverride '
    '1.0 vs 1.134 — base v3 figée, rien retouché (calib/axes/floorR/matériau/'
    'éclairage/bornes x)',
    () async {
      final projectRoot = Directory.current.path;
      const sku = 'D720';
      const sceneKey = 'haussmann';
      final photoPath = '$projectRoot/assets/demo_scenes/$sceneKey.jpg';
      final photo = await decodeImageFile(photoPath);
      final photoW = photo.width.toDouble();
      final photoH = photo.height.toDouble();

      // ── Calibration manuelle v3, FIGÉE, reprise à l'identique. ──
      const calibManualV3 = PerspCalib(
        ceilL: CalibPoint(xPct: 0.16, yPct: 0.090),
        ceilR: CalibPoint(xPct: 0.56, yPct: 0.088),
        floorL: CalibPoint(xPct: 0.16, yPct: 0.685),
        floorR: CalibPoint(xPct: 0.56, yPct: 0.686),
        wallTL: CalibPoint(xPct: 0.16, yPct: 0.090),
        wallTR: CalibPoint(xPct: 0.56, yPct: 0.088),
        wallBL: CalibPoint(xPct: 0.16, yPct: 0.685),
        wallBR: CalibPoint(xPct: 0.56, yPct: 0.686),
      );

      final jsonStr = await File('$projectRoot/assets/profiles/$sku.json').readAsString();
      final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      final bboxHMm = (profileJson['bbox_mm']['h'] as num).toDouble();
      final baseProfile = loadProfileFromJson(profileJson);

      final scene = buildCalibratedScene(
        calib: calibManualV3,
        imageWidthPx: photoW,
        imageHeightPx: photoH,
        roomHeightM: roomHeightMInjectable,
      );

      // ── Rectification de cible : pH recalculé SUR LA CALIBRATION
      //    MANUELLE (pas le preset large, périmé). ──
      final pHPixelsManuel = (calibManualV3.floorL.yPct - calibManualV3.ceilL.yPct) * photoH;
      expect(pHPixelsManuel, closeTo(1060.885, 0.01));
      final pxParMmRectifie = pHPixelsManuel / (roomHeightMInjectable * 1000.0);
      expect(pxParMmRectifie, closeTo(0.424354, 1e-5));
      const facteurB = 1.1606032994794675; // établi en P14-C, conservé (report P14-E)
      final cibleRectifieePx = bboxHMm * pxParMmRectifie * facteurB;
      expect(cibleRectifieePx, closeTo(99.9, 0.5));

      // ── Trajet + mesh de base (override=1.0, identique v3). ──
      const pathSubdivisionStepMm = 50.0;
      final edgeVec = scene.ceilROnEdge - scene.ceilLOnEdge;
      final edgeLengthM = edgeVec.length;
      final edgeDir = edgeVec.normalized();
      final subdivisionCount = (edgeLengthM * 1000.0 / pathSubdivisionStepMm).ceil();
      final pathMeters = <vm.Vector3>[
        for (var i = 0; i <= subdivisionCount; i++)
          scene.ceilLOnEdge + edgeDir * (edgeLengthM * i / subdivisionCount),
      ];
      final wallPlanes = List.filled(pathMeters.length - 1, scene.backWallPlane);
      final midRingIndex = pathMeters.length ~/ 2;

      final baseMesh = sweepMoulure(
        profile: baseProfile,
        pathMeters: pathMeters,
        wallPlanes: wallPlanes,
        ceilingPlane: scene.ceilingPlane,
      );

      final rings = computeCrossSectionRings(
        profile: baseProfile,
        pathMeters: pathMeters,
        wallPlanes: wallPlanes,
        ceilingPlane: scene.ceilingPlane,
      );
      final ring = rings[midRingIndex];
      final topPtBase = ring[baseProfile.ceilingIndices.first];
      final bottomPtBase = ring[_bottomIdxOf(baseProfile)];

      // ── Anchor line pour le scale-about-edge : la droite mur∩plafond
      //    (ceilLOnEdge->ceilROnEdge), même droite qui définit
      //    `pathMeters` — les extrémités du trajet restent donc fixes
      //    quel que soit `override` (elles sont SUR cette droite). ──
      final anchorLinePoint = scene.ceilLOnEdge;
      final anchorLineDir = edgeDir;

      double measureHeightPxAtOverride(double override) {
        final topScaled = scalePointAboutEdge(topPtBase, anchorLinePoint, anchorLineDir, override);
        final bottomScaled = scalePointAboutEdge(bottomPtBase, anchorLinePoint, anchorLineDir, override);
        final topPx = scene.camera.project(topScaled).pixel;
        final bottomPx = scene.camera.project(bottomScaled).pixel;
        return (bottomPx.y - topPx.y).abs();
      }

      final hauteurPx100 = measureHeightPxAtOverride(1.0);
      final hauteurPx113 = measureHeightPxAtOverride(1.134);

      expect(hauteurPx100, closeTo(99.47, 1.0));
      expect(hauteurPx113, closeTo(112.8, 2.0));

      // ── Bornes x — vérifiées inchangées entre override=1.0 et 1.134
      //    (points d'extrémité de trajet sur la droite d'ancrage,
      //    jamais déplacés par scalePointAboutEdge). ──
      Iterable<double> xBoundsFrac(Mesh mesh) sync* {
        for (var i = 0; i < mesh.vertexCount; i++) {
          yield scene.camera.project(mesh.positionAt(i)).pixel.x / photoW;
        }
      }

      final mesh100 = scaleMeshAboutEdge(baseMesh, anchorLinePoint, anchorLineDir, 1.0);
      final mesh113 = scaleMeshAboutEdge(baseMesh, anchorLinePoint, anchorLineDir, 1.134);

      final xs100 = xBoundsFrac(mesh100).toList();
      final xs113 = xBoundsFrac(mesh113).toList();
      final minX100 = xs100.reduce((a, b) => a < b ? a : b);
      final maxX100 = xs100.reduce((a, b) => a > b ? a : b);
      final minX113 = xs113.reduce((a, b) => a < b ? a : b);
      final maxX113 = xs113.reduce((a, b) => a > b ? a : b);

      expect(minX113, closeTo(minX100, 0.01),
          reason: 'Bornes x doivent rester inchangées entre override=1.0 '
              'et 1.134 (extrémités de trajet sur la droite d\'ancrage) — '
              'interdiction "pas de retour sur floorR / bornes x".');
      expect(maxX113, closeTo(maxX100, 0.01));

      // ── Rendu commun (matériau/éclairage FIGÉS, identiques v3). ──
      const offWhite = ui.Color(0xFFF2EEE4);
      final light = vm.Vector3(-0.4, 0.6, 0.7).normalized();
      const ambient = 0.55;

      Future<Uint8List> renderMatiere(Mesh mesh) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          photo,
          ui.Rect.fromLTWH(0, 0, photoW, photoH),
          ui.Rect.fromLTWH(0, 0, photoW, photoH),
          ui.Paint(),
        );
        paintMeshOnCanvas(
          canvas,
          mesh,
          scene.camera,
          baseColor: offWhite,
          lightDirWorld: light,
          ambient: ambient,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(photo.width, photo.height);
        return encodePng(image);
      }

      final png100 = await renderMatiere(mesh100);
      const outPng100Path = '/tmp/p14_fast_d720_after_v4_scale100.png';
      await File(outPng100Path).writeAsBytes(png100);
      expect(await File(outPng100Path).exists(), isTrue);

      final png113 = await renderMatiere(mesh113);
      const outPng113Path = '/tmp/p14_fast_d720_after_v4_scale113.png';
      await File(outPng113Path).writeAsBytes(png113);
      expect(await File(outPng113Path).exists(), isTrue);

      // ── Wireframe (override=1.0). ──
      final recorderWire = ui.PictureRecorder();
      final canvasWire = ui.Canvas(recorderWire);
      canvasWire.drawImageRect(
        photo,
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Paint(),
      );
      paintMeshWireframe(canvasWire, mesh100, scene.camera);
      final pictureWire = recorderWire.endRecording();
      final imageWire = await pictureWire.toImage(photo.width, photo.height);
      final pngWire = await encodePng(imageWire);
      const outPngWirePath = '/tmp/p14_fast_d720_wire_v4.png';
      await File(outPngWirePath).writeAsBytes(pngWire);
      expect(await File(outPngWirePath).exists(), isTrue);

      // ── Rapport (6-8 lignes). ──
      final retombeeEquivMm = bboxHMm * 1.134;
      final report = StringBuffer();
      report.writeln('P14-FAST v4 — cible rectifiée + comparateur override 1.0 vs 1.134 (D720, calib manuelle v3 figée)');
      report.writeln('pH mesure = ${pHPixelsManuel.toStringAsFixed(3)} px (calib manuelle : ceilL.yPct=0.090, floorL.yPct=0.685, roomHeightM=$roomHeightMInjectable)');
      report.writeln('pxParMm recalcule = ${pxParMmRectifie.toStringAsFixed(6)} (cible perimee 0.556296 abandonnee, venait du preset large invalide)');
      report.writeln('cible corrigee = ${cibleRectifieePx.toStringAsFixed(2)} px (bboxHMm=$bboxHMm x pxParMm x B=1.1606)');
      report.writeln('hauteur mesuree (override=1.0)   = ${hauteurPx100.toStringAsFixed(2)} px (ecart cible ${(hauteurPx100 - cibleRectifieePx).abs().toStringAsFixed(2)}px -> aucune correction geometriquement justifiee)');
      report.writeln('hauteur mesuree (override=1.134) = ${hauteurPx113.toStringAsFixed(2)} px (retombee equivalente implicite = ${retombeeEquivMm.toStringAsFixed(1)}mm -> NON conforme au D720 reel, 202.87mm)');
      report.writeln('bornes x = [${minX100.toStringAsFixed(4)}, ${maxX100.toStringAsFixed(4)}] (identiques a override=1.134, extremites sur droite d\'ancrage, jamais deplacees)');
      report.writeln('Defauts restants : extremites nettes au jambage (coupe droite, pas de retour ni de coupe sur tableaux de porte) ; override=1.134 est une EXAGERATION VISUELLE de comparaison, PAS un facteur retenu -- reference = 1.0. NE PAS declarer D720 renderable.');

      const outTxtPath = '/tmp/p14_fast_d720_after_v4.txt';
      await File(outTxtPath).writeAsString(report.toString());
      expect(await File(outTxtPath).exists(), isTrue);

      // ignore: avoid_print
      print(report.toString());
    },
  );
}
