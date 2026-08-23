/* Prompts d'image — v2
 *
 * TROIS CHANGEMENTS, ET LE PREMIER EST LE PLUS IMPORTANT.
 *
 * 1. LES PROMPTS SONT EN ANGLAIS. Les modèles d'image sont entraînés
 *    massivement sur des légendes anglaises. Un prompt français passe par une
 *    traduction implicite et perd en fidélité — c'est la première cause de
 *    résultats mous. Le reste du projet reste en français; seul ce qui part
 *    to le modèle change de langue.
 *
 * 2. L'ESTHÉTIQUE CHANGE. L'ancienne visait le magazine : céramique mate,
 *    nappe de lin, fond calme. C'est joli et faux. On vise maintenant une
 *    vraie cuisine de famille — comptoir de bois, lumière de fenêtre, un
 *    linge qui traîne, quelques miettes. L'imperfection rend la photo
 *    crédible.
 *
 * 3. LA COMPOSITION VARIE. Toutes les images avaient le même angle. Trente
 *    photos identiques ressemblent à un gabarit, pas à une collection. La
 *    variation est semée par l'identifiant de la recette : déterministe, donc
 *    la même recette garde toujours son cadrage.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));

const STYLE = [
  "candid home food photography",
  "shot in a real family kitchen, not a studio",
  "soft natural window light, warm and slightly uneven",
  "worn wooden table or kitchen counter, everyday ceramic dishware",
  "shallow depth of field, 50mm lens, gentle background blur",
  "a few crumbs and a rumpled dish towel nearby, lived-in and unstyled",
  "realistic toddler-sized portion, honest home cooking",
  "natural colours, no colour grading, no glossy magazine styling"
].join(", ");

const CADRAGES = [
  "overhead flat lay, camera directly above",
  "three-quarter angle from about 40 degrees, close to the food",
  "eye-level side view across the table, plate in sharp focus",
  "slightly overhead at 60 degrees, one corner of the table visible"
];

const MOMENTS = [
  "morning light through a kitchen window",
  "soft overcast afternoon light",
  "warm late-day light falling across the counter"
];

const NEGATIF = [
  "no whole nuts", "no whole grapes", "no candy", "no text", "no logos",
  "no watermark", "no people", "no hands", "no faces",
  "no polished silverware", "no black background", "no studio lighting",
  "no artificial steam", "no garnish that is not listed",
  "blurry", "grainy", "noisy", "distorted", "deformed", "low quality",
  "oversaturated", "plastic looking", "cgi", "illustration", "cartoon"
].join(", ");

/* Noms anglais des ingrédients. C'est de la présentation, pas de la donnée de
 * sécurité — les allergènes restent dérivés du catalogue français. */
const NOMS_EN = {
  farine_ble: "wheat flour", farine_avoine: "oat flour", farine_riz: "rice flour",
  farine_pois_chiches: "chickpea flour", melange_sans_gluten: "gluten-free flour blend",
  fecule_mais: "cornstarch", flocons_avoine: "rolled oats", chapelure: "breadcrumbs",
  chapelure_sans_gluten: "gluten-free breadcrumbs", pates_ble: "wheat pasta",
  pates_riz: "rice pasta", riz: "rice", couscous: "couscous", quinoa: "quinoa",
  tortillas_ble: "flour tortillas", tortillas_mais: "corn tortillas",

  oeuf: "egg", compote_pommes: "unsweetened applesauce", puree_banane: "mashed banana",
  lin_moulu: "ground flaxseed", graines_chia: "chia seeds", aquafaba: "aquafaba",

  lait_vache: "milk", beurre: "butter", creme_35: "heavy cream",
  fromage_cheddar: "cheddar cheese", fromage_parmesan: "parmesan",
  fromage_mozzarella: "mozzarella", yogourt_nature: "plain yogurt",
  yogourt_grec: "greek yogurt", boisson_soya: "soy milk", boisson_avoine: "oat milk",
  lait_coco: "coconut milk", yogourt_coco: "coconut yogurt", yogourt_soya: "soy yogurt",
  margarine_sans_lait: "dairy-free margarine", levure_alimentaire: "nutritional yeast",

  huile_olive: "olive oil", huile_canola: "canola oil", puree_avocat: "mashed avocado",
  beurre_arachide: "peanut butter", beurre_tournesol: "sunflower seed butter",
  beurre_soya: "soy butter", tahini: "tahini", beurre_amande: "almond butter",
  noix_grenoble: "walnuts",

  poulet: "chicken", dinde_hachee: "ground turkey", poisson_blanc: "white fish",
  saumon: "salmon", crevette: "shrimp", tofu_ferme: "firm tofu",
  lentilles: "cooked lentils", pois_chiches: "chickpeas",

  miel: "honey", sirop_erable: "maple syrup", sucre: "sugar", dattes: "pitted dates",

  banane: "banana", pomme: "apple", mangue: "mango", bleuets: "blueberries",
  raisins_secs: "raisins", abricots_seches: "dried apricots", jus_citron: "lemon juice",

  patate_douce: "sweet potato", courge_butternut: "butternut squash",
  carotte: "cooked carrot", carotte_crue: "raw carrot", concombre: "cucumber",
  courgette: "zucchini", epinards: "spinach", petits_pois: "green peas",
  poivron: "bell pepper", brocoli: "broccoli", oignon: "onion", ail: "garlic",
  tomates_broyees: "crushed tomatoes",

  moutarde_dijon: "dijon mustard", sel: "salt", cannelle: "cinnamon",
  vanille: "vanilla", basilic: "basil", gingembre: "ginger",
  sauce_soya: "soy sauce", sauce_tamari: "tamari", coco_aminos: "coconut aminos",
  sauce_poisson: "fish sauce", levure_chimique: "baking powder",
  bicarbonate: "baking soda", bouillon_sans_sel: "chicken broth", eau: "water"
};

/* On décrit le TYPE de plat plutôt que de traduire le titre : un titre
 * français traduit mot à mot donne des prompts bancals. */
const PLATS_EN = {
  "Déjeuner": "breakfast dish", "Repas": "family meal",
  "Collation": "snack", "Dessert": "dessert"
};

const EXCLUSIONS = {
  lait: "no visible cheese, cream or butter",
  oeuf: "no visible egg",
  arachide: "no visible peanuts",
  noix: "no visible tree nuts, whole or chopped",
  ble: "no visible bread or wheat pasta",
  soya: "no visible soy sauce",
  sesame: "no visible sesame seeds",
  poisson: "no visible fish",
  crustaces_mollusques: "no visible shellfish",
  moutarde: "no visible mustard",
  sulfites: "no bright orange dried fruit"
};

function nomAnglais(id, catalogue) {
  if (NOMS_EN[id]) return NOMS_EN[id];
  const d = catalogue[id];
  return d ? d.name.toLowerCase().replace(/\(.*?\)/g, "").trim() : id;
}

/* Choix déterministe : même recette, même cadrage, toujours. */
function graine(texte) {
  let h = 0;
  for (const octet of Buffer.from(texte, "utf8")) h = (h * 31 + octet) >>> 0;
  return h;
}

function promptPour(recette, donnees) {
  const catalogue = donnees.catalogue;
  const ordre = ["protein", "flour", "vegetable", "fruit", "dairy", "liquid", "fat", "sweetener"];

  const visibles = recette.ingredients
    .map(function (u) {
      const d = catalogue[u.id];
      if (!d) return null;
      const role = u.role || d.roles[0];
      return { name: nomAnglais(u.id, catalogue), role: role,
               rang: ordre.indexOf(role) === -1 ? 99 : ordre.indexOf(role) };
    })
    .filter(Boolean)
    .filter(function (x) { return ["seasoning", "leavening"].indexOf(x.role) === -1; })
    .sort(function (a, b) { return a.rang - b.rang; })
    .slice(0, 6)
    .map(function (x) { return x.name; });

  const presents = require(path.join(__dirname, "..", "engine", "engine.js"))
    .analyserAllergenes(recette, catalogue);
  const exclusions = Object.keys(EXCLUSIONS)
    .filter(function (id) { return presents.indexOf(id) === -1; })
    .map(function (id) { return EXCLUSIONS[id]; });

  const g = graine(recette.id);
  const cadrage = CADRAGES[g % CADRAGES.length];
  const moment = MOMENTS[Math.floor(g / CADRAGES.length) % MOMENTS.length];
  const plat = PLATS_EN[recette.category] || "home-cooked dish";

  return {
    positif: [
      "A homemade " + plat + " served in an everyday bowl on a kitchen table",
      "clearly visible: " + visibles.join(", "),
      cadrage,
      moment,
      STYLE
    ].join(". "),
    negatif: NEGATIF + ", " + exclusions.join(", "),
    /* La révision reste en français : c'est toi qui la lis. */
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

function aGenerer(corpus, donnees, manifeste, dossierImages) {
  manifeste = manifeste || {};
  const base = dossierImages || racine;

  return corpus.map(function (r) {
    const emp = empreinte(r);
    const actuel = manifeste[r.id];
    /* The manifest says what was verified; the disk says what exists. */
    const surDisque = actuel && actuel.fichier && fs.existsSync(path.join(base, actuel.fichier));
    const etat = !actuel ? "manquante"
      : (!surDisque ? "fichier absent"
      : (actuel.empreinte !== emp ? "périmée" : "à jour"));
    if (etat === "à jour") return null;

    const p = promptPour(r, donnees);
    return {
      id: r.id, name: r.name, etat: etat, empreinte: emp,
      fichier: "images/" + r.id + "-" + emp + ".webp",
      prompt: p.positif, negatif: p.negatif, aVerifier: p.aVerifier
    };
  }).filter(Boolean);
}

function validerEntree(entree, recette, dossierImages) {
  const e = [];
  if (!entree.fichier) e.push("fichier manquant");
  else if (dossierImages !== false) {
    const base = dossierImages || racine;
    if (!fs.existsSync(path.join(base, entree.fichier))) e.push("fichier introuvable sur le disque");
  }
  if (!entree.empreinte) e.push("empreinte manquante");
  if (recette && entree.empreinte !== empreinte(recette))
    e.push("empreinte périmée : les ingrédients ont changé depuis la génération");
  if (!entree.revisePar) e.push("aucune révision — image non publiable");
  if (entree.revisePar && /automatique/i.test(entree.revisePar)) {
    if (!entree.verification) e.push("révision automatique sans verdict de vision");
    else if (!entree.verification.reconnus) e.push("la vision n'a reconnu aucun ingrédient de la recette");
    else if (entree.verification.moteur === "absent") e.push("aucun moteur de vision n'a réellement vérifié");
  }
  if (entree.largeur && entree.largeur < 800) e.push("image trop petite : " + entree.largeur + " px");
  return { ok: e.length === 0, erreurs: e };
}

function visuelPour(recette, resultat, manifeste, dossierImages) {
  const entree = manifeste && manifeste[recette.id];
  const utilisable = entree && validerEntree(entree, recette, dossierImages).ok;
  if (utilisable && resultat.status === "as_is") {
    return { type: "photo", fichier: entree.fichier };
  }
  return { type: "illustration",
           reason: !utilisable ? "aucune photo révisée"
                               : "la recette est adaptée — la photo montrerait autre chose" };
}

if (require.main === module) {
  const donnees = {
    catalogue: lire("data/ingredients.json"),
    substitutions: lire("data/substitutions.json"),
    base: lire("data/base.json")
  };
  let corpus = lire("data/recipes.json");
  for (const p of ["data/imported/imported-recipes.json",
                   "data/generated/generated-recipes.json"]) {
    try { corpus = corpus.concat(lire(p)); } catch (e) {}
  }
  let manifeste = {};
  try { manifeste = lire("generation/images/manifest.json"); } catch (e) {}

  const plan = aGenerer(corpus, donnees, manifeste);
  fs.mkdirSync(path.join(racine, "generation", "images"), { recursive: true });
  fs.writeFileSync(path.join(racine, "generation", "images", "to-generate.json"),
    JSON.stringify(plan, null, 2) + "\n");
  if (!fs.existsSync(path.join(racine, "generation", "images", "manifest.json"))) {
    fs.writeFileSync(path.join(racine, "generation", "images", "manifest.json"), "{}\n");
  }
  console.log("À générer : " + plan.length + " image(s) sur " + corpus.length + " recettes");
  if (plan.length) {
    console.log("\nExemple de prompt :\n");
    console.log(plan[0].prompt);
    console.log("\nNégatif :\n");
    console.log(plan[0].negatif);
  }
}

module.exports = { promptPour: promptPour, aGenerer: aGenerer, validerEntree: validerEntree,
                   visuelPour: visuelPour, empreinte: empreinte, STYLE: STYLE,
                   NOMS_EN: NOMS_EN, CADRAGES: CADRAGES };
