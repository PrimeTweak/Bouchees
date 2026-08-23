# Marche à suivre — Bouchées v0.6

Trois choses ne peuvent pas se faire en interface graphique : générer les
images, faire tourner le serveur en local, et lancer les outils du mois. Elles
demandent une commande. Tout le reste — hébergement, Stripe, dépôt — se fait
au navigateur, et je l'ai écrit comme ça.

---

## A. Le cycle du mois — UNE commande

    node tools/cycle.js

C'est tout. La commande enchaîne : trouver les trous → écrire le prompt
contraint → faire rédiger les recettes → valider contre le catalogue →
vérifier la cohérence culinaire → publier dans le lot du mois → générer les
images → les faire vérifier par un modèle de vision → écrire le manifeste →
republier.

Options utiles :

    node tools/cycle.js --sec                 # montre tout, n'écrit rien
    node tools/cycle.js --recettes-seulement  # saute les images
    node tools/cycle.js --images-seulement    # saute la rédaction
    node tools/cycle.js --lot=2026-10         # force le lot de destination
    node tools/cycle.js --max=5               # limite le nombre d'images

Avant de publier pour vrai, lance `node tests/test.js` : **79 tests**, aucun
« ÉCHEC » attendu.

### Les clés (variables d'environnement)

Sans clé, le cycle tourne quand même en mode simulé — utile pour voir la
mécanique, inutile pour du vrai contenu.

| Variable | Sert à |
|---|---|
| `ANTHROPIC_API_KEY` ou `OPENAI_API_KEY` | rédiger les recettes et vérifier les images |
| `DRAWTHINGS_URL` | générer les images en local (`http://127.0.0.1:7860`) |
| `MOTEUR_TEXTE`, `MOTEUR_IMAGE`, `MOTEUR_VISION` | forcer un adaptateur précis |

### Ce que le cycle NE vérifie pas

Le goût, la levée, la texture réelle. Une recette non cuisinée peut être ratée.
Elle ne peut pas être **dangereuse** : les allergènes et les règles d'âge
vivent dans les tables déterministes, pas dans le test en cuisine. C'est un
risque de qualité, assumé, et le journal du cycle te le rappelle chaque fois.

---

## B. Les images — automatiques de bout en bout

Tu ne regardes rien. Le cycle génère l'image, un modèle de vision la **décrit**,
et le code compare cette description à la liste d'ingrédients réelle. Si un
aliment absent de la recette apparaît, l'image est rejetée toute seule et
l'app garde son illustration.

Pour brancher Draw Things sur ton Mac :

1. Ouvre Draw Things → **Réglages** → active l'**API HTTP** (port 7860).
2. Dans le Terminal, avant de lancer le cycle :

       export DRAWTHINGS_URL=http://127.0.0.1:7860
       export ANTHROPIC_API_KEY=sk-ant-…

3. `node tools/cycle.js --images-seulement`

Ce que le code rejette automatiquement, sans toi :

- un allergène **absent de la recette** visible dans l'image (fromage sur une
  recette sans lait, noix sur une recette sans noix)
- un **risque d'étouffement** visible (noix entières, raisins entiers)
- une image qui **ne ressemble pas** à la recette
- une vision en panne, illisible, ou non configurée

Les faux amis sont gérés : « lait de coco » ne déclenche pas la famille lait,
« poudre à pâte » ne déclenche pas le blé, « beurre de tournesol » n'est pas du
beurre. Ces cas sont testés.

**Le repli est toujours sûr.** Une image rejetée coûte une illustration —
une image acceptée à tort coûte la confiance d'un parent. Le code penche
donc toujours du côté du rejet.

---

## C. Mettre le code sur GitHub (interface graphique)

1. Va sur **github.com**, bouton **New** (vert, en haut à droite).
2. Nom : `bouchees`. Coche **Private**. Bouton **Create repository**.
3. Sur la page suivante, clique **uploading an existing file**.
4. Glisse le contenu du dossier du projet dans la zone. Attends la fin.
5. Bouton **Commit changes**.

---

## D. Héberger le serveur (interface graphique)

Le serveur est en Node pur, sans aucune dépendance : rien à installer.

1. Va sur **render.com**, crée un compte avec ton compte GitHub.
2. **New** → **Web Service** → choisis le dépôt `bouchees`.
3. Remplis :
   - **Build Command** : laisse vide
   - **Start Command** : `node server/server.js`
   - **Instance Type** : le plus petit suffit pour commencer
4. Section **Environment** → **Add Environment Variable**, quatre fois :

   | Clé | Valeur |
   |---|---|
   | `STRIPE_CLE_SECRETE` | ta clé `sk_…` |
   | `STRIPE_PRIX` | l'identifiant `price_…` |
   | `STRIPE_WEBHOOK_SECRET` | le `whsec_…` de l'étape E |
   | `BOUCHEES_ORIGINE` | l'adresse `https://…onrender.com` |

5. **Create Web Service**. Note l'adresse à la fin du déploiement.

⚠️ Les comptes sont dans un fichier JSON. C'est correct pour démarrer et pour
tester, mais un hébergeur qui redémarre peut l'effacer. Dès que tu as de vrais
abonnés, il faut une base de données — dis-le-moi et je fais le changement.

---

## E. Brancher Stripe (interface graphique)

1. **stripe.com** → crée un compte.
2. **Catalogue de produits** → **Ajouter un produit** :
   - Nom : `Bouchées — abonnement mensuel`
   - Modèle : **Récurrent**, mensuel
   - Prix : à toi de le fixer
   - Après l'enregistrement, copie l'identifiant `price_…` → c'est `STRIPE_PRIX`
3. **Développeurs** → **Clés API** → copie la clé secrète `sk_…`
   → c'est `STRIPE_CLE_SECRETE`. Ne la mets jamais dans le dépôt.
4. **Développeurs** → **Webhooks** → **Ajouter un point de terminaison** :
   - URL : `https://…onrender.com/api/webhook/stripe`
   - Événements à envoyer :
     - `checkout.session.completed`
     - `customer.subscription.created`
     - `customer.subscription.updated`
     - `customer.subscription.deleted`
     - `invoice.payment_failed`
   - Après l'enregistrement, copie le secret `whsec_…`
     → c'est `STRIPE_WEBHOOK_SECRET`
5. Retourne dans Render, colle les trois valeurs, redéploie.

**Teste avant d'annoncer quoi que ce soit.** Stripe a un mode test avec des
cartes fictives (`4242 4242 4242 4242`). Fais un cycle complet : abonnement,
déverrouillage, annulation, reverrouillage.

---

## F. Ce que je n'ai pas fait, et pourquoi

- **Générer les images** — mon environnement n'a pas de réseau ni d'outil
  d'image. J'ai écrit les prompts, le plan et la validation.
- **Déployer et brancher Stripe** — il faut tes clés et ton compte. Je n'y
  touche pas, et le code ne les contient nulle part.
- **Une vraie base de données** — pertinent seulement quand tu auras des
  abonnés. Le fichier JSON suffit d'ici là.
- **Fixer le prix** — ce n'est pas de mon ressort.

## G. Ce qui reste faux tant que le serveur n'est pas en ligne

Ouvre `web/index.html` directement et un bandeau orange te le dira :
**en mode fichier, les lots verrouillés sont quand même dans la page.**
L'interface les cache, c'est tout. Le verrou réel, c'est le serveur qui
n'envoie jamais un lot non autorisé. La démonstration te laisse voir le
parcours d'abonnement au complet — bouton « S'abonner » inclus — sans rien
protéger.


---

## H. L'app iOS — sideload sans compte développeur

**Tu n'ouvres jamais Xcode.** Le projet `.xcodeproj` est fabriqué par XcodeGen
sur le runner de GitHub, à partir de `ios/project.yml`. C'est aussi pour ça
qu'il n'est pas dans le dépôt : un `.xcodeproj` versionné, c'est la moitié des
conflits Git d'un projet iOS, et ici il se refabrique en deux secondes.

Les six couleurs, l'icône, les entitlements et l'`Info.plist` sont déjà dans
le dépôt. Il n'y a rien à préparer.

### Produire l'IPA

1. Pousse sur `main` (ou github.com → **Actions** → **Run workflow**).
2. Le workflow lance les 90 tests, publie le contenu, génère le projet,
   bâtit, et empaquette.
3. Onglet **Actions** → le dernier run → section **Artifacts** en bas →
   télécharge `Bouchees-unsigned-ipa`. Dézippe : tu as ton `.ipa`.

**Le workflow refuse de bâtir si les tests tombent.** Si le run est rouge,
ouvre-le : l'étape en échec dit quoi réparer.

### Si ton profil Feather n'est pas en wildcard

Lance le workflow à la main (**Actions → Run workflow**) et entre ton
identifiant de bundle dans le champ prévu. Il remplace `ca.bouchees.app`
partout pour ce build. Sinon Feather refusera de signer.

### Dans Feather

Import du `.p12` et du `.mobileprovision` côté certificats, import de l'IPA,
signer, installer. Tu connais le reste.

### Ce qui ne marchera pas avec un certificat resigné

**Les achats intégrés.** StoreKit exige un profil venant d'un compte App Store
Connect avec la capacité IAP et les produits déclarés. Concrètement : le
paywall s'ouvrira, la liste de produits reviendra vide, et l'app affichera
« Les abonnements n'ont pas pu être chargés ». C'est le comportement attendu,
pas un bug.

Pour tester quand même le parcours d'achat, `ios/App/App/Bouchees.storekit`
simule les deux abonnements. Dans Xcode (si tu l'installes un jour) :
**Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration**,
choisis ce fichier. Achats simulés, aucun compte requis. Le vrai test d'achat
demande TestFlight, donc le compte payant.

### Ce qui fonctionne dès le premier sideload

Recettes, profils, substitutions, illustrations, hors ligne, **et le scanner** —
la caméra ne demande aucun entitlement, juste le texte de l'`Info.plist`. Tout
le cœur du produit est testable.

Le scanner a besoin du serveur pour la route `/api/produit`. Déploie une fois
sur Render (section D) et l'app le trouvera toute seule.

## I. L'abonnement iOS

Stripe ne peut pas déverrouiller de contenu dans une app iOS — c'est la règle
3.1.1, et c'est le rejet le plus courant pour ce genre d'app. Le code délègue
donc à StoreKit sous iOS, et garde Stripe pour le web. Le serveur accepte les
deux et reste seul juge des droits.

### Dans App Store Connect

1. **Abonnements** → nouveau groupe → deux produits :
   `ca.bouchees.abo.mensuel` et `ca.bouchees.abo.annuel`.
2. Remplis les métadonnées de chacun (nom d'affichage, description) — un
   produit incomplet ne se charge pas et le paywall reste vide en révision.
3. **Notifications du serveur App Store** → V2 → URL de production :
   `https://ton-serveur/api/webhook/apple`

### Sur le serveur

    APPLE_BUNDLE_ID=ca.bouchees.app
    APPLE_PRODUITS=ca.bouchees.abo.mensuel,ca.bouchees.abo.annuel

Puis télécharge **Apple Root CA - G3** depuis
`https://www.apple.com/certificateauthority/` et dépose le fichier `.cer`
dans `serveur/`. Sans cette racine, le serveur **refuse toutes** les
transactions — c'est voulu : mieux vaut ne rien déverrouiller que d'accorder
un accès sur une signature non vérifiée.

Teste le cycle complet en bac à sable avant de soumettre : achat,
déverrouillage, annulation, reverrouillage.

---

## J. La soumission

Tout est dans `ios/DOSSIER-REVISION.md` : notes au réviseur, étiquettes de
confidentialité, classement d'âge, et les trois rejets probables avec la
réponse à chacun. Lis-le en entier avant de soumettre — il contient des
choses qui se décident **avant** le build, pas après.
