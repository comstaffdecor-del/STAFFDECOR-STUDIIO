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
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Size;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalogue_data.dart';
import '../core/chiffrage.dart';
import '../core/perspective/edge_detect.dart';
import '../models/project_item.dart';
import '../models/persp_calib.dart';

const _prefsKey = 'sds_state';

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
      // ⚠️ SÉCURITÉ TEMPORAIRE : un résidu de bug géométrique dans
      // `edge_detect.dart` peut encore produire, sur certaines photos,
      // un rendu de produit totalement aberrant (grand "X" en diagonale
      // au lieu d'une bande suivant le plafond) malgré les garde-fous de
      // sanité déjà ajoutés (span mini, X gauche<droite, écart Y mini).
      // Tant que ce résidu n'est pas totalement corrigé et vérifié
      // visuellement sur toutes les scènes démo, on N'APPLIQUE PAS
      // encore automatiquement le résultat à [perspCalib] — on le
      // calcule et l'expose (confiance, etc.) pour debug/tests, mais on
      // conserve la calibration par défaut fiable comme valeur active.
      // TODO: repasser `_autoApplyDetection` à true une fois le bug du
      // rendu en "X" définitivement corrigé et vérifié sur les 4 scènes
      // démo + import utilisateur.
      // ignore: dead_code
      const autoApplyDetection = false;
      // ignore: dead_code
      if (geo != null && autoApplyDetection) {
        perspCalib = geo.calib;
        calibAutoDetected = true;
        edgeDetectConfidence = geo.confidence;
        isCalibrated = true;
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
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    roomImage = frame.image;
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
    notifyListeners();
    unawaited(autoDetectEdges());
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

  /// Charge une vraie photo de scène démo depuis les assets
  /// (`assets/demo_scenes/<key>.jpg`) et l'affiche comme [roomImage],
  /// exactement comme une photo importée par l'utilisateur — corrige le
  /// bug où le sélecteur de scène démo ne changeait qu'un libellé texte
  /// sans jamais charger/afficher de vraie image.
  Future<void> loadDemoScene(String key, {Size? containerSize}) async {
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
        // Détection auto des arêtes sur la vraie photo de scène démo —
        // remplace la calibration par défaut par la perspective réelle
        // dès que l'analyse Sobel/Hough est terminée.
        unawaited(autoDetectEdges());
      }
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

  void openMetresPanel() {
    showMetresPanel = true;
    notifyListeners();
  }

  void closeMetresPanel() {
    showMetresPanel = false;
    notifyListeners();
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
  void removeProd(String ref) {
    selectedProducts = selectedProducts.where((p) => p.ref != ref).toList();
    prodPositions.remove(ref);
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
    notifyListeners();
    save();
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
  void quickToggleProd(String ref) {
    final existing = getProdInProject(ref);
    if (existing != null) {
      removeProd(ref);
    } else {
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
