# ÉTAT DU PROJET — staff_decor_studio / moteur de perspective (VP)

**Ce fichier doit permettre à une session neuve de reprendre le travail en
lisant SEULEMENT ce document.** Reconstruit depuis `git log` et le contenu
réel des tests/fichiers — pas de mémoire, pas de chiffre non re-vérifié.

Dernière mise à jour : après le commit **`b2d5e9c`** (Point 5 complet).

---

## 1. SHA poussé et vérifié (local == remote `github/main`)

```
b2d5e9c8aa4205b10090c08d1e074c4fcbd8863c
```

Vérifié par `git rev-parse HEAD` ET `git fetch github main && git rev-parse
github/main` — les deux commandes renvoient exactement ce SHA (voir sortie
de la commande dans l'historique de conversation, non ré-archivée ici).

Historique récent (`git log --oneline -8`) :
```
b2d5e9c Point 5 complet: test filet Groupe 6 (aucun preset reel n'emprunte les catch de _safeToward) + nettoyage scories (eslint-disable JS orphelin, commentaire voix haute obsolete) - 211/211 tests passes
11f6093 genspark auto-backup
3ee406b Point 1: suite complete (flutter test sans filtre) apres correctifs frac()/exceptions - 193/193 tests passes, log complet archive
3028172 Point 6a: reecriture vp_frac_degenere_test.dart - remplace frac>0.05 et estRepliMilieu (disqualifies) par 4 groupes non circulaires
1ef8a4b Point 2/3/4/5: Point 4a validation independante, reciblage Point 4 vers axe profondeur (vert), exceptions explicites frac(), garde _safeToward
9a6d5e9 WIP: extend buildSyntheticWall avec points de mur latéral + expectedDepthVpClosedForm (Point 2)
e2f349e genspark auto-backup
4a01dc7 logs(Étape A): sortie brute flutter test sur HEAD — constat VERT
```

**⚠️ Point d'attention permanent (Point 0 du brief) :** un bot d'auto-backup
écrit en parallèle sur ce même dépôt (voir commit `11f6093 "genspark
auto-backup"` ci-dessus, qui a capturé du travail avant qu'un `git commit`
explicite n'ait pu être fait). **Toujours lancer `git log --oneline -1`
avant toute écriture**, dans CHAQUE tour, sans exception. Ne jamais faire
`commit --amend` ni `rebase` sur un commit déjà poussé (imposerait un
`push --force` — c'est le scénario de perte de code réelle avec un bot qui
écrit en parallèle).

**⚠️ Authentification GitHub instable en cours de session :** le token du
remote `github` s'est invalidé DEUX FOIS pendant ce tour de travail (entre
des commandes séparées de quelques minutes). **Conséquence opérationnelle
appliquée à partir de maintenant : push après CHAQUE point terminé, jamais
en fin de tour uniquement** — sinon un token expiré peut faire perdre
plusieurs points de travail validé.

---

## 2. Résultat de suite complète le plus récent

**211 tests, "All tests passed!", exit code 0.**
Log complet : `docs/logs/suite_complete_apres_point5.txt`
(exécuté via `flutter test > docs/logs/suite_complete_apres_point5.txt 2>&1`,
donc jamais lancé sans redirection).

Historique des exécutions complètes :
- 193 tests passés → commit `3ee406b` (avant les modifications Points 3/4/5
  de ce tour), log `docs/logs/suite_complete_apres_correctif.txt`.
- 211 tests passés → après Points 3/4/5 de ce tour (18 tests nets ajoutés :
  5 Point 3-bis + 4 jitter + 4 Groupe 5 + 4 Groupe 6 + 1 test négatif — voir
  détail par point ci-dessous), log `docs/logs/suite_complete_apres_point5.txt`.

`flutter analyze` (projet complet, log `docs/logs/analyze_avant_commit_point5.txt`) :
**0 erreur, 1 warning préexistant non lié** (`unused_local_variable` dans
`test/core/perspective/_debug_grid_zoom_test.dart:38`, fichier non modifié
ce tour), reste = `info` (style, préexistants).

---

## 3. Points acquis (avec chiffres clés vérifiés dans les logs versionnés)

### Point 0 — discipline de vérification HEAD
Acquis en continu. Voir avertissement section 1.

### Point 1 — suite complète sans filtre, jamais lancée depuis les exceptions `frac()`
**FAIT.** 193/193 tests passés (avant ce tour), commit `3ee406b`, log
`docs/logs/suite_complete_apres_correctif.txt`. SHA vérifié local==remote
à l'époque.

### Point 2 — reformulation : le conditionnement cible l'ENTRÉE, pas le solveur
**Fait factuellement (mesures ci-dessous), reformulation à porter dans le
rapport final (Point 11).** Phrase obligatoire : **« l'entrée ne contient
pas l'information »** (pas « le solveur est inexploitable »).

### Point 3 — garde de conditionnement, SANS seuil deviné
**FAIT, poussé.**

- Ligne visée : `lib/core/perspective/vanishing_point.dart`, ancien
  `final vpFinite = vpTop ?? vpBottom;` — repli silencieux remplacé par un
  calcul EXPLICITE de résidu quand les deux couples (haut : wallTL→fTL /
  wallTR→fTR ; bas : wallBL→fBL / wallBR→fBR) produisent chacun une
  intersection finie.
- API ajoutée à `VanishingPoint` : `residualPx` (double?, résidu en px),
  `residualFrac` (double?, résidu normalisé par `dist(fTL, vp)` — la
  distance p→vp, PAS `pH`), `residualExceeds(thresholdFrac)` (bool, décision
  explicite laissée à l'appelant, aucun seuil dans le moteur).
- **Mesure sur les 4 presets réels** (`Groupe 5`,
  `test/core/perspective/vp_frac_degenere_test.dart`, log
  `docs/logs/groupe5_conditionnement.txt`) :

  | preset      | residualPx | residualFrac (fraction de dist(fTL,vp)) |
  |-------------|-----------:|-----------------------------------------:|
  | haussmann   |   696.5 px |                                   121.1% |
  | moderne     |   570.4 px |                                   109.4% |
  | provencal   |   606.8 px |                                   108.1% |
  | scandinave  |   551.4 px |                                    98.3% |

- **Contrôle négatif** (`Point 3-bis`,
  `test/core/perspective/_synth_vp_harness_test.dart`, log
  `docs/logs/point3bis_apres_nettoyage.txt`) : sur scène SYNTHÉTIQUE bien
  conditionnée (8 points d'une seule projection cohérente), résidu
  ~3-7e-13 px, ~3-6e-16 en fraction — quasi zéro, sans ambiguïté avec les
  chiffres ci-dessus.
- Aucun seuil de rejet n'est deviné dans `vanishing_point.dart` ni dans les
  tests : `residualExceeds()` est testé sur ses deux bords (0.01 → false,
  1e-20 → true) mais aucune valeur "correcte" n'est choisie — décision
  laissée au Point 7 (produit).

### Point 4 — honnêteté sur l'identité algébrique + test jitter paramétré
**FAIT, poussé.**

- Docstrings de `Point 4a` et `Point 4`
  (`_synth_vp_harness_test.dart`) corrigées : l'accord à 1.4e-16/1.6e-16/
  4.0e-16 entre `compute()` et le test Point 4a est une IDENTITÉ ALGÉBRIQUE
  (même fonction `lineIntersect`, mêmes points — `wall.ceilL == fTL`), PAS
  une validation indépendante. Le seuil 2% du groupe Point 4 n'a jamais été
  réellement exercé par ce test.
- **Nouveau test jitter paramétré par l'angle** (groupe "Point 4 — jitter
  paramétré par l'angle", fin de `_synth_vp_harness_test.dart`, log
  `docs/logs/jitter_angle.txt`) : perturbe `wallTL` de 2px perpendiculaire
  à `wallTL→fTL`, compare le déplacement réel du VP à la loi fermée
  `displacement ≈ (jitter/L1)·(D/sin(angle))` (angle = angle entre les
  deux fuyantes), tolérance 5%.

  | theta | angle fuyantes | L1     | D        | déplacement réel | prédit  | err_rel |
  |------:|----------------:|-------:|---------:|------------------:|--------:|--------:|
  |  2.0° |          81.95° | 233.7px| 947.6px  |            8.199px| 8.189px | 1.21e-3 |
  |  8.0° |          83.82° | 240.0px| 1017.6px |            8.538px| 8.530px | 9.04e-4 |
  | 18.0° |          87.87° | 249.4px| 1157.7px |            9.287px| 9.290px | 2.98e-4 |
  | 32.0° |          65.71° | 260.7px| 1427.1px |           11.972px|12.013px | 3.45e-3 |

  4/4 tests verts, err_rel toujours << 5% — ce test PEUT devenir rouge si le
  conditionnement empire (loi vérifiée jusqu'à theta=45° lors du dérivation,
  hors commit — voir section 6 "sondes jetables").

### Point 5 — restriction des exceptions de `_safeToward` + test filet
**FAIT, poussé (ce tour).**

- `lib/core/perspective/cornice_plinth_painter.dart`, fonction
  `_safeToward` : `catch (e)` non typé remplacé par `on ArgumentError catch
  (e)` / `on StateError catch (e)` — toute autre exception (bug de refactor,
  `NoSuchMethodError`, etc.) remonte désormais normalement au lieu d'être
  avalée silencieusement (dangereux en particulier car `debugPrint` sous
  `kDebugMode` ne produit AUCUN signal en release).
- **Test filet** : `Groupe 6` (fin de
  `test/core/perspective/vp_frac_degenere_test.dart`, log
  `docs/logs/groupe6_safetoward_presets_reels.txt`) — pour chacun des 4
  presets réels, appelle `vp.frac(p, depthPx)` pour les 8 points de
  calibration réels × les 4 profondeurs par défaut réellement utilisées en
  production (`corniceDefaultPx` fond/latéral, `plintheDefault`
  fond/latéral — chemin empruntable par 275/283 réf. catalogue sans profil
  JSON), et vérifie qu'AUCUN appel ne lève. **4/4 presets verts** —
  aujourd'hui, `_safeToward` n'emprunte aucune de ses branches catch en
  production. Ce test est un FILET (peut devenir rouge si Point 7 câble la
  garde du Point 3 en amont), pas une garantie permanente — documenté
  explicitement dans le test lui-même.
- **Nettoyage de scories** (signalées par l'utilisateur, relevant du Point
  10, traitées immédiatement) : suppression d'un `// eslint-disable-next-
  line` orphelin (commentaire d'outillage JS sans effet en Dart) et
  réécriture d'un bloc de commentaire du 3ᵉ test "Point 3-bis" qui
  raisonnait à voix haute et décrivait une construction abandonnée
  ("segment de longueur quasi nulle") différente de celle réellement codée
  (translation horizontale identique appliquée à `fBL`/`fBR`).

---

## 4. Point en cours

**Aucun point en cours au moment de cette mise à jour** — Point 5 vient
d'être clos et poussé. Le prochain point à traiter, dans l'ordre imposé,
est le **Point 6**.

---

## 5. Points restants (ordre imposé, ne pas réordonner)

- **Point 6** — Groupe 3 (`vp_frac_degenere_test.dart`) : `vp.x = 700.00`
  sur moderne/provençal/scandinave est le centre canvas imposé par
  calibration (haussmann à 742.0). Le test actuel "distance au centre mur
  fond > 50px" ne passe QUE par la composante verticale (dy) — à vérifier
  et corriger. **À faire** : splitter les assertions x/y, justifier ou
  remplacer le seuil de 50px, marquer l'assertion en x comme
  **expected-to-fail** (trace de sous-détermination, pas un test à faire
  passer par contournement).
- **Point 7** — Instrumenter DEUX voies derrière un flag (repli projection
  parallèle ancré sur `metresHauteur` seul VS erreur explicite par défaut),
  rapporter le rendu observé dans chaque cas, **sans arbitrer** — la
  décision revient au product owner.
- **Point 8** — ⚠️ **Ne rien commencer sans accord explicite de
  l'utilisateur** (rappel du message utilisateur de ce tour). Focale depuis
  fuyantes latérales, normale au mur via homographie, câblage
  `RoomPainter → buildCalibratedScene → sweepMoulure → paintMeshOnCanvas`,
  abandon du chemin 2D pour Corniches/Plinthes/Moulures/Profils LED
  uniquement (erreur explicite pour les autres familles).
- **Point 9** — Volet catalogue : jointure `index.json` × `catalogue_data.dart`
  via `normalize_sku` (`dxf2profile.py`), logging des matches non-exacts.
  Cas 20-54 à investiguer (grep échoue dans `catalogue_data.dart`, mais
  `assets/profiles/20-54.json` existe et `catalogue.csv` ligne 354 a
  `20.54` — identifier la variation orthographique). Recalculer le ratio de
  couverture sur les 4 familles (Corniches/Plinthes/Moulures/Profils LED),
  jamais "43/458" ni "31/62" (obsolète, à corriger dans le docstring de
  `build_profiles_index.py`). Rappel des comptages établis : 43 lignes
  `statut_gate == OK`, concordant avec `index.json`, total 80 profils.
- **Point 10** — Hygiène restante :
  - Dédupliquer la ligne D887 dans `docs/annexe_A_run_step_extrait.csv`
    (deux lignes identiques champ à champ, seul le suffixe de tentative
    diffère — le rapport annonce 5 SKU, le fichier doit en montrer 5).
  - Relancer la sonde `tools/calib_measure/vp_current_state_probe.dart`
    avec les valeurs finales (non ramassée par `flutter test` sans
    argument — à exécuter séparément).
  - Purger les figures issues de scripts `/tmp` supprimés dans les
    en-têtes versionnés.
  - Pas de bloc "CORRECTION Bug #N". Pas de `??` silencieux.
  - Le verrou sur `ETAT_MOTEUR_RENDU.md` peut être levé ; l'audit du
    harnais existe déjà sous `docs/logs/etape_b_audit_harnais.txt`.
  - *(Deux scories mineures déjà traitées par anticipation ce tour — voir
    Point 5 ci-dessus.)*
- **Point 11 (rapport final)** — SHA poussé + résultat suite complète
  (nombre de tests + échecs) ; facteur d'amplification et résidu
  haut/bas par preset (absolu + fraction) ; `frac(θ)` sur scène bruitée
  avec tolérance dépendant de l'angle ; nombre de lignes de logique
  modifiées dans `lib/` hors commentaires ; liste des assertions
  supprimées/remplacées avec raison ; rendu observé dans les deux voies du
  Point 7, sans arbitrage.

---

## 6. Notes de méthode (à ne pas oublier en reprenant)

- **Sondes jetables** : plusieurs fichiers `test/core/perspective/_tmp_*.dart`
  ont été créés, exécutés, puis supprimés (`rm -f`) pendant la dérivation
  des Points 3/4 — jamais commités. Les chiffres qu'ils ont produits sont
  TOUS reproduits par les groupes de tests permanents cités ci-dessus
  (Point 3-bis, Groupe 5, jitter). Aucune valeur de ce document ne dépend
  d'un fichier non versionné.
- **Convention de log** : depuis ce point du projet, **toute exécution de
  `flutter test` doit être redirigée** (`> docs/logs/<nom>.txt 2>&1`), puis
  lue via `tail`/`grep` sur le fichier — plus de `flutter test` affiché
  brut dans le terminal.
- **Après CHAQUE point désormais** : commit + `git push github main` +
  `git rev-parse HEAD` (vérifié contre `git fetch github main &&
  git rev-parse github/main`) + mise à jour de ce fichier. Ne pas attendre
  la fin du tour (voir avertissement authentification, section 1).
