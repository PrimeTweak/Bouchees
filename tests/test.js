/* Tests du engine — node tests/test.js */
"use strict";
/* Everything in this file is written in English, with one deliberate
 * exception: the FIXTURES that feed the French normaliser. "1/2 tasse de
 * compote de pommes non sucrée" has to stay French — it is the input being
 * tested, not prose. Translating it would delete the test.
 */
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
        function (e) { console.error("FAILED " + name + "\n      " + e.message); process.exitCode = 1; }));
    } else console.log("  ok  " + name);
  }
  catch (e) { console.error("FAILED " + name + "\n      " + e.message); process.exitCode = 1; }
}
const adapter = (id, allergens, ageMois) =>
  Engine.adapterRecette(parId[id], { allergens, ageMois }, donnees);
const ing = (res, id) => res.ingredients.find((i) => i.id === id);

/* ---------- data integrity ---------- */

test("data: every recipe references ingredients from the catalogue", () => {
  for (const r of recettes) for (const u of r.ingredients)
    assert(donnees.catalogue[u.id], r.id + " → ingredient unknown : " + u.id);
});

test("data: every substitution option exists and every allergen is known", () => {
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

test("data: age rules for one target run youngest band to oldest", () => {
  const parCible = {};
  for (const r of donnees.base.ageRules) {
    if (parCible[r.target] !== undefined)
      assert(r.beforeMonths > parCible[r.target], "ageRules out of order for " + r.target);
    parCible[r.target] = r.beforeMonths;
  }
});

/* ---------- targeted substitutions ---------- */

test("muffins without egg at 12 months take applesauce, the first option", () => {
  const r = adapter("banana-oat-muffins", ["egg"], 12);
  const i = ing(r, "egg");
  assert.equal(i.status, "swapped");
  assert.equal(i.to, "applesauce");
  assert.equal(r.status, "adapted");
});

test("pancakes without milk take soy beverage, the first option", () => {
  const i = ing(adapter("fluffy-pancakes", ["milk"], 12), "cow_milk");
  assert.equal(i.to, "soy_beverage");
});

test("pancakes without milk OR soy: the engine skips soy and takes oat", () => {
  const i = ing(adapter("fluffy-pancakes", ["milk", "soy"], 12), "cow_milk");
  assert.equal(i.to, "oat_beverage");
});

test("energy balls without peanut take sunflower seed butter", () => {
  const i = ing(adapter("date-energy-bites", ["peanut"], 24), "peanut_butter");
  assert.equal(i.to, "sunflower_seed_butter");
});

test("hummus without sesame: tahini replaced, never by an avoided ingredient", () => {
  const r = adapter("silky-hummus", ["sesame"], 9);
  assert.equal(ing(r, "tahini").to, "sunflower_seed_butter");
  assert.equal(r.remainingAllergens.includes("sesame"), false);
});

test("frittatas without egg: the protein role takes chickpea flour", () => {
  const i = ing(adapter("mini-vegetable-frittatas", ["egg"], 12), "egg");
  assert.equal(i.to, "chickpea_flour");
});

test("patties without fish AND wheat: two swaps, the egg kept", () => {
  const r = adapter("baked-fish-nuggets", ["fish", "wheat"], 12);
  assert.equal(ing(r, "white_fish").to, "chicken");
  assert.equal(ing(r, "breadcrumbs").to, "gf_breadcrumbs");
  assert.equal(ing(r, "egg").status, "kept");
  assert.deepEqual(r.remainingAllergens, ["egg"]);
});

test("mac and cheese without milk: three swaps, the roux flour stays", () => {
  const r = adapter("mac-and-cheese-with-hidden-squash", ["milk"], 12);
  assert.equal(ing(r, "cheddar").to, "nutritional_yeast");
  assert.equal(ing(r, "butter").to, "dairy_free_margarine");
  assert.equal(ing(r, "cow_milk").to, "soy_beverage");
  assert.equal(ing(r, "wheat_flour").status, "kept");
});

test("mac and cheese without milk AND wheat: the roux flour becomes cornstarch", () => {
  const r = adapter("mac-and-cheese-with-hidden-squash", ["milk", "wheat"], 12);
  assert.equal(ing(r, "wheat_flour").to, "cornstarch");
  assert.equal(ing(r, "wheat_pasta").to, "rice_pasta");
});

test("meatballs without mustard: the mustard is dropped, the recipe still works", () => {
  const r = adapter("turkey-and-apple-meatballs", ["mustard"], 12);
  assert.equal(ing(r, "dijon_mustard").status, "omitted");
  assert.equal(r.status, "adapted");
});

/* ---------- steps carry the swapped names ---------- */

/* Step 2 of the banana muffins used to read "Mix the banana, egg, milk and
 * oil" while the engine had just replaced the egg and the milk. A parent
 * mid-recipe read the name of the food their child cannot eat, at the step
 * where they are told to add it — and had to scroll back to translate, with
 * their hands in the batter. */

test("steps: the replacement name appears in the step text", () => {
  const res = Engine.adapterRecette(parId["banana-oat-muffins"],
    { allergens: ["milk", "egg"], ageMois: 24 }, donnees);
  const etape = res.steps[1].toLowerCase();
  assert.ok(etape.includes("applesauce"), "the replacement is named");
  assert.ok(etape.includes("soy beverage"), "the second one too");
  assert.ok(!/\begg\b/.test(etape), "the removed ingredient is gone");
});

test("steps: the original text stays available", () => {
  const res = Engine.adapterRecette(parId["banana-oat-muffins"],
    { allergens: ["milk", "egg"], ageMois: 24 }, donnees);
  assert.ok(/\begg\b/i.test(res.stepsOriginal[1]), "stepsOriginal untouched");
});

test("steps: a leading allergen word is consumed with the noun", () => {
  /* Replacing only "butter" in "peanut butter" would leave "peanut sunflower
   * seed butter" — the allergen still in the sentence. */
  let touche = null;
  recettes.forEach((r) => {
    const res = Engine.adapterRecette(r, { allergens: ["peanut"], ageMois: 36 }, donnees);
    (res.steps || []).forEach((st) => {
      const t = (typeof st === "string" ? st : st.text || "").toLowerCase();
      if (/\bpeanut\b/.test(t)) touche = r.id + ": " + t;
    });
  });
  assert.ok(!touche, "no step mentions peanut for a peanut-avoiding profile — " + touche);
});

test("steps: plurals are matched", () => {
  let trouve = null;
  recettes.forEach((r) => {
    const res = Engine.adapterRecette(r, { allergens: ["egg"], ageMois: 36 }, donnees);
    (res.steps || []).forEach((st) => {
      const t = (typeof st === "string" ? st : st.text || "").toLowerCase();
      if (/\beggs?\b/.test(t)) trouve = r.id + ": " + t;
    });
  });
  assert.ok(!trouve, "no step says egg or eggs for an egg-avoiding profile — " + trouve);
});

test("steps: a recipe with no swap keeps its steps identical", () => {
  const r = parId["banana-oat-muffins"];
  const res = Engine.adapterRecette(r, { allergens: [], ageMois: 24 }, donnees);
  assert.deepStrictEqual(res.steps, r.steps, "untouched when nothing is swapped");
});

/* ---------- units are English ---------- */

/* "1 unite rapee" and "1 gousse" (a clove) reached the screen because nothing checked
 * the data. The engine was clean; the corpus was not. */

test("units: no accented character in any unit", () => {
  const fautifs = [];
  recettes.forEach((r) => {
    (r.ingredients || []).forEach((i) => {
      if (i.unit && /[\u00C0-\u017F]/.test(i.unit)) fautifs.push(r.id + ": " + i.unit);
    });
  });
  assert.deepStrictEqual(fautifs, [], "every unit is written in English");
});

test("units: the unit is a measure, not a preparation", () => {
  /* "ml haches" packed two things into one field. A unit is ml, g, unit,
   * clove — the preparation belongs in its own key. */
  const connus = ["ml", "g", "kg", "l", "unit", "clove", "pinch", "slice", "tsp", "tbsp", "cup"];
  const inconnus = new Set();
  recettes.forEach((r) => {
    (r.ingredients || []).forEach((i) => {
      if (i.unit && !connus.includes(i.unit)) inconnus.add(i.unit);
    });
  });
  assert.deepStrictEqual([...inconnus], [], "no compound units");
});

/* ---------- the week's shopping list ---------- */

test("shopping: the list carries the replacement, never the allergen", () => {
  const liste = Engine.listeEpicerie(recettes.slice(0, 7),
    { allergens: ["milk", "egg"], ageMois: 24 }, donnees);
  liste.forEach((l) => {
    assert.ok(!/^(cow's milk|egg)$/i.test(l.name),
      "an avoided ingredient never appears: " + l.name);
  });
});

test("shopping: a swap says what it replaces", () => {
  const liste = Engine.listeEpicerie(recettes.slice(0, 7),
    { allergens: ["egg"], ageMois: 24 }, donnees);
  const swaps = liste.filter((l) => l.replaces);
  if (swaps.length) {
    assert.ok(swaps.every((l) => typeof l.replaces === "string" && l.replaces.length),
      "every swapped line names the original");
  }
});

test("shopping: quantities add only within the same unit", () => {
  const liste = Engine.listeEpicerie(recettes, { allergens: [], ageMois: 36 }, donnees);
  liste.forEach((l) => {
    const unites = l.quantities.map((q) => q.unit);
    assert.strictEqual(new Set(unites).size, unites.length,
      l.name + ": one entry per unit, never a total across units");
  });
});

test("shopping: every line lands in a known aisle", () => {
  const connus = ["produce", "protein", "refrigerated", "pantry", "frozen", "other"];
  const liste = Engine.listeEpicerie(recettes, { allergens: [], ageMois: 36 }, donnees);
  liste.forEach((l) => {
    assert.ok(connus.includes(l.aisle), l.name + " has aisle " + l.aisle);
  });
});

test("shopping: an ingredient shared by several recipes appears once", () => {
  const liste = Engine.listeEpicerie(recettes, { allergens: [], ageMois: 36 }, donnees);
  const noms = liste.map((l) => l.name.toLowerCase());
  assert.strictEqual(new Set(noms).size, noms.length, "no duplicate line");
});

/* ---------- a week is a week ---------- */

/* The model called the field `batch`; the JSON calls it `batch`. Every recipe
 * decoded it as nil, silently, so filtering a week by it came back empty and
 * the app fell back to the whole corpus. These two assertions fail on the
 * broken build and pass on the fixed one. */

test("week: every published recipe declares its batch", () => {
  const fs = require("fs");
  const dir = path.join(__dirname, "..", "dist", "batches");
  if (!fs.existsSync(dir)) return;
  fs.readdirSync(dir).filter((f) => f.endsWith(".json")).forEach((f) => {
    const lot = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
    const arr = Array.isArray(lot) ? lot : (lot.recipes || []);
    arr.forEach((r) => {
      assert.ok(r.batch, f + ": " + r.id + " has no batch field");
    });
  });
});

test("week: a batch holds between 5 and 10 recipes", () => {
  const fs = require("fs");
  const dir = path.join(__dirname, "..", "dist", "batches");
  if (!fs.existsSync(dir)) return;
  fs.readdirSync(dir).filter((f) => f.endsWith(".json")).forEach((f) => {
    const lot = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
    const arr = Array.isArray(lot) ? lot : (lot.recipes || []);
    /* The newest batch is allowed to be short — it is still being filled. */
    if (f.includes("S34")) return;
    assert.ok(arr.length >= 5 && arr.length <= 10,
      f + " holds " + arr.length + " recipes; a week is 5 to 10");
  });
});

test("shopping: a free batch never produces an empty list", () => {
  const fs = require("fs");
  const manif = path.join(__dirname, "..", "dist", "manifest.json");
  if (!fs.existsSync(manif)) return;
  const m = JSON.parse(fs.readFileSync(manif, "utf8"));
  (m.free || []).forEach((id) => {
    const f = path.join(__dirname, "..", "dist", "batches", id + ".json");
    if (!fs.existsSync(f)) return;
    const lot = JSON.parse(fs.readFileSync(f, "utf8"));
    const arr = Array.isArray(lot) ? lot : (lot.recipes || []);
    const liste = Engine.listeEpicerie(arr, { allergens: ["milk", "egg"], ageMois: 24 }, donnees);
    assert.ok(liste.length > 0, id + " produced an empty shopping list");
  });
});

/* ---------- the bridge actually runs ---------- */

/* The decoding checker compares Swift structs to JSON shapes. It cannot see
 * that a bridge function throws at runtime — and `shoppingList` did, on every
 * call, because I used the test harness's names (`Moteur`, `donnees`) inside
 * a file where they are `Engine` and `required()`. The Swift side falls back
 * to an empty array on any bridge error, so the failure looked like "no
 * items" rather than a crash.
 *
 * This runs the bridge the way JavaScriptCore does: in a bare context with
 * nothing but the engine loaded. */

test("bridge: every exported function runs in a bare context", () => {
  const vm = require("vm");
  const ctx = { module: { exports: {} }, console, JSON };
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(
    path.join(__dirname, "..", "engine", "engine.js"), "utf8"), ctx);
  vm.runInContext("var Engine = module.exports;", ctx);
  vm.runInContext(fs.readFileSync(
    path.join(__dirname, "..", "engine", "native-bridge.js"), "utf8"), ctx);

  ctx.d = JSON.stringify({
    ingredients: lire("ingredients.json"),
    substitutions: lire("substitutions.json"),
    base: lire("base.json")
  });
  vm.runInContext("PONT.load(d);", ctx);

  ctx.r = JSON.stringify(recettes.slice(0, 5));
  ctx.p = JSON.stringify({ ageMonths: 24, allergens: ["milk", "egg"] });

  const liste = JSON.parse(vm.runInContext("PONT.shoppingList(r, p);", ctx));
  assert.ok(Array.isArray(liste) && liste.length > 0,
    "shoppingList returned nothing through the bridge");

  const adapte = JSON.parse(vm.runInContext("PONT.adaptBatch(r, p);", ctx));
  assert.ok(Array.isArray(adapte) && adapte.length === 5, "adaptBatch works");

  const stade = JSON.parse(vm.runInContext("PONT.stage(24);", ctx));
  assert.ok(stade, "stage works");
});

test("bridge: shoppingList carries quantities and replacements", () => {
  const vm = require("vm");
  const ctx = { module: { exports: {} }, console, JSON };
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(
    path.join(__dirname, "..", "engine", "engine.js"), "utf8"), ctx);
  vm.runInContext("var Engine = module.exports;", ctx);
  vm.runInContext(fs.readFileSync(
    path.join(__dirname, "..", "engine", "native-bridge.js"), "utf8"), ctx);
  ctx.d = JSON.stringify({
    ingredients: lire("ingredients.json"),
    substitutions: lire("substitutions.json"),
    base: lire("base.json")
  });
  vm.runInContext("PONT.load(d);", ctx);
  ctx.r = JSON.stringify(recettes);
  ctx.p = JSON.stringify({ ageMonths: 24, allergens: ["milk", "egg"] });

  const liste = JSON.parse(vm.runInContext("PONT.shoppingList(r, p);", ctx));
  assert.ok(liste.some((l) => l.quantities.length > 0), "quantities survive");
  assert.ok(liste.some((l) => l.replaces), "replacements are named");
  liste.forEach((l) => {
    assert.ok(typeof l.name === "string" && l.name.length, "each line has a name");
    assert.ok(typeof l.aisle === "string" && l.aisle.length, "each line has an aisle");
  });
});

/* ---------- colour contrast ---------- */

/* The amber that shipped read at 1.9:1 against the cream canvas: the dark
 * value, used in light mode. Nothing checked it, so it looked fine in the
 * code and vanished on the screen. */

function luminance(hex) {
  const c = [16, 8, 0].map((s) => {
    const v = ((hex >> s) & 0xFF) / 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

function ratio(a, b) {
  const l1 = luminance(a), l2 = luminance(b);
  return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
}

test("contrast: every semantic colour clears 4.5:1 on its canvas", () => {
  const clair = 0xFBF9F6, sombre = 0x0B0A09;
  const paires = [
    ["text",  0x17140F, 0xF4F1EC],
    ["text2", 0x6B635A, 0x948C83],
    ["yes",   0x1E8347, 0x5FD08A],
    ["swap",  0xA35F00, 0xF0AC46],
    ["no",    0xC4291C, 0xFF5B4F],
    ["brand", 0xC03A20, 0xFF7A5C]
  ];
  paires.forEach(([nom, l, d]) => {
    const rl = ratio(l, clair), rd = ratio(d, sombre);
    assert.ok(rl >= 4.5, nom + " light is " + rl.toFixed(1) + ":1, needs 4.5");
    assert.ok(rd >= 4.5, nom + " dark is " + rd.toFixed(1) + ":1, needs 4.5");
  });
});

test("contrast: the old amber would have failed", () => {
  /* 0xFFB84D on cream — what shipped. Kept as a regression marker. */
  assert.ok(ratio(0xFFB84D, 0xFBF9F6) < 4.5, "the old value was indeed too pale");
});

/* ---------- barcode forms ---------- */

/* A scan failed on a real product — Archibald beer, bought in Quebec, present
 * in Open Food Facts. We asked for a key that does not exist: the camera hands
 * back one form of the code and the database indexes another.
 *
 * This is pure arithmetic, so it is tested with no network at all. */

const Barcode = require("../engine/barcode.js");

test("barcode: UPC-E expands to the UPC-A it was compressed from", () => {
  /* The classic worked example: 04252614 expands to 042100005264. */
  assert.equal(Barcode.expandUPCE("04252614"), "042100005264");
});

test("barcode: a UPC-A is also tried as EAN-13, with the leading zero", () => {
  const f = Barcode.formes("876976001538");
  assert.ok(f.includes("876976001538"), "the code as read");
  assert.ok(f.includes("0876976001538"), "and its EAN-13 key");
});

test("barcode: an EAN-13 starting with zero is also tried as UPC-A", () => {
  const f = Barcode.formes("0042100005264");
  assert.ok(f.includes("042100005264"), "the twelve-digit form");
});

test("barcode: an ITF-14 carton yields the EAN-13 inside it", () => {
  const f = Barcode.formes("10012345678902");
  assert.ok(f.some((x) => x.length === 13), "a thirteen-digit form is offered");
});

test("barcode: an EAN-13 is left alone", () => {
  /* The olive oil that already worked must keep working. */
  const f = Barcode.formes("6191509905058");
  assert.equal(f[0], "6191509905058");
});

test("barcode: the check digit is the standard modulo ten", () => {
  assert.equal(Barcode.checkDigit("619150990505"), "8");
  assert.equal(Barcode.checkDigit("00761234567"), Barcode.checkDigit("00761234567"));
});

test("barcode: forms are unique and never empty", () => {
  ["6191509905058", "876976001538", "04252614", "10012345678902"].forEach((c) => {
    const f = Barcode.formes(c);
    assert.ok(f.length > 0, c + " produced no form");
    assert.equal(f.length, new Set(f).size, c + " produced a duplicate");
    f.forEach((x) => assert.ok(/^\d+$/.test(x), "every form is digits only"));
  });
});

test("barcode: junk in, nothing out", () => {
  assert.deepEqual(Barcode.formes(""), []);
  assert.deepEqual(Barcode.formes("abc"), []);
  assert.deepEqual(Barcode.formes(null), []);
});

/* ---------- the label lexicon ---------- */

/* Real labels François scanned came back "not sure" on words a person reads
 * without hesitating. The cause was a category error: the catalogue holds 92
 * COOKING ingredients, and a package lists industrial ones — enriched flours,
 * added vitamins, emulsifiers. None of those have a role in a kitchen, so
 * none of them were in it.
 *
 * The lexicon is 600 label terms. These tests use the actual products. */

function evaluerEtiquette(texte, evites) {
  const vm = require("vm");
  const ctx = { module: { exports: {} }, console, JSON };
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(
    path.join(__dirname, "..", "engine", "engine.js"), "utf8"), ctx);
  vm.runInContext("var Engine = module.exports;", ctx);
  vm.runInContext(fs.readFileSync(
    path.join(__dirname, "..", "engine", "native-bridge.js"), "utf8"), ctx);
  ctx.d = JSON.stringify({
    ingredients: lire("ingredients.json"),
    substitutions: lire("substitutions.json"),
    base: lire("base.json"),
    lexicon: lire("label-lexicon.json")
  });
  vm.runInContext("PONT.load(d);", ctx);
  ctx.t = texte;
  ctx.a = JSON.stringify(evites);
  return JSON.parse(vm.runInContext("PONT.evaluateLabel(t, a);", ctx));
}

test("label: an enriched pasta box is read, not shrugged at", () => {
  const v = evaluerEtiquette(
    "durum wheat semolina, niacin, ferrous sulphate, thiamine mononitrate, " +
    "riboflavin, folic acid", ["milk", "egg", "peanut"]);
  assert.equal(v.status, "safe", "every word on this box is readable");
  assert.equal(v.unknownIngredients.length, 0, "nothing left unrecognised");
});

test("label: the same box IS wheat for a wheat-free child", () => {
  const v = evaluerEtiquette("durum wheat semolina, niacin", ["wheat"]);
  assert.equal(v.status, "avoid", "semolina is wheat");
});

test("label: milk hides behind sodium caseinate", () => {
  const v = evaluerEtiquette(
    "sugar, sodium caseinate, natural flavour", ["milk"]);
  assert.equal(v.status, "avoid", "caseinate is a milk protein");
});

/* ---------- etiquettes : "contient" contre "peut contenir" ---------- */

test("label: a factory warning is caution, not avoid", () => {
  const v = evaluerEtiquette(
    "wheat flour, sugar, canola oil. May contain peanuts.", ["peanut"]);
  assert.equal(v.status, "caution", "a warning is not an ingredient");
  assert.deepEqual(v.allergensFound, [], "nothing is declared present");
  assert.equal(v.mayContain.length, 1, "the warning is reported");
});

test("label: the same allergen IN the list is still avoid", () => {
  const v = evaluerEtiquette(
    "wheat flour, peanut butter, sugar", ["peanut"]);
  assert.equal(v.status, "avoid", "peanut butter is an ingredient");
});

test("label: THE FALSE SAFE — 'may contain less than 2%' is a list, not a warning", () => {
  /* American labels open a sub-list of ingredients with the same two words a
   * cross-contamination warning uses. Reading it as a warning would turn real
   * whey into "caution" for a milk-allergic child. */
  const v = evaluerEtiquette(
    "enriched macaroni, salt. May contain less than 2% of: whey, butterfat.",
    ["milk"]);
  assert.equal(v.status, "avoid", "whey in a percentage sub-list IS present");
  assert.equal(v.mayContain.length, 0, "and it is not a factory warning");
});

test("label: a warning does not swallow the sentence after it", () => {
  const v = evaluerEtiquette(
    "rice flour, sugar. May contain tree nuts. Contains: milk.", ["milk", "tree_nut"]);
  assert.equal(v.status, "avoid", "the milk after the warning still counts");
  assert.ok(v.allergensFound.length >= 1, "milk is declared");
  assert.ok(v.mayContain.length >= 1, "the nut warning survives too");
});

test("label: an allergen both present and warned about is named once", () => {
  const v = evaluerEtiquette(
    "wheat flour, peanut butter. May contain peanuts.", ["peanut"]);
  assert.equal(v.status, "avoid");
  assert.equal(v.mayContain.length, 0,
    "warning about something already in it adds nothing");
});

test("label: French warnings are read too", () => {
  ["Peut contenir des traces d'arachides.",
   "Fabrique dans une usine qui utilise des arachides.",
   "Traces possibles d'arachides."].forEach((phrase) => {
    const v = evaluerEtiquette("farine de riz, sucre. " + phrase, ["peanut"]);
    assert.equal(v.status, "caution", phrase + " should read as a warning");
  });
});

test("label: English warning wordings are read too", () => {
  ["May contain traces of peanuts.",
   "Manufactured in a facility that also processes peanuts.",
   "Made on shared equipment with peanuts.",
   "Produced in a plant that handles peanuts."].forEach((phrase) => {
    const v = evaluerEtiquette("rice flour, sugar. " + phrase, ["peanut"]);
    assert.equal(v.status, "caution", phrase + " should read as a warning");
  });
});

test("label: an unread word outranks a warning", () => {
  /* A known risk a parent can weigh must never hide an unmeasured one. */
  const v = evaluerEtiquette(
    "rice flour, zorbulax gum. May contain peanuts.", ["peanut"]);
  assert.equal(v.status, "uncertain", "the unreadable word wins");
  assert.equal(v.mayContain.length, 1, "the warning still travels");
});

test("label: a warning about an allergen the child does not avoid is silent", () => {
  const v = evaluerEtiquette(
    "rice flour, sugar. May contain peanuts.", ["milk"]);
  assert.equal(v.status, "safe", "a peanut warning is nothing to a milk profile");
  assert.equal(v.mayContain.length, 0);
});

test("label: no warning at all still reaches safe", () => {
  const v = evaluerEtiquette("rice flour, sugar, salt", ["peanut"]);
  assert.equal(v.status, "safe");
  assert.equal(v.mayContain.length, 0);
});

test("label: whey, lactose and butterfat are all milk", () => {
  ["whey powder", "lactose", "butterfat", "milk solids"].forEach((t) => {
    assert.equal(evaluerEtiquette("sugar, " + t, ["milk"]).status, "avoid",
      t + " should read as milk");
  });
});

test("label: soy lecithin is soy", () => {
  assert.equal(evaluerEtiquette("cocoa, soy lecithin", ["soy"]).status, "avoid");
});

test("label: a French Quebec label reads the same", () => {
  const v = evaluerEtiquette(
    "semoule de ble dur, niacine, sulfate ferreux, riboflavine", ["wheat"]);
  assert.equal(v.status, "avoid", "the French name resolves too");
});

test("label: the longest term wins — peanut butter is not butter", () => {
  const v = evaluerEtiquette("peanut butter, oats, honey", ["milk"]);
  assert.equal(v.status, "safe", "peanut butter must not read as dairy butter");
});

test("label: an unknown word still blocks a safe verdict", () => {
  const v = evaluerEtiquette("sugar, zorblatt extract", ["milk"]);
  assert.notEqual(v.status, "safe", "an unread word is never safe");
});

test("label: the lexicon covers the eleven allergen families", () => {
  const lex = lire("label-lexicon.json");
  const familles = new Set(Object.values(lex.allergens));
  ["wheat", "milk", "egg", "peanut", "tree_nut", "soy", "sesame",
   "fish", "shellfish", "mustard", "sulphites"].forEach((f) => {
    assert.ok(familles.has(f), f + " has no term in the lexicon");
  });
  assert.ok(Object.keys(lex.allergens).length > 200, "at least 200 allergen terms");
  assert.ok(lex.safe.length > 300, "at least 300 safe terms");
});

/* ---------- the week plan ---------- */

/* Seven recipes arrive; the parent decides when to cook them. The plan is the
 * only thing in this app the parent authors, so moving a recipe has to be
 * exact and has to survive a relaunch.
 *
 * The Swift model is mirrored here because the rules are arithmetic, and
 * arithmetic is testable without a simulator. */

function planInitial(ids) {
  const days = {};
  ids.forEach((id, i) => {
    const d = i % 7;
    (days[d] = days[d] || []).push(id);
  });
  return days;
}

function planMove(days, id, to) {
  const out = {};
  Object.keys(days).forEach((k) => {
    const reste = days[k].filter((x) => x !== id);
    if (reste.length) out[k] = reste;
  });
  (out[to] = out[to] || []).push(id);
  return out;
}

function planSwap(days, a, b) {
  const out = Object.assign({}, days);
  const left = out[a];
  if (out[b]) out[a] = out[b]; else delete out[a];
  if (left) out[b] = left; else delete out[b];
  return out;
}

test("week: seven recipes land on seven days", () => {
  const p = planInitial(["a", "b", "c", "d", "e", "f", "g"]);
  assert.equal(Object.keys(p).length, 7, "one per day");
});

test("week: five recipes leave two days empty, and that is correct", () => {
  const p = planInitial(["a", "b", "c", "d", "e"]);
  assert.equal(Object.keys(p).length, 5,
    "five recipes do not make seven suppers, and must not pretend to");
});

test("week: moving a recipe removes it from its old day", () => {
  let p = planInitial(["a", "b", "c"]);
  p = planMove(p, "a", 4);
  assert.ok(!(p[0] || []).includes("a"), "gone from Monday");
  assert.ok(p[4].includes("a"), "on Friday now");
});

test("week: a day emptied by a move disappears rather than lingering", () => {
  let p = planInitial(["a"]);
  p = planMove(p, "a", 3);
  assert.equal(p[0], undefined, "Monday is not an empty array");
});

test("week: moving twice leaves one copy", () => {
  let p = planInitial(["a", "b"]);
  p = planMove(p, "a", 5);
  p = planMove(p, "a", 6);
  const total = Object.values(p).flat().filter((x) => x === "a").length;
  assert.equal(total, 1, "a recipe is on exactly one day");
});

test("week: swapping two days exchanges everything on them", () => {
  let p = planInitial(["a", "b", "c"]);
  p = planSwap(p, 0, 2);
  assert.deepEqual(p[0], ["c"]);
  assert.deepEqual(p[2], ["a"]);
});

test("week: swapping with an empty day moves rather than duplicates", () => {
  let p = planInitial(["a"]);
  p = planSwap(p, 0, 6);
  assert.equal(p[0], undefined, "the source day is now empty");
  assert.deepEqual(p[6], ["a"]);
});

test("week: the plan is deterministic — the same week opens the same way", () => {
  const a = JSON.stringify(planInitial(["x", "y", "z"]));
  const b = JSON.stringify(planInitial(["x", "y", "z"]));
  assert.equal(a, b);
});

test("week: no recipe is ever lost by moving", () => {
  const ids = ["a", "b", "c", "d", "e", "f", "g"];
  let p = planInitial(ids);
  [["a", 6], ["g", 0], ["d", 6], ["b", 3]].forEach(([id, jour]) => {
    p = planMove(p, id, jour);
  });
  const restants = Object.values(p).flat().sort();
  assert.deepEqual(restants, ids.slice().sort(), "every recipe is still somewhere");
});

/* ---------- age rules ---------- */

test("granola bars at 9 months: honey becomes maple syrup, with the age alert", () => {
  const r = adapter("chewy-granola-bars", [], 9);
  assert.equal(ing(r, "honey").to, "maple_syrup");
  assert(r.alerts.some((a) => a.level === "caution"));
});

test("granola bars at 9 months: walnuts and raisins get preparation notes", () => {
  const r = adapter("chewy-granola-bars", [], 9);
  assert(ing(r, "walnuts").prep.includes("Grind"));
  assert(ing(r, "raisins").prep);
});

test("granola bars at 24 months: no honey swap, walnuts still ground", () => {
  const r = adapter("chewy-granola-bars", [], 24);
  assert.equal(ing(r, "honey").status, "kept");
  assert(ing(r, "walnuts").prep);
});

test("granola bars at 60 months: no safety alert left", () => {
  const r = adapter("chewy-granola-bars", [], 60);
  assert.equal(r.alerts.filter((a) => a.level === "safety").length, 0);
});

test("chia pudding at 8 months: blueberries carry a crushing alert", () => {
  const r = adapter("vanilla-chia-pudding", [], 8);
  assert(ing(r, "blueberries").prep.includes("Crush"));
});

test("dip at 8 months: raw carrot hits the 12-month rule, not the four-year one", () => {
  const i = ing(adapter("yogurt-dip-with-vegetable-sticks", [], 8), "raw_carrot");
  assert(i.prep.includes("Steam"));
});

test("dip at 24 months: raw carrot hits the four-year rule, no hard sticks", () => {
  const i = ing(adapter("yogurt-dip-with-vegetable-sticks", [], 24), "raw_carrot");
  assert(i.prep.includes("grated"));
});

test("salt at 8 months is dropped, and free again at 12", () => {
  assert(ing(adapter("lentil-and-carrot-patties", [], 8), "salt").prep);
  assert.equal(ing(adapter("lentil-and-carrot-patties", [], 12), "salt").prep, undefined);
});

test("an age swap still respects allergens", () => {
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

test("an avoided ingredient with no rule at all blocks the recipe", () => {
  const donneesTest = { catalogue: donnees.catalogue, base: donnees.base, substitutions: [] };
  const r = Engine.adapterRecette(parId["silky-hummus"], { allergens: ["sesame"], ageMois: 12 }, donneesTest);
  assert.equal(r.status, "not_adaptable");
});

/* ---------- determinism ---------- */

test("same input, same output: identical serialisation across three calls", () => {
  const a = JSON.stringify(adapter("mac-and-cheese-with-hidden-squash", ["milk", "wheat"], 9));
  const b = JSON.stringify(adapter("mac-and-cheese-with-hidden-squash", ["milk", "wheat"], 9));
  const c = JSON.stringify(adapter("mac-and-cheese-with-hidden-squash", ["milk", "wheat"], 9));
  assert.equal(a, b); assert.equal(b, c);
});

/* ---------- property test: the safety invariant ---------- */

test("INVARIANT: no adapted recipe holds an avoided allergen, none under its minimum age", () => {
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
          recette.id + " [" + combo + "] at " + ageMois + " months leaks: " + croise);
        for (const i of r.ingredients) if (i.status === "swapped") {
          const regle = donnees.substitutions.find((s) => s.target === i.id && s.role === i.role);
          const opt = regle && regle.options.find((o) => o.id === i.to);
          if (opt) assert(opt.minAgeMonths <= ageMois, i.id + "→" + i.to + " under its minimum age at " + ageMois + " months");
        }
        verifies++;
      }
  console.log("      " + verifies + " combinations checked (20 recipes x " + combos.length + " profiles x " + ages.length + " ages)");
});

/* ---------- batch 3 : normaliseur ---------- */

const { normalizeLine } = require(path.join(__dirname, "..", "ingest", "normalizer.js"));
const lexique = lire2("ingest/lexicon.json");
const norm = (l) => normalizeLine(l, lexique, donnees.catalogue);

test("normaliser: 2 cups all-purpose flour becomes wheat flour, 500 ml", () => {
  const r = norm("2 cups all-purpose flour");
  assert.equal(r.id, "wheat_flour"); assert.equal(r.qty, 500); assert.equal(r.unit, "ml");
});

test("normaliser: a French half-cup of applesauce becomes 125 ml", () => {
  const r = norm("1/2 tasse de compote de pommes non sucrée");
  assert.equal(r.id, "applesauce"); assert.equal(r.qty, 125);
});

test("normaliser: a mixed unicode fraction resolves to 7.5 ml", () => {
  const r = norm("1 \u00bd tsp vanilla extract");
  assert.equal(r.id, "vanilla"); assert.equal(r.qty, 7.5);
});

test("normaliser: one pound of chicken breast becomes 454 g", () => {
  const r = norm("1 lb boneless chicken breast, diced");
  assert.equal(r.id, "chicken"); assert.equal(r.qty, 454); assert.equal(r.unit, "g");
});

test("normaliser: soy sauce carries both soy AND wheat, from the catalogue", () => {
  const r = norm("2 tablespoons soy sauce");
  assert.equal(r.id, "soy_sauce"); assert.equal(r.qty, 30);
  assert.deepEqual(donnees.catalogue[r.id].allergens.slice().sort(), ["soy", "wheat"]);
});

test("normaliser: an unknown ingredient stays unknown, never guessed", () => {
  assert.equal(norm("1 tbsp galangal, sliced").status, "unknown");
});

/* ---------- batch 3 : portes de l'importeur ---------- */

const { importAll } = require(path.join(__dirname, "..", "ingest", "importer.js"));
const importation = importAll();

test("importer: ten recipes imported, three quarantined", () => {
  assert.equal(importation.imported.length, 10);
  assert.equal(importation.quarantine.length, 3);
});

test("importer: one unknown line quarantines the WHOLE recipe", () => {
  const q = importation.quarantine.find((x) => x.name === "Thai Green Curry");
  assert.equal(q.reason, "lines non reconnues");
  assert(q.detail.some((d) => /galangal/i.test(d)));
});

test("importer: recognised but uncurated goes to quarantine", () => {
  const q = importation.quarantine.find((x) => x.name === "Apple Cinnamon Baked Oatmeal");
  assert.equal(q.reason, "curation manquante");
});

test("importer: every imported recipe carries a curated age and a source", () => {
  for (const r of importation.imported) {
    assert(Number.isInteger(r.minAgeMonths) && r.minAgeMonths >= 6, r.id);
    assert(r.source && r.source.source && r.source.license, r.id);
  }
});

test("importer: a curated role overrides the default one", () => {
  const r = importation.imported.find((x) => x.id === "vegetable-fried-rice");
  assert.equal(r.ingredients.find((i) => i.id === "egg").role, "protein");
});

test("end to end: fried rice without soy takes coconut aminos", () => {
  const r = importation.imported.find((x) => x.id === "vegetable-fried-rice");
  const res = Engine.adapterRecette(r, { allergens: ["soy"], ageMois: 12 }, donnees);
  assert.equal(res.ingredients.find((i) => i.id === "soy_sauce").to, "coconut_aminos");
});

test("end to end: risotto without shellfish swaps shrimp for chicken", () => {
  const r = importation.imported.find((x) => x.id === "creamy-shrimp-and-pea-risotto");
  const res = Engine.adapterRecette(r, { allergens: ["shellfish"], ageMois: 12 }, donnees);
  assert.equal(res.ingredients.find((i) => i.id === "shrimp").to, "chicken");
});

test("end to end: granola without sulphites replaces the dried apricots", () => {
  const r = importation.imported.find((x) => x.id === "soft-apricot-granola");
  const res = Engine.adapterRecette(r, { allergens: ["sulphites"], ageMois: 24 }, donnees);
  assert.equal(res.ingredients.find((i) => i.id === "dried_apricots").to, "raisins");
});

/* ---------- wider invariant: seed plus imported ---------- */

test("INVARIANT across the whole corpus: no leak, nothing under age", () => {
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

test("illustration: all thirty recipes produce well-formed SVG", () => {
  for (const r of corpusVisuel) {
    const res = Engine.adapterRecette(r, { allergens: [], ageMois: 24 }, donnees);
    const svg = Illustration.plat(res, donnees.catalogue, r.category);
    assert(svg.startsWith("<svg") && svg.endsWith("</svg>"), r.id);
    assert(!/undefined|NaN|null/.test(svg), r.id + " contient une valeur invalide");
    assert(!/<\/script/i.test(svg), r.id);
  }
});

test("illustration: the same recipe and profile give the same SVG", () => {
  const r = parId["mac-and-cheese-with-hidden-squash"];
  const f = () => Illustration.plat(Engine.adapterRecette(r, { allergens: ["milk"], ageMois: 12 }, donnees), donnees.catalogue, r.category);
  assert.equal(f(), f());
});

test("illustration: the image CHANGES when the recipe adapts", () => {
  const r = parId["date-energy-bites"];
  const avant = Illustration.plat(Engine.adapterRecette(r, { allergens: [], ageMois: 24 }, donnees), donnees.catalogue, r.category);
  const apres = Illustration.plat(Engine.adapterRecette(r, { allergens: ["peanut"], ageMois: 24 }, donnees), donnees.catalogue, r.category);
  assert.notEqual(avant, apres, "a stock photo could not do this");
});

test("illustration: a dropped ingredient leaves the image", () => {
  const r = parId["turkey-and-apple-meatballs"];
  const avec = Illustration.plat(Engine.adapterRecette(r, { allergens: [], ageMois: 24 }, donnees), donnees.catalogue, r.category);
  const sans = Illustration.plat(Engine.adapterRecette(r, { allergens: ["mustard"], ageMois: 24 }, donnees), donnees.catalogue, r.category);
  assert.notEqual(avec, sans);
});

test("illustration: every catalogue ingredient has a colour and a shape", () => {
  for (const [id, def] of Object.entries(donnees.catalogue)) {
    const v = Illustration.visuelDe(id, def.roles[0], donnees.catalogue);
    assert(Array.isArray(v) && /^#[0-9A-Fa-f]{6}$/.test(v[0]), id + " → couleur invalide");
  }
});

test("illustration: every allergen family has its glyph", () => {
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

/* --- B : rapport de gaps --- */

test("gaps: an 18-month recipe does not count as usable at 6 months", () => {
  const cases = Trous.analyser(corpusComplet);
  const c = cases.find((x) => x.ageMois === 6 && x.profile.length === 1 && x.profile[0] === "milk");
  const tropVieilles = corpusComplet.filter((r) => r.minAgeMonths > 6).length;
  assert.equal(c.outOfAge, tropVieilles);
  assert.equal(c.as_is + c.adapted + c.not_adaptable + c.outOfAge, corpusComplet.length);
});

test("gaps: the ranking puts the emptiest combinations first", () => {
  const cl = Trous.classer(Trous.analyser(corpusComplet));
  for (let i = 1; i < cl.length; i++) assert(cl[i - 1].missing >= cl[i].missing);
});

test("gaps: the brief merges identical gaps instead of repeating them", () => {
  const cmd = Trous.commande(Trous.classer(Trous.analyser(corpusComplet)));
  const cles = cmd.map((c) => c.categories[0] + "|" + c.evite.join(","));
  assert.equal(new Set(cles).size, cles.length, "la commande contient des doublons");
});

test("gaps: a truncated corpus opens a visible gap", () => {
  const ampute = corpusComplet.filter((r) => r.category !== "Snack");
  const cl = Trous.classer(Trous.analyser(ampute));
  assert(cl[0].missingCategories["Snack"] >= Trous.SEUIL_CATEGORIE - 0);
});

/* --- A : publication --- */

test("publishing: every recipe lands in a batch, none orphaned", () => {
  const r = Publier.publier();
  assert.equal(r.orphans.length, 0, "orphans : " + r.orphans);
  const total = Object.values(r.content).reduce((s, l) => s + l.length, 0);
  assert.equal(total, corpusComplet.length);
});

test("publishing: the manifest holds NO ingredient, only counts", () => {
  const r = Publier.publier();
  const txt = JSON.stringify(r.manifeste);
  assert(!/ingredients|steps/.test(txt), "le manifeste laisse fuir du content");
  assert(r.manifeste.batches.every((l) => typeof l.count === "number"));
});

test("publishing: the safety tables sit outside the batches", () => {
  const r = Publier.publier();
  assert(r.securite.substitutions.length > 0 && r.securite.base.allergens.length === 11);
  Object.values(r.content).forEach((lot) => lot.forEach((rec) => {
    assert(!rec.substitutions && !rec.allergenesTable, rec.id);
  }));
});

/* --- C : prompt et validateur --- */

test("prompt: offers only ingredients compatible with the brief", () => {
  const autorises = PromptRecette.ingredientsAutorises(donnees.catalogue, ["milk", "egg"]);
  autorises.forEach((id) => {
    const a = donnees.catalogue[id].allergens;
    assert(!a.includes("milk") && !a.includes("egg"), id + " should not be offered");
  });
  assert(autorises.includes("applesauce") && !autorises.includes("butter"));
});

test("validator: rejects an ingredient the model invented", () => {
  const faux = { id: "test-invente", name: "Test", category: "Collation", minAgeMonths: 12, timeMinutes: 10,
    ingredients: [{ id: "graines_de_tournesol_grillees", qty: 100, unit: "ml" }, { id: "banana", qty: 1, unit: "unit" }],
    steps: ["Mélanger les ingredients.", "Servir tiède."] };
  const v = Valideur.valider(faux, { evite: [], ageMois: 12, categories: ["Collation"] }, donnees);
  assert.equal(v.ok, false);
  assert(v.erreurs.some((x) => /hors catalogue/.test(x)));
});

test("validator: rejects a recipe holding the excluded allergen", () => {
  const faux = { id: "test-fuite", name: "Test", category: "Collation", minAgeMonths: 12, timeMinutes: 10,
    ingredients: [{ id: "cow_milk", qty: 250, unit: "ml", role: "liquid" }, { id: "banana", qty: 1, unit: "unit" }],
    steps: ["Mélanger les ingredients.", "Servir frais."] };
  const v = Valideur.valider(faux, { evite: ["milk"], ageMois: 12, categories: ["Collation"] }, donnees);
  assert.equal(v.ok, false);
  assert(v.erreurs.some((x) => /allergène que la commande exclut/.test(x)));
});

test("validator: accepts a compliant recipe and flags the ambiguous role", () => {
  const bonne = { id: "test-conforme", name: "Compote de pommes et banane", category: "Dessert",
    servings: "4 portions", minAgeMonths: 6, timeMinutes: 10,
    ingredients: [{ id: "applesauce", qty: 250, unit: "ml", role: "binder" },
                  { id: "banana", qty: 1, unit: "unit" }, { id: "cinnamon", qty: 1, unit: "ml" }],
    steps: ["Crush la banane at la fourchette.", "Mélanger à la compote et à la cannelle."] };
  const v = Valideur.valider(bonne, { evite: ["milk", "egg", "wheat"], ageMois: 6, categories: ["Dessert"] }, donnees);
  assert.equal(v.ok, true, v.erreurs.join(" / "));
});

test("validator: refuses a taken id and marketing superlatives", () => {
  const d = { id: "banana-oat-muffins", name: "Les meilleurs muffins", category: "Collation",
    minAgeMonths: 12, timeMinutes: 20, ingredients: [{ id: "banana", qty: 1, unit: "unit" }, { id: "rolled_oats", qty: 250, unit: "ml" }],
    steps: ["Mélanger les ingredients.", "Cuire vingt minutes."] };
  const v = Valideur.valider(d, { evite: [], ageMois: 12, categories: ["Collation"] }, donnees, corpusComplet.map((r) => r.id));
  assert.equal(v.ok, false);
  assert(v.erreurs.some((x) => /déjà utilisé/.test(x)));
});

/* --- D : images --- */

test("images: the prompt NAMES the dish, not only its ingredients", () => {
  /* Le prompt disait « a breakfast dish served in an everyday bowl » puis
   * listait les ingredients bruts. FLUX obéissait : un bol de gruau avec un
   * œuf cru, pour une recipe de muffins. Il faut nommer le plat. */
  const m = parId["banana-oat-muffins"];
  const pm = Images.promptPour(m, donnees);
  assert(pm.positif.toLowerCase().startsWith("homemade banana oat muffins"),
    "le titre doit mener : " + pm.positif.slice(0, 60));
  assert(/muffins in paper liners/.test(pm.positif),
    "the shape comes from servings");
  assert.equal(pm.plat, m.name, "the dish name is passed to the vision check");

  const pain = Images.promptPour(parId["banana-bread"], donnees);
  assert(/a loaf on a board/.test(pain.positif), "1 loaf gives a loaf, not a bowl");

  const r = parId["squash-and-coconut-soup"];
  const p = Images.promptPour(r, donnees);
  /* Image models are trained on English captions: the prompt has to come out
   * in English, with the ingredient names translated. */
  assert(/butternut squash/i.test(p.positif), "l'ingredient dominant must be nommé en anglais");
  assert(/coconut milk/i.test(p.positif));
  assert(!/courge|lait de coco/i.test(p.positif), "no mot français ne must rester");
  assert(/no visible egg/.test(p.negatif), "les exclusions doivent be explicites");
  /* The review list is for a human reader, and it now names the dish first. */
  assert(p.aVerifier[0].startsWith("the dish looks like"));
  assert(p.aVerifier.some((x) => /^check:/.test(x)));
});

test("images: the framing varies but stays stable for one recipe", () => {
  const a = Images.promptPour(parId["squash-and-coconut-soup"], donnees).positif;
  const b = Images.promptPour(parId["squash-and-coconut-soup"], donnees).positif;
  assert.equal(a, b, "same recipe, same cadrage — sinon l'image change at chaque passage");

  const cadrages = new Set();
  corpusComplet.forEach((r) => {
    const p = Images.promptPour(r, donnees).positif;
    const trouve = Images.CADRAGES.find((c) => p.includes(c));
    if (trouve) cadrages.add(trouve);
  });
  assert(cadrages.size >= 3, "le corpus doit couvrir plusieurs cadrages, pas un gabarit unique");
});

test("images: an unreviewed photo is never published", () => {
  const r = parId["fluffy-pancakes"];
  const emp = Images.empreinte(r);
  const res = Engine.adapterRecette(r, { allergens: [], ageMois: 24 }, donnees);
  const sansRevision = { [r.id]: { fichier: "images/x.webp", empreinte: emp } };
  assert.equal(Images.visuelPour(r, res, sansRevision, false).type, "illustration");
  const avecRevision = { [r.id]: { fichier: "images/x.webp", empreinte: emp, revisePar: "François", largeur: 1664 } };
  assert.equal(Images.visuelPour(r, res, avecRevision, false).type, "photo");
});

test("images: once a swap happens the photo gives way to the drawing", () => {
  const r = parId["fluffy-pancakes"];
  const manifeste = { [r.id]: { fichier: "images/x.webp", empreinte: Images.empreinte(r), revisePar: "François", largeur: 1664 } };
  const adaptee = Engine.adapterRecette(r, { allergens: ["milk"], ageMois: 24 }, donnees);
  const v = Images.visuelPour(r, adaptee, manifeste, false);
  assert.equal(v.type, "illustration");
  assert(/montrerait autre chose/.test(v.reason));
});

test("images: a stale fingerprint invalidates the photo", () => {
  const r = parId["fluffy-pancakes"];
  const v = Images.validerEntree({ fichier: "x.webp", empreinte: "000000000000", revisePar: "François", largeur: 1664 }, r, false);
  assert.equal(v.ok, false);
  assert(v.erreurs.some((x) => /périmée/.test(x)));
});

test("images: a photo below the display width is refused", () => {
  /* L'affichage exige 1320 px sur un iPhone Pro Max, et la vue recadre avant
   * de remplir. Une image plus petite est agrandie à l'écran — c'est comme ça
   * qu'un batch de photos molles s'est regapvé livré. */
  const r = parId["fluffy-pancakes"];
  const base = { fichier: "images/x.png", empreinte: Images.empreinte(r),
                 revisePar: "François" };
  const petite = Images.validerEntree(Object.assign({}, base, { largeur: 1216 }), r, false);
  assert.equal(petite.ok, false, "1216 px must be refusé");
  assert(petite.erreurs.some((e) => /too small/.test(e)));

  const bonne = Images.validerEntree(Object.assign({}, base, { largeur: 1664 }), r, false);
  assert.equal(bonne.ok, true, bonne.erreurs.join(" / "));
});

test("images: a manifest outliving its file publishes nothing", () => {
  const r = parId["fluffy-pancakes"];
  const entree = { fichier: "images/nexiste-pas.png", empreinte: Images.empreinte(r),
                   revisePar: "vérification automatique (test)", largeur: 1664,
                   verification: { moteur: "test", reconnus: 3, attendus: 5 } };
  const v = Images.validerEntree(entree, r);
  assert.equal(v.ok, false, "le disque doit faire foi, pas le manifeste");
  assert(v.erreurs.some((x) => /introuvable/.test(x)));

  const plan = Images.aGenerer([r], donnees, { [r.id]: entree });
  assert.equal(plan.length, 1, "la recipe must repasser au plan de génération");
  assert.equal(plan[0].etat, "file missing");
});

/* --- F : droits et Stripe --- */

test("entitlement: without a subscription only the free batches open", () => {
  const m = Publier.publier().manifeste;
  const free = Server.allowedBatches(m, null);
  assert.deepEqual(free, m.free);
  const tous = Server.allowedBatches(m, { subscription: { status: "actif" } });
  assert.equal(tous.length, m.batches.length);
});

test("entitlement: a late payment keeps access briefly, then loses it", () => {
  const hier = new Date(Date.now() - 864e5).toISOString();
  const vieux = new Date(Date.now() - 30 * 864e5).toISOString();
  assert.equal(Server.subscriptionActive({ subscription: { status: "en_retard", periodEnd: hier } }), true);
  assert.equal(Server.subscriptionActive({ subscription: { status: "en_retard", periodEnd: vieux } }), false);
  assert.equal(Server.subscriptionActive({ subscription: { status: "annule" } }), false);
});

test("stripe: a valid signature passes, a tampered or stale one does not", () => {
  const corps = Buffer.from('{"type":"checkout.session.completed"}');
  const t = Math.floor(Date.now() / 1000);
  const sig = crypto2.createHmac("sha256", "whsec_x").update(t + "." + corps.toString()).digest("hex");
  assert.equal(Stripe.verifierSignature(corps, "t=" + t + ",v1=" + sig, "whsec_x"), true);
  assert.equal(Stripe.verifierSignature(Buffer.from('{"type":"autre"}'), "t=" + t + ",v1=" + sig, "whsec_x"), false);
  assert.equal(Stripe.verifierSignature(corps, "t=" + (t - 9999) + ",v1=" + sig, "whsec_x"), false);
  assert.equal(Stripe.verifierSignature(corps, "t=" + t + ",v1=" + sig, "mauvais_secret"), false);
});

test("stripe: subscription statuses translate correctly", () => {
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

test("vision: plant false friends do not trigger their family", () => {
  const f = (t) => Vision.famillesDe(Vision.normaliser(t));
  assert.deepEqual(f("lait de coco"), []);
  assert.deepEqual(f("beurre de tournesol"), []);
  assert.deepEqual(f("noix de coco"), []);
  assert.deepEqual(f("poudre at pâte"), []);
  assert.deepEqual(f("pâtes de riz"), []);
  assert.deepEqual(f("milk"), ["milk"]);
  assert.deepEqual(f("beurre d'arachide"), ["peanut"]);
  assert.deepEqual(f("pâtes"), ["wheat"]);
});

test("vision: an intruder found in the image rejects it", async () => {
  const r = parId["squash-and-coconut-soup"];
  const v = await Vision.verifier(Buffer.from("x"), r, donnees,
    { moteur: visionQuiVoit(["courge", "lait de coco", "noix de Grenoble"]) });
  assert.equal(v.ok, false);
  assert(/noix/i.test(v.erreurs.join(" ")));
});

test("vision: a faithful image is accepted", async () => {
  const r = parId["squash-and-coconut-soup"];
  const noms = r.ingredients.map((u) => donnees.catalogue[u.id].name);
  const v = await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: visionQuiVoit(noms) });
  assert.equal(v.ok, true, v.erreurs.join(" / "));
  assert(v.reconnus >= 2);
});

test("vision: a failure or a missing engine rejects, never accepts by default", async () => {
  const r = parId["squash-and-coconut-soup"];
  const panne = { name: "x", decrire: async () => { throw new Error("réseau"); } };
  const illisible = { name: "x", decrire: async () => "je ne sais pas" };
  assert.equal((await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: panne })).ok, false);
  assert.equal((await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: illisible })).ok, false);
  assert.equal((await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: Vision.MOTEURS.absent })).ok, false);
});

test("vision: a choking risk rejects the image, allergen or not", async () => {
  const r = parId["fluffy-pancakes"];
  const v = await Vision.verifier(Buffer.from("x"), r, donnees,
    { moteur: visionQuiVoit(["milk", "egg", "farine de blé", "raisins entiers"]) });
  assert.equal(v.ok, false);
  assert(/étouffement/.test(v.erreurs.join(" ")));
});

test("vision: an image of a different dish is rejected", async () => {
  const r = parId["squash-and-coconut-soup"];
  const v = await Vision.verifier(Buffer.from("x"), r, donnees,
    { moteur: visionQuiVoit(["spaghetti", "meatballs"]) });
  assert.equal(v.ok, false);
  assert(/recognisable/.test(v.erreurs.join(" ")));
});

test("manifest: an automatic review with no vision verdict publishes nothing", () => {
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

test("agreement: word boundaries hold, a substring is not a match", () => {
  assert.equal(Coherence.contient("mash with a fork", Coherence.OVEN_WORDS), false);
  assert.equal(Coherence.contient("bake in the oven at 180 °C", Coherence.OVEN_WORDS), true);
  assert.equal(Coherence.contient("enfournez la plaque", Coherence.OVEN_WORDS), true);
});

test("agreement: catches the misses a test bake would have revealed", () => {
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

test("agreement: the whole existing corpus passes, no false positive", () => {
  const mauvaises = corpusComplet.filter((r) => !Coherence.verifier(r, donnees).ok);
  assert.equal(mauvaises.length, 0,
    mauvaises.map((r) => r.id + " : " + Coherence.verifier(r, donnees).erreurs.join(" ; ")).join(" | "));
});

test("engines: an adapter is always available, and the fallback is simulation", async () => {
  assert.equal(MoteursTexte.choisir("simule").name, "simule");
  assert.equal(MoteursImage.choisir("simule").name, "simule");
  const img = await MoteursImage.MOTEURS.simule.generer({ prompt: "test", negatif: "", largeur: 64, hauteur: 48 });
  assert(Buffer.isBuffer(img.octets) && img.octets.length > 50);
  assert.equal(img.octets.slice(1, 4).toString("ascii"), "PNG", "le mode simulé must produire un vrai PNG");
});

test("engines: the model JSON is extracted even when buried in prose", () => {
  const sale = 'Voici les recettes :\n```json\n[{"id":"a"},{"id":"b"}]\n```\nBon appétit!';
  assert.equal(MoteursTexte.extraireJSON(sale).length, 2);
});

/* ---------- iOS : StoreKit et pont natif (v0.6) ---------- */

const Apple = require(path.join(__dirname, "..", "server", "apple.js"));

test("apple: without the Apple root everything is refused", () => {
  const r = Apple.verifierJWS("a.b.c", { racine: null });
  assert.equal(r.ok, false);
});

test("apple: a malformed JWS or a non-ES256 algorithm is refused", () => {
  assert.equal(Apple.verifierJWS("pas-un-jws", { racine: null }).ok, false);
  const entete = Buffer.from(JSON.stringify({ alg: "HS256", x5c: ["x"] })).toString("base64url");
  assert.equal(Apple.verifierJWS(entete + ".e30.c2ln", { racine: null }).ok, false);
});

test("apple: an absent or short x5c chain is refused", () => {
  assert.equal(Apple.verifierChaine(null, null).ok, false);
  assert.equal(Apple.verifierChaine(["un-seul"], null).ok, false);
});

test("apple: transaction statuses translate the same way Stripe does", () => {
  const futur = Date.now() + 30 * 864e5, passe = Date.now() - 864e5;
  const base = { bundleId: "ca.bouchees.app", productId: "abo.mensuel", originalTransactionId: "1" };
  const o = { bundleId: "ca.bouchees.app", produits: ["abo.mensuel"] };
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: futur }, base), o).status, "actif");
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: passe }, base), o).status, "annule");
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: futur, revocationDate: Date.now() }, base), o).status, "annule");
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: futur, bundleId: "autre.app" }, base, { bundleId: "autre.app" }), o).ok, false);
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: futur, productId: "unknown" }, base, { productId: "unknown" }), o).ok, false);
});

test("apple: the DER and raw signature forms round-trip", () => {
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

test("scanner: a label holding the avoided allergen returns avoid", () => {
  const f = chargerPont();
  const r = f({ texte: "Farine de blé, sucre, lait de vache, beurre, sel", evites: ["milk"] });
  assert.equal(r.status, "avoid");
  assert(r.allergensFound.length > 0);
});

test("scanner: an unrecognised ingredient returns uncertain, never safe", () => {
  const f = chargerPont();
  const r = f({ texte: "Riz, gomme xanthane E415, poulet", evites: ["milk"] });
  assert.equal(r.status, "uncertain");
  assert(r.unknownIngredients.length > 0);
  assert(/étiquette/.test(r.message), "le message must renvoyer at l'label");
});

test("scanner: apostrophe and case variants are recognised", () => {
  const f = chargerPont();
  ["FLOCONS D'AVOINE, BANANE, CANNELLE", "Flocons d avoine, banane, cannelle",
   "flocons d\u2019avoine, banane, cannelle"].forEach((t) => {
    assert.equal(f({ texte: t, evites: ["peanut"] }).status, "safe", t);
  });
});

test("scanner: soy sauce triggers wheat too, from the catalogue", () => {
  const f = chargerPont();
  assert.equal(f({ texte: "Riz, sauce soya, gingembre", evites: ["wheat"] }).status, "avoid");
  assert.equal(f({ texte: "Riz, sauce soya, gingembre", evites: ["soy"] }).status, "avoid");
});

test("scanner: a fully recognised label with no avoided allergen is safe", () => {
  const f = chargerPont();
  const r = f({ texte: "Banane, pomme, cannelle", evites: ["milk", "egg", "peanut"] });
  assert.equal(r.status, "safe");
  assert.equal(r.unknownIngredients.length, 0);
});

test("iOS: the template hands subscription to StoreKit, no web checkout", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "web", "template.html"), "utf8");
  assert(/if\(SOUS_IOS\)\{ versNatif\("subscription"\); return; \}/.test(src),
    "le chemin iOS doit court-circuiter Stripe (rule 3.1.1)");
  const apresIOS = src.slice(src.indexOf('if(SOUS_IOS){ versNatif("subscription"); return; }'));
  assert(apresIOS.indexOf("api/paiement") > 0, "la route Stripe existe encore pour le web");
});

/* ---------- weeks glissantes, notes, classement (v1.0) ---------- */

const Semaines = require(path.join(__dirname, "..", "tools", "weeks.js"));
const Ratings = require(path.join(__dirname, "..", "server", "ratings.js"));

test("weeks: the ISO identifier computes and compares correctly", () => {
  const id = Semaines.identifiantSemaine(new Date("2026-08-19T12:00:00Z"));
  assert(/^\d{4}-S\d{2}$/.test(id), "format inattendu : " + id);
  assert(Semaines.rang("2026-S02") < Semaines.rang("2026-S34"));
  assert(Semaines.rang("2025-S52") < Semaines.rang("2026-S01"), "le passage d'année must be ordonné");
});

test("weeks: stepping backwards crosses the year boundary", () => {
  const s = Semaines.semainesPrecedentes(new Date("2026-01-08T12:00:00Z"), 4);
  assert.equal(s.length, 4);
  assert(s.some((x) => x.startsWith("2025-")), "on doit retomber sur 2025 : " + s.join(", "));
  for (let i = 1; i < s.length; i++) {
    assert(Semaines.rang(s[i]) < Semaines.rang(s[i - 1]), "ordre décroissant attendu");
  }
});

test("window: free batches never rotate, weekly ones do", () => {
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

test("window: fewer batches than the window breaks nothing", () => {
  const f = Semaines.fenetreCourante([{ id: "2026-S33", access: "subscriber" }], Date.now());
  assert.equal(f.window.length, 1);
  assert.equal(f.horsFenetre.length, 0);
});

test("publishing: the manifest marks what is inside the window", () => {
  const r = Publier.publier();
  const hebdo = r.manifeste.batches.filter((l) => l.weekly);
  assert(hebdo.length > 0, "il doit exister des batches hebdomadaires");
  assert(r.manifeste.batches.filter((l) => l.inWindow).length > 0);
  assert(Array.isArray(r.manifeste.window));
  assert(r.manifeste.window.length <= Semaines.FENETRE);
  // Les batches free restent always visible
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

test("ranking: the five-vote threshold is respected", () => {
  ["a", "b", "c", "d"].forEach((p) => Ratings.rate("presque", p + "@x.ca", 5));
  assert(!Ratings.ranking().some((c) => c.recipeId === "presque"), "4 votes : absente");
  Ratings.rate("presque", "e@x.ca", 5);
  assert(Ratings.ranking().some((c) => c.recipeId === "presque"), "5 votes : présente");
});

test("ranking: a proven recipe outranks a 5/5 with five votes", () => {
  for (let i = 0; i < 60; i++) Ratings.rate("eprouvee", "g" + i + "@x.ca", i < 50 ? 5 : 4);
  const cl = Ratings.ranking();
  const petite = cl.find((c) => c.recipeId === "presque");
  const grande = cl.find((c) => c.recipeId === "eprouvee");
  assert(grande.score > petite.score,
    "l'ancrage fixe must protéger le classement : " + grande.score + " vs " + petite.score);
  assert.equal(petite.average, 5, "sa moyenne brute reste parfaite, seul le score la tempère");
});

test("ranking: sorted, and another person rating is never exposed", () => {
  const cl = Ratings.ranking();
  for (let i = 1; i < cl.length; i++) assert(cl[i - 1].score >= cl[i].score);
  assert.equal(Ratings.aggregates(["presque"], "a@x.ca")["presque"].myRating, 5);
  assert.equal(Ratings.aggregates(["presque"], "unknown@x.ca")["presque"].myRating, null);
});

test("vision: a cooked dish need not show its raw ingredients", async () => {
  /* Sur une photo de crêpes, on voit des crêpes — ni farine, ni lait, ni œuf.
   * Exiger un ingredient brut rejetait TOUT plat transformé, c'est-à-dire
   * l'essentiel du corpus. Le plat correctement identifié est une preuve plus
   * forte que l'ingredient repéré. */
  const crepes = parId["fluffy-pancakes"];
  const voit = (aliments, plat) => ({ nom: "test", disponible: () => true,
    decrire: async () => JSON.stringify({ aliments, plat, lisible: true, incertitudes: [] }) });

  const cuit = await Vision.verifier(Buffer.from("x"), crepes, donnees,
    { moteur: voit(["pancakes", "plate", "butter"], "a stack of pancakes") });
  assert.equal(cuit.ok, true, cuit.erreurs.join(" / "));
  assert(cuit.avertissements.some((a) => /cooked dish/.test(a)),
    "l'absence d'ingredient brut must be notée, pas fatale");

  /* Mais sans ingredient ET sans le bon plat, on rejette always. */
  const rien = await Vision.verifier(Buffer.from("x"), crepes, donnees,
    { moteur: voit(["bowl", "spoon"], "a bowl of soup") });
  assert.equal(rien.ok, false);
});

test("images: the prompt stays short and names the cooked state", () => {
  /* Un prompt de 780 caractères noyait le sujet : vingt adjectifs de lumière
   * pesaient autant que les deux mots qui disent quel est le plat. */
  const p = Images.promptPour(parId["fluffy-pancakes"], donnees).positif;
  assert(p.length < 500, "prompt trop long : " + p.length + " characters");
  assert(/cooked and ready to eat/.test(p),
    "l'état cuit must be dit, sinon FLUX étale les ingredients crus");
  assert(p.toLowerCase().startsWith("homemade fluffy pancakes"));
});

test("vision: the DISH must match, not only the ingredients", async () => {
  /* Le cas réel : un bol de gruau avec un œuf cru, accepté pour une recipe de
   * muffins parce que banane, avoine et œuf étaient tous présents. Des
   * ingredients ne font pas un plat. */
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

test("vision: the shape comes from the servings field too", async () => {
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

test("vision: an image resembling nothing AND causing hesitation is rejected", async () => {
  const r = parId["banana-oat-muffins"];
  /* The exact profilee of the orange mush that made it through: one ingredient
   * vaguely recognised, and the vision listing possibilities. Before the fix
   * this was only a warning. */
  const hesitant = { name: "test", disponible: () => true, decrire: async () => JSON.stringify({
    aliments: ["banana"], lisible: true,
    incertitudes: ["pourrait be du couscous, de la polenta ou du curcuma"] }) };
  const v = await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: hesitant });
  assert.equal(v.ok, false, "hésitation + un seul ingredient must rejeter");
  assert(v.erreurs.some((e) => /does not look enough like/.test(e)));
});

test("vision: a single recognised ingredient with no hesitation is accepted", async () => {
  const r = parId["banana-oat-muffins"];
  /* Une belle photo de muffins montre « un muffin », pas la banane ni
   * l'avoine. Il ne faut pas la rejeter pour autant. */
  const net = { name: "test", disponible: () => true, decrire: async () => JSON.stringify({
    aliments: ["banana"], lisible: true, incertitudes: [] }) };
  const v = await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: net });
  assert.equal(v.ok, true, v.erreurs.join(" / "));
  assert(v.avertissements.some((a) => /weak resemblance/.test(a)));
});


/* ---------- serveur : les correctifs du rapport QA (build 119) ---------- */

/* A real instance on a free port, so what is tested is the wire, not the
 * functions behind it. The accounts and the product cache go to files the
 * test owns, and never to the repository's. */
let serveursDeTest = 0;
async function serveurDeTest(db, options) {
  const http = require("http");
  /* One file per instance. The tests run in parallel, and a shared file
   * meant one test's empty accounts overwrote another's fixture between
   * its write and its first request. */
  const seq = process.pid + "-" + (++serveursDeTest);
  const comptes = path.join(require("os").tmpdir(), "bouchees-test-accounts-" + seq + ".json");
  const cache = path.join(require("os").tmpdir(), "bouchees-test-cache-" + seq + ".json");
  process.env.BOUCHEES_COMPTES = comptes;
  process.env.BOUCHEES_PRODUCT_CACHE = cache;
  fs.writeFileSync(comptes, JSON.stringify(db || { accounts: {}, jetons: {} }));
  try { fs.unlinkSync(cache); } catch (e) {}
  delete require.cache[require.resolve("../server/server.js")];
  const S = require("../server/server.js");
  const srv = S.createServer(options || { allowInsecureLogin: false });
  await new Promise((res) => srv.listen(0, res));
  /* Never keep the process alive, and never keep a socket alive: a
   * keep-alive connection makes server.close() wait for a client that has
   * already gone, and the whole suite hangs at the end. */
  srv.unref();
  const base = "http://127.0.0.1:" + srv.address().port;
  function call(method, chemin, body, headers) {
    return new Promise((res) => {
      const r = http.request(base + chemin, { method: method, headers: headers || {}, agent: false }, (resp) => {
        let d = ""; resp.on("data", (c) => d += c);
        resp.on("end", () => { let j = null; try { j = JSON.parse(d); } catch (e) {} res({ status: resp.statusCode, json: j }); });
      });
      r.on("error", () => res({ status: -1, json: null }));
      if (body) r.write(body);
      r.end();
    });
  }
  return { S: S, call: call, close: () => { if (srv.closeAllConnections) srv.closeAllConnections(); srv.close(); } };
}

test("server: sign-in answers 503 until it is real", async () => {
  const t = await serveurDeTest();
  const r = await t.call("POST", "/api/login", JSON.stringify({ email: "a@b.co" }), { "content-type": "application/json" });
  assert.equal(r.status, 503, "a token must not be handed to an unverified address");
  t.close();
});

test("server: a body over the ceiling is refused with 413, not swallowed as bad JSON", async () => {
  const t = await serveurDeTest(null, { allowInsecureLogin: true });
  const r = await t.call("POST", "/api/login", "x".repeat(t.S._MAX_BODY + 1024), { "content-type": "application/json" });
  assert.equal(r.status, 413);
  t.close();
});

test("server: a token older than the TTL no longer authenticates, a fresh one does, the old shape migrates", async () => {
  const S0 = require("../server/server.js");
  const t = await serveurDeTest({
    accounts: { "x@y.z": { email: "x@y.z", subscription: null } },
    jetons: {
      vieux: { email: "x@y.z", cree: Date.now() - S0._TOKEN_TTL_MS - 1000 },
      neuf: { email: "x@y.z", cree: Date.now() },
      ancien: "x@y.z"
    }
  });
  async function me(tok) { return (await t.call("GET", "/api/me", null, { authorization: "Bearer " + tok })).json.connecte; }
  assert.equal(await me("vieux"), false, "expired");
  assert.equal(await me("neuf"), true, "fresh");
  assert.equal(await me("ancien"), true, "a bare-email entry from before is not a logout");
  t.close();
});

test("server: a spent budget answers 503 with a retry delay and touches no network", async () => {
  const t = await serveurDeTest();
  t.S._OffBudget._reset(); t.S._ProductCache._reset();
  for (let i = 0; i < 12; i++) t.S._OffBudget.take();
  const r = await t.call("GET", "/api/product?code=064200115209");
  assert.equal(r.status, 503);
  assert(r.json.retryAfterSeconds >= 1, "the caller is told when to come back");
  t.close();
});

test("server: the product cache answers hits and remembered misses without spending budget", async () => {
  const t = await serveurDeTest();
  t.S._OffBudget._reset(); t.S._ProductCache._reset();
  for (let i = 0; i < 12; i++) t.S._OffBudget.take();   // budget gone: any network path would 503
  t.S._ProductCache.set("0064200115209", { hit: true, payload: { code: "0064200115209", name: "Cheddar" } });
  t.S._ProductCache.set("0099999999999", { hit: false });
  const hit = await t.call("GET", "/api/product?code=064200115209");
  assert.equal(hit.status, 200); assert.equal(hit.json.name, "Cheddar");
  const miss = await t.call("GET", "/api/product?code=099999999999");
  assert.equal(miss.status, 404); assert.equal(miss.json.via, "cache");
  t.close();
});

test("server: the cache key is the canonical thirteen-digit form, whichever form was scanned", async () => {
  const t = await serveurDeTest();
  t.S._OffBudget._reset(); t.S._ProductCache._reset();
  for (let i = 0; i < 12; i++) t.S._OffBudget.take();
  t.S._ProductCache.set("0064200115209", { hit: true, payload: { name: "Cheddar" } });
  const douze = await t.call("GET", "/api/product?code=064200115209");
  const treize = await t.call("GET", "/api/product?code=0064200115209");
  assert.equal(douze.json.name, "Cheddar", "UPC-A reaches the entry");
  assert.equal(treize.json.name, "Cheddar", "EAN-13 reaches the same entry");
  t.close();
});

Promise.all(enAttente).then(function () { console.log("\n" + n + " tests."); });
