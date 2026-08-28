/* Prompts d'image — v2
 *
 * TROIS CHANGEMENTS, ET LE PREMIER EST LE PLUS IMPORTANT.
 *
 * 1. PROMPTS ARE IN ENGLISH. Image models are trained overwhelmingly on
 *    English captions. A French prompt goes through an implicit translation
 *    and loses fidelity — the first cause of soft results.
 *
 * 2. THE AESTHETIC CHANGED. The old one aimed at magazine work: matte
 *    nappe de lin, fond calme. C'est joli et faux. On vise maintenant une
 *    real family kitchen — a wooden counter, window light, a dish towel
 *    lying about, a few crumbs. Imperfection is what makes a photo
 *    believable.
 *
 * 3. COMPOSITION VARIES. Every image used to share the same angle. Thirty
 *    identical photos look like a template, not a collection. The variation
 *    is seeded by the recipe id: deterministic, so a given recipe always
 *    keeps its framing.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));

/* Short on purpose. A 700-character style buries the subject: FLUX weighs the
 * whole prompt, so twenty adjectives about lighting compete with the two words
 * that say what the dish is. The subject leads, the style supports. */
const STYLE = [
  "candid home food photography",
  "soft natural window light",
  "worn wooden table, everyday ceramic",
  "shallow depth of field, 50mm",
  "unstyled and lived-in, sharp focus on the food"
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

/* English ingredient names. This is presentation, not safety data — allergens
 * are still derived from the catalogue. */
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

/* The KIND of dish is described rather than the title translated: a title
 * rendered word for word produces awkward prompts. */
/* The categories are English in the data now; the French keys were left over
 * from before the conversion and every recipe fell through to the generic
 * fallback. */
const PLATS_EN = {
  "Breakfast": "breakfast", "Meal": "meal",
  "Snack": "snack", "Dessert": "dessert"
};

/* How the dish is PRESENTED, read off the servings field.
 *
 * The prompt used to say "a breakfast dish served in an everyday bowl" and
 * then list raw ingredients. FLUX obeyed exactly: a bowl of oats with a raw
 * egg on top, for a muffin recipe. It was never told what the dish IS.
 *
 * The servings field already carries the answer — "12 muffins", "10 patties",
 * "1 loaf" — so the shape and the vessel are derived from it. */
const PRESENTATION = [
  [/muffins?/i,             "muffins in paper liners, cooling on a wire rack"],
  [/cr[eê]pes?|pancakes?/i, "a stack of pancakes on a plate"],
  [/patties|galettes?/i,    "browned patties on a plate"],
  [/nuggets?|croquettes?/i, "baked nuggets on a plate"],
  [/meatballs?|boulettes?/i,"meatballs on a plate"],
  [/bites?|boules?/i,       "small round bites on a plate"],
  [/cookies?|biscuits?/i,   "cookies on a wire rack"],
  [/bars?|barres?/i,        "cut bars on parchment"],
  [/loaf|loaves|pains?/i,   "a loaf on a board, one slice cut"],
  [/frittatas?/i,           "mini frittatas in a muffin tin"],
  [/glass|verres?/i,        "a tall glass on a table"],
  [/\bml\b|cups?/i,        "a small serving bowl with a spoon"]
];

function presentationPour(recette) {
  const p = String(recette.servings || "");
  for (let i = 0; i < PRESENTATION.length; i++) {
    if (PRESENTATION[i][0].test(p)) return PRESENTATION[i][1];
  }
  return "a shallow bowl on a table";
}

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

/* Deterministic choice: same recipe, same framing, always. */
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

  /* The exclusions are stated POSITIVELY, in the prompt itself.
   *
   * Proven by isolation on FLUX schnell: the identical request with a negative
   * prompt returns an embossed relief, without it a clean photo. FLUX is
   * distilled without negative guidance, so the negative is subtracted rather
   * than steered away from.
   *
   * Saying "only these foods and nothing else" is how FLUX is meant to be
   * driven, and the vision check remains the real guard: the prompt asks, the
   * verification decides. An intruder still gets the image rejected. */
  /* THE RECIPE NAME LEADS, then how it is presented, then what it is made of.
   * Naming the dish is what stops FLUX from drawing a bowl of loose
   * ingredients: it renders what you name, and it was never named. */
  return {
    positif: [
      /* The dish, cooked and finished. Saying "cooked and ready to eat" stops
       * FLUX from laying out raw ingredients, which is what a list of them
       * invites — it drew a bowl of loose oats for a muffin recipe. */
      "Homemade " + recette.name.toLowerCase() + ", cooked and ready to eat",
      presentationPour(recette),
      "made with " + visibles.slice(0, 4).join(", "),
      cadrage,
      moment,
      STYLE
    ].join(". "),
    negatif: NEGATIF + ", " + exclusions.join(", "),
    /* Passed to the vision check so it can be asked whether the image looks
     * like THIS dish, not merely whether the ingredients are present. */
    plat: recette.name,
    typePlat: plat,
    /* The review list is for a human reader, not for the model. */
    aVerifier: [
      "the dish looks like: " + recette.name,
      "the visible ingredients match: " + visibles.join(", "),
      "no ingredient outside the recipe appears in the image"
    ].concat(exclusions.map(function (x) { return "check: " + x; }))
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
    const etat = !actuel ? "missing"
      : (!surDisque ? "file missing"
      : (actuel.empreinte !== emp ? "stale" : "current"));
    if (etat === "current") return null;

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
  /* The display needs 1320 px on an iPhone Pro Max, 1640 on an iPad, and the
   * view crops before it fills. Anything under 1320 is upscaled on screen —
   * which is exactly how a set of soft photos got shipped once. */
  const LARGEUR_MIN = 1320;
  if (entree.largeur && entree.largeur < LARGEUR_MIN)
    e.push("image too small: " + entree.largeur + " px wide, " + LARGEUR_MIN + " required");
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
  console.log("À générer : " + plan.length + " image(s) sur " + corpus.length + " recipes");
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
