# Checklist Conformite - Soumission Gouvernement

## A. Actions critiques immediates (avant toute soumission)
- [ ] Retirer tous les secrets du depot (`.env`, cles privees, comptes service).
- [ ] Rotation complete des cles exposees (Firebase Admin, OneSignal, API externes, Supabase).
- [ ] Verifier que les secrets sont fournis uniquement via variables d'environnement en production.
- [ ] Produire une version "gouvernement" sans modules non alignes au service public (ou module derriere feature flag strict).
- [ ] Lancer un `flutter analyze` complet + tests smoke et archiver le rapport.

## B. Gouvernance et cadre legal
- [ ] Identifier le responsable de traitement et les sous-traitants.
- [ ] Documenter finalites de traitement par module (emploi, alertes, chat, identite, marketplace).
- [ ] Definir base legale par finalite (service public, consentement, obligation legale, etc.).
- [ ] Mettre en place conditions d'utilisation et politique de confidentialite validees juridiquement.
- [ ] Definir procedure de gestion des demandes utilisateurs (acces, rectification, suppression).

## C. Protection des donnees
- [ ] Inventaire des donnees personnelles par collection Firestore.
- [ ] Politique de retention (duree par type de donnee).
- [ ] Chiffrement en transit (TLS) et au repos confirme.
- [ ] Journalisation des acces admin et actions sensibles.
- [ ] Procedure d'anonymisation/purge pour donnees hors retention.

## D. Securite technique
- [ ] Revue des regles Firestore/Storage et principe du moindre privilege.
- [ ] MFA active pour tous les comptes admin.
- [ ] Separation des environnements (dev, preprod, prod) avec credentials distincts.
- [ ] Durcissement API backend (rate limit, validation schema, authz stricte).
- [ ] Plan de patch management (dependances Flutter/Node, cadence mensuelle).
- [ ] Scan de secrets et scan de dependances dans CI.

## E. Confiance, moderation et usage responsable
- [ ] Politique de moderation des contenus (signalement, triage, escalade, sanctions).
- [ ] Delais cibles de traitement des signalements.
- [ ] Registre des incidents de moderation.
- [ ] Protection des mineurs et contenus sensibles.
- [ ] Charte d'utilisation pour citoyens, entreprises et admins.

## F. Exploitation et continuite de service
- [ ] SLA de service (disponibilite cible, delais support, severites incidents).
- [ ] Astreinte et procedure de gestion d'incident (P1/P2/P3).
- [ ] Sauvegardes testees + plan de reprise (RPO/RTO).
- [ ] Supervision temps reel (erreurs app, API, base, notifications).
- [ ] Plan de communication en cas d'incident majeur.

## G. Pilotage projet et preuves a joindre au dossier
- [ ] Architecture technique (diagramme simple + flux de donnees).
- [ ] Matrice des risques + plan de mitigation.
- [ ] Rapport QA (analyse statique, tests, bugs ouverts/fermes).
- [ ] Tableau de bord KPI propose (adoption, emploi, securite, administration).
- [ ] Planning 90 jours avec responsables nominatifs.

## H. Template suivi interne (a copier dans tes CR hebdo)
| Item | Owner | Echeance | Statut | Preuve |
|---|---|---|---|---|
| Rotation des cles |  |  |  |  |
| Revue regles Firestore |  |  |  |  |
| Edition gouvernement |  |  |  |  |
| Rapport QA complet |  |  |  |  |
| Dossier legal valide |  |  |  |  |

