# DOSSIER TECHNIQUE
## Lualaba Konnect - Architecture, modules et conditions de deploiement

## 1. Objet du dossier
Le present dossier technique decrit l'etat actuel du prototype `Lualaba Konnect`, ses composants principaux, son architecture applicative, ses modules metier et les pre-requis de durcissement avant une utilisation institutionnelle.

## 2. Statut actuel du produit
Le projet est a un niveau `prototype avance / pre-pilote`.

Elements tangibles verifies dans le repo:
- application Flutter
- build web present dans `build/web`
- dashboard admin present dans `dashboard.html`
- backend de notifications present dans `server/`
- Cloud Functions Firebase presentes dans `functions/`
- captures de prototype disponibles a la racine du projet

## 3. Stack technologique

### Frontend
- Flutter / Dart
- cibles: Android, iOS, Web, Windows, macOS, Linux

### Backend et services
- Firebase Core
- Firebase Auth
- Cloud Firestore
- Firebase Storage
- Firebase Messaging
- OneSignal pour notifications push
- Supabase utilise comme service complementaire
- serveur Node pour endpoint de notifications

### Bibliotheques techniques notables
- `flutter_webrtc` pour appels audio/video
- `google_mlkit_text_recognition` pour OCR
- `geolocator` et `geocoding`
- `local_auth`
- `shared_preferences`
- `syncfusion_flutter_pdf`, `pdfx`, `excel`

## 4. Vue d'ensemble de l'architecture
Le systeme s'appuie sur une architecture modulaire composee de:
- une application cliente Flutter
- une base de donnees temps reel orientee documents via Firestore
- un stockage de fichiers via Firebase Storage
- un systeme d'authentification Firebase
- un service de notifications push
- un dashboard admin web
- des fonctions serveur pour traitements et notifications

### Schema simplifie
```text
Utilisateurs
    |
    v
Application Flutter (mobile/web)
    |
    +--> Firebase Auth
    +--> Cloud Firestore
    +--> Firebase Storage
    +--> OneSignal / FCM
    +--> Supabase (services complementaires)
    |
    +--> Notifier server (Node / Vercel ou equivalent)
    |
    +--> Dashboard admin HTML
```

## 5. Modules fonctionnels identifies dans le code

### A. Communication
- fil d'actualites
- messagerie
- gestion de chats et groupes
- appels audio/video WebRTC
- live

### B. Services economiques
- marketplace
- gestion produits
- commandes
- favoris et historique
- echanges vendeur-client

### C. Emploi
- offres d'emploi
- candidatures
- suivi entreprise
- notifications liees aux candidatures

### D. Services de proximite
- mobilite
- location de voitures
- food services
- immobilier / gestion locative
- freelance
- formation
- services rapides comme agrégateur d'acces
- administration de proximite: documents, taxes, rendez-vous

### E. Sante de proximite
- profil sante utilisateur
- teleconsultation video via chat et WebRTC
- suivi de rendez-vous
- rappels de medicaments et notifications intelligentes
- pharmacie et commandes
- documents medicaux avec stockage et numerisation
- QR sante
- module IA de synthese / recommandations
- suivi de mesures de sante
- file d'attente patients

### F. Prevention, meteo et information pratique
- meteo geolocalisee
- qualite de l'air
- alertes vent / poussiere
- conseils utiles et informations de prevention

### G. Parcours d'identite et administration
- inscription avec pieces justificatives
- depot de document PDF d'identite
- validation d'identite cote admin
- controle d'acces administrateur
- dashboard de supervision
- logique de profils verifies pour reduire les faux comptes et mieux tracer les actions sensibles

### H. Alerte / urgence
- menu SOS
- alerte aux contacts
- notifications
- journalisation via chat / messages d'alerte

## 6. Donnees et flux principaux
Les flux majeurs observables sont:
- creation de compte et authentification
- creation / lecture / mise a jour de documents Firestore
- depot de fichiers dans Firebase Storage
- envoi de notifications push
- diffusion de messages et appels
- creation et suivi de candidatures / commandes / reservations

## 7. Administration et controle d'acces
Le projet comporte deja une logique d'administration:
- verification de claims admin
- collection `admin_users`
- demandes d'acces admin
- dashboard d'administration
- page de validation d'identite

Ce point est utile pour un usage public, mais doit etre renforce avant tout pilote institutionnel:
- moindre privilege
- MFA pour admins
- journalisation complete
- revue periodique des droits

## 8. Securite technique - niveau actuel
Points favorables visibles:
- authentification structuree
- separation fonctionnelle frontend / backend
- notifications avec verification de token cote serveur
- base technique compatible avec une edition gouvernee

Points de durcissement indispensables avant pilote:
- retrait de tous les secrets du depot
- rotation des cles
- revue des regles Firestore et Storage
- separation stricte dev / preprod / prod
- politique de logs et supervision
- plan de sauvegarde et reprise
- revue des modules non alignes avec l'edition gouvernementale

Point important:
les modules de sante, d'IA et de documents doivent etre presentes comme `outils d'appui` et `pilotage encadre`, avec gouvernance de donnees renforcee, et non comme systeme hospitalier integral.

Autre point important:
le bloc de validation d'identite peut etre valorise comme un outil de `confiance numerique`.
Dans une edition gouvernementale, il peut aider a reduire:
- les faux profils
- les arnaques en ligne
- certaines usurpations d'identite
- la diffusion de fausses informations par comptes non verifies

## 9. Conformite et edition gouvernement
Pour une soumission publique, il est recommande de preparer une edition gouvernement qui:
- n'expose que les modules utiles au pilote
- masque les modules non retenus
- applique un referentiel de roles
- formalise les finalites de traitement
- documente les KPI attendus

## 10. Conditions de deploiement recommandees

### Phase 1 - Preparation
- gel du perimetre fonctionnel
- retrait des secrets
- configuration des environnements
- matrice d'acces admin
- documentation des traitements

### Phase 2 - Stabilisation
- tests smoke sur parcours critiques
- verification des flux notification
- validation des modules cibles
- corrections bloquantes

### Phase 3 - Pilote
- ouverture a un groupe borne
- suivi KPI hebdomadaire
- revue des incidents
- bilan mensuel

## 11. Risques techniques a signaler honnetement
- risque de securite si les secrets ne sont pas industrialises
- risque de dispersion fonctionnelle si le perimetre n'est pas borne
- risque de gouvernance si plusieurs admins sont ouverts sans controle fort
- risque de confusion publique si l'edition gouvernement n'est pas distincte du produit general

## 12. Recommandation technique officielle
La recommandation n'est pas un deploiement large immediat.
La recommandation est:
- une edition gouvernement restreinte
- un pilote 90 jours
- une supervision mixte
- un durcissement securite avant ouverture

## 13. Pieces techniques a joindre
- schema d'architecture simplifie
- liste des modules retenus pour le pilote
- matrice des roles
- plan de securisation
- plan de reprise
- calendrier de hardening
