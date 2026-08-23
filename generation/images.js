/* Images générées — bloc D
 * node generation/images.js  →  écrit generation/images/a-generer.json
 *
 * Deux décisions codées ici, et elles se tiennent :
 *
 * 1. RÈGLE PHOTO / ILLUSTRATION. Une photo montre le plat d'origine. Une photo
 *    de macaroni gratiné à côté de « sans lait pour Léa » est un mensonge
 *    visuel dans une app d'allergies. Donc : photo seulement quand la recette
 *    est servie telle quelle; dès qu'il y a un échange, l'illustration générée
 *    à partir des ingrédients réels reprend la place. Le mélange devient une
 *    grammaire : photo = rien touché, dessin = on a adapté.
 *
 * 2. PROMPT DÉRIVÉ DES DONNÉES. Le prompt d'image est construit à partir de la
 *    liste d'ingrédients canonique, jamais du titre. Un modèle à qui on dit
 *    « barres granola » ajoute des noix. À qui on dit « avoine, dattes, beurre
 *    de tournesol, aucune noix visible », beaucoup moins.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));

/* Style maison — un seul endroit, pour que 200 images se ressemblent. */
const STYLE = [
  "photographie culinaire naturelle, lumière du jour douce venant de la gauche",
  "vue de dessus légèrement inclinée, environ 30 degrés",
  "vaisselle de céramique mate, teintes crème et vert olive pâle",
  "nappe de lin froissé, fond calme et peu contrasté",
  "aucun texte, aucune main, aucun visage, aucun ustensile de marque",
  "portion réaliste pour un jeune enfant, pas de mise en scène de magazine"
].join(", ");

const NEGATIF = [
  "pas de noix entières visibles", "pas de raisins entiers", "pas de bonbons",
  "pas de texte ni de logo", "pas de personnes", "pas de couverts en argent brillant",
  "pas de fond noir", "pas de vapeur artificielle", "pas de garniture non listée"
].join(", ");

function motsAllergenes(base) {
  return {
    lait: "aucun fromage, aucune crème, aucun beurre visible",
    oeuf: "aucun œuf visible",
    arachide: "aucune arachide visible",
    noix: "aucune noix visible, entière ou en morceaux",
    ble: "aucun pain ni pâte de blé visible",
    soya: "aucune sauce soya visible",
    sesame: "aucune graine de sésame visible",
    poisson: "aucun poisson visible",
    crustaces_mollusques: "aucun crustacé visible",
    moutarde: "aucune moutarde visible",
    sulfites: "aucun fruit séché orange vif"
  };
}

/* Le prompt décrit ce qui est RÉELLEMENT dans le bol, ingrédient par
 * ingrédient, avec les rôles structurels d'abord. */
function promptPour(recette, donnees) {
  const catalogue = donnees.catalogue;
  const ordre = ["proteine", "farine", "legume", "fruit", "lacte", "liquide", "gras", "sucrant"];
  const visibles = recette.ingredients
    .map(function (u) {
      const d = catalogue[u.id];
      if (!d) return null;
      const role = u.role || d.roles[0];
      return { nom: d.nom, role: role, rang: ordre.indexOf(role) === -1 ? 99 : ordre.indexOf(role) };
    })
    .filter(Boolean)
    .filter(function (x) { return ["assaisonnement", "levant"].indexOf(x.role) === -1; })
    .sort(function (a, b) { return a.rang - b.rang; })
    .slice(0, 7)
    .map(function (x) { return x.nom.toLowerCase(); });

  const absents = motsAllergenes(donnees.base);
  const presents = require(path.join(__dirname, "..", "moteur", "moteur.js"))
    .analyserAllergenes(recette, catalogue);
  const exclusions = Object.keys(absents)
    .filter(function (id) { return presents.indexOf(id) === -1; })
    .map(function (id) { return absents[id]; });

  return {
    positif: [
      recette.nom.toLowerCase() + " servi dans un bol de céramique",
      "on voit distinctement : " + visibles.join(", "),
      STYLE
    ].join(". "),
    negatif: [NEGATIF].concat(exclusions).join(", "),
    /* Ce que la révision humaine doit vérifier, dérivé des données. */
    aVerifier: [
      "les ingrédients visibles correspondent à la liste : " + visibles.join(", "),
      "aucun ingrédient absent de la recette n'apparaît dans l'image"
    ].concat(exclusions.map(function (x) { return "vérifier : " + x; }))
  };
}

function empreinte(recette) {
  return crypto.createHash("sha1")
    .update(recette.id + "|" + recette.ingredients.map(function (u) { return u.id; }).sort().join(","))
    .digest("hex").slice(0, 12);
}

/* Le plan de génération du mois : une entrée par recette sans image à jour. */
function aGenerer(corpus, donnees, manifeste, dossierImages) {
  manifeste = manifeste || {};
  const fs2 = require("fs");
  const path2 = require("path");
  const base = dossierImages || path2.join(__dirname, "..");

  return corpus.map(function (r) {
    const emp = empreinte(r);
    const actuel = manifeste[r.id];
    /* Le manifeste dit ce qui a été vérifié; le disque dit ce qui existe.
     * Un manifeste qui survit à la disparition des fichiers ferait poser un
     * champ photo sur des recettes sans image — donc un 404 chez le parent. */
    const surDisque = actuel && actuel.fichier &&
      fs2.existsSync(path2.join(base, actuel.fichier));
    const etat = !actuel ? "manquante"
      : (!surDisque ? "fichier absent"
      : (actuel.empreinte !== emp ? "périmée" : "à jour"));
    if (etat === "à jour") return null;
    const p = promptPour(r, donnees);
    return {
      id: r.id, nom: r.nom, etat: etat, empreinte: emp,
      fichier: "images/" + r.id + "-" + emp + ".webp",
      prompt: p.positif, negatif: p.negatif, aVerifier: p.aVerifier
    };
  }).filter(Boolean);
}

/* Validation d'une entrée de manifeste : sans révision humaine explicite,
 * l'image n'est pas publiée — le repli sur l'illustration est toujours sûr. */
function validerEntree(entree, recette, dossierImages) {
  const e = [];
  if (!entree.fichier) e.push("fichier manquant");
  else if (dossierImages !== false) {
    const fs2 = require("fs");
    const path2 = require("path");
    const base = dossierImages || path2.join(__dirname, "..");
    if (!fs2.existsSync(path2.join(base, entree.fichier))) e.push("fichier introuvable sur le disque");
  }
  if (!entree.empreinte) e.push("empreinte manquante");
  if (recette && entree.empreinte !== empreinte(recette))
    e.push("empreinte périmée : les ingrédients ont changé depuis la génération");
  if (!entree.revisePar) e.push("aucune révision — image non publiable");
  /* Une révision automatique ne vaut que si le verdict de vision est joint et
   * qu'il a reconnu au moins un ingrédient de la recette. Sans ça, on retombe
   * sur l'illustration : le repli est toujours sûr. */
  if (entree.revisePar && /automatique/i.test(entree.revisePar)) {
    if (!entree.verification) e.push("révision automatique sans verdict de vision");
    else if (!entree.verification.reconnus) e.push("la vision n'a reconnu aucun ingrédient de la recette");
    else if (entree.verification.moteur === "absent") e.push("aucun moteur de vision n'a réellement vérifié");
  }
  if (entree.largeur && entree.largeur < 800) e.push("image trop petite : " + entree.largeur + " px");
  return { ok: e.length === 0, erreurs: e };
}

/* La règle qui compte, côté client comme côté serveur. */
function visuelPour(recette, resultat, manifeste, dossierImages) {
  const entree = manifeste && manifeste[recette.id];
  const utilisable = entree && validerEntree(entree, recette, dossierImages).ok;
  if (utilisable && resultat.statut === "telle_quelle") {
    return { type: "photo", fichier: entree.fichier };
  }
  return { type: "illustration", raison: !utilisable ? "aucune photo révisée" : "la recette est adaptée — la photo montrerait autre chose" };
}

if (require.main === module) {
  const donnees = {
    catalogue: lire("donnees/ingredients.json"),
    substitutions: lire("donnees/substitutions.json"),
    base: lire("donnees/base.json")
  };
  let corpus = lire("donnees/recettes.json");
  try { corpus = corpus.concat(lire("donnees/importees/recettes-importees.json")); } catch (e) {}
  let manifeste = {};
  try { manifeste = lire("generation/images/manifeste.json"); } catch (e) {}

  const plan = aGenerer(corpus, donnees, manifeste);
  fs.mkdirSync(path.join(racine, "generation", "images"), { recursive: true });
  fs.writeFileSync(path.join(racine, "generation", "images", "a-generer.json"),
    JSON.stringify(plan, null, 2) + "\n");
  if (!fs.existsSync(path.join(racine, "generation", "images", "manifeste.json"))) {
    fs.writeFileSync(path.join(racine, "generation", "images", "manifeste.json"),
      JSON.stringify({}, null, 2) + "\n");
  }
  console.log("À générer : " + plan.length + " image(s) sur " + corpus.length + " recettes");
  plan.slice(0, 3).forEach(function (p) { console.log("  " + p.etat + " — " + p.nom); });
  console.log("Plan écrit : generation/images/a-generer.json");
}

module.exports = { promptPour: promptPour, aGenerer: aGenerer, validerEntree: validerEntree,
                   visuelPour: visuelPour, empreinte: empreinte, STYLE: STYLE };
