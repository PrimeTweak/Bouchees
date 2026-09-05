# Publier Bouchées sur l'App Store — la marche à suivre

Tout ce qui est dans le code est fait (build 192). Ce qui reste est dans
App Store Connect et dans Render, et personne ne peut le faire à ta place.

## 1. Render — trois variables à ajouter (Environment)

    BOUCHEES_CONTACT          ton courriel réel (les pages légales l'affichent)
    BOUCHEES_PRIVACY_OFFICER  ton nom, ou « François Lévesque, fondateur »
    BOUCHEES_ADMIN_SECRET     la même phrase que dans cle-api.txt

Sans BOUCHEES_CONTACT, les pages affichent bonjour@bouchees.ca — vérifie
que cette adresse existe, ou change-la.

## 2. Draw Things — une question à régler AVANT de soumettre

Ouvre Draw Things et lis le nom du modèle sélectionné.
  - FLUX.1 [schnell], SDXL, SD 1.5 : usage commercial permis. Rien à faire.
  - FLUX.1 [dev] : NON commercial. Il faut régénérer les 51 photos avec
    [schnell] — PHOTOS.command le fait, une nuit de Mac.

## 3. App Store Connect — l'app

  - Privacy Policy URL : https://bouchees.onrender.com/privacy
  - Support URL : https://bouchees.onrender.com/terms (ou ton site)
  - Description : termine-la par cette ligne, Apple l'exige pour un
    abonnement avec l'EULA standard :
      Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
    (ou mets https://bouchees.onrender.com/terms dans le champ EULA)
  - App Privacy (le questionnaire) : « Data Not Collected » pour tout,
    SAUF « Purchases » si tu veux être prudent (Apple les gère). L'app n'a
    ni compte, ni analytique, ni identifiant.
  - Age rating : 4+. Catégorie : Food & Drink.
  - Captures d'écran : iPhone 6.7" et 6.1" (l'app est iPhone seulement).

## 4. App Store Connect — l'abonnement

  - Groupe d'abonnements : un seul.
  - Produits, exactement ces identifiants :
      ca.bouchees.abo.mensuel   (1 mois)
      ca.bouchees.abo.annuel    (1 an)
  - Offre d'introduction : 7 jours gratuits sur chacun — l'app le dit.
  - Chaque produit a besoin d'une capture d'écran « pour la revue »
    (l'écran d'achat de l'app suffit) et doit être SOUMIS avec le binaire.
  - Localisations des produits : français et anglais.

## 5. Le binaire

  - Un build Release signé par ton profil de distribution (le workflow
    ipa.yml fait le build ; la signature App Store demande ton
    certificat de distribution et un profil App Store, pas ad hoc).
  - Version 1.0.0 (1) — ios/project.yml.
  - TestFlight d'abord : installe, ouvre le scanner, achète en sandbox,
    restaure. Si un des trois échoue, c'est côté App Store Connect.

## 6. Ce qu'un réviseur va tester

  - L'onboarding sans compte (il n'y en a pas — c'est voulu, la note de
    revue peut le dire : « No account is required; the free tier is fully
    usable »).
  - L'achat : produits soumis, offre d'essai configurée.
  - Le scanner : il demande la caméra, montre la carte du premier
    lancement, et dit « rien à lire » sur un code inconnu — c'est normal.
  - « Not medical advice » : sur la semaine, dans About, dans les
    conditions. Note de revue suggérée : « Bouchées is a recipe planner
    for parents; it gives no diagnosis and no medical advice. »
