/* Image models are trained overwhelmingly on English captions. Imperfection
 * is what makes a photo believable. */
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const root = path.join(__dirname, "..");
const read = (p) => JSON.parse(fs.readFileSync(path.join(root, p), "utf8"));

/* Short on purpose. A 700-character style buries the subject: FLUX weighs the
 * whole prompt, so twenty adjectives about lighting compete with the two words
 * that say what the dish is. The subject leads, the style supports. */
/* A model gives you what you NAME, and nothing here named a single concrete
 * imperfection — so it produced a clean dish, centred, wiped, lit evenly. */
/* No furniture named: "Worn wooden table" and "one corner of the table
 * visible" are what pulled the camera back far enough to include a room. */
/* Where it sits, and what is behind it: named without a distance it became
 * the subject; named WITH one it is depth. */
const SURFACES = [
  "on a honed marble counter, warm wood cabinetry blurred behind",
  "on a pale oak worktop, a softly lit kitchen falling away behind",
  "on a matte ceramic plate on dark stone, warm light and soft shapes behind",
  "on a light concrete counter, the warm blur of a kitchen behind"
];

/* No light here: saying it twice cost 50 characters and pushed three prompts
 * over the 500 limit — where the clause that gets dropped is this one, the
 * style. */
const STYLE = [
  "candid home photo, handheld",
  "shallow depth of field, 85mm macro"
].join(", ");

/* Two of these are drawn per recipe. More than two and the picture starts to
 * look staged in a different way — deliberately messy, which reads as fake
 * just as fast. */
/* ONE mark per recipe, and short: one concrete imperfection does the work. */
/* "One piece broken open" earns its place twice: it is the imperfection that
 * says a person was here, AND it is the only way to show the crumb — which is
 * what tells a parent whether their own batch came out right. */
const IMPERFECTIONS = [
  "one broken open so the crumb shows",
  "one cut in half, the inside facing the camera",
  "crumbs beside it",
  "uneven browning across the top",
  "a spoon left beside it",
  "the dish slightly off-centre"
];

/* Close: every framing now states the distance, and every one is close. */
const CADRAGES = [
  "close-up filling the frame, camera about 30 cm away",
  "three-quarter angle from 40 degrees, very close",
  "tight overhead crop, the dish filling most of the frame",
  "low eye-level, close enough to see the crumb"
];

/* Warm and directional, all three: the model got opposite instructions, and
 * the flat grey windowsill in the first muffin photo is what that looks like. */
const MOMENTS = [
  "warm light raking across from the left, deep soft shadows",
  "warm light from behind and to the side, the edges glowing",
  "warm overhead light pooling on the surface, the background dim"
];

const NEGATIF = [
  "no whole nuts", "no whole grapes", "no candy", "no text", "no logos",
  "no watermark", "no people", "no hands", "no faces",
  "no polished silverware", "no black background", "no studio lighting",
  "no artificial steam", "no garnish that is not listed",
  /* The catalogue tells: these are what made every render look bought
   * rather than baked. */
  "not a cookbook photo", "no food styling", "no perfect symmetry",
    /* The framing stops the room, not these: naming furniture pulled the camera
   * back only because nothing said how close to stand. */
  "not shot from across a room", "no wide shot", "no empty space around the dish",
  "no blown-out highlights", "no bare wall behind the dish",
  "no cluttered background", "no visible room corners",
  "no wiped plate rim", "no garnish placed for the photo",
  "no props arranged around the dish", "no even studio-flat lighting",
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

/* How the dish is PRESENTED, read off the servings field: the servings field
 * already carries the answer — "12 muffins", "10 patties", "1 loaf" — so the
 * shape and the vessel are derived from it. */
/* How many, and how close: a count belongs in the presentation, because it is
 * the presentation: three muffins photographed close say more about the
 * recipe than twelve photographed from across a room. */
const PRESENTATION = [
  [/muffins?/i,             "three muffins in paper liners, close together"],
  [/cr[e\u00ea]pes?|pancakes?/i, "a short stack of three pancakes"],
  [/patties|galettes?/i,    "two browned patties"],
  [/nuggets?|croquettes?/i, "four baked nuggets"],
  [/meatballs?|boulettes?/i,"five meatballs"],
  [/bites?|boules?/i,       "four small round bites"],
  [/cookies?|biscuits?/i,   "three cookies overlapping"],
  [/bars?|barres?/i,        "two cut bars, one stacked on the other"],
  [/loaf|loaves|pains?/i,   "a loaf on a board, two slices cut and leaning"],
  [/frittatas?/i,           "three mini frittatas"],
  [/glass|verres?/i,        "one tall glass, filled"],
  [/\bml\b|cups?/i,        "one shallow bowl, filled to the rim"]
];

function presentationPour(recipe) {
  const p = String(recipe.servings || "");
  for (let i = 0; i < PRESENTATION.length; i++) {
    if (PRESENTATION[i][0].test(p)) return PRESENTATION[i][1];
  }
    /* The fallback needs a count too: it also named a table, which is the word
   * that pulled the camera back in the first place. */
  return "one shallow bowl, filled to the rim";
}

/* Keyed on the catalogue's allergen ids. They were French — lait, ble — and
 * the catalogue says milk, wheat, so no exclusion ever matched: the model
 * breaded four wheat-free patties by reflex. */
const EXCLUSIONS = {
  milk: "no visible cheese, cream or butter, no white sauce",
  egg: "no visible egg, no egg wash or glossy glaze",
  peanut: "no visible peanuts",
  tree_nut: "no visible tree nuts, whole or chopped",
  wheat: "no breadcrumbs or breaded coating, no visible bread or wheat pasta",
  soy: "no visible soy sauce",
  sesame: "no visible sesame seeds",
  fish: "no visible fish",
  shellfish: "no visible shellfish, no shrimp or crab",
  mustard: "no visible mustard",
  sulphites: "no bright orange dried fruit"
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

function promptPour(recipe, data) {
  const catalogue = data.catalogue;
  const ordre = ["protein", "flour", "vegetable", "fruit", "dairy", "liquid", "fat", "sweetener"];

  const visibles = recipe.ingredients
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
    .analyserAllergenes(recipe, catalogue);
  /* Only what the model actually confuses with THIS dish: a patty invites
   * breadcrumbs, a fish dish invites shellfish. Naming all eleven absent
   * allergens would double the prompt and dilute the subject. */
  const REFLEXES = {
    wheat: /pattie|cake|nugget|croquette|ball|bite|fritter/i,
    egg: /pattie|cake|muffin|bread|pancake|fritter/i,
    milk: /puree|soup|sauce|pasta|risotto|oatmeal|mash|rice/i,
    shellfish: /fish|salmon|risotto|rice|paella/i,
    fish: /pasta|rice|patty|cake/i
  };
  const exclusions = Object.keys(EXCLUSIONS)
    .filter(function (id) { return presents.indexOf(id) === -1; })
    .filter(function (id) { return REFLEXES[id] && REFLEXES[id].test(recipe.name); })
    .map(function (id) { return EXCLUSIONS[id]; })
    /* One only: past 500 characters the style clause at the end is what the
     * model drops, and the photo stops looking like the others. The negative
     * prompt still carries every absent allergen. */
    .slice(0, 1);

  const g = graine(recipe.id);
  const cadrage = CADRAGES[g % CADRAGES.length];
  /* Same seed as the framing, so one recipe always gets the same kitchen. */
  const surface = SURFACES[g % SURFACES.length];
  const moment = MOMENTS[Math.floor(g / CADRAGES.length) % MOMENTS.length];
  const plat = PLATS_EN[recipe.category] || "home-cooked dish";

  /* Two imperfections per recipe, keyed to the same seed as the framing so
   * the corpus stays reproducible — a parent reopening a recipe sees the
   * same picture. */
  const marks = IMPERFECTIONS[g % IMPERFECTIONS.length];

    /* The exclusions are stated POSITIVELY, in the prompt itself: fLUX is
   * distilled without negative guidance, so the negative is subtracted rather
   * than steered away from. */
  /* THE RECIPE NAME LEADS, then how it is presented, then what it is made of.
   * Naming the dish is what stops FLUX from drawing a bowl of loose
   * ingredients: it renders what you name, and it was never named. */
  return {
    positif: [
      /* The dish, cooked and finished. Saying "cooked and ready to eat" stops
       * FLUX from laying out raw ingredients, which is what a list of them
       * invites — it drew a bowl of loose oats for a muffin recipe. */
      "Homemade " + recipe.name.toLowerCase() + ", cooked and ready to eat",
      presentationPour(recipe),
      "made with " + visibles.slice(0, 4).join(", "),
      cadrage,
      surface,
      moment,
      /* Named imperfections, before the style block. The subject still
       * leads; these say the picture was taken, not assembled. */
      marks,
      /* Stated positively too: FLUX is distilled without negative guidance,
       * so a negative prompt alone is not subtracted. */
      exclusions.length ? exclusions.join(", ") : null,
      STYLE
    ].filter(Boolean).join(". "),
    negatif: NEGATIF + ", " + Object.keys(EXCLUSIONS)
      .filter(function (id) { return presents.indexOf(id) === -1; })
      .map(function (id) { return EXCLUSIONS[id]; }).join(", "),
    /* Passed to the vision check so it can be asked whether the image looks
     * like THIS dish, not merely whether the ingredients are present. */
    plat: recipe.name,
    typePlat: plat,
    /* The review list is for a human reader, not for the model. */
    aVerifier: [
      "the dish looks like: " + recipe.name,
      "the visible ingredients match: " + visibles.join(", "),
      "no ingredient outside the recipe appears in the image"
    ].concat(exclusions.map(function (x) { return "check: " + x; }))
  };
}

function empreinte(recipe) {
  return crypto.createHash("sha1")
    .update(recipe.id + "|" + recipe.ingredients.map(function (u) { return u.id; }).sort().join(","))
    .digest("hex").slice(0, 12);
}

function aGenerer(corpus, data, manifest, dossierImages) {
  manifest = manifest || {};
  const base = dossierImages || root;

  return corpus.map(function (r) {
    const emp = empreinte(r);
    const actuel = manifest[r.id];
    /* The manifest says what was verified; the disk says what exists. */
    const surDisque = actuel && actuel.fichier && fs.existsSync(path.join(base, actuel.fichier));
    const state = !actuel ? "missing"
      : (!surDisque ? "file missing"
      : (actuel.empreinte !== emp ? "stale" : "current"));
    if (state === "current") return null;

    const p = promptPour(r, data);
    return {
      id: r.id, name: r.name, state: state, empreinte: emp,
      fichier: "images/" + r.id + "-" + emp + ".webp",
      prompt: p.positif, negatif: p.negatif, aVerifier: p.aVerifier
    };
  }).filter(Boolean);
}

function validerEntree(entry, recipe, dossierImages) {
  const e = [];
  if (!entry.fichier) e.push("fichier manquant");
  else if (dossierImages !== false) {
    const base = dossierImages || root;
    if (!fs.existsSync(path.join(base, entry.fichier))) e.push("fichier introuvable sur le disque");
  }
  if (!entry.empreinte) e.push("empreinte manquante");
  if (recipe && entry.empreinte !== empreinte(recipe))
    e.push("empreinte périmée : les ingrédients ont changé depuis la génération");
  if (!entry.revisePar) e.push("aucune révision — image non publiable");
  if (entry.revisePar && /automatique/i.test(entry.revisePar)) {
    if (!entry.verification) e.push("révision automatique sans verdict de vision");
    else if (!entry.verification.reconnus) e.push("la vision n'a reconnu aucun ingrédient de la recette");
    else if (entry.verification.moteur === "absent") e.push("aucun moteur de vision n'a réellement vérifié");
  }
  /* The display needs 1320 px on an iPhone Pro Max, 1640 on an iPad, and the
   * view crops before it fills. Anything under 1320 is upscaled on screen —
   * which is exactly how a set of soft photos got shipped once. */
  const LARGEUR_MIN = 1320;
  if (entry.largeur && entry.largeur < LARGEUR_MIN)
    e.push("image too small: " + entry.largeur + " px wide, " + LARGEUR_MIN + " required");
  return { ok: e.length === 0, erreurs: e };
}

function visuelPour(recipe, result, manifest, dossierImages) {
  const entry = manifest && manifest[recipe.id];
  const utilisable = entry && validerEntree(entry, recipe, dossierImages).ok;
  if (utilisable && result.status === "as_is") {
    return { type: "photo", fichier: entry.fichier };
  }
  return { type: "illustration",
           reason: !utilisable ? "aucune photo révisée"
                               : "la recette est adaptée — la photo montrerait autre chose" };
}

if (require.main === module) {
  const data = {
    catalogue: read("data/ingredients.json"),
    substitutions: read("data/substitutions.json"),
    base: read("data/base.json")
  };
  let corpus = read("data/recipes.json");
  for (const p of ["data/imported/imported-recipes.json",
                   "data/generated/generated-recipes.json"]) {
    try { corpus = corpus.concat(read(p)); } catch (e) {}
  }
  let manifest = {};
  try { manifest = read("generation/images/manifest.json"); } catch (e) {}

  const plan = aGenerer(corpus, data, manifest);
  fs.mkdirSync(path.join(root, "generation", "images"), { recursive: true });
  fs.writeFileSync(path.join(root, "generation", "images", "to-generate.json"),
    JSON.stringify(plan, null, 2) + "\n");
  if (!fs.existsSync(path.join(root, "generation", "images", "manifest.json"))) {
    fs.writeFileSync(path.join(root, "generation", "images", "manifest.json"), "{}\n");
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
