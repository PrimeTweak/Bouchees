/* Rapport de trous — bloc B
 * node tools/gaps.js
 *
 * Passe tout le corpus dans le moteur pour chaque profile d'évitement réaliste
 * × chaque stade d'âge, et classe les combinaisons par pénurie.
 *
 * C'est ce qui décide du contenu du mois : au lieu de « 8 recettes au hasard »,
 * on écrit « 6 recettes pour le trou le plus douloureux ». Aucune app de
 * recettes générique ne peut faire ça — il faut un moteur déterministe pour
 * savoir ce qui missing.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const Moteur = require(path.join(__dirname, "..", "engine", "engine.js"));
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));

const donnees = {
  catalogue: lire("data/ingredients.json"),
  substitutions: lire("data/substitutions.json"),
  base: lire("data/base.json")
};

/* Profils d'évitement : chaque allergène seul, plus les combinaisons
 * réellement fréquentes chez les tout-petits. */
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
/* Un parent ne mange pas que des soupers : il faut de la variété par catégorie. */
const SEUIL_CATEGORIE = 6;

function nomProfil(ids) {
  if (!ids.length) return "aucun évitement";
  return "sans " + ids.map(function (id) {
    const a = donnees.base.allergens.find((x) => x.id === id);
    return a ? a.name.toLowerCase() : id;
  }).join(" + ");
}
function nomStade(mois) {
  return Moteur.stadePour(mois, donnees.base).name;
}

function analyser(corpus) {
  const cases = [];
  PROFILS.forEach(function (profile) {
    STADES.forEach(function (ageMois) {
      const c = { profile: profile, ageMois: ageMois, as_is: 0, adapted: 0, not_adaptable: 0,
                  outOfAge: 0, byCategory: {}, blockers: {} };
      CATEGORIES.forEach(function (cat) { c.byCategory[cat] = 0; });
      corpus.forEach(function (r) {
        /* Une recette pensée pour 18 mois n'est pas « utilisable » à 6 mois,
         * même si le moteur sait l'adapter côté allergènes. */
        if (ageMois < r.minAgeMonths) { c.outOfAge++; return; }
        const res = Moteur.adapterRecette(r, { allergens: profile, ageMois: ageMois }, donnees);
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

/* Classement : d'abord les combinaisons sous le seuil, puis celles où
 * une catégorie entière est vide (pas un seul déjeuner, par exemple). */
function classer(cases) {
  return cases.slice().sort(function (a, b) {
    if (b.missing !== a.missing) return b.missing - a.missing;
    const videA = CATEGORIES.filter((c) => a.byCategory[c] === 0).length;
    const videB = CATEGORIES.filter((c) => b.byCategory[c] === 0).length;
    if (videB !== videA) return videB - videA;
    return a.usable - b.usable;
  });
}

/* Ingrédients qui bloquent le plus souvent : chaque entrée est une règle
 * de substitution manquante — souvent moins cher à écrire qu'une recette. */
function bloquantsGlobaux(cases) {
  const tot = {};
  cases.forEach(function (c) {
    Object.keys(c.blockers).forEach(function (id) { tot[id] = (tot[id] || 0) + c.blockers[id]; });
  });
  return Object.keys(tot).map(function (id) {
    return { id: id, name: donnees.catalogue[id] ? donnees.catalogue[id].name : id, n: tot[id] };
  }).sort((a, b) => b.n - a.n);
}

/* Une recette sans lait ET sans œufs ET sans arachides sert les trois profils.
 * On fusionne donc les trous qui partagent l'âge et la catégorie : le lot du
 * mois devient une poignée d'instructions fortes, pas vingt lignes redondantes. */
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
  /* Second pliage : le même trou qui revient à 6, 9, 12 et 24 mois est UN
   * trou, pas quatre. On garde l'âge le plus jeune — une recette qui marche
   * à 6 mois marche aussi plus tard. */
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
      reason: g.usable + " recettes usable à " + nomStade(g.ageMois) +
        (g.horsAge ? ", " + g.horsAge + " du corpus visent plus vieux" : "") +
        " — il missing " + g.missing + " " + g.category.toLowerCase() +
        (passePartout ? ". Ce trou existe pour TOUS les profils : une seule recette passe-partout les sert tous." : "")
    });
    reste -= n;
  }
  return out;
}

function markdown(classement, blockers, cmd, nCorpus) {
  const l = [];
  l.push("# Rapport de trous — " + new Date().toISOString().slice(0, 10));
  l.push("");
  l.push("Corpus : **" + nCorpus + " recettes**. Seuils : **" + SEUIL_SEMAINE +
    " recettes usable** par combinaison (de quoi faire une semaine) et **" + SEUIL_CATEGORIE +
    " par catégorie** (un parent ne sert pas que des soupers).");
  l.push("");
  l.push("« Trop vieilles » = recettes dont l'âge minimal dépasse l'âge testé. Elles ne comptent pas.");
  l.push("");
  l.push("## Les 12 combinaisons les plus dépourvues");
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
  l.push("## Ingrédients qui bloquent le plus");
  l.push("");
  l.push("Chaque ligne est une **règle de substitution manquante**. En écrire une");
  l.push("débloque souvent plus de recettes que d'en rédiger une nouvelle.");
  l.push("");
  if (!blockers.length) l.push("Aucun — toutes les recettes bloquées le sont pour des raisons d'âge, pas d'allergène.");
  blockers.slice(0, 10).forEach(function (b) {
    l.push("- **" + b.name + "** (`" + b.id + "`) — bloque " + b.n + " fois");
  });
  l.push("");
  l.push("## Commande suggérée pour le prochain lot");
  l.push("");
  if (!cmd.length) l.push("Aucun trou sous le seuil — le prochain lot peut viser la variété plutôt que la couverture.");
  cmd.forEach(function (c) {
    l.push("- **" + c.n + " " + c.categories[0].toLowerCase() + "** dès " + c.ageMois + " mois — " +
      (c.passePartout ? "**passe-partout** (sans aucun des 11 allergènes prioritaires)" : nomProfil(c.evite)));
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
  console.log("Trous analysés : " + r.cases.length + " combinaisons (" + PROFILS.length + " profils × " + STADES.length + " âges)");
  r.classement.slice(0, 5).forEach(function (c) {
    console.log("  " + nomProfil(c.profile) + " @ " + nomStade(c.ageMois) + " → " + c.usable + " usable" +
      (c.missing ? "  MANQUE " + c.missing : ""));
  });
  console.log("Commande suggérée : " + r.commande.reduce((s, c) => s + c.n, 0) + " recettes");
}

module.exports = { SEUIL_CATEGORIE: SEUIL_CATEGORIE, rapport: rapport, analyser: analyser, classer: classer, commande: commande, nomProfil: nomProfil, PROFILS: PROFILS, STADES: STADES, SEUIL_SEMAINE: SEUIL_SEMAINE };
