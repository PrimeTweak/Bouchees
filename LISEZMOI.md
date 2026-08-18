# Bouchées (nom de travail) — v0.6 : app iOS, StoreKit, scanner

Application de recettes pour bébés et enfants avec allergies.
Position d'architecture : **l'IA rédige, les règles décident.** Toute décision
de sécurité (allergène, âge, texture) sort de tables déterministes, versionnées
et testées — jamais d'un modèle.

## Structure

    donnees/base.json           Familles d'allergènes (liste canadienne, 11),
                                stades de texture par âge, règles d'interdits
                                et de préparations par âge
    donnees/ingredients.json    ~65 ingrédients canoniques : allergènes dérivés,
                                rôles fonctionnels (liant, gras, farine, liquide…)
    donnees/substitutions.json  Table de substitution par (ingrédient × rôle),
                                options ordonnées par priorité, ratio, âge minimum
    donnees/recettes.json       20 recettes témoins couvrant les allergènes majeurs
    donnees/importees/          Recettes importées par le pipeline + rapport (générés)
    moteur/moteur.js            Le moteur (lot 2) — fonctions pures, zéro dépendance,
                                UMD (node + navigateur)
    ingestion/                  Lot 3 — pipeline d'ingestion agnostique de la source :
      lexique.json                alias FR/EN → ingrédients canoniques, unités
      normaliseur.js              ligne brute → ingrédient canonique, jamais deviné
      adaptateurs.js              schémas spoonacular / TheMealDB / générique
      importer.js                 portes de sécurité + rapport : node ingestion/importer.js
      curation.json               registre de curation humaine (âge, rôles, étapes FR)
      sources/                    gabarits de sources (démo, rien de tiers stocké)
      LICENCES.md                 verdicts de licences vérifiés (spoonacular, Edamam)
      rapport-import.md           dernier rapport d'import (généré)
    tests/test.js               41 tests : node tests/test.js
    demo/gabarit.html           Gabarit du banc d'essai technique (source)
    demo/build.js               Build : node demo/build.js → demo/index.html
    demo/index.html             Banc d'essai autonome (généré)
    app/gabarit-app.html        Gabarit de l'app parents (source)
    app/illustration.js         Système visuel — illustration SVG générée à partir
                                des ingrédients ADAPTÉS + glyphes d'allergènes
    app/build.js                Build : node app/build.js → app/index.html
    app/index.html              L'app parents autonome (générée — un seul fichier)
    outils/trous.js             Bloc B — où manquent les recettes (profil × âge)
    outils/publier.js           Bloc A — écrit dist/ : manifeste + lots versionnés
    outils/rapport-trous.md     Dernier rapport (généré)
    generation/prompt-recette.js  Bloc C — prompt contraint au catalogue
    generation/valideur-recette.js Bloc C — rejette tout ingrédient inventé
    generation/images.js        Bloc D — prompts d'image + règle photo/illustration
    generation/images/          manifeste.json (révisions humaines) + a-generer.json
    serveur/serveur.js          Bloc F — API, droits, service filtré (Node pur)
    serveur/stripe.js           Bloc F — signature webhook + session de paiement
    donnees/publication.json    Bloc A — quel lot publie quoi, et à quel accès
    dist/                       Sortie de publication servie par le serveur
    outils/cycle.js             LE cycle du mois en une commande
    generation/moteurs-texte.js Adaptateurs de rédaction (anthropic/openai/simulé)
    generation/moteurs-image.js Adaptateurs d'image (Draw Things/openai/simulé)
    generation/vision.js        Vérification des images — remplace la révision humaine
    generation/coherence.js     Contrôle culinaire — remplace une partie de la cuisson
    serveur/apple.js            Bloc I — vérification StoreKit 2 (JWS, chaîne x5c)
    ios/App/App/*.swift         Bloc H — coquille SwiftUI, scanner, StoreKit
    ios/DOSSIER-REVISION.md     Bloc J — tout pour la soumission App Store
    ios/project.yml             Bloc G — XcodeGen : le .xcodeproj est généré
    ios/App/App/Bouchees.storekit  Achats simulés pour tester sans compte Apple
    .github/workflows/ipa.yml   Bloc G — IPA non signé à chaque poussée
    MARCHE-A-SUIVRE.md          Publier, générer, héberger, brancher Stripe

## Ce que le moteur garantit (testé)

- Une recette adaptée ne contient **jamais** un allergène évité. Les allergènes
  sont dérivés du catalogue d'ingrédients, jamais lus d'étiquettes externes.
- Un substitut n'introduit jamais un allergène évité et respecte son âge minimum.
  S'il n'existe aucune option sûre : statut `non_adaptable` avec alerte bloquante —
  jamais de retrait silencieux.
- Les règles d'âge s'appliquent à l'ingrédient **final** (origine ou substitut) :
  swaps (miel → sirop d'érable avant 12 mois), préparations (noix moulues avant
  4 ans, bleuets écrasés avant 12 mois…), avec la règle de la tranche la plus
  jeune d'abord.
- Déterminisme : même entrée, même sortie.

Suite complète : `node tests/test.js` → **90 tests**.

Tests de propriété : **3 040 combinaisons** sur les témoins (20 recettes × 19
profils × 8 âges) + **2 550 combinaisons** sur le corpus complet (30 recettes,
témoins + importées). `node tests/test.js` → 41 ok.

## Les deux portes de l'importeur (lot 3)

1. **Reconnaissance totale** : une seule ligne d'ingrédient non reconnue par le
   lexique et la recette entière part en quarantaine. On ne devine jamais.
2. **Curation humaine** : sans entrée dans `curation.json` (âge minimal validé,
   rôles confirmés, étapes en français), pas d'import — même tout reconnu.

Dernier passage : 10 importées, 3 en quarantaine (voir `ingestion/rapport-import.md`).
L'IA peut proposer des alias de lexique ou des entrées de curation; un humain
les valide. Licences des API commerciales : voir `ingestion/LICENCES.md` —
verdict : incompatibles avec le stockage, le corpus grandit par contenu maison,
sources libres ou ententes directes.

## Limites assumées de la v0.1

- Les **quantités des substituts** restent en ratio texte (« 60 ml par œuf ») —
  le recalcul des quantités affichées viendra dans un lot ultérieur.
- Les **étapes ne sont pas réécrites** après substitution (c'est le lot 5, couche IA).
- Les tables (substitutions, âges, textures) sont un **point de départ curé, non
  validé par un professionnel** — révision par nutritionniste/allergologue
  requise avant toute mise en service réelle.

## Le système visuel (v0.3)

Pas de photo : une photo montre le plat d'origine, et une image qui montre du
fromage à côté d'un « sans lait pour Léa » est un piège dans une app d'allergies.
Chaque tuile est un SVG généré **à partir de la liste d'ingrédients après
adaptation** — quand le beurre d'arachide devient du beurre de tournesol,
l'image change. Déterministe : même recette + même profil = même image.
La composition suit la nature du plat (potage qui remplit le bol, plat en
morceaux, dôme de pâtisserie). Testé : `illustration : l'image CHANGE quand la
recette s'adapte`.

## Refonte UI (v0.3) — les 8 points

1. Accueil guidé en trois écrans (prénom, âge, allergènes) au lieu d'un profil bidon
2. Tuiles illustrées partout (voir ci-dessus)
3. Hiérarchie : une carte héro « notre choix », puis sections par verdict
4. Langage de parent : « Oui, telle quelle » / « Oui — avec 2 échanges » / « Pas cette fois »
5. Âge par stades (6–8, 9–11, 1–2 ans, 2–3 ans, 4 ans +) + réglage fin au mois
6. Allergènes : les 6 courants avec glyphes, les 5 autres sous un lien
7. Une seule barre collante (avatars des enfants), le reste défile
8. Profil replié en avatars; toucher un prénom ouvre une feuille d'édition

## Delta v0.2 (depuis v0.1)

NOUVEAUX (`git add`) :

    ingestion/lexique.json          ingestion/normaliseur.js
    ingestion/adaptateurs.js        ingestion/importer.js
    ingestion/curation.json         ingestion/LICENCES.md
    ingestion/rapport-import.md     ingestion/sources/partenaire-qc.json
    ingestion/sources/spoonacular-fixture.json
    ingestion/sources/mealdb-fixture.json
    donnees/importees/recettes-importees.json
    donnees/importees/rapport-import.json
    app/gabarit-app.html            app/build.js            app/index.html

MODIFIÉS :

    donnees/base.json               donnees/ingredients.json
    donnees/substitutions.json      tests/test.js
    demo/index.html (reconstruit)   LISEZMOI.md

SUPPRIMÉS : aucun.

## L'abonnement mensuel (v0.4)

**Ce qui est gratuit, pour toujours** : le moteur, les substitutions, les règles
d'âge, les profils, le mode famille, et les lots de départ. Un parent qui reçoit
un diagnostic un mardi soir ne doit pas buter sur un écran de paiement.
**Ce qui est payant** : le flux de nouvelles recettes chaque mois, ciblé sur les
profils réels.

Le mur tient côté **serveur** : `/api/recettes` ne renvoie jamais un lot non
autorisé. Un mur côté client s'ouvre avec Ctrl+U — l'app le dit elle-même dans
un bandeau tant qu'aucun serveur ne répond.

Le cycle du mois : `trous.js` dit où ça manque → `prompt-recette.js` transforme
ça en prompt contraint → le modèle rédige → `valideur-recette.js` rejette tout
ingrédient inventé → **quelqu'un cuisine la recette** → curation → `publier.js`.

Images : prompt dérivé de la liste d'ingrédients (jamais du titre), et
**photo seulement si la recette est servie telle quelle**. Dès qu'un échange a
lieu, l'illustration reprend la place — une photo montrerait le plat d'origine.
Sans champ `revisePar`, aucune photo n'est publiée.

## Le cycle automatique (v0.5)

`node outils/cycle.js` fait tout : trous → prompt → rédaction → validation →
cohérence → publication → images → vision → manifeste → republication.

**La vision remplace tes yeux.** Un modèle décrit l'image, le CODE compare la
description à la liste d'ingrédients. Un aliment absent de la recette qui
apparaît dans l'image = rejet automatique, et l'illustration reprend la place.
Faux amis gérés et testés : « lait de coco » ≠ lait, « poudre à pâte » ≠ blé,
« beurre de tournesol » ≠ beurre. En cas de panne, de réponse illisible ou de
vision non configurée : **rejet**, jamais acceptation par défaut. Le repli
coûte une illustration; un faux accord coûte la confiance d'un parent.

**La cohérence remplace une partie de la cuisson.** Attrapé : proportions
aberrantes, ingrédient jamais utilisé dans les étapes, four sans température,
temps incohérent, protéine crue jamais cuite, rendement invraisemblable.
Pas attrapé : le goût, la levée, la texture. Une recette non cuisinée peut être
ratée — jamais dangereuse, la sécurité vivant dans les tables déterministes.

## L'app iOS (v0.6)

**Un seul moteur.** Le moteur de substitution reste en JavaScript, dans un
WKWebView chargé depuis le bundle. On ne le réécrit pas en Swift : deux
moteurs, ce sont deux vérités, et sur des allergies c'est inacceptable. Le
natif fournit les sens — caméra, hors ligne, StoreKit, haptique — et pose des
questions au moteur par un pont.

**Le scanner** lit un code-barres, consulte Open Food Facts, et fait rendre le
verdict par le moteur — jamais par les étiquettes de la base, qui sont
indicatives. Un ingrédient non reconnu donne « incertain » et renvoie à
l'étiquette : on ne devine pas. Licence ODbL respectée : consultation à la
demande, aucune fusion dans notre base, attribution affichée.

**L'abonnement iOS passe par StoreKit** (règle 3.1.1 — Stripe ne peut pas
déverrouiller du contenu dans une app iOS). La transaction signée part au
serveur, qui vérifie la chaîne de certificats jusqu'à la racine Apple
épinglée. Sans cette racine sur le serveur : refus de tout. Stripe reste en
place pour le web; le serveur accepte les deux sources.

## Delta v0.6 (depuis v0.5)

NOUVEAUX (`git add`) :

    serveur/apple.js                  ios/App/App/BoucheesApp.swift
    ios/App/App/PontMoteur.swift      ios/App/App/Scanner.swift
    ios/App/App/Abonnement.swift      ios/App/App/ContenuLocal.swift
    ios/App/App/EcransSecondaires.swift  ios/App/App/Info.plist
    ios/DOSSIER-REVISION.md           .github/workflows/ipa.yml

MODIFIÉS :

    serveur/serveur.js     (routes Apple + consultation de produits)
    app/gabarit-app.html   (pont natif, abonnement iOS → StoreKit)
    app/index.html         (reconstruit)
    tests/test.js          (11 nouveaux tests — 90 au total)
    LISEZMOI.md            MARCHE-A-SUIVRE.md

SUPPRIMÉS : aucun.

**Aucun Xcode requis.** Le projet est généré par XcodeGen (`ios/project.yml`)
sur le runner GitHub. Le `.xcodeproj` n'est pas versionné — il se refabrique
à chaque build, et un projet Xcode dans Git ne cause que des conflits.

**Non compilé.** Aucun Xcode dans mon environnement : les fichiers Swift
n'ont jamais été bâtis. Attends-toi à des ajustements au premier build.
Le JavaScript, le serveur et la vérification StoreKit, eux, sont testés.

## Delta v0.5 (depuis v0.4)

NOUVEAUX (`git add`) :

    outils/cycle.js                   generation/moteurs-texte.js
    generation/moteurs-image.js       generation/vision.js
    generation/coherence.js

MODIFIÉS :

    generation/images.js   (la révision automatique compte, avec verdict joint)
    app/gabarit-app.html   (photo si telle quelle, illustration sinon)
    app/index.html         (reconstruit)
    tests/test.js          (12 nouveaux tests — 79 au total)
    LISEZMOI.md            MARCHE-A-SUIVRE.md

SUPPRIMÉS : aucun.

## Delta v0.4 (depuis v0.3)

NOUVEAUX (`git add`) :

    donnees/publication.json          outils/trous.js
    outils/publier.js                 outils/rapport-trous.md
    outils/rapport-trous.json         generation/prompt-recette.js
    generation/valideur-recette.js    generation/images.js
    generation/prompt-du-mois.txt     generation/images/a-generer.json
    generation/images/manifeste.json  serveur/serveur.js
    serveur/stripe.js                 MARCHE-A-SUIVRE.md
    dist/manifeste.json               dist/securite.json
    dist/lots/2026-06.json            dist/lots/2026-07.json
    dist/lots/2026-08.json            dist/lots/2026-09.json

MODIFIÉS :

    app/gabarit-app.html   (paywall, lots, nouveautés, mode serveur)
    app/build.js           (injection de la publication)
    app/index.html         (reconstruit)
    tests/test.js          (20 nouveaux tests — 67 au total)
    LISEZMOI.md

SUPPRIMÉS : aucun.

À ignorer dans Git : `serveur/comptes.json` (données de comptes).

## Delta v0.3 (depuis v0.2)

NOUVEAU (`git add`) :

    app/illustration.js

MODIFIÉS :

    app/gabarit-app.html   (refonte complète)
    app/build.js           (injection du système visuel)
    app/index.html         (reconstruit)
    tests/test.js          (6 tests visuels — 47 au total)
    LISEZMOI.md

SUPPRIMÉS : aucun.
