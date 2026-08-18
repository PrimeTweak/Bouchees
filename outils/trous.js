/* Rapport de trous — bloc B
 * node outils/trous.js
 *
 * Passe tout le corpus dans le moteur pour chaque profil d'évitement réaliste
 * × chaque stade d'âge, et classe les combinaisons par pénurie.
 *
 * C'est ce qui décide du contenu du mois : au lieu de « 8 recettes au hasard »,
 * on écrit « 6 recettes pour le trou le plus douloureux ». Aucune app de
 * recettes générique ne peut faire ça — il faut un moteur déterministe pour
 * savoir ce qui manque.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const Moteur = require(path.join(__dirname, "..", "moteur", "moteur.js"));
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));

const donnees = {
  catalogue: lire("donnees/ingredients.json"),
  substitutions: lire("donnees/substitutions.json"),
  base: lire("donnees/base.json")
};

/* Profils d'évitement : chaque allergène seul, plus les combinaisons
 * réellement fréquentes chez les tout-petits. */
const PROFILS = donnees.base.allergenes.map((a) => [a.id]).concat([
  ["lait", "oeuf"], ["lait", "soya"], ["lait", "ble"], ["oeuf", "ble"],
  ["arachide", "noix"], ["arachide", "noix", "sesame"],
  ["lait", "oeuf", "ble"], ["lait", "oeuf", "arachide", "noix"],
  ["poisson", "crustaces_mollusques"]
]);
const STADES = [6, 9, 12, 24, 48];
const CATEGORIES = ["Déjeuner", "Repas", "Collation", "Dessert"];

/* Seuil : en dessous, un parent n'a pas de quoi faire une semaine. */
const SEUIL_SEMAINE = 7;
/* Un parent ne mange pas que des soupers : il faut de la variété par catégorie. */
const SEUIL_CATEGORIE = 3;

function nomProfil(ids) {
  if (!ids.length) return "aucun évitement";
  return "sans " + ids.map(function (id) {
    const a = donnees.base.allergenes.find((x) => x.id === id);
    return a ? a.nom.toLowerCase() : id;
  }).join(" + ");
}
function nomStade(mois) {
  return Moteur.stadePour(mois, donnees.base).nom;
}

function analyser(corpus) {
  const cases = [];
  PROFILS.forEach(function (profil) {
    STADES.forEach(function (ageMois) {
      const c = { profil: profil, ageMois: ageMois, telle_quelle: 0, adaptee: 0, non_adaptable: 0,
                  hors_age: 0, parCategorie: {}, bloquants: {} };
      CATEGORIES.forEach(function (cat) { c.parCategorie[cat] = 0; });
      corpus.forEach(function (r) {
        /* Une recette pensée pour 18 mois n'est pas « utilisable » à 6 mois,
         * même si le moteur sait l'adapter côté allergènes. */
        if (ageMois < r.ageMinBase) { c.hors_age++; return; }
        const res = Moteur.adapterRecette(r, { allergenes: profil, ageMois: ageMois }, donnees);
        c[res.statut]++;
        if (res.statut !== "non_adaptable") {
          if (c.parCategorie[r.categorie] !== undefined) c.parCategorie[r.categorie]++;
        } else {
          res.ingredients.filter((i) => i.statut === "impossible").forEach(function (i) {
            c.bloquants[i.id] = (c.bloquants[i.id] || 0) + 1;
          });
        }
      });
      c.utilisables = c.telle_quelle + c.adaptee;
      c.manqueCategories = {};
      CATEGORIES.forEach(function (cat) {
        const d = Math.max(0, SEUIL_CATEGORIE - c.parCategorie[cat]);
        if (d) c.manqueCategories[cat] = d;
      });
      const sommeCat = Object.values(c.manqueCategories).reduce((a, b) => a + b, 0);
      c.manque = Math.max(Math.max(0, SEUIL_SEMAINE - c.utilisables), sommeCat);
      cases.push(c);
    });
  });
  return cases;
}

/* Classement : d'abord les combinaisons sous le seuil, puis celles où
 * une catégorie entière est vide (pas un seul déjeuner, par exemple). */
function classer(cases) {
  return cases.slice().sort(function (a, b) {
    if (b.manque !== a.manque) return b.manque - a.manque;
    const videA = CATEGORIES.filter((c) => a.parCategorie[c] === 0).length;
    const videB = CATEGORIES.filter((c) => b.parCategorie[c] === 0).length;
    if (videB !== videA) return videB - videA;
    return a.utilisables - b.utilisables;
  });
}

/* Ingrédients qui bloquent le plus souvent : chaque entrée est une règle
 * de substitution manquante — souvent moins cher à écrire qu'une recette. */
function bloquantsGlobaux(cases) {
  const tot = {};
  cases.forEach(function (c) {
    Object.keys(c.bloquants).forEach(function (id) { tot[id] = (tot[id] || 0) + c.bloquants[id]; });
  });
  return Object.keys(tot).map(function (id) {
    return { id: id, nom: donnees.catalogue[id] ? donnees.catalogue[id].nom : id, n: tot[id] };
  }).sort((a, b) => b.n - a.n);
}

/* Une recette sans lait ET sans œufs ET sans arachides sert les trois profils.
 * On fusionne donc les trous qui partagent l'âge et la catégorie : le lot du
 * mois devient une poignée d'instructions fortes, pas vingt lignes redondantes. */
function commande(classement, cible) {
  cible = cible || 8;
  const groupes = {};
  for (const c of classement) {
    if (c.manque === 0) continue;
    const cats = Object.keys(c.manqueCategories);
    const cles = cats.length ? cats : ["Repas"];
    cles.forEach(function (cat) {
      const cle = c.ageMois + "|" + cat;
      if (!groupes[cle]) groupes[cle] = { ageMois: c.ageMois, categorie: cat, evite: {}, manque: 0, horsAge: c.hors_age, utilisables: c.utilisables };
      c.profil.forEach(function (a) { groupes[cle].evite[a] = 1; });
      groupes[cle].manque = Math.max(groupes[cle].manque, c.manqueCategories[cat] || 1);
      groupes[cle].utilisables = Math.min(groupes[cle].utilisables, c.utilisables);
    });
  }
  /* Second pliage : le même trou qui revient à 6, 9, 12 et 24 mois est UN
   * trou, pas quatre. On garde l'âge le plus jeune — une recette qui marche
   * à 6 mois marche aussi plus tard. */
  const parTrou = {};
  Object.values(groupes).forEach(function (g) {
    const evite = Object.keys(g.evite).sort();
    const cle = g.categorie + "|" + evite.join(",");
    if (!parTrou[cle] || g.ageMois < parTrou[cle].ageMois) {
      parTrou[cle] = { ageMois: g.ageMois, categorie: g.categorie, evite: evite,
                       manque: g.manque, horsAge: g.horsAge, utilisables: g.utilisables };
    } else {
      parTrou[cle].manque = Math.max(parTrou[cle].manque, g.manque);
    }
  });
  const lignes = Object.values(parTrou)
    .sort((a, b) => (b.manque - a.manque) || (a.utilisables - b.utilisables));
  const out = [];
  let reste = cible;
  for (const g of lignes) {
    if (reste <= 0) break;
    const passePartout = g.evite.length > 5;
    const n = Math.min(reste, passePartout ? 2 : Math.max(2, g.manque));
    out.push({
      n: n, ageMois: g.ageMois, categories: [g.categorie], evite: g.evite,
      passePartout: passePartout,
      raison: g.utilisables + " recettes utilisables à " + nomStade(g.ageMois) +
        (g.horsAge ? ", " + g.horsAge + " du corpus visent plus vieux" : "") +
        " — il manque " + g.manque + " " + g.categorie.toLowerCase() +
        (passePartout ? ". Ce trou existe pour TOUS les profils : une seule recette passe-partout les sert tous." : "")
    });
    reste -= n;
  }
  return out;
}

function markdown(classement, bloquants, cmd, nCorpus) {
  const l = [];
  l.push("# Rapport de trous — " + new Date().toISOString().slice(0, 10));
  l.push("");
  l.push("Corpus : **" + nCorpus + " recettes**. Seuils : **" + SEUIL_SEMAINE +
    " recettes utilisables** par combinaison (de quoi faire une semaine) et **" + SEUIL_CATEGORIE +
    " par catégorie** (un parent ne sert pas que des soupers).");
  l.push("");
  l.push("« Trop vieilles » = recettes dont l'âge minimal dépasse l'âge testé. Elles ne comptent pas.");
  l.push("");
  l.push("## Les 12 combinaisons les plus dépourvues");
  l.push("");
  l.push("| Profil | Âge | Telles quelles | Adaptées | Bloquées | Trop vieilles | Manque | Catégories en pénurie |");
  l.push("|---|---|---|---|---|---|---|---|");
  classement.slice(0, 12).forEach(function (c) {
    const cats = Object.keys(c.manqueCategories);
    l.push("| " + nomProfil(c.profil) + " | " + nomStade(c.ageMois) + " | " + c.telle_quelle +
      " | " + c.adaptee + " | " + c.non_adaptable + " | " + c.hors_age + " | " + (c.manque || "—") +
      " | " + (cats.length ? cats.map((k) => k + " (" + c.manqueCategories[k] + ")").join(", ") : "—") + " |");
  });
  l.push("");
  l.push("## Ingrédients qui bloquent le plus");
  l.push("");
  l.push("Chaque ligne est une **règle de substitution manquante**. En écrire une");
  l.push("débloque souvent plus de recettes que d'en rédiger une nouvelle.");
  l.push("");
  if (!bloquants.length) l.push("Aucun — toutes les recettes bloquées le sont pour des raisons d'âge, pas d'allergène.");
  bloquants.slice(0, 10).forEach(function (b) {
    l.push("- **" + b.nom + "** (`" + b.id + "`) — bloque " + b.n + " fois");
  });
  l.push("");
  l.push("## Commande suggérée pour le prochain lot");
  l.push("");
  if (!cmd.length) l.push("Aucun trou sous le seuil — le prochain lot peut viser la variété plutôt que la couverture.");
  cmd.forEach(function (c) {
    l.push("- **" + c.n + " " + c.categories[0].toLowerCase() + "** dès " + c.ageMois + " mois — " +
      (c.passePartout ? "**passe-partout** (sans aucun des 11 allergènes prioritaires)" : nomProfil(c.evite)));
    l.push("    - " + c.raison);
  });
  l.push("");
  l.push("Ce fichier est régénéré par `node outils/trous.js`. Il alimente");
  l.push("`generation/prompt-recette.js`, qui transforme la commande en prompt contraint.");
  return l.join("\n");
}

function rapport(corpus) {
  const cases = analyser(corpus);
  const classement = classer(cases);
  const bloquants = bloquantsGlobaux(cases);
  const cmd = commande(classement);
  return { cases: cases, classement: classement, bloquants: bloquants, commande: cmd };
}

if (require.main === module) {
  let corpus = lire("donnees/recettes.json");
  try { corpus = corpus.concat(lire("donnees/importees/recettes-importees.json")); } catch (e) {}
  const r = rapport(corpus);
  fs.writeFileSync(path.join(racine, "outils", "rapport-trous.md"),
    markdown(r.classement, r.bloquants, r.commande, corpus.length) + "\n");
  fs.writeFileSync(path.join(racine, "outils", "rapport-trous.json"),
    JSON.stringify({ classement: r.classement.slice(0, 25), bloquants: r.bloquants, commande: r.commande }, null, 2) + "\n");
  console.log("Trous analysés : " + r.cases.length + " combinaisons (" + PROFILS.length + " profils × " + STADES.length + " âges)");
  r.classement.slice(0, 5).forEach(function (c) {
    console.log("  " + nomProfil(c.profil) + " @ " + nomStade(c.ageMois) + " → " + c.utilisables + " utilisables" +
      (c.manque ? "  MANQUE " + c.manque : ""));
  });
  console.log("Commande suggérée : " + r.commande.reduce((s, c) => s + c.n, 0) + " recettes");
}

module.exports = { SEUIL_CATEGORIE: SEUIL_CATEGORIE, rapport: rapport, analyser: analyser, classer: classer, commande: commande, nomProfil: nomProfil, PROFILS: PROFILS, STADES: STADES, SEUIL_SEMAINE: SEUIL_SEMAINE };
