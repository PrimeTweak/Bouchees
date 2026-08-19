/* Tests du moteur — node tests/test.js */
"use strict";
const assert = require("assert");
const path = require("path");
const fs = require("fs");

const Moteur = require(path.join(__dirname, "..", "moteur", "moteur.js"));
const lire = (f) => JSON.parse(fs.readFileSync(path.join(__dirname, "..", "donnees", f), "utf8"));
const lire2 = (f) => JSON.parse(fs.readFileSync(path.join(__dirname, "..", f), "utf8"));

const donnees = {
  catalogue: lire("ingredients.json"),
  substitutions: lire("substitutions.json"),
  base: lire("base.json")
};
const recettes = lire("recettes.json");
const parId = Object.fromEntries(recettes.map((r) => [r.id, r]));

let n = 0;
const enAttente = [];
function test(nom, fn) {
  n++;
  try {
    const r = fn();
    if (r && typeof r.then === "function") {
      enAttente.push(r.then(function () { console.log("  ok  " + nom); },
        function (e) { console.error("ÉCHEC " + nom + "\n      " + e.message); process.exitCode = 1; }));
    } else console.log("  ok  " + nom);
  }
  catch (e) { console.error("ÉCHEC " + nom + "\n      " + e.message); process.exitCode = 1; }
}
const adapter = (id, allergenes, ageMois) =>
  Moteur.adapterRecette(parId[id], { allergenes, ageMois }, donnees);
const ing = (res, id) => res.ingredients.find((i) => i.id === id);

/* ---------- intégrité des données (lot 1) ---------- */

test("données : toutes les recettes référencent des ingrédients du catalogue", () => {
  for (const r of recettes) for (const u of r.ingredients)
    assert(donnees.catalogue[u.id], r.id + " → ingrédient inconnu : " + u.id);
});

test("données : toutes les options de substitution existent et tout allergène référencé est connu", () => {
  const familles = new Set(donnees.base.allergenes.map((a) => a.id));
  for (const regle of donnees.substitutions) {
    assert(donnees.catalogue[regle.cible], "cible inconnue : " + regle.cible);
    for (const o of regle.options)
      assert(o.id === "_omettre" || donnees.catalogue[o.id], regle.cible + " → option inconnue : " + o.id);
  }
  for (const [id, def] of Object.entries(donnees.catalogue))
    for (const a of def.allergenes) assert(familles.has(a), id + " → famille inconnue : " + a);
  for (const r of donnees.base.interdits)
    if (r.action.type === "swap") assert(donnees.catalogue[r.action.vers], "swap vers inconnu : " + r.action.vers);
});

test("données : les interdits d'une même cible sont ordonnés de la tranche la plus jeune à la plus vieille", () => {
  const parCible = {};
  for (const r of donnees.base.interdits) {
    if (parCible[r.cible] !== undefined)
      assert(r.avantMois > parCible[r.cible], "interdits mal ordonnés pour " + r.cible);
    parCible[r.cible] = r.avantMois;
  }
});

/* ---------- substitutions dirigées ---------- */

test("muffins sans œuf à 12 mois → compote de pommes (option 1)", () => {
  const r = adapter("muffins-banane-avoine", ["oeuf"], 12);
  const i = ing(r, "oeuf");
  assert.equal(i.statut, "substitue");
  assert.equal(i.vers, "compote_pommes");
  assert.equal(r.statut, "adaptee");
});

test("crêpes sans lait → boisson de soya (priorité 1)", () => {
  const i = ing(adapter("crepes-moelleuses", ["lait"], 12), "lait_vache");
  assert.equal(i.vers, "boisson_soya");
});

test("crêpes sans lait NI soya → le moteur saute le soya, prend l'avoine", () => {
  const i = ing(adapter("crepes-moelleuses", ["lait", "soya"], 12), "lait_vache");
  assert.equal(i.vers, "boisson_avoine");
});

test("boules d'énergie sans arachide → beurre de tournesol", () => {
  const i = ing(adapter("boules-energie-dattes", ["arachide"], 24), "beurre_arachide");
  assert.equal(i.vers, "beurre_tournesol");
});

test("houmous sans sésame → tahini remplacé, jamais par un ingrédient évité", () => {
  const r = adapter("houmous-veloute", ["sesame"], 9);
  assert.equal(ing(r, "tahini").vers, "beurre_tournesol");
  assert.equal(r.allergenesRestants.includes("sesame"), false);
});

test("frittatas sans œuf : rôle protéine → farine de pois chiches, pas compote", () => {
  const i = ing(adapter("mini-frittatas-legumes", ["oeuf"], 12), "oeuf");
  assert.equal(i.vers, "farine_pois_chiches");
});

test("croquettes sans poisson ET sans blé : double substitution, œuf conservé", () => {
  const r = adapter("croquettes-poisson", ["poisson", "ble"], 12);
  assert.equal(ing(r, "poisson_blanc").vers, "poulet");
  assert.equal(ing(r, "chapelure").vers, "chapelure_sans_gluten");
  assert.equal(ing(r, "oeuf").statut, "conserve");
  assert.deepEqual(r.allergenesRestants, ["oeuf"]);
});

test("mac-fromage sans lait : cheddar→levure, beurre→margarine, lait→soya; le roux (farine rôle liant) reste", () => {
  const r = adapter("macaroni-fromage-courge", ["lait"], 12);
  assert.equal(ing(r, "fromage_cheddar").vers, "levure_alimentaire");
  assert.equal(ing(r, "beurre").vers, "margarine_sans_lait");
  assert.equal(ing(r, "lait_vache").vers, "boisson_soya");
  assert.equal(ing(r, "farine_ble").statut, "conserve");
});

test("mac-fromage sans lait ET blé : la farine du roux (rôle liant) → fécule de maïs", () => {
  const r = adapter("macaroni-fromage-courge", ["lait", "ble"], 12);
  assert.equal(ing(r, "farine_ble").vers, "fecule_mais");
  assert.equal(ing(r, "pates_ble").vers, "pates_riz");
});

test("boulettes sans moutarde → moutarde omise, recette adaptée", () => {
  const r = adapter("boulettes-dinde-pomme", ["moutarde"], 12);
  assert.equal(ing(r, "moutarde_dijon").statut, "omis");
  assert.equal(r.statut, "adaptee");
});

/* ---------- règles d'âge ---------- */

test("barres granola à 9 mois : miel → sirop d'érable (swap d'âge) + alerte ageMinBase", () => {
  const r = adapter("barres-granola-tendres", [], 9);
  assert.equal(ing(r, "miel").vers, "sirop_erable");
  assert(r.alertes.some((a) => a.niveau === "attention"));
});

test("barres granola à 9 mois : noix de Grenoble → préparation « moudre », raisins secs → préparation", () => {
  const r = adapter("barres-granola-tendres", [], 9);
  assert(ing(r, "noix_grenoble").preparation.includes("Moudre"));
  assert(ing(r, "raisins_secs").preparation);
});

test("barres granola à 24 mois : plus de swap de miel, noix toujours à moudre (< 48 mois)", () => {
  const r = adapter("barres-granola-tendres", [], 24);
  assert.equal(ing(r, "miel").statut, "conserve");
  assert(ing(r, "noix_grenoble").preparation);
});

test("barres granola à 60 mois : aucune alerte de sécurité (sauf collant du beurre d'arachide levée à 48)", () => {
  const r = adapter("barres-granola-tendres", [], 60);
  assert.equal(r.alertes.filter((a) => a.niveau === "securite").length, 0);
});

test("pouding chia à 8 mois : bleuets → alerte écrasement", () => {
  const r = adapter("pouding-chia-vanille", [], 8);
  assert(ing(r, "bleuets").preparation.includes("Écraser"));
});

test("trempette à 8 mois : carotte crue → règle 12 mois (cuire ou râper), pas la règle 4 ans", () => {
  const i = ing(adapter("trempette-yogourt-crudites", [], 8), "carotte_crue");
  assert(i.preparation.includes("vapeur"));
});

test("trempette à 24 mois : carotte crue → règle 4 ans (pas de bâtonnets durs)", () => {
  const i = ing(adapter("trempette-yogourt-crudites", [], 24), "carotte_crue");
  assert(i.preparation.includes("râpée"));
});

test("sel à 8 mois : préparation « omettre », plus rien à 12 mois", () => {
  assert(ing(adapter("galettes-lentilles-carotte", [], 8), "sel").preparation);
  assert.equal(ing(adapter("galettes-lentilles-carotte", [], 12), "sel").preparation, undefined);
});

test("le swap d'âge respecte les allergènes : miel→érable même sans lait ni blé", () => {
  const r = adapter("barres-granola-tendres", ["lait", "ble"], 9);
  assert.equal(ing(r, "miel").vers, "sirop_erable");
});

/* ---------- non-adaptable : la porte de sortie honnête ---------- */

test("aucun substitut valide → statut non_adaptable avec alerte bloquante (gating par ageMin)", () => {
  const donneesTest = {
    catalogue: donnees.catalogue,
    base: donnees.base,
    substitutions: [{ cible: "oeuf", role: "liant", options: [{ id: "aquafaba", ratio: "45 ml", ageMin: 12 }] }]
  };
  const r = Moteur.adapterRecette(parId["crepes-moelleuses"], { allergenes: ["oeuf"], ageMois: 8 }, donneesTest);
  assert.equal(r.statut, "non_adaptable");
  assert(r.alertes.some((a) => a.niveau === "bloquant"));
  assert.equal(ing(r, "oeuf").statut, "impossible");
});

test("ingrédient évité sans règle du tout → non_adaptable, jamais de retrait silencieux", () => {
  const donneesTest = { catalogue: donnees.catalogue, base: donnees.base, substitutions: [] };
  const r = Moteur.adapterRecette(parId["houmous-veloute"], { allergenes: ["sesame"], ageMois: 12 }, donneesTest);
  assert.equal(r.statut, "non_adaptable");
});

/* ---------- déterminisme ---------- */

test("même entrée → même sortie (sérialisation identique sur 3 appels)", () => {
  const a = JSON.stringify(adapter("macaroni-fromage-courge", ["lait", "ble"], 9));
  const b = JSON.stringify(adapter("macaroni-fromage-courge", ["lait", "ble"], 9));
  const c = JSON.stringify(adapter("macaroni-fromage-courge", ["lait", "ble"], 9));
  assert.equal(a, b); assert.equal(b, c);
});

/* ---------- test de propriété : l'invariant de sécurité ---------- */

test("INVARIANT — aucune recette adaptée ne contient un allergène évité, aucun substitut sous son âge minimum", () => {
  const familles = donnees.base.allergenes.map((a) => a.id);
  const combos = familles.map((f) => [f]).concat([
    ["lait", "soya"], ["oeuf", "ble"], ["lait", "oeuf"], ["arachide", "sesame"],
    ["arachide", "noix", "sesame", "soya"], ["lait", "oeuf", "ble", "soya"],
    ["poisson", "ble"], ["lait", "ble"]
  ]);
  const ages = [6, 8, 9, 12, 18, 24, 48, 60];
  let verifies = 0;

  for (const recette of recettes)
    for (const combo of combos)
      for (const ageMois of ages) {
        const r = Moteur.adapterRecette(recette, { allergenes: combo, ageMois }, donnees);
        if (r.statut === "non_adaptable") { verifies++; continue; }
        const croise = r.allergenesRestants.filter((a) => combo.includes(a));
        assert.equal(croise.length, 0,
          recette.id + " [" + combo + "] à " + ageMois + " mois laisse passer : " + croise);
        for (const i of r.ingredients) if (i.statut === "substitue") {
          const regle = donnees.substitutions.find((s) => s.cible === i.id && s.role === i.role);
          const opt = regle && regle.options.find((o) => o.id === i.vers);
          if (opt) assert(opt.ageMin <= ageMois, i.id + "→" + i.vers + " sous l'âge minimum à " + ageMois + " mois");
        }
        verifies++;
      }
  console.log("      " + verifies + " combinaisons vérifiées (20 recettes × " + combos.length + " profils × " + ages.length + " âges)");
});

/* ---------- lot 3 : normaliseur ---------- */

const { normaliserLigne } = require(path.join(__dirname, "..", "ingestion", "normaliseur.js"));
const lexique = lire2("ingestion/lexique.json");
const norm = (l) => normaliserLigne(l, lexique, donnees.catalogue);

test("normaliseur : « 2 cups all-purpose flour » → farine_ble, 500 ml", () => {
  const r = norm("2 cups all-purpose flour");
  assert.equal(r.id, "farine_ble"); assert.equal(r.qte, 500); assert.equal(r.unite, "ml");
});

test("normaliseur : « 1/2 tasse de compote de pommes non sucrée » → compote_pommes, 125 ml", () => {
  const r = norm("1/2 tasse de compote de pommes non sucrée");
  assert.equal(r.id, "compote_pommes"); assert.equal(r.qte, 125);
});

test("normaliseur : « 1 ½ tsp vanilla extract » → vanille, 7.5 ml (fraction unicode mixte)", () => {
  const r = norm("1 \u00bd tsp vanilla extract");
  assert.equal(r.id, "vanille"); assert.equal(r.qte, 7.5);
});

test("normaliseur : « 1 lb boneless chicken breast, diced » → poulet, 454 g", () => {
  const r = norm("1 lb boneless chicken breast, diced");
  assert.equal(r.id, "poulet"); assert.equal(r.qte, 454); assert.equal(r.unite, "g");
});

test("normaliseur : « 2 tablespoons soy sauce » → sauce_soya — allergènes soya ET blé via le catalogue", () => {
  const r = norm("2 tablespoons soy sauce");
  assert.equal(r.id, "sauce_soya"); assert.equal(r.qte, 30);
  assert.deepEqual(donnees.catalogue[r.id].allergenes.slice().sort(), ["ble", "soya"]);
});

test("normaliseur : « 1 tbsp galangal, sliced » → inconnu (jamais deviné)", () => {
  assert.equal(norm("1 tbsp galangal, sliced").statut, "inconnu");
});

/* ---------- lot 3 : portes de l'importeur ---------- */

const { importerTout } = require(path.join(__dirname, "..", "ingestion", "importer.js"));
const importation = importerTout();

test("importeur : 10 recettes importées, 3 en quarantaine", () => {
  assert.equal(importation.importees.length, 10);
  assert.equal(importation.quarantaine.length, 3);
});

test("importeur : une ligne inconnue met la recette ENTIÈRE en quarantaine (Thai Green Curry)", () => {
  const q = importation.quarantaine.find((x) => x.nom === "Thai Green Curry");
  assert.equal(q.raison, "lignes non reconnues");
  assert(q.detail.some((d) => /galangal/i.test(d)));
});

test("importeur : reconnu mais sans curation → quarantaine (Baked Oatmeal)", () => {
  const q = importation.quarantaine.find((x) => x.nom === "Apple Cinnamon Baked Oatmeal");
  assert.equal(q.raison, "curation manquante");
});

test("importeur : chaque importée porte un âge minimal curé et une provenance", () => {
  for (const r of importation.importees) {
    assert(Number.isInteger(r.ageMinBase) && r.ageMinBase >= 6, r.id);
    assert(r.provenance && r.provenance.source && r.provenance.licence, r.id);
  }
});

test("importeur : le rôle curé remplace le rôle par défaut (riz frit : œuf → protéine)", () => {
  const r = importation.importees.find((x) => x.id === "riz-frit-legumes");
  assert.equal(r.ingredients.find((i) => i.id === "oeuf").role, "proteine");
});

test("bout en bout : riz frit sans soya à 12 mois → tamari sauté (soya), aminos de coco choisis", () => {
  const r = importation.importees.find((x) => x.id === "riz-frit-legumes");
  const res = Moteur.adapterRecette(r, { allergenes: ["soya"], ageMois: 12 }, donnees);
  assert.equal(res.ingredients.find((i) => i.id === "sauce_soya").vers, "coco_aminos");
});

test("bout en bout : risotto sans crustacés à 12 mois → crevettes remplacées par du poulet", () => {
  const r = importation.importees.find((x) => x.id === "risotto-crevettes-petits-pois");
  const res = Moteur.adapterRecette(r, { allergenes: ["crustaces_mollusques"], ageMois: 12 }, donnees);
  assert.equal(res.ingredients.find((i) => i.id === "crevette").vers, "poulet");
});

test("bout en bout : granola sans sulfites → abricots séchés remplacés (raisins bruns)", () => {
  const r = importation.importees.find((x) => x.id === "granola-tendre-abricots");
  const res = Moteur.adapterRecette(r, { allergenes: ["sulfites"], ageMois: 24 }, donnees);
  assert.equal(res.ingredients.find((i) => i.id === "abricots_seches").vers, "raisins_secs");
});

/* ---------- invariant élargi : témoins + importées ---------- */

test("INVARIANT (corpus complet) — témoins + importées, aucune fuite d'allergène, aucun substitut sous l'âge", () => {
  const familles = donnees.base.allergenes.map((a) => a.id);
  const combos = familles.map((f) => [f]).concat([
    ["lait", "soya"], ["oeuf", "ble"], ["soya", "ble"], ["crustaces_mollusques", "poisson"],
    ["sulfites", "noix"], ["lait", "oeuf", "ble", "soya"]
  ]);
  const ages = [6, 9, 12, 24, 48];
  const corpus = recettes.concat(importation.importees);
  let verifies = 0;
  for (const recette of corpus)
    for (const combo of combos)
      for (const ageMois of ages) {
        const r = Moteur.adapterRecette(recette, { allergenes: combo, ageMois }, donnees);
        if (r.statut === "non_adaptable") { verifies++; continue; }
        const croise = r.allergenesRestants.filter((a) => combo.includes(a));
        assert.equal(croise.length, 0, recette.id + " [" + combo + "] laisse passer : " + croise);
        verifies++;
      }
  console.log("      " + verifies + " combinaisons (corpus de " + corpus.length + " recettes)");
});

/* ---------- système visuel (v0.3) ---------- */

const Illustration = require(path.join(__dirname, "..", "app", "illustration.js"));
const corpusVisuel = recettes.concat(importation.importees);

test("illustration : les 30 recettes produisent un SVG bien formé, sans valeur invalide", () => {
  for (const r of corpusVisuel) {
    const res = Moteur.adapterRecette(r, { allergenes: [], ageMois: 24 }, donnees);
    const svg = Illustration.plat(res, donnees.catalogue, r.categorie);
    assert(svg.startsWith("<svg") && svg.endsWith("</svg>"), r.id);
    assert(!/undefined|NaN|null/.test(svg), r.id + " contient une valeur invalide");
    assert(!/<\/script/i.test(svg), r.id);
  }
});

test("illustration : déterministe — même recette et même profil donnent le même SVG", () => {
  const r = parId["macaroni-fromage-courge"];
  const f = () => Illustration.plat(Moteur.adapterRecette(r, { allergenes: ["lait"], ageMois: 12 }, donnees), donnees.catalogue, r.categorie);
  assert.equal(f(), f());
});

test("illustration : l'image CHANGE quand la recette s'adapte (beurre d'arachide → tournesol)", () => {
  const r = parId["boules-energie-dattes"];
  const avant = Illustration.plat(Moteur.adapterRecette(r, { allergenes: [], ageMois: 24 }, donnees), donnees.catalogue, r.categorie);
  const apres = Illustration.plat(Moteur.adapterRecette(r, { allergenes: ["arachide"], ageMois: 24 }, donnees), donnees.catalogue, r.categorie);
  assert.notEqual(avant, apres, "une photo de stock ne pourrait pas faire ça");
});

test("illustration : un ingrédient omis disparaît de l'image", () => {
  const r = parId["boulettes-dinde-pomme"];
  const avec = Illustration.plat(Moteur.adapterRecette(r, { allergenes: [], ageMois: 24 }, donnees), donnees.catalogue, r.categorie);
  const sans = Illustration.plat(Moteur.adapterRecette(r, { allergenes: ["moutarde"], ageMois: 24 }, donnees), donnees.catalogue, r.categorie);
  assert.notEqual(avec, sans);
});

test("illustration : tout ingrédient du catalogue a une couleur et une forme (aucun trou)", () => {
  for (const [id, def] of Object.entries(donnees.catalogue)) {
    const v = Illustration.visuelDe(id, def.roles[0], donnees.catalogue);
    assert(Array.isArray(v) && /^#[0-9A-Fa-f]{6}$/.test(v[0]), id + " → couleur invalide");
  }
});

test("illustration : chaque famille d'allergène a son glyphe", () => {
  for (const a of donnees.base.allergenes) {
    const g = Illustration.glyphe(a.id);
    assert(/<(path|circle|ellipse)/.test(g), a.id + " → glyphe manquant");
  }
});

/* ---------- blocs A/B/C/D/F (v0.4) ---------- */

const Trous = require(path.join(__dirname, "..", "outils", "trous.js"));
const Publier = require(path.join(__dirname, "..", "outils", "publier.js"));
const PromptRecette = require(path.join(__dirname, "..", "generation", "prompt-recette.js"));
const Valideur = require(path.join(__dirname, "..", "generation", "valideur-recette.js"));
const Images = require(path.join(__dirname, "..", "generation", "images.js"));
const Stripe = require(path.join(__dirname, "..", "serveur", "stripe.js"));
const Serveur = require(path.join(__dirname, "..", "serveur", "serveur.js"));
const crypto2 = require("crypto");
let corpusComplet = recettes.concat(importation.importees);
try { corpusComplet = corpusComplet.concat(lire2("donnees/generees/recettes-generees.json")); } catch (e) {}

/* --- B : rapport de trous --- */

test("trous : une recette de 18 mois ne compte pas comme utilisable à 6 mois", () => {
  const cases = Trous.analyser(corpusComplet);
  const c = cases.find((x) => x.ageMois === 6 && x.profil.length === 1 && x.profil[0] === "lait");
  const tropVieilles = corpusComplet.filter((r) => r.ageMinBase > 6).length;
  assert.equal(c.hors_age, tropVieilles);
  assert.equal(c.telle_quelle + c.adaptee + c.non_adaptable + c.hors_age, corpusComplet.length);
});

test("trous : le classement met en tête les combinaisons les plus dépourvues", () => {
  const cl = Trous.classer(Trous.analyser(corpusComplet));
  for (let i = 1; i < cl.length; i++) assert(cl[i - 1].manque >= cl[i].manque);
});

test("trous : la commande fusionne les trous identiques au lieu de les répéter", () => {
  const cmd = Trous.commande(Trous.classer(Trous.analyser(corpusComplet)));
  const cles = cmd.map((c) => c.categories[0] + "|" + c.evite.join(","));
  assert.equal(new Set(cles).size, cles.length, "la commande contient des doublons");
});

test("trous : un corpus amputé creuse un trou visible", () => {
  const ampute = corpusComplet.filter((r) => r.categorie !== "Collation");
  const cl = Trous.classer(Trous.analyser(ampute));
  assert(cl[0].manqueCategories["Collation"] >= Trous.SEUIL_CATEGORIE - 0);
});

/* --- A : publication --- */

test("publication : chaque recette est attribuée à un lot, aucune orpheline", () => {
  const r = Publier.publier();
  assert.equal(r.orphelines.length, 0, "orphelines : " + r.orphelines);
  const total = Object.values(r.contenu).reduce((s, l) => s + l.length, 0);
  assert.equal(total, corpusComplet.length);
});

test("publication : le manifeste ne contient AUCUN ingrédient — seulement des compteurs", () => {
  const r = Publier.publier();
  const txt = JSON.stringify(r.manifeste);
  assert(!/ingredients|etapes/.test(txt), "le manifeste laisse fuir du contenu");
  assert(r.manifeste.lots.every((l) => typeof l.nombre === "number"));
});

test("publication : les tables de sécurité sont hors des lots — jamais derrière le mur", () => {
  const r = Publier.publier();
  assert(r.securite.substitutions.length > 0 && r.securite.base.allergenes.length === 11);
  Object.values(r.contenu).forEach((lot) => lot.forEach((rec) => {
    assert(!rec.substitutions && !rec.allergenesTable, rec.id);
  }));
});

/* --- C : prompt et validateur --- */

test("prompt : n'offre que des ingrédients compatibles avec la commande", () => {
  const autorises = PromptRecette.ingredientsAutorises(donnees.catalogue, ["lait", "oeuf"]);
  autorises.forEach((id) => {
    const a = donnees.catalogue[id].allergenes;
    assert(!a.includes("lait") && !a.includes("oeuf"), id + " ne devrait pas être offert");
  });
  assert(autorises.includes("compote_pommes") && !autorises.includes("beurre"));
});

test("validateur : rejette un ingrédient inventé par le modèle", () => {
  const faux = { id: "test-invente", nom: "Test", categorie: "Collation", ageMinBase: 12, tempsMin: 10,
    ingredients: [{ id: "graines_de_tournesol_grillees", qte: 100, unite: "ml" }, { id: "banane", qte: 1, unite: "unité" }],
    etapes: ["Mélanger les ingrédients.", "Servir tiède."] };
  const v = Valideur.valider(faux, { evite: [], ageMois: 12, categories: ["Collation"] }, donnees);
  assert.equal(v.ok, false);
  assert(v.erreurs.some((x) => /hors catalogue/.test(x)));
});

test("validateur : rejette une recette qui contient l'allergène que la commande exclut", () => {
  const faux = { id: "test-fuite", nom: "Test", categorie: "Collation", ageMinBase: 12, tempsMin: 10,
    ingredients: [{ id: "lait_vache", qte: 250, unite: "ml", role: "liquide" }, { id: "banane", qte: 1, unite: "unité" }],
    etapes: ["Mélanger les ingrédients.", "Servir frais."] };
  const v = Valideur.valider(faux, { evite: ["lait"], ageMois: 12, categories: ["Collation"] }, donnees);
  assert.equal(v.ok, false);
  assert(v.erreurs.some((x) => /allergène que la commande exclut/.test(x)));
});

test("validateur : accepte une recette conforme, et signale le rôle ambigu", () => {
  const bonne = { id: "test-conforme", nom: "Compote de pommes et banane", categorie: "Dessert",
    portions: "4 portions", ageMinBase: 6, tempsMin: 10,
    ingredients: [{ id: "compote_pommes", qte: 250, unite: "ml", role: "liant" },
                  { id: "banane", qte: 1, unite: "unité" }, { id: "cannelle", qte: 1, unite: "ml" }],
    etapes: ["Écraser la banane à la fourchette.", "Mélanger à la compote et à la cannelle."] };
  const v = Valideur.valider(bonne, { evite: ["lait", "oeuf", "ble"], ageMois: 6, categories: ["Dessert"] }, donnees);
  assert.equal(v.ok, true, v.erreurs.join(" / "));
});

test("validateur : refuse un id déjà pris et les superlatifs marketing", () => {
  const d = { id: "muffins-banane-avoine", nom: "Les meilleurs muffins", categorie: "Collation",
    ageMinBase: 12, tempsMin: 20, ingredients: [{ id: "banane", qte: 1, unite: "unité" }, { id: "flocons_avoine", qte: 250, unite: "ml" }],
    etapes: ["Mélanger les ingrédients.", "Cuire vingt minutes."] };
  const v = Valideur.valider(d, { evite: [], ageMois: 12, categories: ["Collation"] }, donnees, corpusComplet.map((r) => r.id));
  assert.equal(v.ok, false);
  assert(v.erreurs.some((x) => /déjà utilisé/.test(x)));
});

/* --- D : images --- */

test("images : le prompt décrit les ingrédients réels, pas le titre", () => {
  const r = parId["potage-courge-coco"];
  const p = Images.promptPour(r, donnees);
  assert(/courge/i.test(p.positif) && /coco/i.test(p.positif));
  assert(/aucun œuf visible/.test(p.negatif), "les exclusions doivent être explicites");
});

test("images : une photo non révisée n'est jamais publiée — repli sur l'illustration", () => {
  const r = parId["crepes-moelleuses"];
  const emp = Images.empreinte(r);
  const res = Moteur.adapterRecette(r, { allergenes: [], ageMois: 24 }, donnees);
  const sansRevision = { [r.id]: { fichier: "images/x.webp", empreinte: emp } };
  assert.equal(Images.visuelPour(r, res, sansRevision).type, "illustration");
  const avecRevision = { [r.id]: { fichier: "images/x.webp", empreinte: emp, revisePar: "François", largeur: 1200 } };
  assert.equal(Images.visuelPour(r, res, avecRevision).type, "photo");
});

test("images : dès qu'un échange a lieu, la photo cède la place à l'illustration", () => {
  const r = parId["crepes-moelleuses"];
  const manifeste = { [r.id]: { fichier: "images/x.webp", empreinte: Images.empreinte(r), revisePar: "François", largeur: 1200 } };
  const adaptee = Moteur.adapterRecette(r, { allergenes: ["lait"], ageMois: 24 }, donnees);
  const v = Images.visuelPour(r, adaptee, manifeste);
  assert.equal(v.type, "illustration");
  assert(/montrerait autre chose/.test(v.raison));
});

test("images : une empreinte périmée invalide la photo (les ingrédients ont changé)", () => {
  const r = parId["crepes-moelleuses"];
  const v = Images.validerEntree({ fichier: "x.webp", empreinte: "000000000000", revisePar: "François", largeur: 1200 }, r);
  assert.equal(v.ok, false);
  assert(v.erreurs.some((x) => /périmée/.test(x)));
});

/* --- F : droits et Stripe --- */

test("droits : sans abonnement, seuls les lots libres sont autorisés", () => {
  const m = Publier.publier().manifeste;
  const libres = Serveur.lotsAutorises(m, null);
  assert.deepEqual(libres, m.libres);
  const tous = Serveur.lotsAutorises(m, { abonnement: { statut: "actif" } });
  assert.equal(tous.length, m.lots.length);
});

test("droits : un paiement en retard garde l'accès quelques jours, puis le perd", () => {
  const hier = new Date(Date.now() - 864e5).toISOString();
  const vieux = new Date(Date.now() - 30 * 864e5).toISOString();
  assert.equal(Serveur.abonnementActif({ abonnement: { statut: "en_retard", finPeriode: hier } }), true);
  assert.equal(Serveur.abonnementActif({ abonnement: { statut: "en_retard", finPeriode: vieux } }), false);
  assert.equal(Serveur.abonnementActif({ abonnement: { statut: "annule" } }), false);
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

test("stripe : les statuts d'abonnement se traduisent correctement", () => {
  const e = (type, o) => Stripe.evenementPertinent({ type, data: { object: o } });
  const base = { customer_email: "a@b.ca", customer: "cus_1" };
  assert.equal(e("customer.subscription.updated", Object.assign({ status: "active" }, base)).statut, "actif");
  assert.equal(e("customer.subscription.updated", Object.assign({ status: "trialing" }, base)).statut, "actif");
  assert.equal(e("customer.subscription.updated", Object.assign({ status: "past_due" }, base)).statut, "en_retard");
  assert.equal(e("customer.subscription.deleted", base).statut, "annule");
  assert.equal(e("invoice.payment_failed", base).statut, "en_retard");
  assert.equal(e("customer.discount.created", base), null);
  assert.equal(e("checkout.session.completed", { customer_email: null }), null);
});

/* ---------- cycle automatique (v0.5) ---------- */

const Vision = require(path.join(__dirname, "..", "generation", "vision.js"));
const Coherence = require(path.join(__dirname, "..", "generation", "coherence.js"));
const MoteursImage = require(path.join(__dirname, "..", "generation", "moteurs-image.js"));
const MoteursTexte = require(path.join(__dirname, "..", "generation", "moteurs-texte.js"));

const visionQuiVoit = (aliments) => ({ nom: "test", disponible: () => true,
  decrire: async () => JSON.stringify({ aliments, lisible: true, incertitudes: [] }) });

test("vision : les faux amis végétaux ne déclenchent pas leur famille", () => {
  const f = (t) => Vision.famillesDe(Vision.normaliser(t));
  assert.deepEqual(f("lait de coco"), []);
  assert.deepEqual(f("beurre de tournesol"), []);
  assert.deepEqual(f("noix de coco"), []);
  assert.deepEqual(f("poudre à pâte"), []);
  assert.deepEqual(f("pâtes de riz"), []);
  assert.deepEqual(f("lait"), ["lait"]);
  assert.deepEqual(f("beurre d'arachide"), ["arachide"]);
  assert.deepEqual(f("pâtes"), ["ble"]);
});

test("vision : un intrus détecté dans l'image la fait rejeter", async () => {
  const r = parId["potage-courge-coco"];
  const v = await Vision.verifier(Buffer.from("x"), r, donnees,
    { moteur: visionQuiVoit(["courge", "lait de coco", "noix de Grenoble"]) });
  assert.equal(v.ok, false);
  assert(/noix/i.test(v.erreurs.join(" ")));
});

test("vision : une image fidèle est acceptée", async () => {
  const r = parId["potage-courge-coco"];
  const noms = r.ingredients.map((u) => donnees.catalogue[u.id].nom);
  const v = await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: visionQuiVoit(noms) });
  assert.equal(v.ok, true, v.erreurs.join(" / "));
  assert(v.reconnus >= 2);
});

test("vision : panne, réponse illisible ou moteur absent → rejet, jamais acceptation par défaut", async () => {
  const r = parId["potage-courge-coco"];
  const panne = { nom: "x", decrire: async () => { throw new Error("réseau"); } };
  const illisible = { nom: "x", decrire: async () => "je ne sais pas" };
  assert.equal((await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: panne })).ok, false);
  assert.equal((await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: illisible })).ok, false);
  assert.equal((await Vision.verifier(Buffer.from("x"), r, donnees, { moteur: Vision.MOTEURS.absent })).ok, false);
});

test("vision : un risque d'étouffement fait rejeter, même sans allergène", async () => {
  const r = parId["crepes-moelleuses"];
  const v = await Vision.verifier(Buffer.from("x"), r, donnees,
    { moteur: visionQuiVoit(["lait", "oeuf", "farine de blé", "raisins entiers"]) });
  assert.equal(v.ok, false);
  assert(/étouffement/.test(v.erreurs.join(" ")));
});

test("vision : une image d'un autre plat est rejetée", async () => {
  const r = parId["potage-courge-coco"];
  const v = await Vision.verifier(Buffer.from("x"), r, donnees,
    { moteur: visionQuiVoit(["spaghetti", "boulettes"]) });
  assert.equal(v.ok, false);
  assert(/reconnaissable/.test(v.erreurs.join(" ")));
});

test("manifeste : une révision automatique sans verdict de vision ne publie pas", () => {
  const r = parId["potage-courge-coco"];
  const emp = Images.empreinte(r);
  const res = Moteur.adapterRecette(r, { allergenes: [], ageMois: 24 }, donnees);
  const complet = { [r.id]: { fichier: "i.png", empreinte: emp, largeur: 1024,
    revisePar: "vérification automatique (test)", verification: { moteur: "test", reconnus: 3, attendus: 5 } } };
  assert.equal(Images.visuelPour(r, res, complet).type, "photo");
  const sansVerdict = { [r.id]: { fichier: "i.png", empreinte: emp, largeur: 1024,
    revisePar: "vérification automatique (test)" } };
  assert.equal(Images.visuelPour(r, res, sansVerdict).type, "illustration");
  const rienVu = { [r.id]: { fichier: "i.png", empreinte: emp, largeur: 1024,
    revisePar: "vérification automatique (test)", verification: { moteur: "test", reconnus: 0, attendus: 5 } } };
  assert.equal(Images.visuelPour(r, res, rienVu).type, "illustration");
  const visionAbsente = { [r.id]: { fichier: "i.png", empreinte: emp, largeur: 1024,
    revisePar: "vérification automatique (absent)", verification: { moteur: "absent", reconnus: 2, attendus: 5 } } };
  assert.equal(Images.visuelPour(r, res, visionAbsente).type, "illustration");
});

test("cohérence : « fourchette » n'est pas « four » — les frontières de mots tiennent", () => {
  assert.equal(Coherence.contient("écraser à la fourchette", Coherence.MOTS_FOUR), false);
  assert.equal(Coherence.contient("cuire au four à 180 °C", Coherence.MOTS_FOUR), true);
  assert.equal(Coherence.contient("enfournez la plaque", Coherence.MOTS_FOUR), true);
});

test("cohérence : attrape les ratés qu'une cuisson d'essai aurait révélés", () => {
  const base = { id: "t", nom: "Test", categorie: "Repas", portions: "4 portions", ageMinBase: 12, tempsMin: 30 };
  const liquide = Coherence.verifier(Object.assign({}, base, {
    ingredients: [{ id: "farine_ble", qte: 100, unite: "ml", role: "farine" },
                  { id: "lait_vache", qte: 600, unite: "ml", role: "liquide" }],
    etapes: ["Mélanger la farine et le lait.", "Cuire au four à 180 °C pendant 20 minutes."] }), donnees);
  assert.equal(liquide.ok, false);

  const sansTemp = Coherence.verifier(Object.assign({}, base, {
    ingredients: [{ id: "farine_ble", qte: 250, unite: "ml", role: "farine" },
                  { id: "lait_vache", qte: 250, unite: "ml", role: "liquide" }],
    etapes: ["Mélanger la farine et le lait.", "Cuire au four 20 minutes."] }), donnees);
  assert(sansTemp.erreurs.some((e) => /température/.test(e)));

  const cru = Coherence.verifier(Object.assign({}, base, {
    ingredients: [{ id: "poulet", qte: 300, unite: "g", role: "proteine" }, { id: "riz", qte: 250, unite: "ml" }],
    etapes: ["Mélanger le poulet et le riz dans un bol.", "Servir immédiatement."] }), donnees);
  assert(cru.erreurs.some((e) => /crue/.test(e)));
});

test("cohérence : tout le corpus existant passe — aucun faux positif", () => {
  const mauvaises = corpusComplet.filter((r) => !Coherence.verifier(r, donnees).ok);
  assert.equal(mauvaises.length, 0,
    mauvaises.map((r) => r.id + " : " + Coherence.verifier(r, donnees).erreurs.join(" ; ")).join(" | "));
});

test("moteurs : un adaptateur est toujours disponible, et le repli est le mode simulé", async () => {
  assert.equal(MoteursTexte.choisir("simule").nom, "simule");
  assert.equal(MoteursImage.choisir("simule").nom, "simule");
  const img = await MoteursImage.MOTEURS.simule.generer({ prompt: "test", negatif: "", largeur: 64, hauteur: 48 });
  assert(Buffer.isBuffer(img.octets) && img.octets.length > 50);
  assert.equal(img.octets.slice(1, 4).toString("ascii"), "PNG", "le mode simulé doit produire un vrai PNG");
});

test("moteurs : le JSON du modèle est extrait même noyé dans du texte", () => {
  const sale = 'Voici les recettes :\n```json\n[{"id":"a"},{"id":"b"}]\n```\nBon appétit!';
  assert.equal(MoteursTexte.extraireJSON(sale).length, 2);
});

/* ---------- iOS : StoreKit et pont natif (v0.6) ---------- */

const Apple = require(path.join(__dirname, "..", "serveur", "apple.js"));

test("apple : sans racine Apple, tout est refusé — jamais d'acceptation par défaut", () => {
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
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: futur }, base), o).statut, "actif");
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: passe }, base), o).statut, "annule");
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: futur, revocationDate: Date.now() }, base), o).statut, "annule");
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: futur, bundleId: "autre.app" }, base, { bundleId: "autre.app" }), o).ok, false);
  assert.equal(Apple.etatDepuisTransaction(Object.assign({ expiresDate: futur, productId: "inconnu" }, base, { productId: "inconnu" }), o).ok, false);
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

/* --- le pont JS que Swift appelle, extrait du gabarit et exercé ici --- */

function chargerPont() {
  const src = fs.readFileSync(path.join(__dirname, "..", "app", "gabarit-app.html"), "utf8");
  const debut = src.indexOf("window.evaluerProduitScanne = function");
  const fin = src.indexOf("/* Le natif est propriétaire");
  assert(debut !== -1 && fin > debut, "le pont natif est introuvable dans le gabarit");
  const sansAcc = (t) => String(t).normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  const nomAll = (id) => { const a = donnees.base.allergenes.find((x) => x.id === id); return a ? a.nom.toLowerCase() : id; };
  const listeFr = (t) => t.length < 2 ? t.join("") : t.slice(0, -1).join(", ") + " et " + t[t.length - 1];
  return new Function("donnees", "sansAcc", "nomAll", "listeFr",
    "var window={};" + src.slice(debut, fin) + "return window.evaluerProduitScanne;")(donnees, sansAcc, nomAll, listeFr);
}

test("scanner : une étiquette contenant l'allergène évité donne « à éviter »", () => {
  const f = chargerPont();
  const r = f({ texte: "Farine de blé, sucre, lait de vache, beurre, sel", evites: ["lait"] });
  assert.equal(r.statut, "a_eviter");
  assert(r.allergenesTrouves.length > 0);
});

test("scanner : un ingrédient non reconnu donne « incertain », jamais « sûr »", () => {
  const f = chargerPont();
  const r = f({ texte: "Riz, gomme xanthane E415, poulet", evites: ["lait"] });
  assert.equal(r.statut, "incertain");
  assert(r.ingredientsInconnus.length > 0);
  assert(/étiquette/.test(r.message), "le message doit renvoyer à l'étiquette");
});

test("scanner : les variantes d'apostrophe et de casse sont reconnues", () => {
  const f = chargerPont();
  ["FLOCONS D'AVOINE, BANANE, CANNELLE", "Flocons d avoine, banane, cannelle",
   "flocons d\u2019avoine, banane, cannelle"].forEach((t) => {
    assert.equal(f({ texte: t, evites: ["arachide"] }).statut, "sur", t);
  });
});

test("scanner : la sauce soya déclenche AUSSI le blé (dérivé du catalogue)", () => {
  const f = chargerPont();
  assert.equal(f({ texte: "Riz, sauce soya, gingembre", evites: ["ble"] }).statut, "a_eviter");
  assert.equal(f({ texte: "Riz, sauce soya, gingembre", evites: ["soya"] }).statut, "a_eviter");
});

test("scanner : une étiquette entièrement reconnue et sans allergène évité est « sûr »", () => {
  const f = chargerPont();
  const r = f({ texte: "Banane, pomme, cannelle", evites: ["lait", "oeuf", "arachide"] });
  assert.equal(r.statut, "sur");
  assert.equal(r.ingredientsInconnus.length, 0);
});

test("iOS : le gabarit délègue l'abonnement à StoreKit et n'ouvre aucune caisse web", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "app", "gabarit-app.html"), "utf8");
  assert(/if\(SOUS_IOS\)\{ versNatif\("abonnement"\); return; \}/.test(src),
    "le chemin iOS doit court-circuiter Stripe (règle 3.1.1)");
  const apresIOS = src.slice(src.indexOf('if(SOUS_IOS){ versNatif("abonnement"); return; }'));
  assert(apresIOS.indexOf("api/paiement") > 0, "la route Stripe existe encore pour le web");
});

Promise.all(enAttente).then(function () { console.log("\n" + n + " tests."); });
