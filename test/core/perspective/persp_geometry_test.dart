library;

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/persp_geometry.dart';
import 'package:staff_decor_studio/core/perspective/strip_px_from_dims.dart';
import 'package:staff_decor_studio/core/perspective/cornice_plinth_painter.dart';

/// Premier fichier de test pour `persp_geometry.dart` — aucun n'existait
/// avant ce commit (confirmé par `find`/`grep`, aucun fichier ni aucune
/// mention de `perpDown`/`perpUp` dans `test/core/perspective/`).
///
/// ## Ce que ce fichier NE fait PAS double emploi avec
///
/// `b07da00` ("verrouille corniceDefault reel + cas D705 (axe y inverse)")
/// touche UNIQUEMENT `strip_px_from_dims_test.dart` et verrouille une
/// propriété du CONTOUR DXF BRUT (`profil_mm` a son `max(y)==0` côté
/// plafond au lieu de `min(y)==0` pour D705) — anomalie déjà absorbée
/// SANS AUCUNE normalisation par le loader (`profile_dims.dart`, voir sa
/// docstring "insensible au signe de l'axe"), déjà testée et verte dans
/// `profile_dims_test.dart`. Ce commit ne touche ni `perpDown`, ni
/// `perpUp`, ni rien qui dépende de la convention Y-down du CANVAS.
///
/// Le présent fichier teste une convention DIFFÉRENTE et jusqu'ici non
/// couverte : celle du CANVAS Flutter (Y croît vers le bas), au niveau où
/// `perpDown`/`perpUp` calculent le décalage perpendiculaire utilisé par
/// `paintCorniceSet`/`paintPlintheSet` (`cornice_plinth_painter.dart`)
/// pour positionner le bord bas de la bande de corniche par rapport à
/// l'arête plafond. Confirmé structurellement non couvert par mutation
/// testing (inversion complète du signe dans `perpDown`, suite complète
/// de 99 tests relancée : `All tests passed!` — aucun test existant ne
/// détecte cette mutation).
///
/// ## Pourquoi pas un test unitaire sur `perpDown` avec formule recopiée
///
/// Un test qui recalculerait `Offset(-dy/l*fH, dx/l*fH)` dans l'attendu
/// serait quasi tautologique : il passerait pour la seule raison qu'on a
/// recopié la définition. Les assertions ci-dessous portent au contraire
/// sur une propriété OBSERVABLE et DOCUMENTÉE du domaine — "la bande de
/// corniche part de l'arête plafond et descend vers l'intérieur de la
/// pièce, jamais au-dessus" (docstring de `perpDown` : "orienté vers le
/// bas du mur ... descend depuis la ligne plafond") — exprimée comme une
/// inégalité sur la position des sommets produits (bas de bande VS arête
/// haute), pas comme une égalité à une formule.
///
/// ## Rôle de l'asymétrie D704/D621
///
/// Aucun profil du dépôt (`assets/profiles/D705.json`, `D718.json`,
/// `D720.json`) n'a de section franchement asymétrique (les trois sont
/// des déclinaisons homothétiques du même modèle carré, cf.
/// `docs/ETAT_MOTEUR_RENDU.md`) — sur une section carrée, un mélange
/// entre `faceMurFond` (dérivé de `retombeeMm`, consommé par `perpDown`
/// pour le décalage vertical) et `faceHorizFond` (dérivé de
/// `projectionMm`, consommé ailleurs pour la convergence de la face
/// plafond) serait indétectable par coïncidence numérique.
///
/// D704 (corniche classique, 7,3 × 4,9 cm, fiche vérifiée le 2026-08-13,
/// https://staffdecor.fr/corniches/corniches-classiques/d704/) et D621
/// (corniche contemporaine, 10,2 × 12,2 cm, fiche vérifiée le
/// 2026-08-13, https://staffdecor.fr/corniches/corniches-contemporaines/d621/)
/// ont chacune une section franchement asymétrique, dans des sens
/// OPPOSÉS l'une de l'autre. Ni `D704.json` ni `D621.json` n'existent
/// dans `assets/profiles/` (vérifié par `ls` avant d'écrire ce fichier) :
/// `loadProfileDims('D704')` renverrait `null`, la voie loader est donc
/// inutilisable ici. Le site affiche les deux nombres sans jamais dire
/// lequel est la retombée et lequel est la projection — déduire cette
/// assignation de l'ordre d'affichage introduirait exactement
/// l'hypothèse que ce test est censé vérifier. Les `ProfileDims`
/// ci-dessous sont donc construits À LA MAIN, EXPLICITEMENT SYNTHÉTIQUES :
/// seul l'ORDRE DE GRANDEUR (dizaines de mm) et le RATIO retombée/
/// projection (>1 pour l'une, <1 pour l'autre, motivés par l'asymétrie
/// réelle et vérifiée des deux fiches) sont repris — l'assignation
/// retombée=X / projection=Y est un choix arbitraire de ce test, pas une
/// donnée du fabricant. Un bug qui mélangerait `faceMurFond`/
/// `faceHorizFond` survivrait à la fixture A (retombée > projection) OU
/// à la fixture B (retombée < projection) selon le sens du mélange, mais
/// pas aux deux à la fois — c'est le couple qui discrimine, pas chaque
/// fixture isolément.
void main() {
  const tol = 0.001;
  const pH = 500.0;
  const metresHauteur = 2.5;

  // Segment du mur du fond représentatif : quasi horizontal (fTL.dy ==
  // fTR.dy), comme dans l'appel réel `perpDown(fTL, fTR, th.faceMurFond)`
  // de `paintCorniceSet` — la ligne plafond du mur photographié de face.
  const fTL = Offset(100.0, 200.0);
  const fTR = Offset(700.0, 200.0);

  /// Calcule `th.faceMurFond` en passant PAR LE PIPELINE RÉEL
  /// (`stripPxFromDims` → `corniceFor`), jamais par un littéral pixel
  /// recopié à la main.
  double faceMurFondPourFixtureSynthetique({
    required double retombeeMmSynthetique,
    required double projectionMmSynthetique,
  }) {
    final r = stripPxFromDims(
      pH: pH,
      metresHauteur: metresHauteur,
      retombeeMm: retombeeMmSynthetique,
      projectionMm: projectionMmSynthetique,
    );
    expect(r, isNotNull);
    final th = corniceFor(r, pH);
    return th.faceMurFond;
  }

  group('perpDown — convention canvas Y-down, segment du mur du fond', () {
    test(
      'Fixture A (synthétique, ordre de grandeur D704 — corniche '
      'classique, 7,3 × 4,9 cm, fiche vérifiée le 2026-08-13 — '
      'retombée > projection, assignation choisie par ce test, PAS '
      'déduite du site, D704.json absent de assets/profiles/) : le bas '
      'de la bande produit par perpDown() se trouve strictement SOUS '
      'l\'arête plafond (dy croissant = descend, convention canvas '
      'Flutter Y vers le bas), et l\'amplitude de la descente vaut '
      'th.faceMurFond — jamais th.faceHorizFond.',
      () {
        final faceMurFond = faceMurFondPourFixtureSynthetique(
          retombeeMmSynthetique: 73.0,
          projectionMmSynthetique: 49.0,
        );

        final offset = perpDown(fTL, fTR, faceMurFond);
        final botL = fTL + offset;
        final botR = fTR + offset;

        // Position observable des sommets produits par rapport à
        // l'arête plafond — PAS une comparaison à une formule.
        expect(
          botL.dy,
          greaterThan(fTL.dy),
          reason:
              'Le sommet bas doit être STRICTEMENT sous l\'arête plafond '
              '(dy canvas croît vers le bas) : la corniche descend vers '
              'l\'intérieur de la pièce, jamais au-dessus de l\'arête.',
        );
        expect(botR.dy, greaterThan(fTR.dy));

        // Amplitude de la descente = th.faceMurFond (retombée), jamais
        // th.faceHorizFond (projection) — discriminé par la fixture B
        // ci-dessous, de ratio opposé.
        expect(offset.dy, closeTo(faceMurFond, tol));
      },
    );

    test(
      'Fixture B (synthétique, ordre de grandeur D621 — corniche '
      'contemporaine, 10,2 × 12,2 cm, fiche vérifiée le 2026-08-13 — '
      'retombée < projection, RATIO OPPOSÉ à la fixture A, assignation '
      'choisie par ce test, D621.json absent de assets/profiles/) : '
      'même invariant que la fixture A malgré le ratio inversé — si un '
      'bug mélangeait faceMurFond/faceHorizFond, l\'une des deux '
      'fixtures le révélerait forcément (l\'autre pourrait rester '
      'verte par coïncidence numérique selon le sens du mélange).',
      () {
        final faceMurFond = faceMurFondPourFixtureSynthetique(
          retombeeMmSynthetique: 102.0,
          projectionMmSynthetique: 122.0,
        );

        final offset = perpDown(fTL, fTR, faceMurFond);
        final botL = fTL + offset;
        final botR = fTR + offset;

        expect(
          botL.dy,
          greaterThan(fTL.dy),
          reason:
              'Le sommet bas doit être STRICTEMENT sous l\'arête plafond, '
              'même avec un profil dont la projection dépasse la '
              'retombée (ratio opposé à la fixture A) — la convention '
              'canvas ne doit pas dépendre du ratio du profil.',
        );
        expect(botR.dy, greaterThan(fTR.dy));
        expect(offset.dy, closeTo(faceMurFond, tol));
      },
    );

    test(
      'RÉGRESSION DE MUTATION (documentaire) : cette assertion est '
      'formulée pour rougir immédiatement si perpDown() inversait son '
      'signe (mutation testée manuellement le 2026-08-13 : '
      'Offset(-dy/l*fH, dx/l*fH) -> Offset(dy/l*fH, -dx/l*fH), suite '
      'complète alors verte à 99/99 SANS ce fichier — la preuve que '
      'cette zone était non couverte). Segment purement horizontal '
      '(dy=0) : perpDown doit renvoyer un décalage purement vertical '
      '(dx≈0) et positif (dy>0) ; la mutation renverrait dy<0 ici.',
      () {
        final offset = perpDown(fTL, fTR, 27.5);
        expect(offset.dx, closeTo(0.0, tol));
        expect(offset.dy, greaterThan(0.0));
      },
    );
  });

  // ---------------------------------------------------------------------
  // perpUp (plinthe) — ajouté en commit additif après 5f4de67, suite à
  // une réserve explicite : 5f4de67 ne couvre que perpDown/corniche.
  // perpUp n'est PAS du code mort — grep -n "perpUp" lib/ confirme trois
  // appels réels dans cornice_plinth_painter.dart::paintPlintheSet
  // (upFond, upLatG, upLatD), donc le tester a un objet.
  //
  // Mutation testing appliquée le 2026-08-13, séparément de celle de
  // perpDown : suppression de la négation dans perpUp (devient un
  // doublon de perpDown au lieu de son opposé), suite complète relancée
  // (102 tests, avec 5f4de67 déjà en place) -> `All tests passed!`.
  // Confirme que 5f4de67 ne couvre PAS indirectement le chemin plinthe :
  // ce commit additif a un objet réel, ce n'est pas un doublon inutile.
  // Fichier de production ensuite restauré depuis backup, `git diff
  // --stat` réverifié vide avant d'écrire ce group.
  // ---------------------------------------------------------------------
  group('perpUp — convention canvas Y-up, segment du sol du fond', () {
    // Arête sol représentative : quasi horizontale (fBL.dy == fBR.dy),
    // comme dans l'appel réel `perpUp(fBL, fBR, th.faceMurFond)` de
    // `paintPlintheSet`. Y plus grand qu'un exemple de ligne plafond
    // typique, cohérent avec une scène où le sol est sous le plafond.
    const fBL = Offset(100.0, 600.0);
    const fBR = Offset(700.0, 600.0);

    test(
      'Fixture A (synthétique, ordre de grandeur D704 — mêmes valeurs '
      'que le group perpDown ci-dessus, retombée > projection) : le '
      'haut de la bande produit par perpUp() se trouve strictement '
      'AU-DESSUS de l\'arête sol (dy décroissant = monte, convention '
      'canvas Flutter Y vers le bas), et l\'amplitude de la montée vaut '
      'th.faceMurFond — jamais th.faceHorizFond. Passe par le pipeline '
      'réel stripPxFromDims -> corniceFor, comme le group perpDown, '
      'pour ne pas mélanger les styles de fixture dans ce fichier.',
      () {
        final faceMurFond = faceMurFondPourFixtureSynthetique(
          retombeeMmSynthetique: 73.0,
          projectionMmSynthetique: 49.0,
        );

        final offset = perpUp(fBL, fBR, faceMurFond);
        final topL = fBL + offset;
        final topR = fBR + offset;

        expect(
          topL.dy,
          lessThan(fBL.dy),
          reason:
              'Le sommet haut doit être STRICTEMENT au-dessus de l\'arête '
              'sol (dy canvas croît vers le bas, donc "monter" = dy plus '
              'petit) : la plinthe monte vers l\'intérieur de la pièce, '
              'jamais en dessous du niveau du sol.',
        );
        expect(topR.dy, lessThan(fBR.dy));
        expect(offset.dy, closeTo(-faceMurFond, tol));
      },
    );

    test(
      'Fixture B (synthétique, ordre de grandeur D621 — mêmes valeurs '
      'que le group perpDown ci-dessus, retombée < projection, RATIO '
      'OPPOSÉ à la fixture A) : même invariant que la fixture A malgré '
      'le ratio inversé — même rôle discriminant que pour perpDown.',
      () {
        final faceMurFond = faceMurFondPourFixtureSynthetique(
          retombeeMmSynthetique: 102.0,
          projectionMmSynthetique: 122.0,
        );

        final offset = perpUp(fBL, fBR, faceMurFond);
        final topL = fBL + offset;
        final topR = fBR + offset;

        expect(
          topL.dy,
          lessThan(fBL.dy),
          reason:
              'Le sommet haut doit être STRICTEMENT au-dessus de l\'arête '
              'sol, même avec un profil dont la projection dépasse la '
              'retombée (ratio opposé à la fixture A).',
        );
        expect(topR.dy, lessThan(fBR.dy));
        expect(offset.dy, closeTo(-faceMurFond, tol));
      },
    );

    test(
      'RÉGRESSION DE MUTATION (documentaire) : cette assertion est '
      'formulée pour rougir immédiatement si perpUp() perdait sa '
      'négation par rapport à perpDown() (mutation testée manuellement '
      'le 2026-08-13 : Offset(-p.dx, -p.dy) -> Offset(p.dx, p.dy), '
      'suite complète alors verte à 102/102 SANS ce group — la preuve '
      'que ce chemin était non couvert malgré 5f4de67). Segment '
      'purement horizontal (dy=0) : perpUp doit renvoyer un décalage '
      'purement vertical (dx≈0) et négatif (dy<0) ; la mutation '
      'renverrait dy>0 ici (identique à perpDown au lieu de son '
      'opposé).',
      () {
        final offset = perpUp(fBL, fBR, 27.5);
        expect(offset.dx, closeTo(0.0, tol));
        expect(offset.dy, lessThan(0.0));
      },
    );
  });
}
