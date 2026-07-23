/// Moteur de calcul pur — port fidèle de chiffrage.js.
///
/// Aucun accès UI ici : fonctions pures uniquement, comme dans l'original.
/// La logique de `calcQteCom` / `calcLigne` / `calcChiffrage` / `computeMetres`
/// est reproduite à l'identique (elle était correcte dans l'ancienne version).
///
/// CORRECTION Bug #7 : `getQteNetteForFamille` est ici réellement appelée
/// par `AppState.addToProject` / `quickToggleProd` (voir app_state.dart),
/// alors que dans l'ancienne version cette fonction, bien qu'implémentée
/// correctement, n'avait AUCUN point d'appel — les quantités par défaut
/// étaient toujours codées en dur (`unite=='pce' ? 1 : 5`), ignorant
/// totalement les métrés saisis par l'utilisateur.
library;

import 'package:intl/intl.dart';
import '../data/catalogue_data.dart';
import '../models/project_item.dart';

/// Formate un montant en prix HT français : "1 234,50 €"
String fmtPrix(double val) {
  final f = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: '€',
    decimalDigits: 2,
  );
  return f.format(val);
}

/// Formate une quantité avec au plus [dec] décimales (défaut 2), style fr-FR.
String fmtN(double val, {int dec = 2}) {
  final f = NumberFormat.decimalPattern('fr_FR');
  f.maximumFractionDigits = dec;
  f.minimumFractionDigits = 0;
  return f.format(val);
}

/// Résultat du calcul de quantité commerciale.
class QteComResult {
  final double qteCom;
  final int? nbBarres;
  const QteComResult({required this.qteCom, this.nbBarres});
}

/// Calcule la quantité commerciale et le nb de barres.
///
/// - [qteNette] : métré net (ml, m², pce)
/// - [unite] : 'ml' | 'm²' | 'pce'
/// - [margePct] : 0.05 / 0.10 / 0.15 / 0.20
/// - [barre] : longueur barre en m (null si N/A)
QteComResult calcQteCom(
  double qteNette,
  String unite,
  double margePct,
  double? barre,
) {
  final qteAvecMarge = qteNette * (1 + margePct);

  if (unite == 'ml' && barre != null && barre > 0) {
    // Profilé vendu en barres : arrondi au nombre de barres sup.
    final nbBarres = (qteAvecMarge / barre).ceil();
    return QteComResult(qteCom: nbBarres * barre, nbBarres: nbBarres);
  }

  if (unite == 'm²') {
    // Arrondi à 0.1 m² supérieur
    final qteCom = (qteAvecMarge * 10).ceilToDouble() / 10;
    return QteComResult(qteCom: qteCom);
  }

  // 'pce' ou autre
  final qteCom = qteAvecMarge.ceilToDouble();
  return QteComResult(qteCom: qteCom);
}

/// Une ligne complète du devis pour un item du projet.
class LigneDevis {
  final String ref;
  final String famille;
  final String designation;
  final String unite;
  final double qteNette;
  final double qteCom;
  final int? nbBarres;
  final double puHt;
  final double totalHt;

  const LigneDevis({
    required this.ref,
    required this.famille,
    required this.designation,
    required this.unite,
    required this.qteNette,
    required this.qteCom,
    required this.nbBarres,
    required this.puHt,
    required this.totalHt,
  });
}

/// Calcule une ligne complète du devis pour un item du projet.
LigneDevis? calcLigne(ProjectItem item, double margePct) {
  final px = getPrixInfo(item.famille);
  if (px == null) return null;

  final r = calcQteCom(item.qte, px.unite, margePct, px.barre);
  final totalHt = r.qteCom * px.prix;

  return LigneDevis(
    ref: item.ref,
    famille: item.famille,
    designation: item.ref, // le nom est identique à la ref dans le GED
    unite: px.unite,
    qteNette: item.qte,
    qteCom: r.qteCom,
    nbBarres: r.nbBarres,
    puHt: px.prix,
    totalHt: totalHt,
  );
}

/// Résultat complet du chiffrage projet.
class Chiffrage {
  final List<LigneDevis> lignes;
  final double totalHt;
  final double tva;
  final double totalTtc;
  final String badge;

  const Chiffrage({
    required this.lignes,
    required this.totalHt,
    required this.tva,
    required this.totalTtc,
    required this.badge,
  });
}

/// Calcule le chiffrage complet à partir de la liste des produits du projet.
Chiffrage calcChiffrage({
  required List<ProjectItem> selectedProducts,
  required double margeCoupePct,
  required bool isCalibrated,
}) {
  final lignes = selectedProducts
      .map((item) => calcLigne(item, margeCoupePct))
      .whereType<LigneDevis>()
      .toList();

  final totalHt = lignes.fold<double>(0, (s, l) => s + l.totalHt);
  final tva = totalHt * 0.20;
  final totalTtc = totalHt + tva;

  return Chiffrage(
    lignes: lignes,
    totalHt: totalHt,
    tva: tva,
    totalTtc: totalTtc,
    badge: isCalibrated ? 'Calibré ±3%' : 'Estimatif ±15%',
  );
}

/// Résultat du calcul de métrés (périmètre / surface).
class MetresResult {
  final double perimetre;
  final double perimetreNet;
  final double surface;
  const MetresResult({
    required this.perimetre,
    required this.perimetreNet,
    required this.surface,
  });
}

/// Calcule périmètre / surface à partir des dimensions saisies.
///
/// Port fidèle de la formule d'origine :
/// - Périmètre total du sol/plafond = 2 × (murA + murB)
/// - Déduction portes (0.9m standard) + fenêtres (1.0m standard)
/// - Surface murs = périmètre × hauteur − ouvertures
MetresResult computeMetres({
  required double metresMurA,
  required double metresMurB,
  required double metresHauteur,
  required double metresPortes,
  required double metresFenetres,
}) {
  final perimetre = 2 * (metresMurA + metresMurB);

  final deductions = (metresPortes * 0.9) + (metresFenetres * 1.0);
  final perimetreNet = (perimetre - deductions).clamp(0, double.infinity);

  final surfaceOuv = (metresPortes * 0.9 * 2.05) + (metresFenetres * 1.0 * 1.2);
  final surface = ((perimetre * metresHauteur) - surfaceOuv).clamp(
    0,
    double.infinity,
  );

  return MetresResult(
    perimetre: perimetre,
    perimetreNet: perimetreNet.toDouble(),
    surface: surface.toDouble(),
  );
}

/// Retourne la quantité nette recommandée pour une famille donnée, en
/// fonction des métrés calculés de la pièce.
///
/// ⚠️ CORRECTION Bug #7 : dans l'ancienne version, cette fonction existait
/// et était correcte, mais n'était JAMAIS appelée — `addToProject` /
/// `_quickToggleProd` utilisaient toujours une quantité par défaut codée en
/// dur (5 ml ou 1 pce), sans jamais tenir compte des métrés saisis par
/// l'utilisateur dans le panneau "Métrés". Ici, cette fonction DOIT être
/// appelée par le flux d'ajout au projet (voir AppState.addToProject).
double getQteNetteForFamille(String famille, MetresResult metres) {
  switch (famille) {
    case 'Corniches':
    case 'Moulures':
    case 'Plinthes':
    case 'Profils LED':
      return metres.perimetreNet;
    case 'Parements':
    case 'Lambris':
      return metres.surface;
    case 'Encadrements':
    case 'Ornements':
      return 1;
    case 'Colonnes':
      return 2;
    default:
      return 0;
  }
}

/// Prix total estimé HT pour une qte + famille donnée (aperçu live modal).
class PrixPreview {
  final double ht;
  final String detail;
  const PrixPreview({required this.ht, required this.detail});
}

PrixPreview calcPrixPreview(double qte, String famille, double margePct) {
  final px = getPrixInfo(famille);
  if (px == null) return const PrixPreview(ht: 0, detail: '');

  final r = calcQteCom(qte, px.unite, margePct, px.barre);
  final ht = r.qteCom * px.prix;

  var detail =
      '${fmtN(qte)} ${px.unite} × ${fmtN(margePct * 100, dec: 0)}% marge';
  if (r.nbBarres != null) {
    detail +=
        ' → ${r.nbBarres} barre${r.nbBarres! > 1 ? 's' : ''} × ${px.barre}m';
  }
  return PrixPreview(ht: ht, detail: detail);
}
