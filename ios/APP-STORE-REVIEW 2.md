# Dossier de révision App Store — Bouchées

Tout ce qu'il faut fournir à Apple, et les pièges qui font rejeter cette
catégorie d'app en particulier.

---

## 1. Notes au réviseur (à copier dans App Store Connect)

> **Ce que fait l'app**
> Bouchées adapte des recettes aux allergies alimentaires et à l'âge d'un
> enfant. Le moteur d'adaptation est déterministe : des tables versionnées
> décident des substitutions, jamais un modèle de langage.
>
> **Compte de test**
> Courriel : revue@bouchees.example — aucun mot de passe requis, la connexion
> se fait par jeton. Ce compte a un abonnement actif en bac à sable.
>
> **Parcours en 5 étapes**
> 1. À l'ouverture, créez un profil : prénom, âge (essayez 9 mois), et cochez
>    « Lait » et « Œufs ».
> 2. Onglet **Recettes** : chaque carte affiche un verdict au prénom de
>    l'enfant. Ouvrez « Macaroni au fromage et courge cachée » — la fiche
>    montre chaque ingrédient remplacé et pourquoi.
> 3. Onglet **Scanner** : pointez n'importe quel code-barres d'aliment
>    emballé. L'app lit la liste d'ingrédients et rend un verdict.
>    (Codes de test qui fonctionnent : voir plus bas.)
> 4. Onglet **Réglages** → **S'abonner** : achat intégré, deux durées.
>    Le bouton **Restaurer mes achats** est dans le même écran.
> 5. Mettez l'appareil en mode avion et rouvrez l'app : tout le contenu déjà
>    téléchargé reste utilisable. C'est le cas d'usage principal — vérifier une
>    recette à l'épicerie, souvent sans signal.
>
> **Fonctions natives, pas un site web**
> Lecture de code-barres par la caméra (AVFoundation), fonctionnement complet
> hors ligne, profils stockés sur l'appareil, StoreKit 2, retour haptique.
> La vue de contenu affiche des fichiers embarqués dans le bundle, jamais une
> URL distante.
>
> **Contenu médical**
> L'app affiche un avertissement dans les réglages et au pied de chaque
> écran : elle ne remplace pas un avis médical et le plan d'un allergologue a
> préséance. Les tables d'allergènes suivent la liste des allergènes
> prioritaires de Santé Canada.
>
> **Données de produits**
> Consultation d'Open Food Facts (licence ODbL) au moment du scan seulement.
> Aucune donnée de produit n'est conservée ni fusionnée dans notre base.
> L'attribution est affichée sur chaque fiche de produit.

**Codes-barres de test à fournir** : choisis trois produits canadiens courants
présents dans Open Food Facts, vérifie-les toi-même avant de soumettre, et
inscris-les dans les notes. Un scanner qui ne trouve rien pendant la révision
se lit comme un scanner cassé.

---

## 2. Étiquettes de confidentialité (App Privacy)

Ce que l'app collecte réellement, à déclarer exactement ainsi :

| Type | Collecté | Lié à l'identité | Suivi | Usage |
|---|---|---|---|---|
| Adresse courriel | Oui | Oui | Non | Gestion du compte et de l'abonnement |
| Identifiant d'achat | Oui | Oui | Non | Vérification de l'abonnement |
| Contenu utilisateur (prénom, âge, allergènes de l'enfant) | **Non** | — | — | Reste sur l'appareil |
| Diagnostics, publicité, localisation, contacts, photos | Non | — | — | — |

**Le point qui compte** : les profils d'enfants ne quittent pas l'appareil.
Ce n'est pas une formule — c'est vrai dans le code (`ContenuLocal.swift`
écrit dans le conteneur de l'app, et aucune route serveur ne les reçoit).
Si ça change un jour, cette déclaration doit changer le même jour.

**Santé** : ne coche PAS la catégorie « Santé et forme physique ». Une
préférence alimentaire déclarée par un parent n'est pas un dossier médical, et
cocher cette case attire un examen plus lourd sans raison. Mais si tu ajoutes
un jour un champ « diagnostic » ou « ordonnance », ça devient de la donnée de
santé et la déclaration change.

---

## 3. Classement d'âge et Catégorie Enfants

**Catégorie principale** : Cuisine et boissons. Secondaire : Style de vie.

**Ne pas** soumettre à la **Catégorie Enfants**. L'app s'adresse aux *parents*,
pas aux enfants. La Catégorie Enfants impose des règles lourdes (aucun lien
externe sans barrière parentale, aucune collecte de données, publicité
contextuelle seulement) et ne correspond pas au produit. Le classement d'âge
reste **4+** puisqu'il n'y a aucun contenu sensible.

Corollaire à respecter : ne décris jamais l'app comme étant « pour les
enfants » dans le titre, le sous-titre ou les captures. Écris « pour les
parents » ou « pour la famille ». Apple lit ces champs pour décider si tu
aurais dû être dans la Catégorie Enfants.

---

## 4. Les trois rejets probables, et la réponse

### 4.2 — Fonctionnalité minimale
Le risque classique d'une app qui contient un WebView. La réponse n'est pas
un argument, c'est une démonstration : le scanner de code-barres et le mode
hors ligne sont impossibles dans Safari. Mets-les dans les **deux premières
captures d'écran** et dans les notes au réviseur — le réviseur regarde les
captures avant d'ouvrir l'app.

### 3.1.1 — Achat intégré
L'app ne doit contenir **aucun** chemin vers une caisse web. Vérifie avant de
soumettre : sous iOS, le bouton d'abonnement appelle StoreKit et jamais Stripe
(c'est codé, mais teste-le sur l'appareil). Vérifie aussi qu'aucun texte ne
dit « moins cher sur notre site ». Le bouton **Restaurer mes achats** doit
être visible sans être abonné.

### 1.4.1 — Sécurité physique
Une app d'allergies alimentaires touche à la sécurité. Ce qui aide : les
avertissements présents, l'absence de promesse de diagnostic, et le fait que
l'app dise « lisez l'étiquette » dès qu'un ingrédient n'est pas reconnu plutôt
que de deviner. Ne mets **aucune** formule du genre « garanti sans allergène »
nulle part — ni dans l'app, ni dans la fiche App Store.

---

## 5. À vérifier avant chaque soumission

- [ ] `node tests/test.js` passe au complet
- [ ] Le compte de test fonctionne et son abonnement bac à sable est actif
- [ ] Les achats intégrés sont **soumis avec la version** (un IAP en attente
      qui n'est pas joint à la build fait rejeter la build)
- [ ] Les prix et durées affichés correspondent à App Store Connect
- [ ] Mode avion : l'app s'ouvre et reste utilisable
- [ ] Le texte de la caméra dit précisément à quoi elle sert
- [ ] Aucun lien de paiement web dans l'app
- [ ] Les captures montrent le scanner et le hors ligne
- [ ] L'avertissement médical est visible sans défiler dans les réglages
- [ ] L'attribution Open Food Facts est visible sur la fiche produit

---

## 6. Ce que je ne peux pas faire à ta place

- **Compiler.** Aucun Xcode ici : le code Swift n'a jamais été compilé.
  Attends-toi à des ajustements au premier build — imports, noms de couleurs
  d'assets, cible de déploiement.
- **Créer le projet Xcode.** `ios/App/App.xcodeproj` doit être créé une fois
  dans Xcode (App → SwiftUI), puis les fichiers `.swift` glissés dedans. Le
  workflow GitHub Actions suppose ce chemin.
- **Les couleurs d'assets.** Le code référence `Betterave`, `Pois`, `Courge`,
  `Canneberge`, `CourgePale`, `Fond`. Crée-les dans `Assets.xcassets` avec les
  valeurs du LISEZMOI, sinon SwiftUI affichera du noir.
- **Signer, soumettre, fixer les prix.** Ton compte, tes clés, ta décision.
