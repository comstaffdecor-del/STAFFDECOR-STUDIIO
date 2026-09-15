/// AppState — état global centralisé de l'application.
///
/// Port fidèle de `STATE` (state.js) en `ChangeNotifier` Provider.
/// Toute la logique métier (ajout produit, snap, métrés, calibration...)
/// vit ici, comme dans l'ancienne version où tous les modules
/// lisaient/écrivaient via STATE.*.
///
/// ⚠️ CORRECTION Bug #7 (audit rendering) : `addToProject` et
/// `quickToggleProd` utilisent désormais `getQteNetteForFamille()` (via
/// les métrés calculés) comme quantité par défaut, au lieu de la valeur
/// codée en dur `unite=='pce' ? 1 : 5` de l'ancienne version qui ignorait
/// totalement le panneau "Métrés" saisi par l'utilisateur.
///
/// Persistance : utilise `shared_preferences` (équivalent local du
/// `sessionStorage` d'origine — pas de backend cloud pour l'état
/// utilisateur, fidèle au comportement original éphémère par session).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Size;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalogue_data.dart';
import '../data/catalogue_visibility.dart' show CatalogueVisibilityGate;
import '../data/ia_ambiance_preview.dart' show kAiPreviewEnabled;
import '../core/chiffrage.dart';
import '../core/perspective/edge_detect.dart';
import '../models/contact_info.dart';
import '../models/project_item.dart';
import '../models/persp_calib.dart';
import '../models/saved_project.dart';

const _prefsKey = 'sds_state';
const _projectsPrefsKey = 'sds_saved_projects';

/// Résultat d'un aperçu IA réussi, conservé en mémoire (jamais persisté
/// sur disque — [Uint8List] volatile, cohérent avec [AppState.roomImage])
/// pour permettre à l'écran Avant/Après d'afficher la vraie photo
/// originale à côté de l'image IA générée, sans relancer Gemini. Tous
/// les champs de traçabilité ([model], [sku], [usedProductReference],
/// [productReferencePath]) proviennent tels quels de la réponse du
/// proxy `/api/ai-render` (voir [AiPreviewResult] dans
/// `ia_ambiance_preview.dart`), jamais recalculés côté client.
class AiComparisonResult {
  /// Photo/scène EXACTE envoyée au proxy pour cette génération (avant
  /// ajout de la corniche/moulure IA) — le "AVANT" du comparatif.
  final Uint8List originalImageBytes;

  /// Image générée par Gemini (avec le produit intégré) — le "APRÈS".
  final Uint8List aiImageBytes;

  final String sku;
  final String? model;
  final bool? usedProductReference;
  final String? productReferencePath;
  // P21-HYBRIDE — 'add' (photo brute → IA ajoute la corniche) ou
  // 'refine' (scène déjà composée par le moteur dynamique → IA
  // n'améliore que le réalisme). Traçabilité uniquement, lue telle
  // quelle depuis la réponse du proxy.
  final String? renderMode;

  const AiComparisonResult({
    required this.originalImageBytes,
    required this.aiImageBytes,
    required this.sku,
    this.model,
    this.usedProductReference,
    this.productReferencePath,
    this.renderMode,
  });
}

/// Calcule le rectangle d'affichage "contain" d'une image source dans un
/// conteneur donné (letterboxing centré) — port fidèle de la logique
/// `fitImageContain` de l'ancienne version (studio.js).
ImgDraw computeImgDraw(
  double srcW,
  double srcH,
  double containerW,
  double containerH,
) {
  if (srcW <= 0 || srcH <= 0 || containerW <= 0 || containerH <= 0) {
    return ImgDraw(dx: 0, dy: 0, dw: containerW, dh: containerH, scale: 1);
  }
  final scale = (containerW / srcW < containerH / srcH)
      ? containerW / srcW
      : containerH / srcH;
  final dw = srcW * scale;
  final dh = srcH * scale;
  final dx = (containerW - dw) / 2;
  final dy = (containerH - dh) / 2;
  return ImgDraw(dx: dx, dy: dy, dw: dw, dh: dh, scale: scale);
}

class AppState extends ChangeNotifier {
  /* ── Navigation ── */
  String currentScreen = 'home';

  /* ── Sélection produits projet ── */
  List<ProjectItem> selectedProducts = [];

  /* ── Chiffrage ── */
  double margeCoupePct = 0.10; // défaut 10%

  /* ── Calibrage ── */
  bool isCalibrated = false;
  double? pxPerCm;
  PerspCalib? perspCalib;

  /* ── Talon plinthe ── */
  double talonMm = 0; // 0–30 mm

  /* ── Métrés saisis ── */
  double metresMurA = 0;
  double metresMurB = 0;
  double metresHauteur = 2.5;
  double metresPortes = 1;
  double metresFenetres = 1;

  /* ── Métrés calculés (mis à jour par computeAndStoreMetres) ── */
  double metresPerimetre = 0;
  double metresPerimetreNet = 0;
  double metresSurface = 0;

  /* ── Studio ── */
  String? studioSelected; // ref du produit sélectionné dans le strip
  bool anchorMode = false;
  String catTabStudio = 'Corniches';
  ImgDraw? imgDraw;

  /// Image de la pièce (photo importée ou scène démo) décodée pour le
  /// [CustomPainter]. Null tant qu'aucune photo/démo n'est chargée.
  ui.Image? roomImage;

  /// Compteur incrémenté à CHAQUE nouvelle image de pièce chargée (import
  /// photo ou scène démo) — sert de signature simple et fiable pour
  /// détecter un changement de scène, bien plus robuste qu'un hash sur
  /// [roomImage] (qui peut être un objet Dart réutilisé/identique en
  /// mémoire). Utilisé exclusivement par [shouldAutoTriggerAiPreview]
  /// (P20-AUTO) pour la protection anti-boucle du déclenchement
  /// automatique de l'aperçu IA — ne pilote aucun rendu.
  int roomImageVersion = 0;

  /// Vrai si la scène active est une scène démo (pas une vraie photo).
  bool isDemoRoom = false;

  /// Scène démo active ('haussmann' | 'moderne' | 'provencal' | 'scandinave')
  String demoScene = 'haussmann';

  /// Affiche/masque les repères de calibration (poignées dorées) sur la
  /// photo en cours d'édition.
  bool showCalibHandles = false;

  /// Affiche/masque les produits en surimpression sur la photo.
  bool showProductOverlay = true;

  /// Dernière taille connue de la zone photo (mémorisée pour pouvoir
  /// recharger/recalculer une image sans avoir à repasser explicitement
  /// la taille du conteneur, ex: changement de scène démo).
  Size? _lastPhotoZoneSize;

  /// Dernière taille RÉELLE et FIABLE de la zone photo, mesurée par le
  /// [LayoutBuilder] du Studio (contrainte par le cadre "téléphone" sur
  /// desktop — voir [AppShell], max 430×932). À utiliser IMPÉRATIVEMENT
  /// au lieu de `MediaQuery.of(context).size` pour tout calcul de
  /// letterboxing d'image importée : sur desktop/large écran,
  /// `MediaQuery.size` renvoie la taille de la FENÊTRE NAVIGATEUR
  /// entière (ex: 1920×1080), alors que la photo s'affiche en réalité
  /// dans un cadre contraint bien plus petit (430px large max) — utiliser
  /// `MediaQuery.size` pour calculer l'`imgDraw` (letterboxing "contain")
  /// produisait un rectangle d'affichage totalement faux par rapport au
  /// canvas réellement rendu, d'où la photo "hors champs" signalée par
  /// l'utilisateur (bug reproductible uniquement en desktop/large fenêtre,
  /// jamais sur mobile plein écran où les deux tailles coïncident).
  Size? get lastPhotoZoneSize => _lastPhotoZoneSize;

  /// Vrai pendant le chargement asynchrone d'une scène démo (affiche un
  /// petit indicateur de chargement dans la zone photo).
  bool demoSceneLoading = false;

  /// Vrai pendant l'exécution de la détection automatique des arêtes
  /// (Sobel + Hough) sur la photo — voir [_autoDetectEdges].
  bool edgeDetecting = false;

  /// Vrai si la calibration actuelle ([perspCalib]) a été déduite
  /// automatiquement par [detectRoomEdges] à partir de la vraie
  /// photo/pièce démo (par opposition à la calibration par défaut
  /// arbitraire [PerspCalib.defaultCalib] ou à un ajustement manuel de
  /// l'utilisateur via les poignées dorées).
  bool calibAutoDetected = false;

  /// Confiance (0..1) de la dernière détection automatique d'arêtes —
  /// affichée à l'utilisateur (badge) pour indiquer la fiabilité du
  /// calage produit sur la photo.
  double? edgeDetectConfidence;

  /// Lance la détection automatique des arêtes (plafond/sol/murs) sur
  /// [roomImage] et met à jour [perspCalib] avec le résultat si la
  /// confiance est suffisante — c'est ce qui permet aux produits
  /// (corniches, plinthes...) de se caler sur la VRAIE perspective de
  /// la pièce plutôt que sur les 8 points par défaut arbitraires.
  /// Appelé automatiquement après tout chargement de photo (import ou
  /// scène démo) ; peut aussi être relancé manuellement (bouton
  /// "repérer auto" dans la barre d'outils Studio).
  Future<void> autoDetectEdges() async {
    if (roomImage == null) return;
    edgeDetecting = true;
    notifyListeners();
    try {
      final geo = await detectRoomEdges(roomImage!);
      // P9k/P9l : le "X" historique (croisement diagonal des coins) est
      // structurellement écarté depuis la suppression de
      // `_estimateWallX` — X fixes (0.20/0.80), seul Y varie avec un
      // tilt borné. Vérifié visuellement sans croisement sur les 4
      // scènes démo (voir docs/ETAT.md, section P9l). L'application
      // automatique est donc branchée.
      const autoApplyDetection = true;
      if (geo != null && autoApplyDetection) {
        perspCalib = geo.calib;
        // P9k : la geometrie auto est appliquee (grille posee sans clic)
        // mais NE vaut PAS calibration certifiee : erreur mesuree 0,058
        // a 0,079 sur le plafond, 0,2433 sur le sol moderne, barrieres
        // P9c (mean<0,02) et P9d non franchies. Laisser false pour que
        // EstimBadge reste "Estimatif +-15%" et que chiffrage.dart:172
        // n'annonce pas une precision inexistante. Passe a true par
        // updateCalibPoint des que l'utilisateur touche une poignee.
        calibAutoDetected = false;
        edgeDetectConfidence = geo.confidence;
        // isCalibrated reste a sa valeur courante (false par defaut ici,
        // via setRoomImageBytes/loadDemoScene) — PAS mis a true : c'est
        // ce booleen, pas calibAutoDetected, qui pilote le badge
        // "Calibre +-3%" de chiffrage.dart/EstimBadge. Le laisser a
        // true aurait annonce la precision exacte que ce commentaire dit
        // justement ne pas encore atteindre. Voir updateCalibPoint (seul
        // point qui doit legitimement lever isCalibrated).
      } else if (geo != null) {
        // Détection calculée mais non appliquée (sécurité) — on garde
        // la calibration par défaut active, tout en mémorisant la
        // confiance pour affichage/diagnostic éventuel.
        perspCalib ??= PerspCalib.defaultCalib;
        calibAutoDetected = false;
        edgeDetectConfidence = geo.confidence;
      } else {
        // Détection non concluante (photo trop sombre/complexe) :
        // on conserve la calibration par défaut, l'utilisateur peut
        // ajuster manuellement via les poignées dorées.
        perspCalib ??= PerspCalib.defaultCalib;
        calibAutoDetected = false;
        edgeDetectConfidence = null;
      }
    } catch (_) {
      perspCalib ??= PerspCalib.defaultCalib;
      calibAutoDetected = false;
      edgeDetectConfidence = null;
    } finally {
      edgeDetecting = false;
      notifyListeners();
      save();
    }
  }

  /// Charge une image mémoire (bytes) et met à jour [roomImage] +
  /// [imgDraw] (mode "contain" dans une zone de taille [containerSize]).
  Future<void> setRoomImageBytes(
    Uint8List bytes, {
    required Size containerSize,
    bool demo = false,
  }) async {
    // CORRECTIF (brief "persistance propre du rendu d'aperçu + reset
    // propre au changement de scène", Objectif 3) : toute nouvelle scène
    // (import photo OU scène démo, voir [loadDemoScene] plus bas) doit
    // repartir d'une vue propre — aucun ancien rendu d'ambiance IA
    // distant ne doit rester affiché par-dessus la nouvelle scène source
    // ([currentAmbiancePreviewBytes] pilote la vue principale de
    // `_PhotoZone`, voir sa docstring). [roomImage] lui-même est de
    // toute façon réécrit juste en dessous : cet appel supprime
    // uniquement le rendu VISUEL résiduel d'un aperçu précédent.
    clearCurrentAmbiancePreview();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    roomImage = frame.image;
    roomImageVersion++;
    isDemoRoom = demo;
    _lastPhotoZoneSize = containerSize;
    imgDraw = computeImgDraw(
      roomImage!.width.toDouble(),
      roomImage!.height.toDouble(),
      containerSize.width,
      containerSize.height,
    );
    // Calibration par défaut immédiate (affichage instantané), puis
    // détection auto des arêtes en arrière-plan pour caler les produits
    // sur la VRAIE perspective de la photo dès qu'elle est disponible.
    perspCalib = PerspCalib.defaultCalib;
    calibAutoDetected = false;
    // P18-DEMO-SAFE Pt.2 : la géométrie est réinitialisée ci-dessus mais
    // isCalibrated restait à true — badge "Calibré ±3%" affiché à tort
    // sur une calibration par défaut après une scène démo.
    isCalibrated = false;
    notifyListeners();
    unawaited(autoDetectEdges());
    // P22-HYBRIDE-AUTO — RETIRÉ après test visuel réel (voir docstring
    // complète de [maybeAutoTriggerHybridAiPreview]) : Mano/Nano en
    // mode 'refine' sur une capture du rendu dynamique produit un
    // résultat visuellement dégradé. JAMAIS de captureComposedScene()
    // ici.
    //
    // P23-STANDARD-AUTO — nouvelle photo chargée : si un produit est
    // déjà sélectionné (cas d'un changement de photo en cours de
    // projet), déclenche automatiquement l'aperçu IA en mode STANDARD
    // (photo brute + renderMode='add'), seul rendu validé
    // visuellement — voir docstring de
    // [maybeAutoTriggerStandardAiPreview] pour tous les garde-fous
    // (whitelist, anti-boucle, debounce, quota session).
    //
    // CORRECTIF (brief "Persist quota + studioSelected") :
    // `selectedProducts.first.ref` n'est PAS forcément la référence que
    // l'utilisateur regarde/vient d'activer — un utilisateur qui a déjà
    // 2 produits en projet (ex: une corniche ET une plinthe, familles
    // différentes) et qui change de photo verrait l'auto-trigger partir
    // sur le PREMIER produit de la liste, potentiellement pas celui
    // affiché/actif dans le strip Studio. [studioSelected] (assigné dans
    // [addToProject], seule écriture de ce champ, ET remis à `null` par
    // [removeProd] quand la ref retirée était la sélection active)
    // reflète la DERNIÈRE ref réellement activée par l'utilisateur.
    //
    // BLINDAGE SUPPLÉMENTAIRE (brief "regression réelle : studioSelected
    // jamais remis à null dans removeProd") : même si [removeProd] reset
    // désormais [studioSelected] correctement, on revérifie ICI son
    // appartenance à [selectedProducts] par défense en profondeur —
    // ex: restauration d'état ([restore]) qui ne recharge pas
    // explicitement [studioSelected], ou toute future voie de retrait
    // qui oublierait ce reset. Sans cette double vérification, un
    // `studioSelected` obsolète pointant vers un produit ABSENT du
    // projet déclencherait une génération IA AUTOMATIQUE — donc
    // FACTURÉE — sur un SKU que l'utilisateur ne veut plus voir.
    if (selectedProducts.isNotEmpty) {
      final selectedIsStillActive = studioSelected != null &&
          getProdInProject(studioSelected!) != null;
      final activeRef =
          selectedIsStillActive ? studioSelected! : selectedProducts.first.ref;
      maybeAutoTriggerStandardAiPreview(ref: activeRef);
    }
  }

  /// Recalcule [imgDraw] quand la taille du conteneur change (rotation,
  /// resize) sans recharger l'image.
  void recomputeImgDraw(Size containerSize) {
    _lastPhotoZoneSize = containerSize;
    if (roomImage == null) return;
    imgDraw = computeImgDraw(
      roomImage!.width.toDouble(),
      roomImage!.height.toDouble(),
      containerSize.width,
      containerSize.height,
    );
    notifyListeners();
  }

  /// Mémorise la taille actuelle de la zone photo, sans notifier ni
  /// recalculer quoi que ce soit — appelé en continu par [LayoutBuilder]
  /// pour que [loadDemoScene] connaisse toujours la bonne taille de
  /// conteneur, même avant qu'une image ne soit chargée.
  void registerPhotoZoneSize(Size size) {
    _lastPhotoZoneSize = size;
  }

  /// P9m : retourne le preset de calibration mesuré à la main pour la
  /// scène démo [key] (voir [PerspCalib.demoPresets]), ou `null` si [key]
  /// ne correspond à aucune des 4 scènes démo connues (cas d'une photo
  /// utilisateur importée, qui doit continuer à passer par
  /// [autoDetectEdges]). Lit directement [PerspCalib.demoPresets] plutôt
  /// que de dupliquer les clés dans un switch, pour éviter tout risque de
  /// désynchronisation entre les deux listes de clés.
  PerspCalib? _presetForScene(String key) => PerspCalib.demoPresets[key];

  /// Charge une vraie photo de scène démo depuis les assets
  /// (`assets/demo_scenes/<key>.jpg`) et l'affiche comme [roomImage],
  /// exactement comme une photo importée par l'utilisateur — corrige le
  /// bug où le sélecteur de scène démo ne changeait qu'un libellé texte
  /// sans jamais charger/afficher de vraie image.
  Future<void> loadDemoScene(String key, {Size? containerSize}) async {
    // CORRECTIF (brief "persistance propre du rendu d'aperçu + reset
    // propre au changement de scène", Objectif 3) : voir le commentaire
    // symétrique dans [setRoomImageBytes] — même règle pour un
    // changement de scène démo (première sélection OU re-sélection
    // depuis [_DemoScenePicker]) : aucun ancien rendu IA distant ne doit
    // survivre au changement de scène.
    clearCurrentAmbiancePreview();
    final size = containerSize ?? _lastPhotoZoneSize;
    if (size == null || size.width <= 0 || size.height <= 0) {
      // Zone photo pas encore mesurée : on mémorise juste le choix, le
      // chargement effectif sera déclenché dès que la taille sera connue.
      demoScene = key;
      isDemoRoom = true;
      notifyListeners();
      return;
    }
    demoScene = key;
    isDemoRoom = true;
    demoSceneLoading = true;
    notifyListeners();
    try {
      final data = await rootBundle.load('assets/demo_scenes/$key.jpg');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      roomImage = frame.image;
      roomImageVersion++;
      _lastPhotoZoneSize = size;
      imgDraw = computeImgDraw(
        roomImage!.width.toDouble(),
        roomImage!.height.toDouble(),
        size.width,
        size.height,
      );
      // ⚠️ CORRECTION Bug "angles" : chaque scène démo a sa PROPRE
      // géométrie réelle (ligne de plafond, ligne de sol, angles des
      // murs) — on ne peut plus appliquer la même calibration générique
      // [PerspCalib.defaultCalib] à toutes les photos, sinon la bande de
      // corniche/plinthe se retrouve décrochée en diagonale de
      // l'architecture réellement visible sur la photo. On utilise le
      // preset mesuré à la main dédié à cette scène (voir
      // [PerspCalib.demoPresets]).
      perspCalib = PerspCalib.forDemoScene(key);
      calibAutoDetected = false;
    } catch (_) {
      // Asset introuvable/décodage échoué : on reste en mode démo
      // procédural (fallback _paintDemoRoom du RoomPainter).
      roomImage = null;
    } finally {
      demoSceneLoading = false;
      notifyListeners();
      if (roomImage != null) {
        // P9m : les 4 scènes de démo ont une calibration mesurée à la main
        // dans persp_calib.dart. On la charge directement plutôt que de
        // passer par le détecteur, dont l'erreur est de 0,058-0,079 au
        // plafond et 0,2433 au sol moderne (barrière P9c non franchie).
        // Les photos utilisateur inconnues (preset introuvable) continuent
        // d'aller vers autoDetectEdges().
        final preset = _presetForScene(key);
        if (preset != null) {
          perspCalib = preset;
          calibAutoDetected = true;
          isCalibrated = true;
          edgeDetectConfidence = 1.0;
          notifyListeners();
        } else {
          unawaited(autoDetectEdges());
        }
      }
      // P22-HYBRIDE-AUTO — RETIRÉ (voir setRoomImageBytes ci-dessus et
      // docstring de [maybeAutoTriggerHybridAiPreview]) : rejet visuel
      // confirmé par test réel, aucun déclenchement automatique ici.
      //
      // P23-STANDARD-AUTO — brief "Correction finale du flow produit"
      // ne liste QUE [setRoomImageBytes] et [addToProject] comme points
      // d'entrée du nouveau mécanisme standard — volontairement PAS
      // reconnecté ici (scène démo) pour rester strictement dans le
      // périmètre explicitement validé. À reconnecter explicitement si
      // le besoin est confirmé pour les scènes démo.
    }
  }

  void updateCalibPoint(String key, CalibPoint p) {
    final c = perspCalib ?? PerspCalib.defaultCalib;
    switch (key) {
      case 'ceilL':
        perspCalib = c.copyWith(ceilL: p);
        break;
      case 'ceilR':
        perspCalib = c.copyWith(ceilR: p);
        break;
      case 'floorL':
        perspCalib = c.copyWith(floorL: p);
        break;
      case 'floorR':
        perspCalib = c.copyWith(floorR: p);
        break;
      case 'wallTL':
        perspCalib = c.copyWith(wallTL: p);
        break;
      case 'wallTR':
        perspCalib = c.copyWith(wallTR: p);
        break;
      case 'wallBL':
        perspCalib = c.copyWith(wallBL: p);
        break;
      case 'wallBR':
        perspCalib = c.copyWith(wallBR: p);
        break;
    }
    isCalibrated = true;
    notifyListeners();
  }

  void toggleShowCalibHandles() {
    showCalibHandles = !showCalibHandles;
    notifyListeners();
  }

  void toggleProductOverlay() {
    showProductOverlay = !showProductOverlay;
    notifyListeners();
  }

  /// Change la scène démo active et charge la vraie photo correspondante
  /// (voir [loadDemoScene]) — remplace l'ancien comportement qui ne
  /// modifiait qu'un libellé sans jamais afficher d'image.
  void setDemoScene(String scene) {
    loadDemoScene(scene);
  }

  /// Active le mode "pièce démo" et charge la vraie photo de la scène
  /// actuellement sélectionnée ([demoScene]) — remplace l'ancien rendu
  /// 100% procédural par une vraie photo d'intérieur.
  void setDemoRoomMode() {
    perspCalib = PerspCalib.defaultCalib;
    loadDemoScene(demoScene);
  }

  void setCatTabStudio(String fam) {
    catTabStudio = fam;
    notifyListeners();
  }

  void setTalonMm(double v) {
    talonMm = v;
    notifyListeners();
    save();
  }

  void setMargeCoupePct(double v) {
    margeCoupePct = v;
    notifyListeners();
    save();
  }

  void goTo(String screen) {
    currentScreen = screen;
    notifyListeners();
  }

  void setCompPos(double v) {
    compPos = v.clamp(0, 100);
    notifyListeners();
  }

  /* ── Catalogue (setters notifiants) ── */

  void setCatFam(String fam) {
    catFam = fam;
    catPage = 0;
    notifyListeners();
    save();
  }

  void setCatSearch(String q) {
    catSearch = q;
    catPage = 0;
    notifyListeners();
    save();
  }

  void setCatPage(int page) {
    catPage = page;
    notifyListeners();
  }

  /* ── Positions produits sur la photo (drag & drop) ── */
  Map<String, SnapPos> prodPositions = {};

  /* ── Catalogue ── */
  String catFam = 'all';
  String catSearch = '';
  int catPage = 0;
  final int catPerPage = 20;

  /* ── Comparateur ── */
  double compPos = 50; // position divider en %

  /* ── Modals / UI ── */
  bool devisWarnShown = false;
  String? productModalRef;
  double productModalQte = 5;
  bool showMetresPanel = false;

  /// Affiche/masque le modal "Enregistrer le projet" (Studio) — voir
  /// [saveCurrentAsProject].
  bool showSaveProjectModal = false;

  void openSaveProjectModal() {
    showSaveProjectModal = true;
    notifyListeners();
  }

  void closeSaveProjectModal() {
    showSaveProjectModal = false;
    notifyListeners();
  }

  /* ── Contact commercial (Bug #14/#15/#16/#22) ── */

  /// ⚠️ CORRECTION Bug #14/#22 (retour utilisateur : "il faut RETIRER le
  /// prix/devis visible (panneau bas du Comparateur + écran Devis)
  /// jusqu'à la saisie des coordonnées, l'objectif est la génération de
  /// leads, pas l'affichage libre d'un prix") — tant que
  /// [contactSubmitted] est faux, le Comparateur et le Devis masquent
  /// leurs montants et affichent un appel à contact à la place. Passe à
  /// `true` dès qu'un [ContactInfo] valide (avec consentement RGPD) a
  /// été soumis via [submitContact] — persistant (voir [save]/[restore])
  /// pour ne pas re-demander les coordonnées à chaque session.
  bool contactSubmitted = false;

  /// Dernières coordonnées soumises (pré-remplissage du modal si
  /// l'utilisateur rouvre le formulaire, et corps du mailto généré).
  ContactInfo? lastContactInfo;

  /// Affiche/masque le modal de saisie des coordonnées.
  bool showContactModal = false;

  void openContactModal() {
    showContactModal = true;
    notifyListeners();
  }

  void closeContactModal() {
    showContactModal = false;
    notifyListeners();
  }

  /// Enregistre les coordonnées et débloque l'affichage du chiffrage.
  /// Validation stricte (prénom/nom/email non vides + RGPD cochée) faite
  /// côté UI ([ContactModal]) avant appel — ici on se contente de
  /// persister et de lever le verrou de prix.
  void submitContact(ContactInfo info) {
    lastContactInfo = info;
    contactSubmitted = true;
    showContactModal = false;
    notifyListeners();
    save();
  }

  void openMetresPanel() {
    showMetresPanel = true;
    notifyListeners();
  }

  void closeMetresPanel() {
    showMetresPanel = false;
    notifyListeners();
  }

  /// Affiche/masque le panneau "Reconnaissance automatique" (P15-IA-DEMO,
  /// Volet B) — voir [IaSuggestionPanel]. Même pattern que
  /// [showMetresPanel]/[openMetresPanel]/[closeMetresPanel] ci-dessus.
  bool showIaSuggestionPanel = false;

  void openIaSuggestionPanel() {
    showIaSuggestionPanel = true;
    notifyListeners();
  }

  void closeIaSuggestionPanel() {
    showIaSuggestionPanel = false;
    notifyListeners();
  }

  /// Affiche/masque le panneau "Aperçu d'ambiance IA" (P17-VISUEL) —
  /// même pattern que [showIaSuggestionPanel] ci-dessus. Le panneau
  /// s'ouvre toujours (même si [kAiPreviewEnabled] est faux) : c'est
  /// son propre contenu qui affiche le bouton grisé "fonction bientôt
  /// disponible" dans ce cas, jamais un point d'entrée disparu sans
  /// explication.
  bool showAiAmbiancePanel = false;

  /// Référence produit à pré-sélectionner à l'ouverture du panneau IA —
  /// utilisé par le déclenchement automatique (P20-AUTO) ET par l'icône
  /// générique de la topbar (prefillRef == null dans ce dernier cas),
  /// pour sauter les écrans "choix produit" / "choix scène" quand la
  /// photo ET le produit sont déjà connus.
  String? aiAmbiancePrefillRef;

  /// Si vrai, le panneau IA utilise automatiquement la scène courante du
  /// Studio et lance la génération réelle (proxy Gemini) sans attendre
  /// d'action supplémentaire de l'utilisateur — réservé au déclenchement
  /// automatique (P20-AUTO/P22-HYBRIDE-AUTO), jamais à l'icône générique
  /// de la topbar (qui garde le parcours pas à pas complet, y compris le
  /// choix libre du produit/scène).
  bool aiAmbianceAutoGenerate = false;

  /// P22-HYBRIDE-AUTO — vrai UNIQUEMENT quand le déclenchement
  /// automatique provient de [maybeAutoTriggerHybridAiPreview] (rendu
  /// dynamique déjà composé, renderMode='refine') — jamais pour l'ancien
  /// mécanisme brut [maybeAutoTriggerAiPreview] (non appelé en
  /// production, voir sa docstring) ni pour l'icône manuelle de la
  /// topbar. [AiAmbiancePanel] lit ce champ pour savoir qu'il doit
  /// consommer [consumePendingHybridAutoScene] et forcer
  /// `renderMode: 'refine'`, au lieu du parcours manuel habituel (photo
  /// brute + choix libre 'add'/'refine' par l'utilisateur).
  bool aiAmbianceAutoGenerateHybrid = false;

  /// Vrai pendant qu'une génération IA (déclenchée automatiquement ou
  /// manuellement) est en cours — mis à jour par [AiAmbiancePanel] via
  /// [setAiAmbianceGenerating]. Sert de garde anti-boucle : tant qu'une
  /// génération est en vol, [maybeAutoTriggerAiPreview] ne déclenche
  /// jamais une seconde génération par-dessus.
  bool aiAmbianceGenerating = false;

  void setAiAmbianceGenerating(bool value) {
    aiAmbianceGenerating = value;
    // BUG-1-FIX (STOP-CLIENT-RELEASE) : ce flag pilote désormais AUSSI
    // l'affichage du rendu local RoomPainter (`withProducts` dans
    // `studio_screen.dart`, masqué pendant toute génération distante) —
    // notifyListeners() est donc désormais nécessaire pour que ce
    // changement soit reflété immédiatement à l'écran (avant, ce flag
    // n'était qu'une garde interne anti-boucle, jamais lu par l'UI).
    notifyListeners();
  }

  /// Signature (sku + version de la scène courante) du dernier aperçu IA
  /// déjà déclenché AUTOMATIQUEMENT — protection anti-boucle P20-AUTO :
  /// tant que ni le produit sélectionné ni la photo/scène n'ont changé,
  /// on ne redéclenche jamais la génération, même si `notifyListeners`
  /// est appelé N fois entre-temps (métrés, calibration, etc.).
  String? _lastAiAutoTriggerKey;

  void openAiAmbiancePanel({
    String? prefillRef,
    bool autoGenerate = false,
    bool autoGenerateHybrid = false,
  }) {
    aiAmbiancePrefillRef = prefillRef;
    aiAmbianceAutoGenerate = autoGenerate;
    aiAmbianceAutoGenerateHybrid = autoGenerateHybrid;
    showAiAmbiancePanel = true;
    notifyListeners();
  }

  void closeAiAmbiancePanel() {
    showAiAmbiancePanel = false;
    aiAmbiancePrefillRef = null;
    aiAmbianceAutoGenerate = false;
    aiAmbianceAutoGenerateHybrid = false;
    // Une scène pré-capturée non consommée (ex: panneau fermé avant que
    // _generate() n'ait eu l'occasion de l'utiliser) ne doit jamais
    // fuiter vers une prochaine ouverture manuelle du panneau.
    _pendingHybridAutoScene = null;
    // BUG-3-FIX (STOP-CLIENT-RELEASE) : si le panneau est fermé PENDANT
    // qu'une génération réseau est en vol (widget démonté avant la fin de
    // `_generate()`), ce flag restait bloqué à `true` pour toujours —
    // `maybeAutoTriggerStandardAiPreview` refusait alors silencieusement
    // tout nouveau déclenchement automatique pour le reste de la session
    // (garde `if (aiAmbianceGenerating) return;`), et le rendu local
    // RoomPainter restait masqué indéfiniment (`withProducts` dans
    // `studio_screen.dart`). Le futur `finally` de `_generate()` réécrira
    // `false` de toute façon une fois la requête HTTP terminée (résultat
    // ignoré car le widget n'est plus monté), donc cette remise à zéro
    // immédiate ne peut jamais faire courir deux générations en même temps.
    aiAmbianceGenerating = false;
    notifyListeners();
  }

  /// P20-AUTO (INFRASTRUCTURE DORMANTE — voir [maybeAutoTriggerHybridAiPreview]
  /// pour le mécanisme RÉELLEMENT utilisé en production, brief "nouvelle
  /// règle produit" ci-dessous).
  ///
  /// ⚠️ DÉCISION PRODUIT (mise à jour) : le déclenchement automatique
  /// "brut" ci-dessous — qui ouvrait le panneau IA en pré-remplissant
  /// [aiAmbianceAutoGenerate]=true SANS jamais passer par le rendu
  /// dynamique composé, c'est-à-dire en laissant Gemini "inventer"
  /// entièrement la pose de la corniche depuis la photo brute
  /// (renderMode='add' implicite côté [AiAmbiancePanel._generate]) — a
  /// été jugé trop instable visuellement et RETIRÉ de la production (3
  /// appels supprimés dans [setRoomImageBytes], [loadDemoScene],
  /// [addToProject], voir commit "Retire le declenchement IA
  /// automatique"). Ce n'était PAS un rejet de l'automatisation en
  /// elle-même, mais du mode "Gemini fait tout depuis la photo brute"
  /// sans contrôle géométrique.
  ///
  /// La fonction reste ici, INCHANGÉE et non appelée nulle part dans
  /// lib/ (sauf tests de non-régression), comme trace de cette
  /// architecture antérieure — ne PAS la réappeler en production : voir
  /// [maybeAutoTriggerHybridAiPreview] pour le successeur validé.
  void maybeAutoTriggerAiPreview() {
    if (!kAiPreviewEnabled) return;
    if (roomImage == null) return;
    if (selectedProducts.isEmpty) return;
    if (aiAmbianceGenerating) return;
    if (showAiAmbiancePanel) return; // ne coupe pas un panneau déjà ouvert

    final ref = selectedProducts.first.ref;
    final key = '$ref#$roomImageVersion';
    if (_lastAiAutoTriggerKey == key) return; // déjà généré pour ce couple

    _lastAiAutoTriggerKey = key;
    openAiAmbiancePanel(prefillRef: ref, autoGenerate: true);
  }

  /// P22-HYBRIDE-AUTO (INFRASTRUCTURE DORMANTE — REJETÉE après test
  /// visuel réel, voir décision produit ci-dessous).
  ///
  /// ⚠️ DÉCISION PRODUIT (mise à jour, brief "validation : le mode
  /// hybride auto est rejeté") : ce mécanisme avait été implémenté puis
  /// reconnecté à [setRoomImageBytes]/[loadDemoScene]/[addToProject]
  /// (brief "nouvelle règle produit" précédent), mais un test visuel
  /// réel a montré que Mano/Nano en mode 'refine' sur une capture du
  /// rendu dynamique produit un MAUVAIS RENDU : l'IA affine (améliore le
  /// réalisme de) une scène déjà composée qui peut être géométriquement
  /// imprécise, ce qui AGGRAVE le défaut au lieu de le corriger — pire
  /// visuellement que le rendu dynamique déterministe seul. Les 3 appels
  /// automatiques ont donc été RETIRÉS (voir commentaires dans
  /// [setRoomImageBytes], [loadDemoScene], [addToProject]).
  ///
  /// La fonction reste ici, INCHANGÉE et non appelée nulle part dans
  /// lib/ (sauf tests de non-régression), exactement comme
  /// [maybeAutoTriggerAiPreview] (mode brut, déjà dormant) — ne PAS la
  /// réappeler en production sans une nouvelle validation visuelle
  /// explicite. Mano/Nano reste disponible en mode MANUEL via l'icône
  /// topbar "Aperçu d'ambiance IA" ([openAiAmbiancePanel] sans
  /// `autoGenerateHybrid`), avec `renderMode: 'add'` par défaut sur
  /// photo brute + `control/<sku>.png` — c'est le SEUL rendu visuellement
  /// validé à ce jour. Le mode 'refine'/hybride reste accessible comme
  /// option secondaire dans le panneau ("Scène avec produit déjà posé"),
  /// jamais automatique.
  ///
  /// Documentation du mécanisme conservée ci-dessous pour mémoire (flow
  /// et garde-fous qui restent corrects si ce chantier est un jour
  /// rouvert avec un moteur dynamique plus précis) :
  ///
  /// Flow attendu (NON appliqué en production) :
  ///   1. l'utilisateur importe une photo ;
  ///   2. l'utilisateur choisit un produit (SKU whitelisté) ;
  ///   3. le moteur dynamique déterministe (RoomPainter/
  ///      cornice_plinth_painter, JAMAIS modifié ici) pose le produit
  ///      immédiatement, comme aujourd'hui ;
  ///   4. DÈS QUE la capture de cette scène composée est disponible
  ///      ([captureComposedScene]), l'app envoie AUTOMATIQUEMENT ce
  ///      rendu (pas la photo brute) au proxy Nano/Mano avec
  ///      `renderMode: 'refine'` ;
  ///   5. l'image IA s'affiche quand elle est prête, en tâche de fond —
  ///      sans bouton "Générer", sans que l'utilisateur ait à choisir
  ///      entre "add"/"refine"/"scène composée".
  ///
  /// Garde-fous (TOUTES les conditions doivent être réunies, sinon
  /// retour immédiat sans effet — jamais de génération "best effort") :
  ///  1. [kAiPreviewEnabled] doit être vrai ;
  ///  2. une photo/scène doit être chargée ([roomImage] non null) ;
  ///  3. au moins un produit doit être sélectionné
  ///     ([selectedProducts]) ;
  ///  4. le SKU du produit doit être whitelisté (présent dans
  ///     `assets/profiles/index.json`, voir [CatalogueVisibilityGate])
  ///     — mêmes 43 refs qualifiées que le reste du catalogue
  ///     présentation, jamais un SKU hors gate ;
  ///  5. aucune génération ne doit déjà être en cours
  ///     ([aiAmbianceGenerating]) — anti-chevauchement ;
  ///  6. le couple (SKU, [roomImageVersion], 'refine') ne doit PAS être
  ///     strictement identique au dernier couple déjà déclenché
  ///     ([_lastHybridAutoTriggerKey]) — anti-boucle : changer de photo
  ///     OU de produit relance une génération, le reste (métrés,
  ///     calibration manuelle, notifyListeners répétés) jamais ;
  ///  7. la capture de la scène composée
  ///     ([captureComposedScene]) doit RÉUSSIR (bytes non nuls) — si le
  ///     Studio n'est pas encore monté ou que la capture échoue, on
  ///     abandonne silencieusement CETTE tentative (la clé anti-boucle
  ///     n'est marquée qu'après un succès, donc une prochaine
  ///     notification pourra retenter).
  ///
  /// En cas d'échec de génération côté proxy/Gemini (429, réseau,
  /// timeout...), le rendu dynamique déterministe reste affiché tel
  /// quel dans le Studio dès la fermeture du panneau : [AiAmbiancePanel]
  /// gère déjà cet échec avec son propre écran fallback ("Réessayer" /
  /// fermer), jamais un crash ni un état bloquant — voir [_generate]
  /// dans `ai_ambiance_panel.dart`.
  String? _lastHybridAutoTriggerKey;

  /// Vrai UNIQUEMENT pendant qu'une capture de scène composée est en
  /// cours de résolution pour le déclenchement automatique hybride —
  /// distinct de [aiAmbianceGenerating] (qui couvre l'appel réseau lui-
  /// même) : évite de lancer deux captures concurrentes si
  /// `notifyListeners` est appelé plusieurs fois pendant l'attente de
  /// [captureComposedScene].
  bool _hybridAutoCaptureInFlight = false;

  void maybeAutoTriggerHybridAiPreview() {
    if (!kAiPreviewEnabled) return;
    if (roomImage == null) return;
    if (selectedProducts.isEmpty) return;
    if (aiAmbianceGenerating) return;
    if (_hybridAutoCaptureInFlight) return;

    final ref = selectedProducts.first.ref;

    // Garde whitelist SKU — même source que le reste du catalogue
    // présentation (assets/profiles/index.json). `null` = index pas
    // encore chargé : on ne bloque PAS dans ce cas précis (fail-open,
    // cohérent avec [applyPresentationVisibility]) mais on attend que
    // l'appelant renotifie une fois l'index chargé plutôt que de
    // marquer la clé anti-boucle prématurément.
    final visible = CatalogueVisibilityGate.instance.presentationVisible(ref);
    if (visible == false) return; // SKU explicitement hors whitelist

    final key = '$ref#$roomImageVersion#refine';
    if (_lastHybridAutoTriggerKey == key) return; // déjà généré pour ce couple

    _hybridAutoCaptureInFlight = true;
    // La capture (RepaintBoundary → toImage → crop sur imgDraw, voir
    // studio_screen.dart) n'est disponible qu'APRÈS que le premier
    // frame du Studio ait posé le produit — on laisse donc passer un
    // frame avant de tenter la capture, pour laisser RoomPainter
    // dessiner la corniche fraîchement sélectionnée avant d'en prendre
    // un instantané (sinon on capturerait la scène SANS le produit).
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      Uint8List? composedBytes;
      try {
        composedBytes = await captureComposedScene();
      } finally {
        _hybridAutoCaptureInFlight = false;
      }
      if (composedBytes == null) return; // Studio pas encore monté / échec capture
      if (aiAmbianceGenerating) return; // une génération a démarré entre-temps
      // Re-vérifie que rien n'a changé pendant l'attente de la capture
      // (photo remplacée, produit changé) avant de marquer la clé et de
      // déclencher — sinon on capturerait/enverrait une scène périmée.
      if (selectedProducts.isEmpty || selectedProducts.first.ref != ref) return;
      final currentKey = '$ref#$roomImageVersion#refine';
      if (currentKey != key) return; // scène/produit a changé entre-temps
      if (_lastHybridAutoTriggerKey == currentKey) return;

      _lastHybridAutoTriggerKey = currentKey;
      _pendingHybridAutoScene = composedBytes;
      openAiAmbiancePanel(prefillRef: ref, autoGenerate: true, autoGenerateHybrid: true);
    });
  }

  /// Bytes de la scène composée déjà capturée par
  /// [maybeAutoTriggerHybridAiPreview], consommés une seule fois par
  /// [AiAmbiancePanel] (voir [consumePendingHybridAutoScene]) — évite de
  /// recapturer une deuxième fois la même scène (potentiellement
  /// différente si le layout a changé entre-temps) juste après l'avoir
  /// déjà obtenue ici pour évaluer la clé anti-boucle.
  Uint8List? _pendingHybridAutoScene;

  /// Consomme (et efface) la scène composée pré-capturée par le
  /// déclenchement automatique hybride — `null` si aucun déclenchement
  /// automatique n'est en cours (ex: ouverture manuelle classique de
  /// l'icône topbar).
  Uint8List? consumePendingHybridAutoScene() {
    final bytes = _pendingHybridAutoScene;
    _pendingHybridAutoScene = null;
    return bytes;
  }

  /// P23-STANDARD-AUTO — brief "Correction finale du flow produit : le
  /// rendu IA validé est le MODE STANDARD".
  ///
  /// SEUL mécanisme d'auto-déclenchement IA appelé en production (voir
  /// [setRoomImageBytes] et [addToProject]). Contrairement à
  /// [maybeAutoTriggerHybridAiPreview] (REJETÉ, voir sa docstring), ce
  /// mécanisme n'utilise JAMAIS [captureComposedScene] : il envoie
  /// TOUJOURS la photo BRUTE courante ([roomImage]) au proxy Nano/Mano,
  /// avec `renderMode: 'add'` (Gemini ajoute lui-même la corniche
  /// `control/<sku>.png` depuis zéro) — c'est le SEUL rendu validé
  /// visuellement à ce jour.
  ///
  /// Flow :
  ///   1. l'utilisateur importe une photo, ou sélectionne/ajoute un
  ///      produit sur une photo déjà chargée ;
  ///   2. après un court [debounce] (évite de facturer une génération
  ///      par SKU parcouru rapidement, ex: scroll produit) ;
  ///   3. le panneau IA s'ouvre automatiquement et lance directement la
  ///      génération réelle sur la photo brute + `renderMode: 'add'` —
  ///      aucun bouton "Générer" à cliquer ;
  ///   4. le résultat s'affiche avec le badge "MODE STANDARD — corniche
  ///      ajoutée depuis photo brute" ([AiAmbiancePanel], voir
  ///      [aiAmbianceAutoGenerate]==true && [aiAmbianceAutoGenerateHybrid]
  ///      ==false) ;
  ///   5. en cas d'échec proxy/Gemini, le rendu dynamique déterministe
  ///      (RoomPainter) reste affiché tel quel — jamais de crash, voir
  ///      l'écran fallback existant de [AiAmbiancePanel].
  ///
  /// [ref] — la référence QUI VIENT D'ÊTRE sélectionnée par
  /// l'utilisateur (passée explicitement par l'appelant), JAMAIS
  /// `selectedProducts.first.ref` : un utilisateur qui a déjà 2 produits
  /// dans des familles différentes puis en change un doit voir l'IA
  /// réagir au produit qu'il vient de toucher, pas au premier de la
  /// liste (qui peut être un tout autre SKU choisi il y a longtemps).
  ///
  /// Garde-fous (TOUTES les conditions doivent être réunies) :
  ///  1. [kAiPreviewEnabled] doit être vrai ;
  ///  2. une photo doit être chargée ([roomImage] non null) ;
  ///  3. [ref] doit être whitelisté (`assets/profiles/index.json`, voir
  ///     [CatalogueVisibilityGate]) — jamais de `clientPrompt` libre, le
  ///     serveur reconstruit tout depuis `sku` + gabarit fixe ;
  ///  4. aucune génération ne doit déjà être en cours
  ///     ([aiAmbianceGenerating]) — anti-chevauchement ;
  ///  5. le couple (`ref`, [roomImageVersion], 'add') ne doit pas être
  ///     strictement identique au dernier couple déjà déclenché — cache
  ///     anti-boucle par clé `roomImageVersion#sku#add`
  ///     ([_lastStandardAutoTriggerKey]) ;
  ///  6. un quota maximum de générations automatiques par JOUR
  ///     CALENDAIRE, persisté ([_standardAutoTriggerCount] <
  ///     [kMaxStandardAutoTriggersPerDay])
  ///     ne doit pas être dépassé — anti-coût minimal : au-delà, l'IA
  ///     automatique s'arrête silencieusement (le rendu dynamique reste
  ///     affiché), l'utilisateur garde toujours l'accès MANUEL via
  ///     l'icône topbar.
  ///
  /// [debounce] : un changement rapproché de SKU (ex: l'utilisateur
  /// clique D520 puis D545 puis D609 en moins de 2 secondes) annule
  /// systématiquement la tentative précédente encore en attente — SEUL
  /// le dernier SKU sélectionné après [kStandardAutoTriggerDebounce]
  /// sans nouveau changement part effectivement en génération. Implanté
  /// via un simple `Timer` annulé/relancé à chaque appel (voir
  /// [_standardAutoTriggerDebounce]).
  static const Duration kStandardAutoTriggerDebounce = Duration(milliseconds: 1500);

  /// Nombre maximum de générations IA STANDARD auto-déclenchées par JOUR
  /// CALENDAIRE (et non plus par "session applicative" — voir CORRECTIF
  /// ci-dessous). Persisté dans `shared_preferences` sous une clé DATÉE
  /// ([_standardAutoTriggerPrefsKey]) : le quota se remet naturellement
  /// à 0 au changement de jour calendaire, indépendamment du nombre de
  /// fois où [AppState] est recréé (ex: rechargements successifs de la
  /// page web le même jour ne "remboursent" jamais le quota). Anti-coût
  /// minimal viable, voir docstring de [maybeAutoTriggerStandardAiPreview].
  /// Ne bloque JAMAIS le parcours manuel (icône topbar), uniquement
  /// l'automatique.
  ///
  /// RENOMMAGE (brief "rename quota PerDay") : cette constante s'appelait
  /// à l'origine `kMaxStandardAutoTriggersPerSession`, nom devenu
  /// trompeur dès l'introduction de la persistance `shared_preferences`
  /// par clé datée (voir [_standardAutoTriggerCount]) — le quota n'a
  /// jamais été "par session applicative" une fois cette persistance en
  /// place, mais bien "par jour calendaire". Renommé en
  /// `kMaxStandardAutoTriggersPerDay` pour refléter la sémantique réelle.
  static const int kMaxStandardAutoTriggersPerDay = 10;

  /// TEST-ONLY (jamais lu/modifié en dehors des tests) : permet de
  /// couper le bruit des logs `[AI_AUTO_STANDARD]` dans les suites de
  /// tests qui exercent volontairement de nombreux appels à
  /// [maybeAutoTriggerStandardAiPreview] (ex: épuisement du quota
  /// jour/session) — ces logs restent utiles en debug réel (`flutter
  /// run`) mais polluent la sortie de `flutter test` sans apporter
  /// d'information supplémentaire dans ces cas précis. `true` par
  /// défaut : ne change RIEN au comportement hors tests.
  @visibleForTesting
  static bool debugAiAutoStandardLogsEnabled = true;

  /// CORRECTIF (brief "Persist quota SharedPreferences") : un compteur
  /// purement en mémoire est réinitialisé à 0 à chaque F5/rechargement de
  /// la page web — sur le web, [AppState] est reconstruit à chaque
  /// rechargement, contrairement à une "vraie session" mobile. Sans
  /// persistance, un utilisateur (ou un test manuel) qui recharge la
  /// page peut redéclencher indéfiniment des générations facturées en
  /// contournant le quota. Le compteur est donc lu/écrit dans
  /// `shared_preferences` sous une clé DATÉE (`ai_auto_standard_count_
  /// YYYY-MM-DD`, voir [_standardAutoTriggerPrefsKey]) : le quota se
  /// remet naturellement à 0 chaque nouveau jour calendaire, sans avoir
  /// besoin d'un mécanisme de purge séparé.
  int _standardAutoTriggerCount = 0;

  /// Vrai une fois [_standardAutoTriggerCount] effectivement chargé
  /// depuis `shared_preferences` pour la clé du jour courant — tant que
  /// c'est faux, la valeur en mémoire (0 par défaut) peut être
  /// temporairement inexacte ; voir [_ensureStandardAutoTriggerCountLoaded].
  bool _standardAutoTriggerCountLoaded = false;

  /// Évite les lectures concurrentes de `shared_preferences` si
  /// [maybeAutoTriggerStandardAiPreview] est appelée plusieurs fois avant
  /// la fin du premier chargement (ex: plusieurs taps rapides avant même
  /// l'expiration du debounce).
  Future<void>? _standardAutoTriggerCountLoading;

  /// Clé `shared_preferences` du quota auto-IA STANDARD pour AUJOURD'HUI
  /// (heure locale de l'appareil) — voir docstring de
  /// [_standardAutoTriggerCount].
  String _standardAutoTriggerPrefsKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return 'ai_auto_standard_count_$y-$m-$day';
  }

  /// Charge (une seule fois par jour calendaire) le compteur persisté
  /// depuis `shared_preferences` dans [_standardAutoTriggerCount]. Appelé
  /// en "fire-and-forget" dès le premier appel de
  /// [maybeAutoTriggerStandardAiPreview] ; le [Timer] de debounce (1,5 s)
  /// laisse largement le temps à cette lecture asynchrone de se terminer
  /// avant que le contrôle de quota AUTORITAIRE (dans le callback du
  /// Timer, voir plus bas) ne s'exécute réellement.
  Future<void> _ensureStandardAutoTriggerCountLoaded() async {
    if (_standardAutoTriggerCountLoaded) return;
    if (_standardAutoTriggerCountLoading != null) {
      await _standardAutoTriggerCountLoading;
      return;
    }
    final completer = Completer<void>();
    _standardAutoTriggerCountLoading = completer.future;
    try {
      final prefs = await SharedPreferences.getInstance();
      _standardAutoTriggerCount = prefs.getInt(_standardAutoTriggerPrefsKey()) ?? 0;
    } catch (_) {
      _standardAutoTriggerCount = 0;
    } finally {
      _standardAutoTriggerCountLoaded = true;
      completer.complete();
    }
  }

  /// Persiste [_standardAutoTriggerCount] AVANT d'ouvrir le panneau IA
  /// (donc avant tout appel réseau vers le proxy Gemini) — garantit qu'un
  /// rechargement de page juste après une génération auto ne "rembourse"
  /// jamais artificiellement le quota du jour.
  Future<void> _persistStandardAutoTriggerCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_standardAutoTriggerPrefsKey(), _standardAutoTriggerCount);
    } catch (_) {
      // stockage indisponible — comportement dégradé mais non bloquant,
      // identique au reste de la persistance de cette classe (voir [save]).
    }
  }

  /// Signature (`sku#roomImageVersion#add`) du dernier aperçu IA
  /// STANDARD déjà déclenché AUTOMATIQUEMENT — anti-boucle : tant que ni
  /// le SKU ni la photo n'ont changé, on ne redéclenche jamais.
  String? _lastStandardAutoTriggerKey;

  Timer? _standardAutoTriggerDebounce;

  /// BUG-1-FIX (STOP-CLIENT-RELEASE) : vrai pendant la fenêtre de debounce
  /// (1,5 s, [kStandardAutoTriggerDebounce]) entre le tap produit dans le
  /// strip Studio et l'ouverture EFFECTIVE du panneau "Aperçu d'ambiance"
  /// (ou l'abandon silencieux si un garde-fou bloque le déclenchement).
  /// Consulté par `studio_screen.dart` (aux côtés de [showAiAmbiancePanel]
  /// et [aiAmbianceGenerating]) pour masquer le rendu local RoomPainter du
  /// produit pendant CETTE fenêtre courte : sans cela, le produit qui vient
  /// d'être ajouté à [selectedProducts] par `addToProject` resterait
  /// visible localement pendant ~1,5 s avant que le panneau ne s'ouvre,
  /// violant la règle "jamais de tentative de pose locale visible avant le
  /// retour distant". Toujours remis à `false` avant la fin du callback du
  /// [Timer], que le déclenchement aboutisse ou soit abandonné.
  bool pendingStandardAutoTrigger = false;

  @visibleForTesting
  void disposeStandardAutoTriggerDebounceForTesting() {
    _standardAutoTriggerDebounce?.cancel();
    _standardAutoTriggerDebounce = null;
    pendingStandardAutoTrigger = false;
  }

  /// Réinitialise l'état du quota EN MÉMOIRE (pas dans
  /// `shared_preferences`) pour permettre à un test de repartir d'un
  /// chargement propre — utile pour tester le comportement de
  /// [_ensureStandardAutoTriggerCountLoaded] sur une nouvelle instance
  /// [AppState] simulant un rechargement de page le même jour.
  @visibleForTesting
  void resetStandardAutoTriggerQuotaForTesting() {
    _standardAutoTriggerCount = 0;
    _standardAutoTriggerCountLoaded = false;
    _standardAutoTriggerCountLoading = null;
  }

  /// Attend explicitement la fin du chargement du quota persisté —
  /// réservé aux tests qui doivent vérifier une valeur de
  /// [_standardAutoTriggerCount] déjà chargée depuis
  /// `shared_preferences` sans dépendre du timing du debounce.
  @visibleForTesting
  Future<void> ensureStandardAutoTriggerQuotaLoadedForTesting() =>
      _ensureStandardAutoTriggerCountLoaded();

  void maybeAutoTriggerStandardAiPreview({required String ref}) {
    if (kDebugMode && debugAiAutoStandardLogsEnabled) {
      debugPrint('[AI_AUTO_STANDARD] called ref=$ref '
          'hasRoom=${roomImage != null} '
          'generating=$aiAmbianceGenerating '
          'visible=${CatalogueVisibilityGate.instance.presentationVisible(ref)} '
          'version=$roomImageVersion '
          'enabled=$kAiPreviewEnabled '
          'countLoaded=$_standardAutoTriggerCountLoaded '
          'count=$_standardAutoTriggerCount/$kMaxStandardAutoTriggersPerDay');
    }
    if (!kAiPreviewEnabled) {
      if (kDebugMode && debugAiAutoStandardLogsEnabled) {
        debugPrint('[AI_AUTO_STANDARD] skip: disabled');
      }
      return;
    }
    if (roomImage == null) {
      if (kDebugMode && debugAiAutoStandardLogsEnabled) {
        debugPrint('[AI_AUTO_STANDARD] skip: no room image');
      }
      return;
    }

    // Garde whitelist SKU — même source que le reste du catalogue
    // présentation. `null` = index pas encore chargé : fail-open (on ne
    // bloque pas), cohérent avec [applyPresentationVisibility] et
    // [maybeAutoTriggerHybridAiPreview].
    final visible = CatalogueVisibilityGate.instance.presentationVisible(ref);
    if (visible == false) {
      if (kDebugMode && debugAiAutoStandardLogsEnabled) {
        debugPrint('[AI_AUTO_STANDARD] skip: unsupported sku ref=$ref');
      }
      return; // SKU explicitement hors whitelist
    }

    // CORRECTIF (brief "Persist quota SharedPreferences") : lance (sans
    // attendre) le chargement du quota persisté du jour — le debounce de
    // 1,5 s ci-dessous laisse largement le temps à cette lecture (rapide,
    // shared_preferences) de se terminer avant le contrôle AUTORITAIRE
    // fait dans le callback du Timer.
    unawaited(_ensureStandardAutoTriggerCountLoaded());

    final key = '$ref#$roomImageVersion#add';
    if (_lastStandardAutoTriggerKey == key) {
      if (kDebugMode && debugAiAutoStandardLogsEnabled) {
        debugPrint('[AI_AUTO_STANDARD] skip: already generated key=$key');
      }
      return; // déjà généré pour ce couple
    }
    if (_standardAutoTriggerCountLoaded &&
        _standardAutoTriggerCount >= kMaxStandardAutoTriggersPerDay) {
      // Pré-contrôle rapide (uniquement si le quota est déjà chargé) —
      // évite de programmer un Timer pour rien. Le contrôle AUTORITAIRE
      // (après chargement garanti) est refait dans le callback ci-dessous
      // de toute façon.
      if (kDebugMode && debugAiAutoStandardLogsEnabled) {
        debugPrint('[AI_AUTO_STANDARD] skip: quota reached');
      }
      return;
    }

    // Debounce : un nouvel appel (changement rapide de SKU) annule
    // systématiquement la tentative précédente encore en attente.
    _standardAutoTriggerDebounce?.cancel();
    // BUG-1-FIX (STOP-CLIENT-RELEASE) : le produit vient d'être ajouté à
    // [selectedProducts] (par [addToProject], juste avant cet appel) —
    // sans ce flag, le rendu local RoomPainter l'afficherait déjà pendant
    // toute la fenêtre de debounce ci-dessous, avant même que le panneau
    // ne s'ouvre. `notifyListeners()` déclenche le rebuild immédiat de
    // `studio_screen.dart` (qui consulte ce champ pour `withProducts`).
    pendingStandardAutoTrigger = true;
    notifyListeners();
    _standardAutoTriggerDebounce = Timer(kStandardAutoTriggerDebounce, () async {
      // Contrôle AUTORITAIRE du quota : on attend ici la fin du
      // chargement lancé plus haut (déjà terminé dans l'écrasante
      // majorité des cas, le debounce ayant laissé le temps) avant de
      // décider quoi que ce soit — jamais de quota approximatif basé sur
      // une valeur par défaut (0) pas encore relue depuis le disque.
      await _ensureStandardAutoTriggerCountLoaded();

      if (!kAiPreviewEnabled) {
        if (kDebugMode && debugAiAutoStandardLogsEnabled) {
          debugPrint('[AI_AUTO_STANDARD] skip: disabled');
        }
        pendingStandardAutoTrigger = false;
        notifyListeners();
        return;
      }
      if (roomImage == null) {
        if (kDebugMode && debugAiAutoStandardLogsEnabled) {
          debugPrint('[AI_AUTO_STANDARD] skip: no room image');
        }
        pendingStandardAutoTrigger = false;
        notifyListeners();
        return;
      }
      if (aiAmbianceGenerating) {
        if (kDebugMode && debugAiAutoStandardLogsEnabled) {
          debugPrint('[AI_AUTO_STANDARD] skip: generation already running');
        }
        pendingStandardAutoTrigger = false;
        notifyListeners();
        return;
      }
      final currentKey = '$ref#$roomImageVersion#add';
      if (currentKey != key) {
        pendingStandardAutoTrigger = false;
        notifyListeners();
        return; // photo/version a changé entre-temps
      }
      if (_lastStandardAutoTriggerKey == currentKey) {
        if (kDebugMode && debugAiAutoStandardLogsEnabled) {
          debugPrint('[AI_AUTO_STANDARD] skip: already generated key=$currentKey');
        }
        pendingStandardAutoTrigger = false;
        notifyListeners();
        return;
      }
      if (_standardAutoTriggerCount >= kMaxStandardAutoTriggersPerDay) {
        if (kDebugMode && debugAiAutoStandardLogsEnabled) {
          debugPrint('[AI_AUTO_STANDARD] skip: quota reached');
        }
        pendingStandardAutoTrigger = false;
        notifyListeners();
        return;
      }

      _lastStandardAutoTriggerKey = currentKey;
      _standardAutoTriggerCount++;
      // Persisté AVANT l'ouverture du panneau (donc avant tout appel
      // réseau vers le proxy Gemini) — voir docstring de
      // [_persistStandardAutoTriggerCount].
      await _persistStandardAutoTriggerCount();
      if (kDebugMode && debugAiAutoStandardLogsEnabled) {
        debugPrint('[AI_AUTO_STANDARD] opening panel ref=$ref key=$currentKey '
            'count=$_standardAutoTriggerCount/$kMaxStandardAutoTriggersPerDay');
      }
      // Le panneau (showAiAmbiancePanel, mis à `true` par
      // [openAiAmbiancePanel] ci-dessous) prend le relais de
      // [pendingStandardAutoTrigger] pour masquer le rendu local — safe de
      // le redescendre à `false` ici avant l'ouverture effective.
      pendingStandardAutoTrigger = false;
      // autoGenerateHybrid volontairement absent (défaut false) :
      // AiAmbiancePanel utilisera _useCurrentScene() (photo brute) +
      // _generate() -> renderMode='add' (resolveRenderModeForScene),
      // jamais captureComposedScene().
      openAiAmbiancePanel(prefillRef: ref, autoGenerate: true);
    });
  }

  /// Dernier aperçu IA généré avec succès — stocké ici (et non plus
  /// gardé uniquement en état local éphémère de [AiAmbiancePanel]) pour
  /// que l'écran Avant/Après (Comparateur) puisse afficher photo
  /// originale vs image IA générée SANS relancer Gemini. Voir
  /// [setLastAiComparisonResult].
  AiComparisonResult? lastAiComparisonResult;

  /// Enregistre le résultat d'une génération IA réussie — appelé
  /// uniquement par [AiAmbiancePanel] après une réponse `ok` du proxy
  /// `/api/ai-render`, jamais recalculé/deviné ici. [originalImageBytes]
  /// est la MÊME photo/scène envoyée au proxy (avant génération), pour
  /// un vrai comparatif avant/après cohérent.
  void setLastAiComparisonResult(AiComparisonResult result) {
    lastAiComparisonResult = result;
    notifyListeners();
  }

  /// Dernier rendu d'ambiance IA DISTANT réussi — DIFFÉRENT de
  /// [lastAiComparisonResult] (utilisé uniquement par le Comparateur
  /// Avant/Après). Ce champ pilote la vue PRINCIPALE du Studio
  /// (`_PhotoZone` dans `studio_screen.dart`) : quand il est non-null,
  /// il devient l'image affichée en Studio, y compris APRÈS fermeture
  /// du panneau [AiAmbiancePanel] — c'est tout l'objet de ce mécanisme
  /// (brief "persistance propre du rendu d'aperçu").
  ///
  /// ⚠️ RÈGLE CRITIQUE — séparation stricte source de vérité / vue
  /// affichée :
  ///   - [roomImage] reste TOUJOURS la source de vérité pour tout futur
  ///     appel IA (voir [AiAmbiancePanel._useCurrentScene], qui encode
  ///     `state.roomImage`, jamais ce champ) — sinon un deuxième appel
  ///     travaillerait sur une image déjà transformée par Gemini, avec
  ///     dégradation progressive au fil des appels successifs.
  ///   - Ce champ n'est QUE visuel : `PhotoZone display image =
  ///     currentAmbiancePreviewBytes ?? roomImage`.
  ///
  /// Cycle de vie (voir [setCurrentAmbiancePreview] /
  /// [clearCurrentAmbiancePreview]) :
  ///   - rempli uniquement par [AiAmbiancePanel._generate] au succès
  ///     d'une génération RÉELLE (jamais pour le mock local) ;
  ///   - vidé par [AiAmbiancePanel._reset] (changement de produit,
  ///     "Nouvel aperçu", "Réessayer") ;
  ///   - vidé par [setRoomImageBytes]/[loadDemoScene] (import photo ou
  ///     changement de scène démo) ;
  ///   - JAMAIS vidé par [closeAiAmbiancePanel] : la fermeture du
  ///     panneau ne doit PAS faire disparaître le rendu affiché.
  Uint8List? currentAmbiancePreviewBytes;

  /// Enregistre le dernier rendu d'ambiance IA distant réussi comme vue
  /// principale du Studio — voir docstring de
  /// [currentAmbiancePreviewBytes].
  void setCurrentAmbiancePreview(Uint8List bytes) {
    currentAmbiancePreviewBytes = bytes;
    notifyListeners();
  }

  /// Supprime le rendu d'ambiance IA distant actuellement affiché en vue
  /// principale du Studio — appelé à chaque changement de produit
  /// (avant un nouvel appel) et à chaque changement/import de scène
  /// (photo importée ou scène démo). No-op silencieux si déjà `null`
  /// (safe à appeler systématiquement, sans vérification préalable par
  /// l'appelant).
  void clearCurrentAmbiancePreview() {
    if (currentAmbiancePreviewBytes == null) return;
    currentAmbiancePreviewBytes = null;
    notifyListeners();
  }

  /// P21-HYBRIDE — capture de la scène TELLE QU'AFFICHÉE dans le Studio
  /// (photo + corniche déjà placée par le moteur dynamique déterministe
  /// RoomPainter), enregistrée par [_StudioScreenState] via
  /// [registerComposedSceneCapture] dès que le widget `_PhotoZone` est
  /// monté (RepaintBoundary autour du CustomPaint existant — AUCUNE
  /// modification du moteur RoomPainter lui-même).
  ///
  /// [AiAmbiancePanel] appelle cette fonction (au lieu de relire
  /// `roomImage.toByteData` comme pour la scène brute) uniquement pour
  /// la nouvelle option "Scène avec produit déjà posé" du mode hybride
  /// (renderMode='refine') — jamais pour le flux existant (renderMode=
  /// 'add', scène brute inchangée).
  ///
  /// Null tant que le Studio n'a pas encore été construit à l'écran
  /// (ex: panneau IA ouvert avant tout rendu) — l'appelant doit gérer ce
  /// cas comme un échec de capture, jamais un crash.
  Future<Uint8List?> Function()? _composedSceneCapture;

  void registerComposedSceneCapture(Future<Uint8List?> Function()? capture) {
    _composedSceneCapture = capture;
    // Pas de notifyListeners — pure référence technique, ne pilote aucun
    // affichage.
  }

  Future<Uint8List?> captureComposedScene() async {
    final capture = _composedSceneCapture;
    if (capture == null) return null;
    try {
      return await capture();
    } catch (_) {
      return null;
    }
  }

  /// Vrai si [productModalQte] est une estimation par défaut (aucun métré
  /// saisi pour cette pièce) plutôt qu'une quantité calculée à partir des
  /// dimensions réelles — utilisé par la modal produit pour afficher un
  /// message d'invite ("Saisissez les métrés…") au lieu d'un prix à 0,00 €
  /// qui donnait l'impression d'une application cassée.
  bool productModalQteEstimated = false;

  /* ── Helpers lecture rapide ── */

  /// Nombre total de produits dans le projet
  int get nbProds => selectedProducts.length;

  /// Total HT estimé (sans marge de coupe, prix catalogue brut)
  ///
  /// ⚠️ CORRECTION même bug que [calcLigne] (voir chiffrage.dart) :
  /// `getPrixInfo(item.famille)` retombait toujours sur le prix
  /// générique par famille au lieu du vrai prix du produit (`item.ref`).
  double get totalHtBrut => selectedProducts.fold<double>(0, (acc, item) {
    final px = getPrixInfo(item.ref);
    return acc + (px != null ? px.prix * item.qte : 0);
  });

  /// Retourne l'item du projet correspondant à une ref, ou null.
  ProjectItem? getProdInProject(String ref) {
    for (final p in selectedProducts) {
      if (p.ref == ref) return p;
    }
    return null;
  }

  /// Ajoute ou met à jour un produit dans le projet.
  void upsertProd(String ref, String famille, double qte, String unite) {
    final idx = selectedProducts.indexWhere((p) => p.ref == ref);
    if (idx >= 0) {
      selectedProducts[idx] = selectedProducts[idx].copyWith(
        qte: qte,
        unite: unite,
      );
    } else {
      selectedProducts.add(
        ProjectItem(ref: ref, famille: famille, qte: qte, unite: unite),
      );
    }
    notifyListeners();
    save();
  }

  /// Retire un produit du projet (et sa position de snap).
  ///
  /// CORRECTIF (brief "removeProd doit reset studioSelected") : sans ce
  /// reset, [studioSelected] pouvait continuer à pointer vers une ref
  /// qui n'est PLUS dans [selectedProducts] après un retrait (ex:
  /// quickToggleProd(D609) en retrait). Un import de photo juste après
  /// (`setRoomImageBytes`) lirait alors `studioSelected` (toujours
  /// "D609") comme référence active et déclencherait une génération IA
  /// AUTOMATIQUE — donc FACTURÉE — sur un produit que l'utilisateur
  /// vient explicitement de retirer du projet. Voir aussi le
  /// blindage supplémentaire dans [setRoomImageBytes] (double
  /// protection : ce reset ICI, + une revérification d'appartenance à
  /// [selectedProducts] au moment de lire `studioSelected`).
  void removeProd(String ref) {
    selectedProducts = selectedProducts.where((p) => p.ref != ref).toList();
    prodPositions.remove(ref);
    if (studioSelected == ref) {
      studioSelected = null;
    }
    notifyListeners();
    save();
  }

  /// Enregistre la position de snap d'un produit sur la photo.
  void setSnapPos(String ref, String snapLine, double xPct) {
    prodPositions[ref] = SnapPos(snapLine: snapLine, xPct: xPct);
    notifyListeners();
    save();
  }

  /// Retourne la position de snap d'un produit, ou null.
  SnapPos? getSnapPos(String ref) => prodPositions[ref];

  /* ── Métrés ── */

  /// Recalcule périmètre/périmètre net/surface à partir des champs saisis
  /// et met à jour l'état. Équivalent de `chiffrage.computeMetres()`.
  MetresResult computeAndStoreMetres() {
    final r = computeMetres(
      metresMurA: metresMurA,
      metresMurB: metresMurB,
      metresHauteur: metresHauteur,
      metresPortes: metresPortes,
      metresFenetres: metresFenetres,
    );
    metresPerimetre = r.perimetre;
    metresPerimetreNet = r.perimetreNet;
    metresSurface = r.surface;
    notifyListeners();
    return r;
  }

  /// Applique les champs de métrés saisis (panel) et recalcule.
  void applyMetres({
    required double murA,
    required double murB,
    required double hauteur,
    required double portes,
    required double fenetres,
  }) {
    metresMurA = murA;
    metresMurB = murB;
    metresHauteur = hauteur;
    metresPortes = portes;
    metresFenetres = fenetres;
    computeAndStoreMetres();
    save();
  }

  /* ── Ajout produit au projet (CORRECTION Bug #7) ── */

  /// Ajoute un produit au projet en appliquant :
  /// 1. La règle métier "1 produit par famille en studio" (retire tout
  ///    autre produit de la même famille avant d'ajouter — logique
  ///    confirmée correcte lors de l'audit, conservée à l'identique).
  /// 2. La quantité par défaut basée sur les MÉTRÉS RÉELS de la pièce
  ///    (`getQteNetteForFamille`), et non plus une valeur codée en dur.
  ///
  /// [qteOverride] permet de forcer une quantité explicite (ex: saisie
  /// manuelle dans la modal produit) au lieu du calcul auto depuis les
  /// métrés.
  void addToProject(String ref, {double? qteOverride}) {
    final prod = getProdByRef(ref);
    if (prod == null) return;

    // Règle "1 produit par famille en studio" : retire les autres produits
    // de la même famille avant d'ajouter le nouveau.
    selectedProducts = selectedProducts
        .where((p) => p.famille != prod.famille)
        .toList();

    final metres = computeAndStoreMetres();
    final qte =
        qteOverride ?? qteNetteAvecFallback(prod.famille, prod.unite, metres);

    selectedProducts.add(
      ProjectItem(ref: ref, famille: prod.famille, qte: qte, unite: prod.unite),
    );
    // [ref] devient le produit "actif" du strip Studio — c'est la SEULE
    // écriture de [studioSelected] dans tout le code (champ déclaré mais
    // jamais assigné auparavant, ce qui rendait tout usage de
    // `studioSelected ?? ...` illusoire). Centraliser ici garantit que
    // [studioSelected] reflète toujours la dernière ref réellement
    // ajoutée/activée par l'utilisateur, quel que soit le point d'entrée
    // UI (quickToggleProd, product_modal, future évolutions).
    studioSelected = ref;
    notifyListeners();
    save();
    // P22-HYBRIDE-AUTO — RETIRÉ (voir docstring de
    // [maybeAutoTriggerHybridAiPreview]) : rejet visuel confirmé par
    // test réel, jamais de captureComposedScene() ici.
    //
    // P23-STANDARD-AUTO — [ref] est la référence QUI VIENT D'ÊTRE
    // ajoutée par l'utilisateur (paramètre de cette fonction), JAMAIS
    // `selectedProducts.first.ref` : voir docstring de
    // [maybeAutoTriggerStandardAiPreview] pour la justification et
    // tous les garde-fous (whitelist, anti-boucle, debounce, quota
    // session) — ne déclenche que si une photo est déjà chargée.
    if (roomImage != null) {
      maybeAutoTriggerStandardAiPreview(ref: ref);
    }
  }

  /// Quantité nette pour une famille, avec repli sur une estimation
  /// raisonnable (non-nulle) quand aucun métré réel n'a encore été saisi
  /// pour la pièce — évite l'affichage trompeur d'un prix à 0,00 € dans la
  /// modal produit tant que l'utilisateur n'a pas rempli le panneau
  /// "Métrés". Dès que de vrais métrés sont saisis, la vraie valeur
  /// calculée ([getQteNetteForFamille]) est utilisée en priorité.
  double qteNetteAvecFallback(
    String famille,
    String unite,
    MetresResult metres,
  ) {
    final qte = getQteNetteForFamille(famille, metres);
    if (qte > 0) {
      productModalQteEstimated = false;
      return qte;
    }
    productModalQteEstimated = true;
    // Repli identique à l'ancien comportement (avant la correction Bug #7)
    // — mais utilisé désormais UNIQUEMENT comme estimation par défaut tant
    // qu'aucun métré n'est saisi, jamais comme valeur figée.
    switch (unite) {
      case 'pce':
        return 1;
      case 'm²':
        return 5;
      default: // 'ml'
        return 5;
    }
  }

  /// Ajout/retrait rapide (toggle) d'un produit — utilisé par la vue
  /// catalogue / strip studio pour un clic rapide sans passer par la modal.
  ///
  /// P23-STANDARD-AUTO — CORRECTIF : c'est ICI, pas dans [addToProject],
  /// que passe le VRAI chemin UI du tap sur une tuile du strip Studio
  /// (`product_strip.dart` : `onTap: () => state.quickToggleProd(p.ref)`).
  /// [addToProject] appelle déjà [maybeAutoTriggerStandardAiPreview] en
  /// interne, donc la branche "ajout" ci-dessous en hérite automatiquement
  /// SANS double appel — ce commentaire documente explicitement ce chemin
  /// pour éviter de le reperdre de vue (bug constaté : le clic D609 dans
  /// le Studio ne déclenchait rien car addToProject seul n'était pas le
  /// point d'entrée réellement utilisé par ce widget).
  void quickToggleProd(String ref) {
    final existing = getProdInProject(ref);
    if (existing != null) {
      // Retrait : jamais de déclenchement IA ici (retirer un produit ne
      // doit pas relancer une génération).
      removeProd(ref);
    } else {
      // Ajout : addToProject(ref) déclenche déjà
      // maybeAutoTriggerStandardAiPreview(ref: ref) en interne (voir
      // ci-dessus) — c'est le chemin réel emprunté par le tap utilisateur
      // dans le strip Studio.
      addToProject(ref);
    }
  }

  /// Ouvre un produit dans la modal (pré-remplit la quantité suggérée
  /// depuis les métrés réels plutôt qu'une constante arbitraire).
  void openProduct(String ref) {
    final prod = getProdByRef(ref);
    if (prod == null) return;
    final metres = computeAndStoreMetres();
    final existing = getProdInProject(ref);
    productModalRef = ref;
    if (existing != null) {
      productModalQte = existing.qte;
      productModalQteEstimated = false;
    } else {
      productModalQte = qteNetteAvecFallback(prod.famille, prod.unite, metres);
    }
    notifyListeners();
  }

  void closeProductModal() {
    productModalRef = null;
    notifyListeners();
  }

  /* ── Projets nommés (Enregistrer / Charger / Supprimer) ── */
  //
  // ⚠️ CORRECTION retour utilisateur : "Les boutons d'enregistrement et de
  // téléchargement des projets ne sont pas instinctifs et surtout ne
  // fonctionnent pas." — Avant cette correction, il n'existait AUCUN
  // bouton "Enregistrer le projet" dans toute l'application (l'auto-save
  // de [save]/[restore] ci-dessous est un mécanisme SILENCIEUX qui ne
  // conserve qu'UN SEUL état "en cours", jamais nommé, jamais listé nulle
  // part) ; et l'écran Home affichait deux cartes "projet" 100% factices
  // (texte codé en dur, aucun `onTap`). Cette section introduit un
  // véritable système de projets NOMMÉS : liste persistée, enregistrement
  // explicite (bouton disquette dans le Studio), chargement et suppression
  // depuis l'écran Home.

  /// Liste des projets explicitement enregistrés par l'utilisateur
  /// (persistée séparément de l'état "session courante").
  List<SavedProject> savedProjects = [];

  /// Charge la liste des projets enregistrés — appelé une fois au
  /// démarrage de l'app (voir [AppShell.initState], en complément de
  /// [restore]).
  Future<void> loadSavedProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_projectsPrefsKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      savedProjects = list
          .map((e) => SavedProject.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (_) {
      // stockage indisponible/corrompu — comportement silencieux, comme le reste de la persistance de l'app.
    }
  }

  Future<void> _persistSavedProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = savedProjects.map((p) => p.toJson()).toList();
      await prefs.setString(_projectsPrefsKey, jsonEncode(data));
    } catch (_) {
      // stockage indisponible — silencieux.
    }
  }

  /// Enregistre l'état courant du projet (produits sélectionnés,
  /// positions, métrés, scène démo) sous le nom [name]. Retourne le
  /// [SavedProject] créé. Action EXPLICITE déclenchée par l'utilisateur
  /// (bouton disquette du Studio) — répond directement au retour
  /// utilisateur sur le bouton "enregistrement" non fonctionnel.
  Future<SavedProject> saveCurrentAsProject(String name) async {
    final project = SavedProject(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'Projet sans titre' : name.trim(),
      createdAt: DateTime.now(),
      selectedProducts: List.of(selectedProducts),
      prodPositions: Map.of(prodPositions),
      metresMurA: metresMurA,
      metresMurB: metresMurB,
      metresHauteur: metresHauteur,
      metresPortes: metresPortes,
      metresFenetres: metresFenetres,
      isDemoRoom: isDemoRoom,
      demoScene: demoScene,
    );
    savedProjects = [project, ...savedProjects];
    notifyListeners();
    await _persistSavedProjects();
    return project;
  }

  /// Recharge un projet enregistré : restaure produits/positions/métrés,
  /// et si c'était une scène démo, recharge la vraie photo correspondante
  /// (voir [loadDemoScene]). Pour un projet basé sur une photo IMPORTÉE
  /// (non démo), la photo elle-même n'a pas pu être conservée (voir
  /// limite documentée dans [SavedProject]) — seuls produits/métrés sont
  /// restaurés, l'utilisateur devra réimporter sa photo si besoin.
  void loadProject(String id) {
    SavedProject? project;
    for (final p in savedProjects) {
      if (p.id == id) {
        project = p;
        break;
      }
    }
    if (project == null) return;
    selectedProducts = List.of(project.selectedProducts);
    prodPositions = Map.of(project.prodPositions);
    metresMurA = project.metresMurA;
    metresMurB = project.metresMurB;
    metresHauteur = project.metresHauteur;
    metresPortes = project.metresPortes;
    metresFenetres = project.metresFenetres;
    computeAndStoreMetres();
    currentScreen = 'studio';
    notifyListeners();
    save();
    if (project.isDemoRoom) {
      demoScene = project.demoScene;
      isDemoRoom = true;
      // La taille de la zone photo n'est connue qu'une fois le Studio
      // monté — [loadDemoScene] gère déjà ce cas (mémorise juste le choix
      // si la taille n'est pas encore disponible, voir studio_screen.dart).
      loadDemoScene(project.demoScene);
    }
  }

  /// Supprime un projet enregistré (bouton corbeille, écran Home).
  Future<void> deleteProject(String id) async {
    savedProjects = savedProjects.where((p) => p.id != id).toList();
    notifyListeners();
    await _persistSavedProjects();
  }

  /* ── Persistance (équivalent sessionStorage) ── */

  /// Persiste l'état critique via shared_preferences.
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{
        'selectedProducts': selectedProducts.map((p) => p.toJson()).toList(),
        'prodPositions': prodPositions.map((k, v) => MapEntry(k, v.toJson())),
        'margeCoupePct': margeCoupePct,
        'talonMm': talonMm,
        'metresMurA': metresMurA,
        'metresMurB': metresMurB,
        'metresHauteur': metresHauteur,
        'metresPortes': metresPortes,
        'metresFenetres': metresFenetres,
        'devisWarnShown': devisWarnShown,
        'catFam': catFam,
        'contactSubmitted': contactSubmitted,
        'lastContactInfo': lastContactInfo?.toJson(),
        // ⚠️ CORRECTION Bug "bande cassée après rechargement" (retour
        // utilisateur répété : "mais pourquoi ca ne fonctionne pas") —
        // `perspCalib` et `isCalibrated` ne doivent JAMAIS être persistés
        // entre sessions. Cause racine identifiée : un ancien état
        // sauvegardé (avant l'ajout du garde-fou `autoApplyDetection =
        // false` dans [autoDetectEdges]) pouvait contenir une
        // `perspCalib` issue d'une détection automatique de bords buguée
        // (Sobel/Hough), avec `isCalibrated = true`. Au rechargement,
        // [restore] réinjectait cette calibration obsolète/aberrante
        // par-dessus la calibration fiable posée par [loadDemoScene],
        // produisant la bande de corniche décrochée en arche — alors que
        // toute session "fraîche" (sans état sauvegardé) affichait un
        // rendu correct. La perspective doit toujours être recalculée
        // fraîchement pour la photo/scène courante, jamais restaurée
        // d'une session précédente potentiellement incompatible.
      };
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (_) {
      // stockage indisponible — comportement identique à l'original (try/catch silencieux)
    }
  }

  /// Restaure l'état depuis shared_preferences.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final saved = jsonDecode(raw) as Map<String, dynamic>;

      if (saved['selectedProducts'] != null) {
        selectedProducts = (saved['selectedProducts'] as List)
            .map((e) => ProjectItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (saved['prodPositions'] != null) {
        prodPositions = (saved['prodPositions'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, SnapPos.fromJson(v as Map<String, dynamic>)),
        );
      }
      if (saved['margeCoupePct'] != null) {
        margeCoupePct = (saved['margeCoupePct'] as num).toDouble();
      }
      // ⚠️ `isCalibrated` volontairement PAS restauré — voir commentaire
      // dans [save] : cet ancien flag persisté pouvait figer le badge
      // "Calibré ±3%" avec une `perspCalib` aberrante d'une session
      // précédente. Il est toujours recalculé à neuf par [autoDetectEdges]
      // pour la photo/scène active.
      if (saved['talonMm'] != null) {
        talonMm = (saved['talonMm'] as num).toDouble();
      }
      if (saved['metresMurA'] != null) {
        metresMurA = (saved['metresMurA'] as num).toDouble();
      }
      if (saved['metresMurB'] != null) {
        metresMurB = (saved['metresMurB'] as num).toDouble();
      }
      if (saved['metresHauteur'] != null) {
        metresHauteur = (saved['metresHauteur'] as num).toDouble();
      }
      if (saved['metresPortes'] != null) {
        metresPortes = (saved['metresPortes'] as num).toDouble();
      }
      if (saved['metresFenetres'] != null) {
        metresFenetres = (saved['metresFenetres'] as num).toDouble();
      }
      if (saved['devisWarnShown'] != null) {
        devisWarnShown = saved['devisWarnShown'] as bool;
      }
      if (saved['catFam'] != null) {
        catFam = saved['catFam'] as String;
      }
      if (saved['contactSubmitted'] != null) {
        contactSubmitted = saved['contactSubmitted'] as bool;
      }
      if (saved['lastContactInfo'] != null) {
        lastContactInfo = ContactInfo.fromJson(
          saved['lastContactInfo'] as Map<String, dynamic>,
        );
      }
      // ⚠️ NE PAS restaurer `perspCalib`/`isCalibrated` — voir commentaire
      // dans [save]. Ils sont toujours recalculés à neuf par
      // [loadDemoScene]/[setRoomImageBytes]/[autoDetectEdges] pour la
      // photo/scène active de la session courante.
      computeAndStoreMetres();
      notifyListeners();
    } catch (_) {
      // JSON corrompu — on ignore, comportement identique à l'original
    }
  }
}
