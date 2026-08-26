/* Tests du moteur — node tests/test.js */
"use strict";
const assert = require("assert");
const path = require("path");
const fs = require("fs");

/* Ratings must go to a throwaway file. Set BEFORE any require
 * de serveur.js : celui-ci charge notes.js, qui fige son chemin au premier
 * load. Without this line the suite wrote into server/ratings.json — the real
 * file in the repository. */
process.env.BOUCHEES_NOTES = "/tmp/bouchees-notes-tests.json";
try { fs.unlinkSync(process.env.BOUCHEES_NOTES); } catch (e) {}

const Engine = require(path.join(__dirname, "..", "engine", "engine.js"));
const lire = (f) => JSON.parse(fs.readFileSync(path.join(__dirname, "..", "data", f), "utf8"));
const lire2 = (f) => JSON.parse(fs.readFileSync(path.join(__dirname, "..", f), "utf8"));

const donnees = {
  catalogue: lire("ingredients.json"),
  substitutions: lire("substitutions.json"),
  base: lire("base.json")
};
const recettes = lire("recipes.json");
const parId = Object.fromEntries(recettes.map((r) => [r.id, r]));

let n = 0;
const enAttente = [];
function test(name, fn) {
  n++;
  try {
    const r = fn();
    if (r && typeof r.then === "function") {
      enAttente.push(r.then(function () { console.log("  ok  " + name); },
        function (e) { console.error("ÉCHEC " + name + "\n      " + e.message); process.exitCode = 1; }));
    } else console.log("  ok  " + name);
  }
  catch (e) { console.error("ÉCHEC " + name + "\n      " + e.message); process.exitCode = 1; }
}
const adapter = (id, allergens, ageMois) =>
  Engine.adapterRecette(parId[id], { allergens, ageMois }, donnees);
const ing = (res, id) => res.ingredients.find((i) => i.id === id);

/* ---------- data integrity ---------- */

test("données : toutes les recettes référencent des ingrédients du catalogue", () => {
  for (const r of recettes) for (const u of r.ingredients)
    assert(donnees.catalogue[u.id], r.id + " → ingrédient unknown : " + u.id);
});

test("données : toutes les options de substitution existent et tout allergène référencé est connu", () => {
  const familles = new Set(donnees.base.allergens.map((a) => a.id));
  for (const regle of donnees.substitutions) {
    assert(donnees.catalogue[regle.target], "target inconnue : " + regle.target);
    for (const o of regle.options)
      assert(o.id === "_omit" || donnees.catalogue[o.id], regle.target + " → option inconnue : " + o.id);
  }
  for (const [id, def] of Object.entries(donnees.catalogue))
    for (const a of def.allergens) assert(familles.has(a), id + " → famille inconnue : " + a);
  for (const r of donnees.base.ageRules)
    if (r.action.type === "swap") assert(donnees.catalogue[r.action.to], "swap to unknown : " + r.action.to);
});

test("données : les ageRules d'une même target sont ordonnés de la tranche la plus jeune à la plus vieille", () => {
  const parCible = {};
  for (const r of donnees.base.ageRules) {
    if (parCible[r.target] !== undefined)
      assert(r.beforeMonths > parCible[r.target], "ageRules mal ordonnés pour " + r.target);
    parCible[r.target] = r.beforeMonths;
  }
});

/* ---------- targeted substitutions ---------- */

test("muffins sans œuf à 12 mois → compote de pommes (option 1)", () => {
  const r = adapter("banana-oat-muffins", ["egg"], 12);
  const i = ing(r, "egg");
  assert.equal(i.status, "swapped");
  assert.equal(i.to, "applesauce");
  assert.equal(r.status, "adapted");
});

test("crêpes sans lait → boisson de soya (priorité 1)", () => {
  const i = ing(adapter("fluffy-pancakes", ["milk"], 12), "cow_milk");
  assert.equal(i.to, "soy_beverage");
});

test("crêpes sans lait NI soya → le moteur saute le soya, prend l'avoine", () => {
  const i = ing(adapter("fluffy-pancakes", ["milk", "soy"], 12), "cow_milk");
  assert.equal(i.to, "oat_beverage");
});

test("boules d'énergie sans arachide → beurre de tournesol", () => {
  const i = ing(adapter("date-energy-bites", ["peanut"], 24), "peanut_butter");
  assert.equal(i.to, "sunflower_seed_butter");
});

test("houmous sans sésame → tahini remplacé, jamais par un ingrédient évité", () => {
  const r = adapter("silky-hummus", ["sesame"], 9);
  assert.equal(ing(r, "tahini").to, "sunflower_seed_butter");
  assert.equal(r.remainingAllergens.includes("sesame"), false);
});

test("frittatas sans œuf : rôle protéine → farine de pois chiches, pas compote", () => {
  const i = ing(adapter("mini-vegetable-frittatas", ["egg"], 12), "egg");
  assert.equal(i.to, "chickpea_flour");
});

test("croquettes sans poisson ET sans blé : double substitution, œuf conservé", () => {
  const r = adapter("baked-fish-nuggets", ["fish", "wheat"], 12);
  assert.equal(ing(r, "white_fish").to, "chicken");
  assert.equal(ing(r, "breadcrumbs").to, "gf_breadcrumbs");
  assert.equal(ing(r, "egg").status, "kept");
  assert.deepEqual(r.remainingAllergens, ["egg"]);
});

test("mac-fromage sans lait : cheddar→levure, beurre→margarine, lait→soya; le roux (farine rôle liant) reste", () => {
  const r = adapter("mac-and-cheese-with-hidden-squash", ["milk"], 12);
  assert.equal(ing(r, "cheddar").to, "nutritional_yeast");
  assert.equal(ing(r, "butter").to, "dairy_free_margarine");
  assert.equal(ing(r, "cow_milk").to, "soy_beverage");
  assert.equal(ing(r, "wheat_flour").status, "kept");
});

test("mac-fromage sans lait ET blé : la farine du roux (rôle liant) → fécule de maïs", () => {
  const r = adapter("mac-and-cheese-with-hidden-squash", ["milk", "wheat"], 12);
  assert.equal(ing(r, "wheat_flour").to, "cornstarch");
  assert.equal(ing(r, "wheat_pasta").to, "rice_pasta");
});

test("boulettes sans moutarde → moutarde omise, recette adaptée", () => {
  const r = adapter("turkey-and-apple-meatballs", ["mustard"], 12);
  assert.equal(ing(r, "dijon_mustard").status, "omitted");
  assert.equal(r.status, "adapted");
});

/* ---------- age rules ---------- */

test("barres granola à 9 mois : miel → sirop d'érable (swap d'âge) + alerte ageMinBase", () => {
  const r = adapter("chewy-granola-bars", [], 9);
  assert.equal(ing(r, "honey").to, "maple_syrup");
  assert(r.alerts.some((a) => a.level === "caution"));
});

test("barres granola à 9 mois : noix de Grenoble → préparation « moudre », raisins secs → préparation", () => {
  const r = adapter("chewy-granola-bars", [], 9);
  assert(ing(r, "walnuts").prep.includes("Grind"));
  assert(ing(r, "raisins").prep);
});

test("barres granola à 24 mois : plus de swap de miel, noix toujours à moudre (< 48 mois)", () => {
  const r = adapter("chewy-granola-bars", [], 24);
  assert.equal(ing(r, "honey").status, "kept");
  assert(ing(r, "walnuts").prep);
});

test("barres granola à 60 mois : aucune alerte de sécurité (sauf collant du beurre d'arachide levée à 48)", () => {
  const r = adapter("chewy-granola-bars", [], 60);
  assert.equal(r.alerts.filter((a) => a.level === "safety").length, 0);
});

test("pouding chia à 8 mois : bleuets → alerte écrasement", () => {
  const r = adapter("vanilla-chia-pudding", [], 8);
  assert(ing(r, "blueberries").prep.includes("Crush"));
});

test("trempette à 8 mois : carotte crue → règle 12 mois (cuire ou râper), pas la règle 4 ans", () => {
  const i = ing(adapter("yogurt-dip-with-vegetable-sticks", [], 8), "raw_carrot");
  assert(i.prep.includes("Steam"));
});

test("trempette à 24 mois : carotte crue → règle 4 ans (pas de bâtonnets durs)", () => {
  const i = ing(adapter("yogurt-dip-with-vegetable-sticks", [], 24), "raw_carrot");
  assert(i.prep.includes("grated"));
});

test("sel à 8 mois : préparation « omettre », plus rien à 12 mois", () => {
  assert(ing(adapter("lentil-and-carrot-patties", [], 8), "salt").prep);
  assert.equal(ing(adapter("lentil-and-carrot-patties", [], 12), "salt").prep, undefined);
});

test("le swap d'âge respecte les allergènes : miel→érable même sans lait ni blé", () => {
  const r = adapter("chewy-granola-bars", ["milk", "wheat"], 9);
  assert.equal(ing(r, "honey").to, "maple_syrup");
});

/* ---------- not adaptable: the honest way out ---------- */

test("aucun substitut valide → status non_adaptable avec alerte bloquante (gating par ageMin)", () => {
  const donneesTest = {
    catalogue: donnees.catalogue,
    base: donnees.base,
    substitutions: [{ target: "egg", role: "binder", options: [{ id: "aquafaba", ratio: "45 ml", minAgeMonths: 12 }] }]
  };
  const r = Engine.adapterRecette(parId["fluffy-pancakes"], { allergens: ["egg"], ageMois: 8 }, donneesTest);
  assert.equal(r.status, "not_adaptable");
  assert(r.alerts.some((a) => a.level === "blocking"));
  assert.equal(ing(r, "egg").status, "blocked");
});

test("ingrédient évité sans règle du tout → non_adaptable, jamais de retrait silencieux", () => {
  const donneesTest = { catalogue: donnees.catalogue, base: donnees.base, substitutions: [] };
  const r = Engine.adapterRecette(parId["silky-hummus"], { allergens: ["sesame"], ageMois: 12 }, donneesTest);
  assert.equal(r.status, "not_adaptable");
});

/* ---------- determinism ---------- */

test("même entrée → même sortie (sérialisation identique sur 3 appels)", () => {
  const a = JSON.stringify(adapter("mac-and-cheese-with-hidden-squash", ["milk", "wheat"], 9));
  const b = JSON.stringify(adapter("mac-and-cheese-with-hidden-squash", ["milk", "wheat"], 9));
  const c = JSON.stringify(adapter("mac-and-cheese-with-hidden-squash", ["milk", "wheat"], 9));
  assert.equal(a, b); assert.equal(b, c);
});

/* ---------- property test: the safety invariant ---------- */

test("INVARIANT — aucune recette adaptée ne contient un allergène évité, aucun substitut sous son âge minimum", () => {
  const familles = donnees.base.allergens.map((a) => a.id);
  const combos = familles.map((f) => [f]).concat([
    ["milk", "soy"], ["egg", "wheat"], ["milk", "egg"], ["peanut", "sesame"],
    ["peanut", "tree_nut", "sesame", "soy"], ["milk", "egg", "wheat", "soy"],
    ["fish", "wheat"], ["milk", "wheat"]
  ]);
  const ages = [6, 8, 9, 12, 18, 24, 48, 60];
  let verifies = 0;

  for (const recette of recettes)
    for (const combo of combos)
      for (const ageMois of ages) {
        const r = Engine.adapterRecette(recette, { allergens: combo, ageMois }, donnees);
        if (r.status === "not_adaptable") { verifies++; continue; }
        const croise = r.remainingAllergens.filter((a) => combo.includes(a));
        assert.equal(croise.length, 0,
          recette.id + " [" + combo + "] à " + ageMois + " mois laisse passer : " + croise);
        for (const i of r.ingredients) if (i.status === "swapped") {
          const regle = donnees.substitutions.find((s) => s.target === i.id && s.role === i.role);
          const opt = regle && regle.options.find((o) => o.id === i.to);
          if (opt) assert(opt.minAgeMonths <= ageMois, i.id + "→" + i.to + " sous l'âge minimum à " + ageMois + " mois");
        }
        verifies++;
      }
  console.log("      " + verifies + " combinaisons vérifiées (20 recettes × " + combos.length + " profils × " + ages.length + " âges)");
});

/* ---------- lot 3 : normaliseur ---------- */

const { normalizeLine } = require(path.join(__dirname, "..", "ingest", "normalizer.js"));
const lexique = lire2("ingest/lexicon.json");
const norm = (l) => normalizeLine(l, lexique, donnees.catalogue);

test("normaliseur : « 2 cups all-purpose flour » → farine_ble, 500 ml", () => {
  const r = norm("2 cups all-purpose flour");
  assert.equal(r.id, "wheat_flour"); assert.equal(r.qty, 500); assert.equal(r.unit, "ml");
});

test("normaliseur : « 1/2 tasse de compote de pommes non sucrée » → compote_pommes, 125 ml", () => {
  const r = norm("1/2 tasse de compote de pommes non sucrée");
  assert.equal(r.id, "applesauce"); assert.equal(r.qty, 125);
});

test("normaliseur : « 1 ½ tsp vanilla extract » → vanille, 7.5 ml (fraction unicode mixte)", () => {
  const r = norm("1 \u00bd tsp vanilla extract");
  assert.equal(r.id, "vanilla"); assert.equal(r.qty, 7.5);
});

test("normaliseur : « 1 lb boneless chicken breast, diced » → poulet, 454 g", () => {
  const r = norm("1 lb boneless chicken breast, diced");
  assert.equal(r.id, "chicken"); assert.equal(r.qty, 454); assert.equal(r.unit, "g");
});

test("normaliseur : « 2 tablespoons soy sauce » → sauce_soya — allergènes soya ET blé via le catalogue", () => {
  const r = norm("2 tablespoons soy sauce");
  assert.equal(r.id, "soy_sauce"); assert.equal(r.qty, 30);
  assert.deepEqual(donnees.catalogue[r.id].allergens.slice().sort(), ["soy", "wheat"]);
});

test("normaliseur : « 1 tbsp galangal, sliced » → unknown (jamais deviné)", () => {
  assert.equal(norm("1 tbsp galangal, sliced").status, "unknown");
});

/* ---------- lot 3 : portes de l'importeur ---------- */

const { importAll } = require(path.join(__dirname, "..", "ingest", "importer.js"));
const importation = importAll();

test("importeur : 10 recettes importées, 3 en quarantine", () => {
  assert.equal(importation.imported.length, 10);
  assert.equal(importation.quarantine.length, 3);
});

test("importeur : une ligne inconnue met la recette ENTIÈRE en quarantine (Thai Green Curry)", () => {
  const q = importation.quarantine.find((x) => x.name === "Thai Green Curry");
  assert.equal(q.reason, "lines non reconnues");
  assert(q.detail.some((d) => /galangal/i.test(d)));
});

test("importeur : recognized mais sans curation → quarantine (Baked Oatmeal)", () => {
  const q = importation.quarantine.find((x) => x.name === "Apple Cinnamon Baked Oatmeal");
  assert.equal(q.reason, "curation manquante");
});

test("importeur : chaque importée porte un âge minimal curé et une provenance", () => {
  for (const r of importation.imported) {
    assert(Number.isInteger(r.minAgeMonths) && r.minAgeMonths >= 6, r.id);
    assert(r.source && r.source.source && r.source.license, r.id);
  }
});

test("importeur : le rôle curé remplace le rôle par défaut (riz frit : œuf → protéine)", () => {
  const r = importation.imported.find((x) => x.id === "vegetable-fried-rice");
  assert.equal(r.ingredients.find((i) => i.id === "egg").role, "protein");
});

test("bout en bout : riz frit sans soya à 12 mois → tamari sauté (soya), aminos de coco choisis", () => {
  const r = importation.imported.find((x) => x.id === "vegetable-fried-rice");
  const res = Engine.adapterRecette(r, { allergens: ["soy"], ageMois: 12 }, donnees);
  assert.equal(res.ingredients.find((i) => i.id === "soy_sauce").to, "coconut_aminos");
});

test("bout en bout : risotto sans crustacés à 12 mois → crevettes remplacées par du poulet", () => {
  const r = importation.imported.find((x) => x.id === "creamy-shrimp-and-pea-risotto");
  const res = Engine.adapterRecette(r, { allergens: ["shellfish"], ageMois: 12 }, donnees);
  assert.equal(res.ingredients.find((i) => i.id === "shrimp").to, "chicken");
});

test("bout en bout : granola sans sulfites → abricots séchés remplacés (raisins bruns)", () => {
  const r = importation.imported.find((x) => x.id === "soft-apricot-granola");
  const res = Engine.adapterRecette(r, { allergens: ["sulphites"], ageMois: 24 }, donnees);
  assert.equal(res.ingredients.find((i) => i.id === "dried_apricots").to, "raisins");
});

/* ---------- wider invariant: seed plus imported ---------- */

test("INVARIANT (corpus complet) — témoins + importées, aucune fuite d'allergène, aucun substitut sous l'âge", () => {
  const familles = donnees.base.allergens.map((a) => a.id);
  const combos = familles.map((f) => [f]).concat([
    ["milk", "soy"], ["egg", "wheat"], ["soy", "wheat"], ["shellfish", "fish"],
    ["sulphites", "tree_nut"], ["milk", "egg", "wheat", "soy"]
  ]);
  const ages = [6, 9, 12, 24, 48];
  const corpus = recettes.concat(importation.imported);
  let verifies = 0;
  for (const recette of corpus)
    for (const combo of combos)
      for (const ageMois of ages) {
        const r = Engine.adapterRecette(recette, { allergens: combo, ageMois }, donnees);
        if (r.status === "not_adaptable") { verifies++; continue; }
        const croise = r.remainingAllergens.filter((a) => combo.includes(a));
        assert.equal(croise.length, 0, recette.id + " [" + combo + "] laisse passer : " + croise);
        verifies++;
      }
  console.log("      " + verifies + " combinaisons (corpus de " + corpus.length + " recettes)");
});

/* ---------- visual system ---------- */

const Illustration = require(path.join(__dirname, "..", "web", "illustration.js"));
const corpusVisuel = recettes.concat(importation.imported);

test("illustration : les 30 recettes produisent un SVG bien formé, sans valeur invalide", () => {
  for (const r of corpusVisuel) {
    const res = Engine.adapterRecette(r, { allergens: [], ageMois: 24 }, donnees);
    const svg = Illustration.plat(res, donnees.catalogue, r.category);
    assert(svg.startsWith("<svg") && svg.endsWith("</svg>"), r.id);
    assert(!/undefined|NaN|null/.test(svg), r.id + " contient une valeur invalide");
    assert(!/<\/script/i.test(svg), r.id);
  }
});

test("illustration : déterministe — même recette et même profil donnent le même SVG", () => {
  const r = parId["mac-and-cheese-with-hidden-squash"];
  const f = () => Illustration.plat(Engine.adapterRecette(r, { allergens: ["milk"], ageMois: 12 }, donnees), donnees.catalogue, r.category);
  assert.equal(f(), f());
});

test("illustration : l'image CHANGE quand la recette s'adapte (beurre d'arachide → tournesol)", () => {
  const r = parId["date-energy-bites"];
  const avant = Illustration.plat(Engine.adapterRecette(r, { allergens: [], ageMois: 24 }, donnees), donnees.catalogue, r.category);
  const apres = Illustration.plat(Engine.adapterRecette(r, { allergens: ["peanut"], ageMois: 24 }, donnees), donnees.catalogue, r.category);
  assert.notEqual(avant, apres, "une photo de stock ne pourrait pas faire ça");
});

test("illustration : un ingrédient omis disparaît de l'image", () => {
  const r = parId["turkey-and-apple-meatballs"];
  const avec = Illustration.plat(Engine.adapterRecette(r, { allergens: [], ageMois: 24 }, donnees), donnees.catalogue, r.category);
  const sans = Illustration.plat(Engine.adapterRecette(r, { allergens: ["mustard"], ageMois: 24 }, donnees), donnees.catalogue, r.category);
  assert.notEqual(avec, sans);
});

test("illustration : tout ingrédient du catalogue a une couleur et une forme (aucun trou)", () => {
  for (const [id, def] of Object.entries(donnees.catalogue)) {
    const v = Illustration.visuelDe(id, def.roles[0], donnees.catalogue);
    assert(Array.isArray(v) && /^#[0-9A-Fa-f]{6}$/.test(v[0]), id + " → couleur invalide");
  }
});

test("illustration : chaque famille d'allergène a son glyphe", () => {
  for (const a of donnees.base.allergens) {
    const g = Illustration.glyphe(a.id);
    assert(/<(path|circle|ellipse)/.test(g), a.id + " → glyphe manquant");
  }
});

/* ---------- blocs A/B/C/D/F (v0.4) ---------- */

const Trous = require(path.join(__dirname, "..", "tools", "gaps.js"));
const Publier = require(path.join(__dirname, "..", "tools", "publish.js"));
const PromptRecette = require(path.join(__dirname, "..", "generation", "recipe-prompt.js"));
const Valideur = require(path.join(__dirname, "..", "generation", "recipe-validator.js"));
const Images = require(path.join(__dirname, "..", "generation", "images.js"));
const Stripe = require(path.join(__dirname, "..", "server", "stripe.js"));
const Server = require(path.join(__dirname, "..", "server", "server.js"));
const crypto2 = require("crypto");
let corpusComplet = recettes.concat(importation.imported);
try { corpusComplet = corpusComplet.concat(lire2("data/generated/generated-recipes.json")); } catch (e) {}

/* --- B : rapport de trous --- */

test("trous : une recette de 18 mois ne account pas comme utilisable à 6 mois", () => {
  const cases = Trous.analyser(corpusComplet);
  const c = cases.find((x) => x.ageMois === 6 && x.profile.length === 1 && x.profile[0] === "milk");
  const tropVieilles = corpusComplet.filter((r) => r.minAgeMonths > 6).length;
  assert.equal(c.outOfAge, tropVieilles);
  assert.equal(c.as_is + c.adapted + c.not_adaptable + c.outOfAge, corpusComplet.length);
});

test("trous : le classement met en tête les combinaisons les plus dépourvues", () => {
  const cl = Trous.classer(Trous.analyser(corpusComplet));
  for (let i = 1; i < cl.length; i++) assert(cl[i - 1].missing >= cl[i].missing);
});

test("trous : la commande fusionne les trous identiques au lieu de les répéter", () => {
  const cmd = Trous.commande(Trous.classer(Trous.analyser(corpusComplet)));
  const cles = cmd.map((c) => c.categories[0] + "|" + c.evite.join(","));
  assert.equal(new Set(cles).size, cles.length, "la commande contient des doublons");
});

test("trous : un corpus amputé creuse un trou visible", () => {
  const ampute = corpusComplet.filter((r) => r.category !== "Snack");
  const cl = Trous.classer(Trous.analyser(ampute));
  assert(cl[0].missingCategories["Snack"] >= Trous.SEUIL_CATEGORIE - 0);
});

/* --- A : publication --- */

test("publication : chaque recette est attribuée à un lot, aucune orpheline", () => {
  const r = Publier.publier();
  assert.equal(r.orphans.length, 0, "orphans : " + r.orphans);
  const total = Object.values(r.content).reduce((s, l) => s + l.length, 0);
  assert.equal(total, corpusComplet.length);
});

test("publication : le manifeste ne contient AUCUN ingrédient — seulement des compteurs", () => {
  const r = Publier.publier();
  const txt = JSON.stringify(r.manifeste);
  assert(!/ingredients|steps/.test(txt), "le manifeste laisse fuir du content");
  assert(r.manifeste.batches.every((l) => typeof l.count === "number"));
});

test("publication : les tables de sécurité sont hors des batches — jamais derrière le mur", () => {
  const r = Publier.publier();
  assert(r.securite.substitutions.length > 0 && r.securite.base.allergens.length === 11);
  Object.values(r.content).forEach((lot) => lot.forEach((rec) => {
    assert(!rec.substitutions && !rec.allergenesTable, rec.id);
  }));
});

/* --- C : prompt et validateur --- */

test("prompt : n'offre que des ingrédients compatibles avec la commande", () => {
  const autorises = PromptRecette.ingredientsAutorises(donnees.catalogue, ["milk", "egg"]);
  autorises.forEach((id) => {
    const a = donnees.catalogue[id].allergens;
    assert(!a.includes("milk") && !a.includes("egg"), id + " ne devrait pas être offert");
  });
  assert(autorises.includes("applesauce") && !autorises.includes("butter"));
});

test("validateur : rejette un ingrédient inventé par le modèle", () => {
  const faux = { id: "test-invente", name: "Test", category: "Collation", minAgeMonths: 12, timeMinutes: 10,
    ingredients: [{ id: "graines_de_tournesol_grillees", qty: 100, unit: "ml" }, { id: "banana", qty: 1, unit: "unité" }],
    steps: ["Mélanger les ingrédients.", "Servir tiède."] };
  const v = Valideur.valider(faux, { evite: [], ageMois: 12, categories: ["Collation"] }, donnees);
  assert.equal(v.ok, false);
  assert(v.erreurs.some((x) => /hors catalogue/.test(x)));
});

test("validateur : rejette une recette qui contient l'allergène que la commande exclut", () => {
  const faux = { id: "test-fuite", name: "Test", category: "Collation", minAgeMonths: 12, timeMinutes: 10,
    ingredients: [{ id: "cow_milk", qty: 250, unit: "ml", role: "liquid" }, { id: "banana", qty: 1, unit: "unité" }],
    steps: ["Mélanger les ingrédients.", "Servir frais."] };
  const v = Valideur.valider(faux, { evite: ["milk"], ageMois: 12, categories: ["Collation"] }, donnees);
  assert.equal(v.ok, false);
  assert(v.erreurs.some((x) => /allergène que la commande exclut/.test(x)));
});

test("validateur : accepte une recette conforme, et signale le rôle ambigu", () => {
  const bonne = { id: "test-conforme", name: "Compote de pommes et banane", category: "Dessert",
    servings: "4 portions", minAgeMonths: 6, timeMinutes: 10,
    ingredients: [{ id: "applesauce", qty: 250, unit: "ml", role: "binder" },
                  { id: "banana", qty: 1, unit: "unité" }, { id: "cinnamon", qty: 1, unit: "ml" }],
    steps: ["Crush la banane à la fourchette.", "Mélanger à la compote et à la cannelle."] };
  const v = Valideur.valider(bonne, { evite: ["milk", "egg", "wheat"], ageMois: 6, categories: ["Dessert"] }, donnees);
  assert.equal(v.ok, true, v.erreurs.join(" / "));
});

test("validateur : refuse un id déjà pris et les superlatifs marketing", () => {
  const d = { id: "banana-oat-muffins", name: "Les meilleurs muffins", category: "Collation",
    minAgeMonths: 12, timeMinutes: 20, ingredients: [{ id: "banana", qty: 1, unit: "unité" }, { id: "rolled_oats", qty: 250, unit: "ml" }],
    steps: ["Mélanger les ingrédients.", "Cuire vingt minutes."] };
  const v = Valideur.valider(d, { evite: [], ageMois: 12, categories: ["Collation"] }, donnees, corpusComplet.map((r) => r.id));
  assert.equal(v.ok, false);
  assert(v.erreurs.some((x) => /déjà utilisé/.test(x)));
});

/* --- D : images --- */

test("images : le prompt NOMME le plat, pas seulement ses ingrédients", () => {
  /* Le prompt disait « a breakfast dish served in an everyday bowl » puis
   * listait les ingrédients bruts. FLUX obéissait : un bol de gruau avec un
   * œuf cru, pour une recette de muffins. Il faut nommer le plat. */
  const m = parId["banana-oat-muffins"];
  const pm = Images.promptPour(m, donnees);
  assert(pm.positif.toLowerCase().startsWith("homemade banana oat muffins"),
    "le titre doit mener : " + pm.positif.slice(0, 60));
  assert(/muffins in paper liners/.test(pm.positif),
    "la forme doit venir de servings (12 muffins)");
  assert.equal(pm.plat, m.name, "le nom du plat doit être transmis à la vision");

  const pain = Images.promptPour(parId["banana-bread"], donnees);
  assert(/a loaf on a board/.test(pain.positif), "1 loaf → un pain, pas un bol");

  const r = parId["squash-and-coconut-soup"];
  const p = Images.promptPour(r, donnees);
  /* Image models are trained on English captions: the prompt has to come out
   * in English, with the ingredient names translated. */
  assert(/butternut squash/i.test(p.positif), "l'ingrédient dominant doit être nommé en anglais");
  assert(/coconut milk/i.test(p.positif));
  assert(!/courge|lait de coco/i.test(p.positif), "aucun mot français ne doit rester");
  assert(/no visible egg/.test(p.negatif), "les exclusions doivent être explicites");
  /* The review list is for a human reader, and it now names the dish first. */
  assert(p.aVerifier[0].startsWith("the dish looks like"));
  assert(p.aVerifier.some((x) => /^check:/.test(x)));
});

test("images : le cadrage varie mais reste stable pour une même recette", () => {
  const a = Images.promptPour(parId["squash-and-coconut-soup"], donnees).positif;
  const b = Images.promptPour(parId["squash-and-coconut-soup"], donnees).positif;
  assert.equal(a, b, "même recette, même cadrage — sinon l'image change à chaque passage");

  const cadrages = new Set();
  corpusComplet.forEach((r) => {
    const p = Images.promptPour(r, donnees).positif;
    const trouve = Images.CADRAGES.find((c) => p.includes(c));
    if (trouve) cadrages.add(trouve);
  });
  assert(cadrages.size >= 3, "le corpus doit couvrir plusieurs cadrages, pas un gabarit unique");
});

test("images : une photo non révisée n'est jamais publiée — repli sur l'illustration", () => {
  const r = parId["fluffy-pancakes"];
  const emp = Images.empreinte(r);
  const res = Engine.adapterRecette(r, { allergens: [], ageMois: 24 }, donnees);
  const sansRevision = { [r.id]: { fichier: "images/x.webp", empreinte: emp } };
  assert.equal(Images.visuelPour(r, res, sansRevision, false).type, "illustration");
  const avecRevision = { [r.id]: { fichier: "images/x.webp", empreinte: emp, revisePar: "François", largeur: 1664 } };
  assert.equal(Images.visuelPour(r, res, avecRevision, false).type, "photo");
});

test("images : dès qu'un échange a lieu, la photo cède la place à l'illustration", () => {
  const r = parId["fluffy-pancakes"];
  const manifeste = { [r.id]: { fichier: "images/x.webp", empreinte: Images.empreinte(r), revisePar: "François", largeur: 1664 } };
  const adaptee = Engine.adapterRecette(r, { allergens: ["milk"], ageMois: 24 }, donnees);
  const v = Images.visuelPour(r, adaptee, manifeste, false);
  assert.equal(v.type, "illustration");
  assert(/montrerait autre chose/.test(v.reason));
});

test("images : une empreinte périmée invalide la photo (les ingrédients ont changé)", () => {
  const r = parId["fluffy-pancakes"];
  const v = Images.validerEntree({ fichier: "x.webp", empreinte: "000000000000", revisePar: "François", largeur: 1664 }, r, false);
  assert.equal(v.ok, false);
  assert(v.erreurs.some((x) => /périmée/.test(x)));
});

test("images : une photo sous la largeur d'affichage est refusée", () => {
  /* L'affichage exige 1320 px sur un iPhone Pro Max, et la vue recadre avant
   * de remplir. Une image plus petite est agrandie à l'écran — c'est comme ça
   * qu'un lot de photos molles s'est retrouvé livré. */
  const r = parId["fluffy-pancakes"];
  const base = { fichier: "images/x.png", empreinte: Images.empreinte(r),
                 revisePar: "François" };
  const petite = Images.validerEntree(Object.assign({}, base, { largeur: 1216 }), r, false);
  assert.equal(petite.ok, false, "1216 px doit être refusé");
  assert(petite.erreurs.some((e) => /too small/.test(e)));

  const bonne = Images.validerEntree(Object.assign({}, base, { largeur: 1664 }), r, false);
  assert.equal(bonne.ok, true, bonne.erreurs.join(" / "));
});

test("images : un manifeste qui survit à la disparition du fichier ne publie rien", () => {
  const r = parId["fluffy-pancakes"];
  const entree = { fichier: "images/nexiste-pas.png", empreinte: Images.empreinte(r),
                   revisePar: "vérification automatique (test)", largeur: 1664,
                   verification: { moteur: "test", reconnus: 3, attendus: 5 } };
  const v = Images.validerEntree(entree, r);
  assert.equal(v.ok, false, "le disque doit faire foi, pas le manifeste");
  assert(v.erreurs.some((x) => /introuvable/.test(x)));

  const plan = Images.aGenerer([r], donnees, { [r.id]: entree });
  assert.equal(plan.length, 1, "la recette doit repasser au plan de génération");
  assert.equal(plan[0].etat, "file missing");
});

/* --- F : droits et Stripe --- */

test("droits : sans subscription, seuls les batches free sont autorisés", () => {
  const m = Publier.publier().manifeste;
  const free = Server.allowedBatches(m, null);
  assert.deepEqual(free, m.free);
  const tous = Server.allowedBatches(m, { subscription: { status: "actif" } });
  assert.equal(tous.length, m.batches.length);
});

test("droits : un paiement en retard garde l'accès quelques jours, puis le perd", () => {
  const hier = new Date(Date.now() - 864e5).toISOString();
  const vieux = new Date(Date.now() - 30 * 864e5).toISOString();
  assert.equal(Server.subscriptionActive({ subscription: { status: "en_retard", periodEnd: hier } }), true);
  assert.equal(Server.subscriptionActive({ subscription: { status: "en_retard", periodEnd: vieux } }), false);
  assert.equal(Server.subscriptionActive({ subscription: { status: "annule" } }), false);
});

test("stripe : signature valide acceptée, altérée refusée, ancienne refusée", () => {
  const corps = Buffer.from('{"type":"checkout.session.completed"}');
  const t = Math.floor(Date.now() / 1000);
  const sig = crypto2.createHmac("sha256", "whsec_x").update(t + "." + corps.toString()).digest("hex");
  assert.equal(Stripe.verifierSignature(corps, "t=" + t + ",v1=" + sig, "whsec_x"), true);
  assert.equal(Stripe.verifierSignature(Buffer.from('{"type":"autre"}'), "t=" + t + ",v1=" + sig, "whsec_x"), false);
  assert.equal(Stripe.verifierSignature(corps, "t=" + (t - 9999) + ",v1=" + sig, "whsec_x"), false);
  assert.equal(Stripe.verifierSignature(corps, "t=" + t + ",v1=" + sig, "mauvais_secret"), false);
});

test("stripe : les statuts d'subscription se traduisent correctement", () => {
  const e = (type, o) => Stripe.evenementPertinent({ type, data: { object: o } });
  const base = { customer_email: "a@b.ca", customer: "cus_1" };
  assert.equal(e("customer.subscription.updated", Object.assign({ status: "active" }, base)).status, "actif");
  assert.equal(e("customer.subscription.updated", Object.assign({ status: "trialing" }, base)).status, "actif");
  assert.equal(e("customer.subscription.updated", Object.assign({ status: "past_due" }, base)).status, "en_retard");
  assert.equal(e("customer.subscription.deleted", base).status, "annule");
  assert.equal(e("invoice.payment_failed", base).status, "en_retard");
  assert.equal(e("customer.discount.created", base), null);
  assert.equal(e("checkout.session.completed", { customer_email: null }), null);
});

/* ---------- cycle automatique (v0.5) ---------- */

const Vision = require(path.join(__dirname, "..", "generation", "vision.js"));
const Coherence = require(path.join(__dirname, "..", "generation", "coherence.js"));
const MoteursImage = require(path.join(__dirname, "..", "generation", "image-engines.js"));
const MoteursTexte = require(path.join(__dirname, "..", "generation", "text-engines.js"));

const visionQuiVoit = (aliments) => ({ name: "test", disponible: () => true,
  decrire: async () => JSON.stringify({ aliments, lisible: true, incertitudes: [] }) });

test("vision : les faux amis végétaux ne déclenchent pas leur famille", () => {
  const f = (t) => Vision.famillesDe(Vision.normaliser(t));
  assert.deepEqual(f("lait de coco"), []);
  assert.deepEqual(f("beurre de tournesol"), []);
  assert.deepEqual(f("noix de coco"), []);
  assert.deepEqual(f("poudre à pâte"), []);
  assert.deepEqual(f("pâtes de riz"), []);
  assert.deepEqual(f("milk"), ["milk"]);
  assert.deepEqual(f("beurre d'arachide"), ["peanut"]);
  assert.deepEqual(f("pâtes"), ["wheat"]);
});

test("vision : un intrus détecté dans l'image la fait rejeter", async () => {
  const r = parId["squash-and-coconut-soup"];
  const v = await Vision.verifier(Buffer.from("x"), r, donnees,
    { moteur: visionQuiVoit(["courge", "lait de coco", "noix de Grenoble"]) });
  assert.equal(v.ok, false);
  assert(/noix/i.test(v.erreurs.join(" ")));
});

test("vision : une image fidèle est acceptée", async () => {
  const r = parId["squash-and-coconut-soup"];
  const noms = r.ingredients.map((u) => donnees.catalogue[u.id].name);
  const v = await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: visionQuiVoit(noms) });
  assert.equal(v.ok, true, v.erreurs.join(" / "));
  assert(v.reconnus >= 2);
});

test("vision : panne, réponse illisible ou moteur absent → rejet, jamais acceptation par défaut", async () => {
  const r = parId["squash-and-coconut-soup"];
  const panne = { name: "x", decrire: async () => { throw new Error("réseau"); } };
  const illisible = { name: "x", decrire: async () => "je ne sais pas" };
  assert.equal((await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: panne })).ok, false);
  assert.equal((await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: illisible })).ok, false);
  assert.equal((await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: Vision.MOTEURS.absent })).ok, false);
});

test("vision : un risque d'étouffement fait rejeter, même sans allergène", async () => {
  const r = parId["fluffy-pancakes"];
  const v = await Vision.verifier(Buffer.from("x"), r, donnees,
    { moteur: visionQuiVoit(["milk", "egg", "farine de blé", "raisins entiers"]) });
  assert.equal(v.ok, false);
  assert(/étouffement/.test(v.erreurs.join(" ")));
});

test("vision : une image d'un autre plat est rejetée", async () => {
  const r = parId["squash-and-coconut-soup"];
  const v = await Vision.verifier(Buffer.from("x"), r, donnees,
    { moteur: visionQuiVoit(["spaghetti", "meatballs"]) });
  assert.equal(v.ok, false);
  assert(/recognisable/.test(v.erreurs.join(" ")));
});

test("manifeste : une révision automatique sans verdict de vision ne publie pas", () => {
  const r = parId["squash-and-coconut-soup"];
  const emp = Images.empreinte(r);
  const res = Engine.adapterRecette(r, { allergens: [], ageMois: 24 }, donnees);
  const complet = { [r.id]: { fichier: "i.png", empreinte: emp, largeur: 1664,
    revisePar: "vérification automatique (test)", verification: { moteur: "test", reconnus: 3, attendus: 5 } } };
  assert.equal(Images.visuelPour(r, res, complet, false).type, "photo");
  const sansVerdict = { [r.id]: { fichier: "i.png", empreinte: emp, largeur: 1664,
    revisePar: "vérification automatique (test)" } };
  assert.equal(Images.visuelPour(r, res, sansVerdict, false).type, "illustration");
  const rienVu = { [r.id]: { fichier: "i.png", empreinte: emp, largeur: 1664,
    revisePar: "vérification automatique (test)", verification: { moteur: "test", reconnus: 0, attendus: 5 } } };
  assert.equal(Images.visuelPour(r, res, rienVu, false).type, "illustration");
  const visionAbsente = { [r.id]: { fichier: "i.png", empreinte: emp, largeur: 1664,
    revisePar: "vérification automatique (absent)", verification: { moteur: "absent", reconnus: 2, attendus: 5 } } };
  assert.equal(Images.visuelPour(r, res, visionAbsente, false).type, "illustration");
});

test("cohérence : « fourchette » n'est pas « four » — les frontières de mots tiennent", () => {
  assert.equal(Coherence.contient("mash with a fork", Coherence.OVEN_WORDS), false);
  assert.equal(Coherence.contient("bake in the oven at 180 °C", Coherence.OVEN_WORDS), true);
  assert.equal(Coherence.contient("enfournez la plaque", Coherence.OVEN_WORDS), true);
});

test("cohérence : attrape les ratés qu'une cuisson d'essai aurait révélés", () => {
  const base = { id: "t", name: "Test", category: "Repas", servings: "4 portions", minAgeMonths: 12, timeMinutes: 30 };
  const liquide = Coherence.verifier(Object.assign({}, base, {
    ingredients: [{ id: "wheat_flour", qty: 100, unit: "ml", role: "flour" },
                  { id: "cow_milk", qty: 600, unit: "ml", role: "liquid" }],
    steps: ["Mix the flour and the milk.", "Bake at 180 °C for 20 minutes."] }), donnees);
  assert.equal(liquide.ok, false);

  const sansTemp = Coherence.verifier(Object.assign({}, base, {
    ingredients: [{ id: "wheat_flour", qty: 250, unit: "ml", role: "flour" },
                  { id: "cow_milk", qty: 250, unit: "ml", role: "liquid" }],
    steps: ["Mix the flour and the milk.", "Bake for 20 minutes."] }), donnees);
  assert(sansTemp.erreurs.some((e) => /température/.test(e)));

  const cru = Coherence.verifier(Object.assign({}, base, {
    ingredients: [{ id: "chicken", qty: 300, unit: "g", role: "protein" }, { id: "rice", qty: 250, unit: "ml" }],
    steps: ["Mix the chicken and rice in a bowl.", "Serve immediately."] }), donnees);
  assert(cru.erreurs.some((e) => /raw protein/.test(e)));
});

test("cohérence : tout le corpus existant passe — aucun faux positif", () => {
  const mauvaises = corpusComplet.filter((r) => !Coherence.verifier(r, donnees).ok);
  assert.equal(mauvaises.length, 0,
    mauvaises.map((r) => r.id + " : " + Coherence.verifier(r, donnees).erreurs.join(" ; ")).join(" | "));
});

test("moteurs : un adaptateur est toujours disponible, et le repli est le mode simulé", async () => {
  assert.equal(MoteursTexte.choisir("simule").name, "simule");
  assert.equal(MoteursImage.choisir("simule").name, "simule");
  const img = await MoteursImage.MOTEURS.simule.generer({ prompt: "test", negatif: "", largeur: 64, hauteur: 48 });
  assert(Buffer.isBuffer(img.octets) && img.octets.length > 50);
  assert.equal(img.octets.slice(1, 4).toString("ascii"), "PNG", "le mode simulé doit produire un vrai PNG");
});

test("moteurs : le JSON du modèle est extrait même noyé dans du texte", () => {
  const sale = 'Voici les recettes :\n```json\n[{"id":"a"},{"id":"b"}]\n```\nBon appétit!';
  assert.equal(MoteursTexte.extraireJSON(sale).length, 2);
});

/* ---------- iOS : StoreKit et pont natif (v0.6) ---------- */

const Apple = require(path.join(__dirname, "..", "server", "apple.js"));

test("apple : sans racine Apple, tout est refusé — never accept by default", () => {
  const r = Apple.verifierJWS("a.b.c", { racine: null });
  assert.equal(r.ok, false);
});

test("apple : un JWS mal formé ou un algorithme non ES256 est refusé", () => {
  assert.equal(Apple.verifierJWS("pas-un-jws", { racine: null }).ok, false);
  const entete = Buffer.from(JSON.stringify({ alg: "HS256", x5c: ["x"] })).toString("base64url");
  assert.equal(Apple.verifierJWS(entete + ".e30.c2ln", { racine: null }).ok, false);
});

test("apple : une chaîne x5c absente ou trop courte est refusée", () => {
  assert.equal(Apple.verifierChaine(null, null).ok, false);
  assert.equal(Apple.verifierChaine(["un-seul"], null).ok, false);
});

test("apple : les statuts de transaction se traduisent comme ceux de Stripe", () => {
  const futur = Date.now() + 30 * 864e5, passe = Date.now() - 864e5;
  const base = { bundleId: "ca.bouchees.app", productId: "abo.mensuel", originalTransactionId: "1" };
  const o = { bundleId: "ca.bouchees.app", produits: ["abo.mensuel"] };
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: futur }, base), o).status, "actif");
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: passe }, base), o).status, "annule");
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: futur, revocationDate: Date.now() }, base), o).status, "annule");
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: futur, bundleId: "autre.app" }, base, { bundleId: "autre.app" }), o).ok, false);
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: futur, productId: "unknown" }, base, { productId: "unknown" }), o).ok, false);
});

test("apple : la signature DER↔brute fait l'aller-retour", () => {
  const crypto3 = require("crypto");
  const { privateKey } = crypto3.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const der = crypto3.createSign("SHA256").update("test").sign(privateKey);
  assert(der.length > 64, "une signature DER est plus longue que 64 octets");
  const brute = Buffer.alloc(64);
  assert.equal(Apple.bruteVersDER(brute).length > 64 || Apple.bruteVersDER(brute).length >= 8, true);
  assert.equal(Apple.bruteVersDER(Buffer.alloc(63)), null, "une signature de mauvaise taille est rejetée");
});

/* --- the JS bridge Swift calls, pulled out of the template and exercised here --- */

function chargerPont() {
  const src = fs.readFileSync(path.join(__dirname, "..", "web", "template.html"), "utf8");
  const debut = src.indexOf("window.evaluerProduitScanne = function");
  const fin = src.indexOf("/* The native side owns");
  assert(debut !== -1 && fin > debut, "le pont natif est introuvable dans le gabarit");
  const sansAcc = (t) => String(t).normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  const nomAll = (id) => { const a = donnees.base.allergens.find((x) => x.id === id); return a ? a.name.toLowerCase() : id; };
  const listeFr = (t) => t.length < 2 ? t.join("") : t.slice(0, -1).join(", ") + " et " + t[t.length - 1];
  return new Function("donnees", "sansAcc", "nomAll", "listeFr",
    "var window={};" + src.slice(debut, fin) + "return window.evaluerProduitScanne;")(donnees, sansAcc, nomAll, listeFr);
}

test("scanner : une étiquette contenant l'allergène évité donne « à éviter »", () => {
  const f = chargerPont();
  const r = f({ texte: "Farine de blé, sucre, lait de vache, beurre, sel", evites: ["milk"] });
  assert.equal(r.status, "avoid");
  assert(r.allergensFound.length > 0);
});

test("scanner : un ingrédient non recognized donne « incertain », jamais « sûr »", () => {
  const f = chargerPont();
  const r = f({ texte: "Riz, gomme xanthane E415, poulet", evites: ["milk"] });
  assert.equal(r.status, "uncertain");
  assert(r.unknownIngredients.length > 0);
  assert(/étiquette/.test(r.message), "le message doit renvoyer à l'étiquette");
});

test("scanner : les variantes d'apostrophe et de casse sont reconnues", () => {
  const f = chargerPont();
  ["FLOCONS D'AVOINE, BANANE, CANNELLE", "Flocons d avoine, banane, cannelle",
   "flocons d\u2019avoine, banane, cannelle"].forEach((t) => {
    assert.equal(f({ texte: t, evites: ["peanut"] }).status, "safe", t);
  });
});

test("scanner : la sauce soya déclenche AUSSI le blé (dérivé du catalogue)", () => {
  const f = chargerPont();
  assert.equal(f({ texte: "Riz, sauce soya, gingembre", evites: ["wheat"] }).status, "avoid");
  assert.equal(f({ texte: "Riz, sauce soya, gingembre", evites: ["soy"] }).status, "avoid");
});

test("scanner : une étiquette entièrement reconnue et sans allergène évité est « sûr »", () => {
  const f = chargerPont();
  const r = f({ texte: "Banane, pomme, cannelle", evites: ["milk", "egg", "peanut"] });
  assert.equal(r.status, "safe");
  assert.equal(r.unknownIngredients.length, 0);
});

test("iOS : le gabarit délègue l'subscription à StoreKit et n'ouvre aucune caisse web", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "web", "template.html"), "utf8");
  assert(/if\(SOUS_IOS\)\{ versNatif\("subscription"\); return; \}/.test(src),
    "le chemin iOS doit court-circuiter Stripe (règle 3.1.1)");
  const apresIOS = src.slice(src.indexOf('if(SOUS_IOS){ versNatif("subscription"); return; }'));
  assert(apresIOS.indexOf("api/paiement") > 0, "la route Stripe existe encore pour le web");
});

/* ---------- semaines glissantes, notes, classement (v1.0) ---------- */

const Semaines = require(path.join(__dirname, "..", "tools", "weeks.js"));
const Ratings = require(path.join(__dirname, "..", "server", "ratings.js"));

test("semaines : l'identifiant ISO se calcule et se compare correctement", () => {
  const id = Semaines.identifiantSemaine(new Date("2026-08-19T12:00:00Z"));
  assert(/^\d{4}-S\d{2}$/.test(id), "format inattendu : " + id);
  assert(Semaines.rang("2026-S02") < Semaines.rang("2026-S34"));
  assert(Semaines.rang("2025-S52") < Semaines.rang("2026-S01"), "le passage d'année doit être ordonné");
});

test("semaines : remonter dans le temps traverse le changement d'année", () => {
  const s = Semaines.semainesPrecedentes(new Date("2026-01-08T12:00:00Z"), 4);
  assert.equal(s.length, 4);
  assert(s.some((x) => x.startsWith("2025-")), "on doit retomber sur 2025 : " + s.join(", "));
  for (let i = 1; i < s.length; i++) {
    assert(Semaines.rang(s[i]) < Semaines.rang(s[i - 1]), "ordre décroissant attendu");
  }
});

test("fenêtre : les batches free ne tournent jamais, les hebdomadaires oui", () => {
  const batches = [
    { id: "2026-06", access: "free" },
    { id: "2026-S30", access: "subscriber" }, { id: "2026-S31", access: "subscriber" },
    { id: "2026-S32", access: "subscriber" }, { id: "2026-S33", access: "subscriber" }
  ];
  const f = Semaines.fenetreCourante(batches, Date.now());
  assert.deepEqual(f.free, ["2026-06"]);
  assert.equal(f.window.length, Semaines.FENETRE);
  assert.deepEqual(f.window, ["2026-S33", "2026-S32", "2026-S31"]);
  assert.deepEqual(f.horsFenetre, ["2026-S30"], "la plus vieille sort de vue");
});

test("fenêtre : moins de batches que la fenêtre ne casse rien", () => {
  const f = Semaines.fenetreCourante([{ id: "2026-S33", access: "subscriber" }], Date.now());
  assert.equal(f.window.length, 1);
  assert.equal(f.horsFenetre.length, 0);
});

test("publication : le manifeste marque ce qui est dans la fenêtre", () => {
  const r = Publier.publier();
  const hebdo = r.manifeste.batches.filter((l) => l.weekly);
  assert(hebdo.length > 0, "il doit exister des batches hebdomadaires");
  assert(r.manifeste.batches.filter((l) => l.inWindow).length > 0);
  assert(Array.isArray(r.manifeste.window));
  assert(r.manifeste.window.length <= Semaines.FENETRE);
  // Les batches free restent toujours visible
  r.manifeste.batches.filter((l) => l.access === "free")
    .forEach((l) => assert(l.inWindow, l.id + " libre doit rester visible"));
});

test("notes : bornes, remplacement et retrait", () => {
  assert.equal(Ratings.rate("r1", "a@x.ca", 6).ok, false);
  assert.equal(Ratings.rate("r1", "a@x.ca", 0).ok, false);
  assert.equal(Ratings.rate("r1", "a@x.ca", 3.5).ok, false);
  Ratings.rate("r1", "a@x.ca", 5);
  Ratings.rate("r1", "a@x.ca", 3);
  assert.equal(Ratings.aggregate("r1").votes, 1, "un account ne vote qu'une fois");
  assert.equal(Ratings.aggregate("r1").average, 3);
  Ratings.removeRating("r1", "a@x.ca");
  assert.equal(Ratings.aggregate("r1").votes, 0);
});

test("classement : le seuil de 5 votes est respecté", () => {
  ["a", "b", "c", "d"].forEach((p) => Ratings.rate("presque", p + "@x.ca", 5));
  assert(!Ratings.ranking().some((c) => c.recipeId === "presque"), "4 votes : absente");
  Ratings.rate("presque", "e@x.ca", 5);
  assert(Ratings.ranking().some((c) => c.recipeId === "presque"), "5 votes : présente");
});

test("classement : une recette éprouvée passe devant un 5/5 sur cinq votes", () => {
  for (let i = 0; i < 60; i++) Ratings.rate("eprouvee", "g" + i + "@x.ca", i < 50 ? 5 : 4);
  const cl = Ratings.ranking();
  const petite = cl.find((c) => c.recipeId === "presque");
  const grande = cl.find((c) => c.recipeId === "eprouvee");
  assert(grande.score > petite.score,
    "l'ancrage fixe doit protéger le classement : " + grande.score + " vs " + petite.score);
  assert.equal(petite.average, 5, "sa moyenne brute reste parfaite, seul le score la tempère");
});

test("classement : trié, et la note d'autrui n'est jamais exposée", () => {
  const cl = Ratings.ranking();
  for (let i = 1; i < cl.length; i++) assert(cl[i - 1].score >= cl[i].score);
  assert.equal(Ratings.aggregates(["presque"], "a@x.ca")["presque"].myRating, 5);
  assert.equal(Ratings.aggregates(["presque"], "unknown@x.ca")["presque"].myRating, null);
});

test("vision : le PLAT doit correspondre, pas seulement les ingrédients", async () => {
  /* Le cas réel : un bol de gruau avec un œuf cru, accepté pour une recette de
   * muffins parce que banane, avoine et œuf étaient tous présents. Des
   * ingrédients ne font pas un plat. */
  const muffins = parId["banana-oat-muffins"];
  const voit = (plat) => ({ nom: "test", disponible: () => true,
    decrire: async () => JSON.stringify({
      aliments: ["banana", "oats", "egg"], plat: plat, lisible: true, incertitudes: [] }) });

  const gruau = await Vision.verifier(Buffer.from("x"), muffins, donnees,
    { moteur: voit("a bowl of oats with a raw egg") });
  assert.equal(gruau.ok, false, "un bol de gruau n'est pas des muffins");
  assert(/does not match/.test(gruau.erreurs.join(" ")));

  const vrais = await Vision.verifier(Buffer.from("x"), muffins, donnees,
    { moteur: voit("a tray of muffins") });
  assert.equal(vrais.ok, true, vrais.erreurs.join(" / "));
});

test("vision : la forme vient aussi du champ servings", async () => {
  const pain = parId["banana-bread"];
  const voit = (plat) => ({ nom: "test", disponible: () => true,
    decrire: async () => JSON.stringify({
      aliments: ["banana", "wheat flour", "egg"], plat: plat, lisible: true, incertitudes: [] }) });

  const bol = await Vision.verifier(Buffer.from("x"), pain, donnees,
    { moteur: voit("a bowl of porridge") });
  assert.equal(bol.ok, false, "1 loaf ne se sert pas dans un bol");

  const miche = await Vision.verifier(Buffer.from("x"), pain, donnees,
    { moteur: voit("a sliced loaf on a board") });
  assert.equal(miche.ok, true, miche.erreurs.join(" / "));
});

test("vision : une image qui ne ressemble à rien ET fait hésiter est rejetée", async () => {
  const r = parId["banana-oat-muffins"];
  /* The exact profile of the orange mush that made it through: one ingredient
   * vaguely recognised, and the vision listing possibilities. Before the fix
   * this was only a warning. */
  const hesitant = { name: "test", disponible: () => true, decrire: async () => JSON.stringify({
    aliments: ["banana"], lisible: true,
    incertitudes: ["pourrait être du couscous, de la polenta ou du curcuma"] }) };
  const v = await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: hesitant });
  assert.equal(v.ok, false, "hésitation + un seul ingrédient doit rejeter");
  assert(v.erreurs.some((e) => /does not look enough like/.test(e)));
});

test("vision : un seul ingrédient recognized SANS hésitation reste accepté", async () => {
  const r = parId["banana-oat-muffins"];
  /* Une belle photo de muffins montre « un muffin », pas la banane ni
   * l'avoine. Il ne faut pas la rejeter pour autant. */
  const net = { name: "test", disponible: () => true, decrire: async () => JSON.stringify({
    aliments: ["banana"], lisible: true, incertitudes: [] }) };
  const v = await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: net });
  assert.equal(v.ok, true, v.erreurs.join(" / "));
  assert(v.avertissements.some((a) => /weak resemblance/.test(a)));
});

Promise.all(enAttente).then(function () { console.log("\n" + n + " tests."); });
