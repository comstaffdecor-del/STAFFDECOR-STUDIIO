// Test rouge d'abord (même discipline que Bug 1, ProfileDims, et le
// premier jet de ce fichier sous son ancien nom) — ce fichier doit
// échouer tant que `stripPxFromDims` n'existe pas encore sous cette
// signature (4 champs, retour nullable, sans repli en dur).
//
// Renommage : strippxFromDims -> stripPxFromDims (camelCase).
//
// Changement de contrat, décidé pour éliminer une source de vérité
// dupliquée (0.055/0.140 existaient à la fois ici et dans
// StripThickness.corniceDefault) : la fonction ne porte plus AUCUN
// repli. Elle renvoie `null` quand elle ne peut pas calculer
// (metresHauteur <= 0, ou dims absentes) ; c'est à l'appelant, qui
// détient déjà StripThickness, d'appliquer StripThickness.corniceDefault
// comme défaut.
//
// Extension latérale : faceMurLat/faceHorizLat sont désormais produits
// par ce fichier, en appliquant à faceMurFondPx/faceHorizFondPx le même
// ratio que StripThickness.corniceDefault (0.080/0.055, 0.200/0.140).
// Ce ratio n'a pas d'origine retrouvée dans l'historique du dépôt (voir
// docs/ETAT_MOTEUR_RENDU.md) ; il est traité comme un facteur fixe pour
// une raison indépendante de sa valeur numérique : si fond et lat sont
// multipliés par le même facteur d'échelle mm->px, leur rapport reste
// EXACTEMENT ce qu'il est aujourd'hui, donc le comportement à l'angle
// (continuité/discontinuité entre segment de fond et segment latéral)
// est rigoureusement inchangé par ce commit. Ce facteur ne dépend pas
// du produit mais de la scène : il représente l'agrandissement apparent
// moyen des parois latérales, qui fuient vers le point de fuite. Passer
// en métrique ne rend donc pas la face latérale correcte au sens
// géométrique — cela rescale la même approximation avec des cotes
// réelles côté fond. Les faces latérales ne sont pas cotées par ce
// commit.
//
// Plinthe : hors périmètre. Les 8 profils JSON disponibles sont tous
// des corniches, pilastres, socle, cimaise ou demi-colonne — aucun
// n'est une plinthe (vérifié via
// tools/dxf_pipeline/recoupement_catalogue_vs_profil.csv et
// tools/dxf_pipeline/catalogue.csv, cf. commentaire de
// strip_px_from_dims.dart). StripThickness.plintheDefault(pH) continue
// de s'appliquer tel quel jusqu'à ce qu'un profil de cette famille
// existe ; le même chemin métrique la couvrira alors sans traitement
// particulier, SAUF si le ratio lat/fond propre à la plinthe (1.4615
// mur, 1.4348 horiz, contre 1.4545/1.4286 pour la corniche) doit être
// respecté au lieu du ratio corniche — question qui ne se pose que le
// jour où la donnée existe, donc non traitée ici.
//
// Fonction PURE, SYNCHRONE, SANS AUCUNE ENTRÉE-SORTIE : prend des
// dimensions déjà résolues en entrée (mécanisme d'acheminement
// asynchrone->synchrone, sur le modèle de ProductTextureCache, hors
// périmètre de ce commit).
//
// Facteur de conversion : pxParMm = pH / (metresHauteur * 1000).
// Valeurs choisies à la main, vérifiées par calcul indépendant avant
// écriture de ce test (voir calcul détaillé dans le message de commit) :
//   pH = 500 px, metresHauteur = 2.5 m -> facteur = 0.2 px/mm
//   D720 : retombeeMm = 202.87, projectionMm = 199.145
//     -> faceMurFondPx = 40.574, faceHorizFondPx = 39.829
//     -> faceMurLatPx = 40.574 * (0.080/0.055) = 59.016727...
//     -> faceHorizLatPx = 39.829 * (0.200/0.140) = 56.898571...
//   D718 : retombeeMm = 153.547, projectionMm = 153.405
//     -> faceMurFondPx = 30.7094, faceHorizFondPx = 30.681
//     -> faceMurLatPx = 30.7094 * (0.080/0.055) = 44.668218...
//     -> faceHorizLatPx = 30.681 * (0.200/0.140) = 43.830
//   D705 (seul profil avec axe y inverse cote plafond, cf. lecture
//   directe de assets/profiles/D705.json) : retombeeMm = 102.661,
//   projectionMm = 101.4526
//     -> faceMurFondPx = 20.5322, faceHorizFondPx = 20.29052
//     -> faceMurLatPx = 20.5322 * (0.080/0.055) = 29.865018...
//     -> faceHorizLatPx = 20.29052 * (0.200/0.140) = 28.986457...
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/strip_px_from_dims.dart';
// Import du peintre uniquement dans le TEST, pour lire les champs réels
// de StripThickness.corniceDefault — jamais dans strip_px_from_dims.dart
// lui-même (qui reste pur, sans dart:ui). Le sens de la dépendance est
// peintre -> conversion pure, jamais l'inverse ; ce test la vérifie sans
// l'inverser : il consulte le peintre, il ne l'alimente pas.
import 'package:staff_decor_studio/core/perspective/cornice_plinth_painter.dart';

void main() {
  const tol = 0.001;

  test('D720, pH=500, metresHauteur=2.5 -> conversion métrique réelle, '
      'fond ET latéral', () {
    final r = stripPxFromDims(
      pH: 500.0,
      metresHauteur: 2.5,
      retombeeMm: 202.87,
      projectionMm: 199.145,
    );
    expect(r, isNotNull);
    expect(r!.faceMurFondPx, closeTo(40.574, tol));
    expect(r.faceHorizFondPx, closeTo(39.829, tol));
    expect(r.faceMurLatPx, closeTo(59.016727, tol));
    expect(r.faceHorizLatPx, closeTo(56.898571, tol));
  });

  test('D718, pH=500, metresHauteur=2.5 -> conversion métrique réelle, '
      'fond ET latéral', () {
    final r = stripPxFromDims(
      pH: 500.0,
      metresHauteur: 2.5,
      retombeeMm: 153.547,
      projectionMm: 153.405,
    );
    expect(r, isNotNull);
    expect(r!.faceMurFondPx, closeTo(30.7094, tol));
    expect(r.faceHorizFondPx, closeTo(30.681, tol));
    expect(r.faceMurLatPx, closeTo(44.668218, tol));
    expect(r.faceHorizLatPx, closeTo(43.830, tol));
  });

  test(
    'D705, pH=500, metresHauteur=2.5 -> conversion métrique réelle. '
    'CE TEST NE VÉRIFIE PAS LE SIGNE : stripPxFromDims reçoit ici deux '
    'double en millimetres déjà calculés (littéraux), le loader n\'est '
    'jamais appelé, aucune information de signe ne traverse cette '
    'fonction. La couverture de l\'axe y inversé de D705 vit dans '
    'profile_dims_test.dart, où D705.json est réellement lu depuis '
    'l\'asset. Ce que ce cas apporte ICI : un TROISIÈME jeu de valeurs '
    'indépendant (D720, D718, D705) pour verrouiller l\'arithmétique '
    'de conversion elle-même. Valeurs épinglées en littéraux, calculées '
    'à la main par lecture directe de '
    'profil_mm/face_pose_mur/face_pose_plafond dans '
    'assets/profiles/D705.json puis vérifiées par calcul indépendant '
    '(retombeeMm=102.661, projectionMm=101.4526, cohérent avec '
    'bbox_mm={w:101.453,h:102.661}) — PAS recalculées ici à partir de '
    '0.080/0.055, pour ne pas rendre ce test tautologique.',
    () {
      final r = stripPxFromDims(
        pH: 500.0,
        metresHauteur: 2.5,
        retombeeMm: 102.661,
        projectionMm: 101.4526,
      );
      expect(r, isNotNull);
      expect(r!.faceMurFondPx, closeTo(20.5322, tol));
      expect(r.faceHorizFondPx, closeTo(20.29052, tol));
      expect(r.faceMurLatPx, closeTo(29.865018, tol));
      expect(r.faceHorizLatPx, closeTo(28.986457, tol));
    },
  );

  test(
    'ratio lat/fond préservé : identique à StripThickness.corniceDefault '
    '(0.080/0.055 mur, 0.200/0.140 horiz) — le passage en métrique ne '
    'change pas le comportement à l\'angle',
    () {
      final r = stripPxFromDims(
        pH: 500.0,
        metresHauteur: 2.5,
        retombeeMm: 202.87,
        projectionMm: 199.145,
      );
      expect(r, isNotNull);
      expect(
        r!.faceMurLatPx / r.faceMurFondPx,
        closeTo(0.080 / 0.055, 1e-9),
      );
      expect(
        r.faceHorizLatPx / r.faceHorizFondPx,
        closeTo(0.200 / 0.140, 1e-9),
      );
    },
  );

  test(
    'CAS CRITIQUE — dims absentes (null) -> null, PAS de repli en dur. '
    'C\'est le cas qui compte vraiment : 275 des 283 références du '
    'catalogue n\'ont pas de profil JSON, et doivent continuer à passer '
    'par StripThickness.corniceDefault(pH) exactement comme aujourd\'hui. '
    'Si ce test échouait en retournant un résultat non-null, cela '
    'signifierait un repli caché ici — la duplication de coefficients '
    'que ce commit a justement pour but de supprimer.',
    () {
      final r = stripPxFromDims(
        pH: 500.0,
        metresHauteur: 2.5,
        retombeeMm: null,
        projectionMm: null,
      );
      expect(r, isNull);
    },
  );

  test(
    'metresHauteur = 0 -> null, pas de division par zéro, pas de repli',
    () {
      final r = stripPxFromDims(
        pH: 500.0,
        metresHauteur: 0.0,
        retombeeMm: 202.87,
        projectionMm: 199.145,
      );
      expect(r, isNull);
    },
  );

  test(
    'metresHauteur négative -> null, pas de facteur négatif, pas de repli',
    () {
      final r = stripPxFromDims(
        pH: 500.0,
        metresHauteur: -1.0,
        retombeeMm: 202.87,
        projectionMm: 199.145,
      );
      expect(r, isNull);
    },
  );

  test(
    'retombeeMm seul absent (projectionMm présent) -> null quand même '
    '(cohérence : les deux dims viennent du même ProfileDims, on ne '
    'mélange pas une dim réelle avec un repli pour l\'autre)',
    () {
      final r = stripPxFromDims(
        pH: 500.0,
        metresHauteur: 2.5,
        retombeeMm: null,
        projectionMm: 199.145,
      );
      expect(r, isNull);
    },
  );

  test(
    'NON-RÉGRESSION — le résultat null, combiné à '
    'StripThickness.corniceDefault(pH) côté appelant, doit reproduire '
    'bit-à-bit les coefficients actuels pour les 275 références sans '
    'profil. Ce test appelle RÉELLEMENT StripThickness.corniceDefault '
    'et lit ses champs — il ne recopie plus 0.055/0.140/0.080/0.200 à '
    'la main : recopier ces littéraux ferait passer ce test même si '
    'corniceDefault changeait un jour, ce qui viderait la garantie de '
    'non-régression qu\'il est censé apporter.',
    () {
      const pH = 500.0;
      final attendu = StripThickness.corniceDefault(pH);

      // Le null renvoyé par stripPxFromDims (dims absentes) ne doit
      // rien ajouter ni retirer aux valeurs de corniceDefault : c'est
      // l'appelant qui doit reconstruire StripThickness.corniceDefault
      // dans ce cas, stripPxFromDims lui-même ne calcule rien.
      final r = stripPxFromDims(
        pH: pH,
        metresHauteur: 2.5,
        retombeeMm: null,
        projectionMm: null,
      );
      expect(r, isNull);

      // Valeurs lues sur l'objet réel, pas recalculées : c'est bien
      // la garantie voulue. Si corniceDefault change un jour, ces
      // expect contre 27.5/70.0/40.0/100.0 ECHOUERONT — c'est ça, le
      // verrou. (À ne pas « réparer » en recalculant depuis les
      // coefficients de la factory : cela annulerait le verrou et
      // ferait passer le test même en cas de régression.)
      expect(attendu.faceMurFond, closeTo(27.5, tol));
      expect(attendu.faceHorizFond, closeTo(70.0, tol));
      expect(attendu.faceMurLat, closeTo(40.0, tol));
      expect(attendu.faceHorizLat, closeTo(100.0, tol));
    },
  );
}
