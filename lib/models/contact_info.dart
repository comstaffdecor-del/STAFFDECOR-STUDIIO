/// Coordonnées de contact commercial saisies avant de pouvoir consulter
/// le chiffrage/devis — port du modal `#modal-contact` (contact.js),
/// étendu pour répondre aux points #15/#16 du retour utilisateur :
/// ajout de Nom + Entreprise, et consentement RGPD obligatoire.
library;

class ContactInfo {
  final String prenom;
  final String nom;
  final String entreprise;
  final String email;
  final String tel;
  final String cp;
  final String message;

  /// Consentement RGPD explicite (case à cocher, obligatoire) — sans lui
  /// la soumission est refusée (voir [ContactModal._submit]).
  final bool rgpdConsent;

  const ContactInfo({
    required this.prenom,
    required this.nom,
    required this.entreprise,
    required this.email,
    required this.tel,
    required this.cp,
    required this.message,
    required this.rgpdConsent,
  });

  Map<String, dynamic> toJson() => {
    'prenom': prenom,
    'nom': nom,
    'entreprise': entreprise,
    'email': email,
    'tel': tel,
    'cp': cp,
    'message': message,
    'rgpdConsent': rgpdConsent,
  };

  factory ContactInfo.fromJson(Map<String, dynamic> json) => ContactInfo(
    prenom: json['prenom'] as String? ?? '',
    nom: json['nom'] as String? ?? '',
    entreprise: json['entreprise'] as String? ?? '',
    email: json['email'] as String? ?? '',
    tel: json['tel'] as String? ?? '',
    cp: json['cp'] as String? ?? '',
    message: json['message'] as String? ?? '',
    rgpdConsent: json['rgpdConsent'] as bool? ?? false,
  );
}
