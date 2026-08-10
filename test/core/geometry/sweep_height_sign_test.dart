// Test de non-régression — signe de `heightAxis` dans `sweep.dart`.
//
// Contexte (doute utilisateur, confirmé) : `_downFromCeiling()` retourne
// `heightAxis.y = -1.0` pour un plafond de normale (0,1,0). Combiné à
// `profileToWorld` (`world = wallOrigin + heightAxis*(yProfilMm/1000) + ...`)
// et à la convention `CONVENTIONS.md` §2 (`yProfilMm <= 0`, décroît en
// descendant), le produit `(-1.0) * (nombre négatif)` est **positif** :
// le point du profil monte (Y monde croissant) au lieu de descendre sous le
// plafond. Confirmé algébriquement (`/tmp/sign_check.dart`) et
// empiriquement sur le point bas du mur de D720.json (idx=1,
// y=-202.8698mm) : Y monde calculé = wallOrigin.y + 0.20287 (attendu :
// wallOrigin.y - 0.20287).
//
// Ce fichier fixe DEUX assertions dures qui doivent être VRAIES pour un
// mesh correctement placé (point bas du mur SOUS l'arête mur∩plafond) :
// 1. ring0[wallIndices[0]].y ≈ wallOrigin.y - 0.20287 (tolérance 1e-6 m).
// 2. pixelY(point bas du mur) > pixelY(arête plafond) — convention image
//    (Y croît vers le bas), donc "plus bas visuellement" = pixelY plus
//    grand.
//
// État attendu AVANT correctif (ce commit) : ROUGE — les deux assertions
// échouent (le mesh est actuellement au-dessus du plafond, pas dessous).
// État attendu APRÈS correctif (`sweep.dart`, commit suivant) : VERT.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:staff_decor_studio/core/geometry/calib_to_camera.dart';
import 'package:staff_decor_studio/core/geometry/sweep.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

MoulureProfile loadProfileFromJson(Map<String, dynamic> json) {
  final rawPts = (json['profil_mm'] as List)
      .map((p) => vm.Vector2((p[0] as num).toDouble(), (p[1] as num).toDouble()))
      .toList();
  var pts = rawPts;
  if (rawPts.length > 1 && rawPts.first.distanceTo(rawPts.last) < 1e-6) {
    pts = rawPts.sublist(0, rawPts.length - 1);
  }
  final wallIdx =
      (json['face_pose_mur']['indices'] as List).map((i) => i as int).toList();
  final ceilIdx = (json['face_pose_plafond']['indices'] as List)
      .map((i) => i as int)
      .toList();
  return MoulureProfile(pointsMm: pts, wallIndices: wallIdx, ceilingIndices: ceilIdx);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'signe heightAxis : le point bas du mur (yProfilMm=-202.8698) doit '
    'être SOUS l\'arête mur∩plafond, pas dessus',
    () async {
      const imgW = 2560.0;
      const imgH = 1783.0;
      final calib = PerspCalib.forDemoScene('haussmann');
      final scene =
          buildCalibratedScene(calib: calib, imageWidthPx: imgW, imageHeightPx: imgH);
      final jsonStr =
          await File('${Directory.current.path}/assets/profiles/D720.json')
              .readAsString();
      final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      final profile = loadProfileFromJson(profileJson);

      final pathMeters = [scene.ceilLOnEdge, scene.ceilROnEdge];
      final wallPlanes = [scene.backWallPlane];
      final rings = computeCrossSectionRings(
        profile: profile,
        pathMeters: pathMeters,
        wallPlanes: wallPlanes,
        ceilingPlane: scene.ceilingPlane,
      );
      final ring0 = rings[0];

      // wallIndices[0] = idx 1 dans D720.json -> profil (x=0, y=-202.8698mm)
      // = coin bas du mur (le point le plus loin du plafond côté mur).
      final wallIdx0 = profile.wallIndices.first;
      final bottomWallPoint = ring0[wallIdx0];
      final yProfilMm = profile.pointsMm[wallIdx0].y;
      expect(
        yProfilMm,
        closeTo(-202.8698, 1e-3),
        reason: 'Sanity : le point de test attendu est bien (0,-202.8698mm).',
      );

      // ── Assertion dure #1 : position monde Y ──
      // wallOrigin = ceilLOnEdge (voir _buildSegmentFrame : le premier
      // segment démarre exactement sur l'arête mur∩plafond côté ceilL).
      final wallOriginY = scene.ceilLOnEdge.y;
      final expectedY = wallOriginY + (yProfilMm / 1000.0); // <= wallOriginY
      expect(
        bottomWallPoint.y,
        closeTo(expectedY, 1e-6),
        reason:
            'Le point bas du mur doit être à wallOrigin.y + yProfilMm/1000 '
            '(= wallOrigin.y - 0.202870, DONC en-dessous du plafond) — '
            'obtenu ${bottomWallPoint.y}, attendu $expectedY '
            '(wallOrigin.y=$wallOriginY). Si ce test échoue avec '
            'bottomWallPoint.y ≈ wallOrigin.y + 0.202870 (signe inversé), '
            'c\'est le bug de signe heightAxis confirmé par l\'utilisateur.',
      );

      // ── Assertion dure #2 : ordre en pixels (image Y croît vers le bas) ──
      final pixelBottom = scene.camera.project(bottomWallPoint).pixel;
      final pixelCeiling = scene.camera.project(scene.ceilLOnEdge).pixel;
      expect(
        pixelBottom.y,
        greaterThan(pixelCeiling.y),
        reason:
            'Le point bas du mur doit être visuellement PLUS BAS que '
            'l\'arête plafond, donc pixelY(bas) > pixelY(plafond) en '
            'convention image (Y croît vers le bas). Obtenu '
            'pixelBottom.y=${pixelBottom.y} vs pixelCeiling.y='
            '${pixelCeiling.y}.',
      );
    },
  );
}
