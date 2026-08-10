/// Rendu d'un [Mesh] 3D (sortie de `geometry/sweep.dart`) projeté par une
/// [Camera3D] (`geometry/camera.dart`) sur un `Canvas` Flutter — le
/// consommateur `rendering/` manquant identifié lors du recadrage
/// utilisateur : jusqu'ici, rien dans `lib/core/perspective/` ne dépendait
/// de `sweep.dart` (contrainte explicite de la docstring de tête de
/// `sweep.dart`, levée maintenant que ce fichier existe).
///
/// ⚠️ Ce fichier dépend de `dart:ui` (Canvas, Vertices) — contrairement à
/// `geometry/sweep.dart`/`geometry/camera.dart` qui restent Dart pur. C'est
/// la couche de rendu, pas la géométrie : elle consomme les types
/// `geometry/` sans jamais recalculer une projection ou une convention
/// différente de celle déjà fixée par `Camera3D.project` (aucune
/// projection "maison" ici).
///
/// ## Méthode de rendu
///
/// 1. **Projection** : chaque sommet du [Mesh] (déjà en coordonnées monde
///    mètres, voir `CONVENTIONS.md`) est projeté en pixels via
///    [Camera3D.project] — jamais une autre formule de projection.
/// 2. **Tri peintre (back-to-front)** : `Canvas.drawVertices` n'a pas de
///    z-buffer ; les triangles sont triés par profondeur caméra moyenne
///    décroissante (le plus loin dessiné en premier) avant l'appel unique
///    à `drawVertices`. Suffisant pour une moulure balayée (surface
///    globalement convexe/quasi plane le long du trajet, jamais de
///    repli sur elle-même à cette échelle).
/// 3. **Éclairage** : un seul directionnel fixe (approximation simple,
///    pas de PBR) — luminosité par sommet = `ambient + (1-ambient) *
///    (dot(normal, lightDir) + 1) / 2`, appliquée en multipliant
///    [baseColor]. Les normales par facette (flat shading, déjà produites
///    par [Mesh], règle dure #6 de `sweep.dart`) donnent donc des facettes
///    visuellement distinctes (arêtes vives), fidèle à l'aspect réel d'une
///    moulure en plâtre.
///    [ambient] par défaut = 0.45 — reproduit EXACTEMENT l'ancienne
///    constante figée `0.45 + 0.55 * ...` (aucun changement de rendu pour
///    les appelants existants qui ne précisent pas [ambient]). Un appelant
///    qui veut un contraste plus marqué (ex. lumière directionnelle nette
///    venant d'une fenêtre plutôt qu'un éclairage de pièce diffus) passe
///    une valeur plus basse, ex. `ambient: 0.20`.
library;

import 'dart:ui' as ui;

import 'package:vector_math/vector_math_64.dart' as vm;

import '../geometry/camera.dart';
import '../geometry/sweep.dart';

/// Dessine [mesh] sur [canvas], projeté par [camera] — voir la docstring de
/// tête de fichier pour la méthode complète (projection, tri peintre,
/// éclairage directionnel simple).
///
/// [lightDirWorld] : direction **vers** la source de lumière (pas la
/// direction de propagation du rayon), repère monde — défaut choisi pour
/// une lumière venant d'en haut et légèrement de face, cohérent avec un
/// éclairage de pièce standard (plafonnier + lumière du jour latérale).
///
/// [ambient] : terme ambiant (0..1) du modèle d'éclairage — voir point 3
/// de la docstring de tête de fichier. Défaut 0.45 (comportement historique
/// inchangé pour tout appelant qui ne précise pas ce paramètre).
void paintMeshOnCanvas(
  ui.Canvas canvas,
  Mesh mesh,
  Camera3D camera, {
  ui.Color baseColor = const ui.Color(0xFFEDEAE4),
  vm.Vector3? lightDirWorld,
  double ambient = 0.45,
}) {
  final light = (lightDirWorld ?? vm.Vector3(-0.4, 0.6, 0.7)).normalized();
  final vertexCount = mesh.vertexCount;
  if (vertexCount == 0) return;

  final screenPos = List<ui.Offset>.filled(vertexCount, ui.Offset.zero);
  final depths = List<double>.filled(vertexCount, 0.0);
  for (var i = 0; i < vertexCount; i++) {
    final proj = camera.project(mesh.positionAt(i));
    screenPos[i] = ui.Offset(proj.pixel.x, proj.pixel.y);
    depths[i] = proj.depthCam;
  }

  final triangleCount = mesh.triangleCount;
  final triOrder = List<int>.generate(triangleCount, (i) => i);
  double triDepth(int t) {
    final i0 = mesh.indices[t * 3];
    final i1 = mesh.indices[t * 3 + 1];
    final i2 = mesh.indices[t * 3 + 2];
    return (depths[i0] + depths[i1] + depths[i2]) / 3.0;
  }

  // Back-to-front (le plus loin en premier) — voir point 2 de la
  // docstring de tête de fichier.
  triOrder.sort((a, b) => triDepth(b).compareTo(triDepth(a)));

  final positions = <ui.Offset>[];
  final colors = <ui.Color>[];
  for (final t in triOrder) {
    for (var k = 0; k < 3; k++) {
      final vi = mesh.indices[t * 3 + k];
      positions.add(screenPos[vi]);
      final n = mesh.normalAt(vi);
      final ndotl = n.dot(light).clamp(-1.0, 1.0);
      final brightness = (ambient + (1.0 - ambient) * ((ndotl + 1.0) / 2.0))
          .clamp(0.0, 1.0);
      colors.add(
        ui.Color.from(
          alpha: 1.0,
          red: (baseColor.r * brightness).clamp(0.0, 1.0),
          green: (baseColor.g * brightness).clamp(0.0, 1.0),
          blue: (baseColor.b * brightness).clamp(0.0, 1.0),
        ),
      );
    }
  }

  final vertices = ui.Vertices(
    ui.VertexMode.triangles,
    positions,
    colors: colors,
  );
  canvas.drawVertices(vertices, ui.BlendMode.srcOver, ui.Paint());
}
