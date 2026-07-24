/// Projet sauvegardé nommé par l'utilisateur — répond au retour
/// utilisateur "les boutons d'enregistrement... des projets ne sont pas
/// instinctifs et surtout ne fonctionnent pas".
///
/// Avant cette correction, il n'existait AUCUN bouton "Enregistrer" dans
/// toute l'application : l'état courant était persisté de façon purement
/// implicite (auto-save silencieux via `AppState.save()`/`shared_preferences`
/// à chaque mutation), et l'écran Home affichait DEUX cartes "Mes projets
/// récents" totalement statiques/factices ("Salon Haussmannien", "Chambre
/// Parentale") sans aucun `onTap` — un bouton qui ressemble à une action
/// mais n'en déclenche aucune est exactement la définition de "ne fonctionne
/// pas". Cette classe introduit un vrai système de projets NOMMÉS,
/// explicitement enregistrés par l'utilisateur, listés et rechargeables
/// depuis l'écran Home.
///
/// Limite assumée : la photo importée par l'utilisateur (bytes) n'est PAS
/// re-persistée ici (trop volumineux pour `shared_preferences`, et aucun
/// stockage fichier serveur disponible) — seuls les produits sélectionnés,
/// leurs positions et les métrés sont sauvegardés. Pour une scène démo
/// (`isDemoRoom`), la photo est ré-affichable à l'identique au rechargement
/// (asset embarqué). Pour une photo importée, l'utilisateur devra
/// réimporter sa photo après rechargement d'un projet — le projet
/// (produits + métrés + positions) est lui intégralement restauré.
library;

import 'project_item.dart';

class SavedProject {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<ProjectItem> selectedProducts;
  final Map<String, SnapPos> prodPositions;
  final double metresMurA;
  final double metresMurB;
  final double metresHauteur;
  final double metresPortes;
  final double metresFenetres;
  final bool isDemoRoom;
  final String demoScene;

  const SavedProject({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.selectedProducts,
    required this.prodPositions,
    required this.metresMurA,
    required this.metresMurB,
    required this.metresHauteur,
    required this.metresPortes,
    required this.metresFenetres,
    required this.isDemoRoom,
    required this.demoScene,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'selectedProducts': selectedProducts.map((p) => p.toJson()).toList(),
    'prodPositions': prodPositions.map((k, v) => MapEntry(k, v.toJson())),
    'metresMurA': metresMurA,
    'metresMurB': metresMurB,
    'metresHauteur': metresHauteur,
    'metresPortes': metresPortes,
    'metresFenetres': metresFenetres,
    'isDemoRoom': isDemoRoom,
    'demoScene': demoScene,
  };

  factory SavedProject.fromJson(Map<String, dynamic> json) => SavedProject(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    selectedProducts: (json['selectedProducts'] as List? ?? [])
        .map((e) => ProjectItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    prodPositions: (json['prodPositions'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(k, SnapPos.fromJson(v as Map<String, dynamic>)),
    ),
    metresMurA: (json['metresMurA'] as num?)?.toDouble() ?? 0,
    metresMurB: (json['metresMurB'] as num?)?.toDouble() ?? 0,
    metresHauteur: (json['metresHauteur'] as num?)?.toDouble() ?? 2.5,
    metresPortes: (json['metresPortes'] as num?)?.toDouble() ?? 1,
    metresFenetres: (json['metresFenetres'] as num?)?.toDouble() ?? 1,
    isDemoRoom: json['isDemoRoom'] as bool? ?? false,
    demoScene: json['demoScene'] as String? ?? 'haussmann',
  );
}
