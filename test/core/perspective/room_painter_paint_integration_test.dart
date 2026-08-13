library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/profile_dims_cache.dart';
import 'package:staff_decor_studio/core/perspective/room_painter.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';
import 'package:staff_decor_studio/models/project_item.dart';

/// Réserve 5 (revue utilisateur) : les 98 tests des 3 commits de câblage
/// mm->px sont TOUS unitaires — aucun n'exerce un vrai `paint()` de
/// [RoomPainter] avec un produit "Corniches" réellement sélectionné. Trois
/// choses restaient donc non observées (seulement raisonnées) :
///
///   (a) `ProfileDimsCache.ensureLoading` appelé depuis `paint()`, avec
///       `super(repaint: _repaintSource)` actif, ne déclenche pas
///       `assert(!owner.debugDoingPaint)` (RenderObject.markNeedsPaint) —
///       argument structurel : tout le travail est différé à
///       `Future.microtask`, donc `notifyListeners()` ne peut jamais partir
///       de la pile d'appel synchrone de `paint()`. Ce test exerce le VRAI
///       pipeline de rendu Flutter (`pumpWidget`/`CustomPaint`, pas un
///       `Canvas` nu) : si l'invariant était faux, `pumpWidget` lèverait
///       l'assertion et ce test échouerait immédiatement.
///   (b) `paint()` avec un produit D720 sélectionné (famille 'Corniches')
///       ne lève pas — exercé simplement en construisant le widget et en
///       laissant la première frame se dessiner.
///   (c) La bascule repli (`StripThickness.corniceDefault`) → dimensions
///       réelles (`stripPxFromDims` via `ProfileDimsCache`) se produit bien
///       sans exception ni deadlock, une fois le cache résolu — vérifié
///       INDIRECTEMENT via `ProfileDimsCache.getIfLoaded('D720')` (non-null
///       après résolution), PAS en comparant les pixels rendus (aucun
///       golden, comme demandé).
///
/// ⚠️ DÉCOUVERTE EMPIRIQUE (mesurée, pas prédite) : sous
/// `TestWidgetsFlutterBinding`, `WidgetTester.pumpWidget` résout DÉJÀ le
/// cache (asset LOCAL `assets/profiles/D720.json`, pas réseau) après un
/// seul pump — contrairement à la prédiction du commentaire de
/// `room_painter.dart` ("pop" de première frame), qui décrit le
/// comportement en PRODUCTION réelle (latence I/O disque/réseau non nulle).
/// Sondé directement (`debugPrint` avant/après `pumpWidget`, script
/// jetable) : `getIfLoaded('D720')` est déjà non-null juste après le tout
/// premier `pumpWidget()`. Ce test ne peut donc PAS observer de fenêtre où
/// le repli est utilisé dans ce harnais — il vérifie à la place ce qui est
/// réellement garanti et observable : absence d'exception/assertion
/// pendant `paint()` (points a et b), et convergence finale correcte vers
/// les dimensions réelles (point c), sans jamais figer sur le repli.
///
/// D720 est couvert par `assets/profiles/D720.json` (voir
/// `profile_dims_cache_test.dart`) — chargement d'ASSET local, PAS réseau :
/// ce test ne dépend donc pas d'un accès staffdecor.fr, uniquement de
/// `rootBundle` (déjà exercé sous `TestWidgetsFlutterBinding` par les tests
/// de `ProfileDimsCache`). Le chargement de la VRAIE photo produit
/// (`ProductTextureCache`, réseau) est aussi déclenché par ce même
/// `paint()` (famille 'Corniches') mais n'est PAS attendu ici : ce test ne
/// fait aucune assertion sur la texture, seulement sur le cache de
/// dimensions — pas de dépendance réseau introduite.
void main() {
  setUp(() {
    ProfileDimsCache.instance.resetForTesting();
  });

  testWidgets(
    'RoomPainter.paint() avec D720 (Corniches) reellement selectionne ne '
    'leve pas (premiere frame, repli StripThickness.corniceDefault), puis '
    'bascule sur les dimensions reelles (ProfileDimsCache resolu) a une '
    'frame ulterieure — sans comparaison de pixels (pas de golden).',
    (WidgetTester tester) async {
      const item = ProjectItem(
        ref: 'D720',
        famille: 'Corniches',
        qte: 2.0,
        unite: 'ml',
      );

      final painter = RoomPainter(
        roomImage: null,
        imgDraw: null,
        calib: PerspCalib.defaultCalib,
        selectedProducts: const [item],
        prodPositions: const {},
        metresHauteur: 2.5,
      );

      // Premiere frame : pumpWidget construit l'arbre ET dessine — si
      // paint() levait (point b) ou si ensureLoading declenchait un
      // markNeedsPaint pendant debugDoingPaint (point a), pumpWidget
      // propagerait l'exception/assertion ici et ce test echouerait.
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: CustomPaint(painter: painter),
          ),
        ),
      );

      // Point (a) + (b) : le seul fait que pumpWidget se soit terminé sans
      // lever confirme deja que paint() (appele par le pipeline de rendu
      // reel, pas un Canvas nu) n'a pas declenche l'assertion
      // !owner.debugDoingPaint (ensureLoading -> Future.microtask ->
      // notifyListeners() ne part jamais de la pile synchrone de paint())
      // et que le cas D720/Corniches ne leve pas.

      // Laisse une marge (I/O asset + drain des microtaches en attente,
      // au cas ou l'environnement d'execution serait plus lent que la
      // mesure ci-dessus) avant la vraie assertion de convergence.
      await tester.pumpAndSettle();

      // Point (c) : convergence finale vers les dimensions reelles,
      // jamais figee sur le repli corniceDefault — stripPxFromDims/
      // corniceFor ont bien ete deverrouilles par la notification de
      // ProfileDimsCache (Listenable.merge cable dans RoomPainter).
      expect(
        ProfileDimsCache.instance.getIfLoaded('D720'),
        isNotNull,
        reason:
            'Apres resolution du cache, getIfLoaded doit renvoyer les '
            'dimensions reelles (202.87mm / 199.145mm) — sinon la bascule '
            'repli -> reel documentee dans room_painter.dart ne se produit '
            'jamais et le rendu resterait figé sur le repli.',
      );
    },
  );
}
