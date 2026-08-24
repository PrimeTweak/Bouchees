/* Rapport de trous — bloc B
 * node tools/gaps.js
 *
 * Runs the whole corpus through the engine for every realistic avoidance
 * profile x every age stage, and ranks the combinations by scarcity.
 *
 * This is what decides the month's content: instead of "8 random recipes", it
 * says "6 recipes for the most painful gap". No generic recipe app can do
 * this — it takes a deterministic engine to
 * savoir ce qui missing.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const Engine = require(path.join(__dirname, "..", "engine", "engine.js"));
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));

const donnees = {
  catalogue: lire("data/ingredients.json"),
  substitutions: lire("data/substitutions.json"),
  base: lire("data/base.json")
};

/* Avoidance profiles: each allergen on its own, plus the combinations that
 * actually turn up often in toddlers. */
const PROFILS = donnees.base.allergens.map((a) => [a.id]).concat([
  ["lait", "oeuf"], ["lait", "soya"], ["lait", "ble"], ["oeuf", "ble"],
  ["arachide", "noix"], ["arachide", "noix", "sesame"],
  ["lait", "oeuf", "ble"], ["lait", "oeuf", "arachide", "noix"],
  ["poisson", "crustaces_mollusques"]
]);
const STADES = [6, 9, 12, 24, 48];
const CATEGORIES = ["Breakfast", "Meal", "Snack", "Dessert"];

/* Seuil : en dessous, un parent n'a pas de quoi faire une semaine. */
const SEUIL_SEMAINE = 12;
/* A family does not only eat dinner: variety per category matters. */
const SEUIL_CATEGORIE = 6;

function nomProfil(ids) {
  if (!ids.length) return "aucun évitement";
  return "no " + ids.map(function (id) {
    const a = donnees.base.allergens.find((x) => x.id === id);
    return a ? a.name.toLowerCase() : id;
  }).join(" + ");
}
function nomStade(mois) {
  return Engine.stadePour(mois, donnees.base).name;
}

function analyser(corpus) {
  const cases = [];
  PROFILS.forEach(function (profile) {
    STADES.forEach(function (ageMois) {
      const c = { profile: profile, ageMois: ageMois, as_is: 0, adapted: 0, not_adaptable: 0,
                  outOfAge: 0, byCategory: {}, blockers: {} };
      CATEGORIES.forEach(function (cat) { c.byCategory[cat] = 0; });
      corpus.forEach(function (r) {
        /* A recipe written for 18 months is not "usable" at 6 months, even if
         * the engine can adapt it on the allergen side. */
        if (ageMois < r.minAgeMonths) { c.outOfAge++; return; }
        const res = Engine.adapterRecette(r, { allergens: profile, ageMois: ageMois }, donnees);
        c[res.status]++;
        if (res.status !== "not_adaptable") {
          if (c.byCategory[r.category] !== undefined) c.byCategory[r.category]++;
        } else {
          res.ingredients.filter((i) => i.status === "blocked").forEach(function (i) {
            c.blockers[i.id] = (c.blockers[i.id] || 0) + 1;
          });
        }
      });
      c.usable = c.as_is + c.adapted;
      c.missingCategories = {};
      CATEGORIES.forEach(function (cat) {
        const d = Math.max(0, SEUIL_CATEGORIE - c.byCategory[cat]);
        if (d) c.missingCategories[cat] = d;
      });
      const sommeCat = Object.values(c.missingCategories).reduce((a, b) => a + b, 0);
      c.missing = Math.max(Math.max(0, SEUIL_SEMAINE - c.usable), sommeCat);
      cases.push(c);
    });
  });
  return cases;
}

/* Ranking: combinations under the threshold first, then those where a whole
 * category is empty (not a single breakfast, for instance). */
function classer(cases) {
  return cases.slice().sort(function (a, b) {
    if (b.missing !== a.missing) return b.missing - a.missing;
    const videA = CATEGORIES.filter((c) => a.byCategory[c] === 0).length;
    const videB = CATEGORIES.filter((c) => b.byCategory[c] === 0).length;
    if (videB !== videA) return videB - videA;
    return a.usable - b.usable;
  });
}

/* The ingredients that block most often: each entry is a missing substitution
 * rule — usually cheaper to write than a whole recipe. */
function bloquantsGlobaux(cases) {
  const tot = {};
  cases.forEach(function (c) {
    Object.keys(c.blockers).forEach(function (id) { tot[id] = (tot[id] || 0) + c.blockers[id]; });
  });
  return Object.keys(tot).map(function (id) {
    return { id: id, name: donnees.catalogue[id] ? donnees.catalogue[id].name : id, n: tot[id] };
  }).sort((a, b) => b.n - a.n);
}

/* A recipe with no milk AND no egg AND no peanut serves all three profiles.
 * So gaps sharing an age and a category are merged: the month's batch becomes
 * a handful of strong instructions instead of twenty redundant lines. */
function commande(classement, target) {
  target = target || 8;
  const groupes = {};
  for (const c of classement) {
    if (c.missing === 0) continue;
    const cats = Object.keys(c.missingCategories);
    const cles = cats.length ? cats : ["Repas"];
    cles.forEach(function (cat) {
      const cle = c.ageMois + "|" + cat;
      if (!groupes[cle]) groupes[cle] = { ageMois: c.ageMois, category: cat, evite: {}, missing: 0, horsAge: c.outOfAge, usable: c.usable };
      c.profile.forEach(function (a) { groupes[cle].evite[a] = 1; });
      groupes[cle].missing = Math.max(groupes[cle].missing, c.missingCategories[cat] || 1);
      groupes[cle].usable = Math.min(groupes[cle].usable, c.usable);
    });
  }
  /* Second fold: the same gap appearing at 6, 9, 12 and 24 months is ONE gap,
   * not four. The youngest age is kept — a recipe that works at 6 months also
   * works later. */
  const parTrou = {};
  Object.values(groupes).forEach(function (g) {
    const evite = Object.keys(g.evite).sort();
    const cle = g.category + "|" + evite.join(",");
    if (!parTrou[cle] || g.ageMois < parTrou[cle].ageMois) {
      parTrou[cle] = { ageMois: g.ageMois, category: g.category, evite: evite,
                       missing: g.missing, horsAge: g.horsAge, usable: g.usable };
    } else {
      parTrou[cle].missing = Math.max(parTrou[cle].missing, g.missing);
    }
  });
  const lignes = Object.values(parTrou)
    .sort((a, b) => (b.missing - a.missing) || (a.usable - b.usable));
  const out = [];
  let reste = target;
  for (const g of lignes) {
    if (reste <= 0) break;
    const passePartout = g.evite.length > 5;
    const n = Math.min(reste, passePartout ? 2 : Math.max(2, g.missing));
    out.push({
      n: n, ageMois: g.ageMois, categories: [g.category], evite: g.evite,
      passePartout: passePartout,
      reason: g.usable + " usable recipes at " + nomStade(g.ageMois) +
        (g.horsAge ? ", " + g.horsAge + " du corpus visent plus vieux" : "") +
        " — il missing " + g.missing + " " + g.category.toLowerCase() +
        (passePartout ? ". This gap exists for EVERY profile: one recipe that works for all of them fills it." : "")
    });
    reste -= n;
  }
  return out;
}

function markdown(classement, blockers, cmd, nCorpus) {
  const l = [];
  l.push("# Rapport de trous — " + new Date().toISOString().slice(0, 10));
  l.push("");
  l.push("Corpus: **" + nCorpus + " recipes**. Thresholds: **" + SEUIL_SEMAINE +
    " usable recipes** per combination (enough for a week) and **" + SEUIL_CATEGORIE +
    " par catégorie** (un parent ne sert pas que des soupers).");
  l.push("");
  l.push("\"Too old\" = recipes whose minimum age is above the age being tested. They do not count.");
  l.push("");
  l.push("## The 12 most starved combinations");
  l.push("");
  l.push("| Profil | Âge | Telles quelles | Adaptées | Bloquées | Trop vieilles | Manque | Catégories en pénurie |");
  l.push("|---|---|---|---|---|---|---|---|");
  classement.slice(0, 12).forEach(function (c) {
    const cats = Object.keys(c.missingCategories);
    l.push("| " + nomProfil(c.profile) + " | " + nomStade(c.ageMois) + " | " + c.as_is +
      " | " + c.adapted + " | " + c.not_adaptable + " | " + c.outOfAge + " | " + (c.missing || "—") +
      " | " + (cats.length ? cats.map((k) => k + " (" + c.missingCategories[k] + ")").join(", ") : "—") + " |");
  });
  l.push("");
  l.push("## The ingredients that block most often");
  l.push("");
  l.push("Each line is a **missing substitution rule**. Writing one");
  l.push("often unlocks more recipes than writing a new one.");
  l.push("");
  if (!blockers.length) l.push("None — every blocked recipe is blocked by age, not by an allergen.");
  blockers.slice(0, 10).forEach(function (b) {
    l.push("- **" + b.name + "** (`" + b.id + "`) — bloque " + b.n + " fois");
  });
  l.push("");
  l.push("## Suggested commission for the next batch");
  l.push("");
  if (!cmd.length) l.push("Aucun trou sous le seuil — le prochain lot peut viser la variété plutôt que la couverture.");
  cmd.forEach(function (c) {
    l.push("- **" + c.n + " " + c.categories[0].toLowerCase() + "** from " + c.ageMois + " months — " +
      (c.passePartout ? "**works for everyone** (none of the 11 priority allergens)" : nomProfil(c.evite)));
    l.push("    - " + c.reason);
  });
  l.push("");
  l.push("Ce fichier est régénéré par `node tools/gaps.js`. Il alimente");
  l.push("`generation/recipe-prompt.js`, qui transforme la commande en prompt contraint.");
  return l.join("\n");
}

function rapport(corpus) {
  const cases = analyser(corpus);
  const classement = classer(cases);
  const blockers = bloquantsGlobaux(cases);
  const cmd = commande(classement);
  return { cases: cases, classement: classement, blockers: blockers, commande: cmd };
}

if (require.main === module) {
  let corpus = lire("data/recipes.json");
  try { corpus = corpus.concat(lire("data/imported/imported-recipes.json")); } catch (e) {}
  try { corpus = corpus.concat(lire("data/generated/generated-recipes.json")); } catch (e) {}
  const r = rapport(corpus);
  fs.writeFileSync(path.join(racine, "tools", "rapport-trous.md"),
    markdown(r.classement, r.blockers, r.commande, corpus.length) + "\n");
  fs.writeFileSync(path.join(racine, "tools", "rapport-trous.json"),
    JSON.stringify({ classement: r.classement.slice(0, 25), blockers: r.blockers, commande: r.commande }, null, 2) + "\n");
  console.log("Gaps analysed: " + r.cases.length + " combinations (" + PROFILS.length + " profiles x " + STADES.length + " ages)");
  r.classement.slice(0, 5).forEach(function (c) {
    console.log("  " + nomProfil(c.profile) + " @ " + nomStade(c.ageMois) + " → " + c.usable + " usable" +
      (c.missing ? "  MISSING " + c.missing : ""));
  });
  console.log("Suggested commission: " + r.commande.reduce((s, c) => s + c.n, 0) + " recipes");
}

module.exports = { SEUIL_CATEGORIE: SEUIL_CATEGORIE, rapport: rapport, analyser: analyser, classer: classer, commande: commande, nomProfil: nomProfil, PROFILS: PROFILS, STADES: STADES, SEUIL_SEMAINE: SEUIL_SEMAINE };
