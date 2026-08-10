// Test-outil de DIAGNOSTIC (pas un test-livrable de rendu final) : produit un
// PNG à 3 panneaux côte à côte permettant de trancher entre un bug de
// GÉOMÉTRIE (sweep.dart) et un problème d'ÉCLAIRAGE/OMBRAGE (mesh_painter.
// dart), sur un maillage de 300 mm de corniche SEUL (pas de photo de fond,
// caméra rapprochée en vue 3/4, maillage cadré pour occuper tout le cadre).
//
// ⚠️ CE TOUR : DIAGNOSTIC SEULEMENT. Ce fichier ne corrige RIEN dans
// `sweep.dart`/`mesh_painter.dart` — il les CONSOMME tels qu'ils sont
// aujourd'hui, sans modification, pour observer leur sortie brute.
//
// ⚠️ Sortie écrite dans `/tmp/` — JAMAIS dans `assets/` (règle SPEC.md
// "write-once" / anti-suppression).
//
// ── Panneau 1 : FIL DE FER ────────────────────────────────────────────────
// Toutes les arêtes de triangles du maillage, en noir sur fond blanc.
// Ne dépend d'AUCUN calcul de normale/éclairage — révèle uniquement la
// GÉOMÉTRIE (positions des sommets projetées). Si ce panneau montre un
// simple rectangle (ruban), le bug est dans `sweep.dart` (le balayage ne
// reproduit pas le profil). S'il montre la silhouette du profil avec ses
// gorges, la géométrie du contour est saine.
//
// ── Panneau 2 : NORMALES EN COULEUR, SANS ÉCLAIRAGE ───────────────────────
// Chaque sommet-de-facette colorié directement par sa normale :
// `(r,g,b) = (n+1)/2` (convention standard de normal-map), AUCUN produit
// scalaire avec une lumière. Si ce panneau est monochrome (une seule
// teinte uniforme sur tout le maillage), les normales sont fausses/nulles/
// toutes identiques → bug dans `sweep.dart` (calcul de normale par
// facette). Si les couleurs varient facette par facette (chaque pan du
// profil a sa propre teinte), les normales sont géométriquement saines et
// le problème visuel constaté ailleurs (bande grise plate) est un problème
// d'ÉCLAIRAGE, pas de géométrie.
//
// ── Panneau 3 : OMBRAGE ACTUEL ────────────────────────────────────────────
// Appel direct et NON MODIFIÉ de `paintMeshOnCanvas` (mesh_painter.dart) —
// le lambert tel qu'il est implémenté aujourd'hui, sans aucun changement.
//
// ── Chargement du profil ──────────────────────────────────────────────────
// Charge `assets/profiles/1000.json` — RÉPONSE À LA QUESTION PRÉALABLE : ce
// n'est PAS un L synthétique en dur, c'est un vrai JSON extrait
// (`statut: "OK"`, 49 sommets, bbox 230×30mm, SKU 1000/Colonnes-Pilastres).
// C'est le SEUL des 5 profils JSON présents dans `assets/profiles/` à avoir
// une géométrie exploitable (les 4 autres : `0900.json`, `1005.json`,
// `1145c.json`, `20-54.json` sont tous `statut: "ERREUR_SELECTION"`, 0
// sommet). Ni D899 ni Corniches-D631 (suggérés en repli par l'utilisateur)
// n'existent dans ce sandbox : seuls 5 fichiers DXF existent sous
// `assets/dxf/` (`1145C-pièce.dxf`, `0900.dxf`, `1000.dxf`, `1005.dxf`,
// `20-54.dxf`), aucun ne correspond à D899/D631, et aucun JSON de profil
// extrait n'existe pour ces deux références. `1000.json` est donc utilisé
// par nécessité (seule géométrie réelle disponible), pas par choix idéal.
//
// ── Scène synthétique (pas de photo, pas de calibration) ──────────────────
// Contrairement à `render_corniche_screenshot_test.dart` (qui utilise toute
// la chaîne photo + `PerspCalib` + `buildCalibratedScene`), ce test construit
// une scène minimale directement :
//   - plan plafond horizontal (normale (0,1,0), passant par y=0),
//   - un seul plan mur vertical (normale (0,0,1), passant par z=0),
//   - un trajet DROIT de 300 mm exactement sur l'arête mur∩plafond
//     (segment (0,0,0) -> (0.3,0,0)),
// puis `Camera3D.lookingAt` (camera.dart) est utilisée pour cadrer une vue
// 3/4 rapprochée, calculée à partir de la bounding box RÉELLE du maillage
// produit (pas d'hypothèse a priori sur son orientation) — donc si
// `sweepMoulure` produit un maillage mal orienté/déformé, ce cadrage
// automatique l'affichera fidèlement sans le "corriger" implicitement.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:staff_decor_studio/core/geometry/camera.dart';
import 'package:staff_decor_studio/core/geometry/planes.dart';
import 'package:staff_decor_studio/core/geometry/sweep.dart';
import 'package:staff_decor_studio/core/perspective/mesh_painter.dart';

const String kProfileSku = '1000';
const String kProfileRelPath = 'assets/profiles/1000.json';

/// Duplique volontairement le décodage minimal (même logique que
/// `render_corniche_screenshot_test.dart::loadProfileFromJson`, dupliquée ici
/// pour rester un test isolé, pas de dépendance croisée entre fichiers de
/// test) — dédupe le sommet de fermeture si le premier et le dernier point
/// sont (quasi) confondus (artefact connu de `dxf2profile.py`).
MoulureProfile loadProfileFromJson(
  Map<String, dynamic> json, {
  double dedupToleranceMm = 1e-6,
}) {
  final rawPts = (json['profil_mm'] as List)
      .map((p) => vm.Vector2((p[0] as num).toDouble(), (p[1] as num).toDouble()))
      .toList();

  var pts = rawPts;
  if (rawPts.length > 1 &&
      rawPts.first.distanceTo(rawPts.last) < dedupToleranceMm) {
    pts = rawPts.sublist(0, rawPts.length - 1);
  }

  final wallIdx = (json['face_pose_mur']['indices'] as List)
      .map((i) => i as int)
      .toList();
  final ceilIdx = (json['face_pose_plafond']['indices'] as List)
      .map((i) => i as int)
      .toList();
  return MoulureProfile(
    pointsMm: pts,
    wallIndices: wallIdx,
    ceilingIndices: ceilIdx,
  );
}

/// Bounding box 3D (mètres) des sommets réels du [mesh] — calculée sur la
/// sortie EFFECTIVE de `sweepMoulure`, jamais supposée a priori (voir
/// docstring de tête de fichier : le cadrage caméra doit être honnête vis-à-
/// vis d'un éventuel maillage mal formé).
({vm.Vector3 min, vm.Vector3 max}) meshBoundsM(Mesh mesh) {
  var minV = vm.Vector3(double.infinity, double.infinity, double.infinity);
  var maxV = vm.Vector3(
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );
  for (var i = 0; i < mesh.vertexCount; i++) {
    final p = mesh.positionAt(i);
    minV = vm.Vector3(
      math.min(minV.x, p.x),
      math.min(minV.y, p.y),
      math.min(minV.z, p.z),
    );
    maxV = vm.Vector3(
      math.max(maxV.x, p.x),
      math.max(maxV.y, p.y),
      math.max(maxV.z, p.z),
    );
  }
  return (min: minV, max: maxV);
}

/// Ordre de tri peintre (back-to-front), même méthode que
/// `mesh_painter.dart::paintMeshOnCanvas` — dupliqué ici volontairement (pas
/// de refactor de `mesh_painter.dart` ce tour, règle "diagnostic seulement").
List<int> sortTrianglesBackToFront(Mesh mesh, Camera3D camera) {
  final vertexCount = mesh.vertexCount;
  final depths = List<double>.filled(vertexCount, 0.0);
  for (var i = 0; i < vertexCount; i++) {
    depths[i] = camera.project(mesh.positionAt(i)).depthCam;
  }
  final triangleCount = mesh.triangleCount;
  final order = List<int>.generate(triangleCount, (i) => i);
  double triDepth(int t) {
    final i0 = mesh.indices[t * 3];
    final i1 = mesh.indices[t * 3 + 1];
    final i2 = mesh.indices[t * 3 + 2];
    return (depths[i0] + depths[i1] + depths[i2]) / 3.0;
  }
  order.sort((a, b) => triDepth(b).compareTo(triDepth(a)));
  return order;
}

/// Panneau 1 — fil de fer : toutes les arêtes de triangles, noir sur blanc.
/// N'utilise NI normale NI éclairage : pure géométrie projetée.
void paintWireframe(ui.Canvas canvas, Mesh mesh, Camera3D camera) {
  final paint = ui.Paint()
    ..color = const ui.Color(0xFF000000)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 1.0;
  for (var t = 0; t < mesh.triangleCount; t++) {
    final i0 = mesh.indices[t * 3];
    final i1 = mesh.indices[t * 3 + 1];
    final i2 = mesh.indices[t * 3 + 2];
    final p0 = camera.project(mesh.positionAt(i0)).pixel;
    final p1 = camera.project(mesh.positionAt(i1)).pixel;
    final p2 = camera.project(mesh.positionAt(i2)).pixel;
    final path = ui.Path()
      ..moveTo(p0.x, p0.y)
      ..lineTo(p1.x, p1.y)
      ..lineTo(p2.x, p2.y)
      ..close();
    canvas.drawPath(path, paint);
  }
}

/// Panneau 2 — normales en couleur, SANS ÉCLAIRAGE : `(r,g,b) = (n+1)/2`.
/// Seule différence avec `paintMeshOnCanvas` : la couleur ne dépend QUE de
/// la normale, aucun produit scalaire avec une direction de lumière.
void paintColoredNormalsUnlit(ui.Canvas canvas, Mesh mesh, Camera3D camera) {
  final vertexCount = mesh.vertexCount;
  if (vertexCount == 0) return;

  final screenPos = List<ui.Offset>.filled(vertexCount, ui.Offset.zero);
  for (var i = 0; i < vertexCount; i++) {
    final proj = camera.project(mesh.positionAt(i));
    screenPos[i] = ui.Offset(proj.pixel.x, proj.pixel.y);
  }

  final triOrder = sortTrianglesBackToFront(mesh, camera);

  final positions = <ui.Offset>[];
  final colors = <ui.Color>[];
  for (final t in triOrder) {
    for (var k = 0; k < 3; k++) {
      final vi = mesh.indices[t * 3 + k];
      positions.add(screenPos[vi]);
      final n = mesh.normalAt(vi);
      colors.add(
        ui.Color.from(
          alpha: 1.0,
          red: ((n.x + 1.0) / 2.0).clamp(0.0, 1.0),
          green: ((n.y + 1.0) / 2.0).clamp(0.0, 1.0),
          blue: ((n.z + 1.0) / 2.0).clamp(0.0, 1.0),
        ),
      );
    }
  }

  final vertices = ui.Vertices(ui.VertexMode.triangles, positions, colors: colors);
  canvas.drawVertices(vertices, ui.BlendMode.srcOver, ui.Paint());
}

Future<Uint8List> encodePng(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// Charge une police réelle (Roboto, présente dans le cache pub.dev local)
/// pour que le texte de légende s'affiche correctement dans le PNG — sans
/// ce chargement explicite, `flutter test` (VM headless, pas de polices
/// système) rend tout texte en rectangles noirs pleins (glyphes de secours),
/// illisibles. Purement cosmétique pour CE script de debug, aucun rapport
/// avec `sweep.dart`/`mesh_painter.dart`.
Future<void> loadDebugFont() async {
  const candidatePaths = [
    '/home/sandboxuser/.pub-cache/hosted/pub.dev/flame-1.32.0/extension/devtools/build/assets/packages/devtools_app_shared/fonts/Roboto/Roboto-Regular.ttf',
  ];
  for (final path in candidatePaths) {
    final file = File(path);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      final loader = FontLoader('DebugLegendFont');
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      return;
    }
  }
  // ignore: avoid_print
  print(
    '⚠️ Aucune police trouvée pour la légende — le texte du PNG sera '
    'illisible (rectangles de secours). Purement cosmétique, sans impact '
    'sur le diagnostic géométrie/éclairage.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'debug diagnostic : fil de fer / normales-couleur / ombrage actuel, '
    'sur 300mm de corniche (profil 1000.json), sans photo',
    () async {
      await loadDebugFont();

      final projectRoot = Directory.current.path;
      final jsonPath = '$projectRoot/$kProfileRelPath';

      // ── 1. Chargement du profil réel (voir docstring : PAS un L
      //      synthétique — réponse à la question préalable). ──
      final jsonStr = await File(jsonPath).readAsString();
      final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(profileJson['statut'], 'OK');
      final profile = loadProfileFromJson(profileJson);
      final profileVertexCount = profile.pointsMm.length;

      // ignore: avoid_print
      print('── Profil chargé ──');
      // ignore: avoid_print
      print('  SKU              : $kProfileSku');
      // ignore: avoid_print
      print('  Chemin JSON      : $jsonPath');
      // ignore: avoid_print
      print('  statut           : ${profileJson['statut']}');
      // ignore: avoid_print
      print('  Sommets profil   : $profileVertexCount (après dédup fermeture)');
      // ignore: avoid_print
      print('  bbox_mm (JSON)   : ${profileJson['bbox_mm']}');

      // ── 2. Scène synthétique minimale : plafond horizontal (y=0), un seul
      //      mur vertical (z=0), trajet DROIT de 300mm exactement sur
      //      l'arête mur∩plafond (0,0,0)->(0.3,0,0). AUCUNE photo, AUCUNE
      //      calibration — voir docstring de tête de fichier. ──
      final ceilingPlane = Plane3.fromPointAndNormal(
        vm.Vector3(0, 0, 0),
        vm.Vector3(0, 1, 0),
      );
      final wallPlane = Plane3.fromPointAndNormal(
        vm.Vector3(0, 0, 0),
        vm.Vector3(0, 0, 1),
      );
      final pathMeters = [vm.Vector3(0, 0, 0), vm.Vector3(0.3, 0, 0)];

      // ── 3. sweepMoulure NON MODIFIÉ — on observe sa sortie brute. ──
      final mesh = sweepMoulure(
        profile: profile,
        pathMeters: pathMeters,
        wallPlanes: [wallPlane],
        ceilingPlane: ceilingPlane,
      );

      expect(mesh.vertexCount, greaterThan(0));
      expect(mesh.triangleCount, greaterThan(0));

      final bounds = meshBoundsM(mesh);
      final center = (bounds.min + bounds.max) / 2.0;
      final extent = bounds.max - bounds.min;
      final radius = extent.length / 2.0;

      // ignore: avoid_print
      print('── Maillage produit par sweepMoulure (NON MODIFIÉ) ──');
      // ignore: avoid_print
      print('  Sommets maillage : ${mesh.vertexCount} (dupliqués par facette, flat shading)');
      // ignore: avoid_print
      print('  Triangles        : ${mesh.triangleCount}');
      // ignore: avoid_print
      print('  bbox min (m)     : ${bounds.min}');
      // ignore: avoid_print
      print('  bbox max (m)     : ${bounds.max}');
      // ignore: avoid_print
      print('  centre (m)       : $center');
      // ignore: avoid_print
      print('  rayon (m)        : $radius');

      // ── 4. Caméra 3/4 rapprochée, cadrée sur la bbox RÉELLE du maillage
      //      (pas d'hypothèse a priori sur son orientation, voir docstring
      //      de tête de fichier). Vue 3/4 : décalage sur les 3 axes. ──
      const panelSize = 520.0;
      final principalPoint = vm.Vector2(panelSize / 2, panelSize / 2);
      final viewDir = vm.Vector3(0.55, 0.55, 1.0).normalized();
      final distanceGuess = math.max(radius * 3.0, 0.15);
      final eyeGuess = center + viewDir * distanceGuess;

      // Calibration de la focale en 1 passe (linéaire en focalPx à eye/target
      // fixés) : caméra-test à focalPx=1.0, on mesure l'étendue NDC brute des
      // sommets du maillage, puis on choisit focalPx pour que cette étendue
      // occupe ~92% de la demi-largeur/demi-hauteur du panneau — garantit
      // "le maillage occupe tout le cadre" (spec utilisateur) sans le
      // rogner.
      final probeCamera = Camera3D.lookingAt(
        eye: eyeGuess,
        target: center,
        focalPx: 1.0,
        principalPoint: principalPoint,
      );
      var maxAbsNdcX = 1e-9;
      var maxAbsNdcY = 1e-9;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final proj = probeCamera.project(mesh.positionAt(i));
        final ndcX = (proj.pixel.x - principalPoint.x).abs();
        final ndcY = (proj.pixel.y - principalPoint.y).abs();
        if (ndcX > maxAbsNdcX) maxAbsNdcX = ndcX;
        if (ndcY > maxAbsNdcY) maxAbsNdcY = ndcY;
      }
      const fillFraction = 0.92;
      final focalForX = (panelSize / 2 * fillFraction) / maxAbsNdcX;
      final focalForY = (panelSize / 2 * fillFraction) / maxAbsNdcY;
      final focalPx = math.min(focalForX, focalForY);

      final camera = Camera3D.lookingAt(
        eye: eyeGuess,
        target: center,
        focalPx: focalPx,
        principalPoint: principalPoint,
      );

      final lightDirWorld = vm.Vector3(-0.4, 0.6, 0.7);
      final lightNormalized = lightDirWorld.normalized();

      // ignore: avoid_print
      print('── Caméra debug (Camera3D.lookingAt, vue 3/4, sans photo) ──');
      // ignore: avoid_print
      print('  eye (m)          : ${camera.position}');
      // ignore: avoid_print
      print('  target (m)       : $center');
      // ignore: avoid_print
      print('  focalPx          : $focalPx');
      // ignore: avoid_print
      print('  principalPoint   : $principalPoint');
      // ignore: avoid_print
      print('  lightDirWorld    : $lightDirWorld (normalisée : $lightNormalized)');

      // ── 5. Composition des 3 panneaux + légende. ──
      const gap = 10.0;
      const legendHeight = 190.0;
      const totalWidth = panelSize * 3 + gap * 2;
      const totalHeight = panelSize + legendHeight;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      // Fond blanc plein cadre.
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, totalWidth, totalHeight),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );

      final panelPainters = <void Function(ui.Canvas)>[
        (c) => paintWireframe(c, mesh, camera),
        (c) => paintColoredNormalsUnlit(c, mesh, camera),
        (c) => paintMeshOnCanvas(
              c,
              mesh,
              camera,
              baseColor: const ui.Color(0xFFEDEAE4),
            ),
      ];
      const panelTitles = [
        '1. FIL DE FER (geometrie pure)',
        '2. NORMALES COULEUR (n+1)/2, non eclaire',
        '3. OMBRAGE ACTUEL (lambert, inchange)',
      ];

      for (var p = 0; p < 3; p++) {
        final offsetX = p * (panelSize + gap);
        canvas.save();
        canvas.clipRect(ui.Rect.fromLTWH(offsetX, 0, panelSize, panelSize));
        canvas.translate(offsetX, 0);
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, panelSize, panelSize),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        );
        panelPainters[p](canvas);
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, panelSize, panelSize),
          ui.Paint()
            ..color = const ui.Color(0xFF888888)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        final titleBuilder = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontFamily: 'DebugLegendFont',
            fontSize: 16,
            textAlign: ui.TextAlign.left,
          ),
        )
          ..pushStyle(
            ui.TextStyle(
              color: const ui.Color(0xFF000000),
              fontFamily: 'DebugLegendFont',
            ),
          )
          ..addText(panelTitles[p]);
        final titlePara = titleBuilder.build()
          ..layout(const ui.ParagraphConstraints(width: panelSize - 16));
        canvas.drawParagraph(titlePara, const ui.Offset(8, 8));
        canvas.restore();
      }

      // Légende (bande basse, texte multi-lignes).
      final legendText =
          'SKU : $kProfileSku   |   JSON : $kProfileRelPath\n'
          'Sommets profil (source) : $profileVertexCount   |   '
          'Sommets maillage (dupliques/facette) : ${mesh.vertexCount}   |   '
          'Triangles : ${mesh.triangleCount}\n'
          'Direction lumiere (panneau 3 uniquement) : '
          '(${lightDirWorld.x}, ${lightDirWorld.y}, ${lightDirWorld.z}) '
          'normalisee (${lightNormalized.x.toStringAsFixed(3)}, '
          '${lightNormalized.y.toStringAsFixed(3)}, '
          '${lightNormalized.z.toStringAsFixed(3)})\n'
          'Camera position (eye, m) : '
          '(${camera.position.x.toStringAsFixed(4)}, '
          '${camera.position.y.toStringAsFixed(4)}, '
          '${camera.position.z.toStringAsFixed(4)})   |   '
          'target (m) : (${center.x.toStringAsFixed(4)}, '
          '${center.y.toStringAsFixed(4)}, ${center.z.toStringAsFixed(4)})   |   '
          'focalPx : ${focalPx.toStringAsFixed(1)}\n'
          'Scene synthetique SANS photo : plafond y=0 (normale +Y), '
          'mur z=0 (normale +Z), trajet droit 300mm (0,0,0)->(0.3,0,0).';

      final legendBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          fontFamily: 'DebugLegendFont',
          fontSize: 15,
          textAlign: ui.TextAlign.left,
        ),
      )
        ..pushStyle(
          ui.TextStyle(
            color: const ui.Color(0xFF000000),
            fontFamily: 'DebugLegendFont',
          ),
        )
        ..addText(legendText);
      final legendPara = legendBuilder.build()
        ..layout(const ui.ParagraphConstraints(width: totalWidth - 24));
      canvas.drawParagraph(legendPara, ui.Offset(12, panelSize + 12));

      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(
        totalWidth.round(),
        totalHeight.round(),
      );
      final pngBytes = await encodePng(finalImage);

      const outPath =
          '/tmp/solid2profile_be_test/debug_wireframe_normals_1000.png';
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(pngBytes);

      expect(await outFile.exists(), isTrue);
      expect(pngBytes.length, greaterThan(5000));

      // ignore: avoid_print
      print('── PNG de diagnostic écrit ──');
      // ignore: avoid_print
      print('  Chemin  : $outPath');
      // ignore: avoid_print
      print('  Taille  : ${pngBytes.length} octets');
      // ignore: avoid_print
      print('  Dimensions : ${totalWidth.round()}x${totalHeight.round()} px');
    },
  );
}
