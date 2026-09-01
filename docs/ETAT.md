# ÉTAT DU PROJET — staff_decor_studio / moteur de perspective (VP)

Reconstruit depuis `git log` + contenu réel des tests. Aucun chiffre non
re-vérifié ce tour. Format imposé : chiffres + chemins de logs, sans prose.

## SHA

Écrit au commit **suivant celui-ci** (structurel : ce fichier est commité
AVEC les changements qu'il décrit — le SHA qu'il cite au prochain tour sera
donc toujours celui du commit PRÉCÉDENT le tour en cours, jamais le commit
courant, puisqu'on ne peut pas s'auto-référencer avant `git commit`).

Dernier SHA vérifié local==remote avant ce tour : `efa73e3`.
SHA de ce tour (Point 6 + corrections Groupe 6) : voir `git log --oneline -1`
exécuté après ce commit — pas recopié ici pour éviter l'auto-référence
mentionnée ci-dessus.

## Suite complète

**215 tests, "All tests passed!", exit code 0.**
Log : `docs/logs/suite_complete_apres_point6.txt`.
Convention runner Dart : compteur `+N` affiché est 0-indexé (dernier `+214`
⇒ 215 tests). Vérifié par comparaison avec le run Point 5 (`+210` final ⇒
211 tests, cf. `docs/logs/suite_complete_apres_point5.txt`) : 211 + 4
(Groupe 3 : 4→8 tests, split x/y) = 215. Cohérent.

`flutter analyze` (projet complet) : 0 `error •`, 1 `warning •` préexistant
non lié (`unused_local_variable`,
`test/core/perspective/_debug_grid_zoom_test.dart:38`), reste `info`.
Log : `docs/logs/analyze_apres_point6.txt`.

## Points acquis (0-5, résumé)

P0 discipline `git log -1` avant écriture : continue. P1 193/193, commit
`3ee406b`. P2 reformulation actée : « l'entrée ne contient pas
l'information » (pas « le solveur est inexploitable »), portée au P11.
P3 `residualPx`/`residualFrac` sur `VanishingPoint` — haussmann
696.5px/121.1%, moderne 570.4px/109.4%, provencal 606.8px/108.1%,
scandinave 551.4px/98.3% ; contrôle synthétique ~3-7e-13px
(`docs/logs/point3bis_apres_nettoyage.txt`). P4 jitter/angle 4/4 verts,
err_rel max 3.45e-3 (`docs/logs/jitter_angle.txt`). P5 `_safeToward` :
`catch(e)` → `on ArgumentError`/`on StateError` ; filet Groupe 6 4/4 verts,
commit `b2d5e9c`.

**Point 6 — FAIT ce tour, 3 défauts corrigés + Groupe 3 réécrit.**

Défauts Groupe 6 (relecture externe) corrigés :
1. Test exécutait `frac()` seul ; `_safeToward` exécute
   `vp.toward(p, vp.frac(p, depthPx))` (2 appels, `toward()` peut lever
   indépendamment via le getter `vp` si `w==0`). Corrigé : expression
   complète dans le `try`.
2. `'plinthe.faceHorizFond'/'faceHorizLat'` recopiés en dur (`pH*0.115`,
   `pH*0.165`) → lus depuis `StripThickness.plintheDefault(pH)`.
3. `// ignore: avoid_print` faux positif au-dessus de `leves.add(...)`
   (pas un print) → retiré.
Vérifié : `docs/logs/groupe6_apres_corrections.txt` (4/4 verts).

Groupe 3 réécrit (constat par exécution, `docs/logs/groupe3_avant_split.txt`
puis `docs/logs/groupe3_apres_split.txt`, 8/8 verts) :
- dx=0.0 exact sur moderne/provencal/scandinave ; dx=42.0 (vp.x=742.0)
  sur haussmann seul.
- Hypothèse "asymétrie dx wallTL/wallTR" pour haussmann **testée et
  infirmée** : wallTL.dx-700=-699.944, wallTR.dx-700=+699.944, somme
  exactement 0.0 (symétrie à 3e-13). Cause réelle démontrée (sondes
  jetables supprimées après usage) : combinaison `ceilL.dy≠ceilR.dy`
  (87.75/82.875) ET `wallTL.dy≠wallTR.dy` (97.5/92.625) — isoler une seule
  pente ne reproduit pas 742.0 (571.1 ou 876.1 seuls).
- Assertion x moderne/provencal/scandinave : positive
  (`closeTo(700.0,0.5)`), PAS de `skip:` — documentée comme devant devenir
  rouge le jour où l'axe horizontal porte une information réelle.
- Seuil 50px supprimé. dy/pH rapporté : haussmann 0.5390, moderne 0.5640,
  provencal 0.5580, scandinave 0.5544. Borne `>0.3` utilisée dans
  l'assertion y, documentée explicitement comme CHOISIE (pas dérivée) ;
  décision d'acceptation reportée au Point 7.

## Assertions supprimées/remplacées (pour Point 11)

- Groupe 3 ancien : `(vp.vp - wallCenter).distance > 50.0` (norme
  euclidienne, seuil 50px non justifié, satisfaite uniquement par dy sur
  3/4 presets). Remplacé par : assertion y en fraction de pH (borne 0.3,
  choisie) + assertion x positive (700.0 sur 3 presets, 742.0 mesuré sur
  haussmann avec cause démontrée par sondes jetables).

## Point en cours / suivant

Point 6 clos ce tour. **Point 7 suivant** : instrumenter les deux voies de
décision caméra derrière un flag, rapporter le rendu observé sans arbitrer.
**Point 8 : ne rien commencer sans accord explicite utilisateur.**

## Points restants (ordre imposé)

- **Point 7** — flag repli projection parallèle (`metresHauteur` seul) VS
  erreur explicite par défaut ; rapporter rendu des deux voies, sans
  arbitrer.
- **Point 8** — bloqué, accord explicite requis. Focale fuyantes
  latérales, normale mur via homographie, câblage
  `RoomPainter→buildCalibratedScene→sweepMoulure→paintMeshOnCanvas`,
  abandon 2D hors Corniches/Plinthes/Moulures/Profils LED.
- **Point 9** — jointure `index.json`×`catalogue_data.dart` via
  `normalize_sku`. Cas 20-54 à investiguer. Ratio de couverture sur 4
  familles (jamais "43/458" ni "31/62", obsolètes).
- **Point 10** — dédup D887 (`docs/annexe_A_run_step_extrait.csv`),
  relancer `vp_current_state_probe.dart`, purger figures `/tmp` en-têtes,
  pas de "CORRECTION Bug #N", pas de `??` silencieux, lever verrou
  `ETAT_MOTEUR_RENDU.md`.
- **Point 11** — SHA + suite complète, résidu haut/bas par preset,
  `frac(θ)` bruité, lignes `lib/` modifiées, liste assertions
  supprimées/remplacées (section ci-dessus), rendu Point 7 sans arbitrage.

## Notes de méthode

- Sondes jetables (`test/core/perspective/_tmp_*.dart`) : créées,
  exécutées, supprimées (`rm -f`), jamais commitées. Chiffres reproduits
  par le code permanent committé.
- `flutter test` toujours redirigé (`> docs/logs/<nom>.txt 2>&1`), jamais
  brut au terminal.
- Push après CHAQUE point clos (pas seulement en fin de tour) — risque
  d'expiration de token GitHub observé 2x cette session.
- Bot `genspark auto-backup` écrit en parallèle sur ce dépôt : jamais de
  `commit --amend`/`rebase` sur un commit déjà poussé.
