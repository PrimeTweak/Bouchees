/* Import manuel de recettes générées
 *   node outils/importer-manuel.js <fichier.json> [--lot=2026-09] [--sec]
 *
 * POURQUOI CET OUTIL EXISTE
 *
 * Il y a deux portes d'entrée, et elles ne se ressemblent pas :
 *
 *   ingestion/importer.js  — recettes VENUES DE L'EXTÉRIEUR, en texte libre
 *                            (« 2 cups all-purpose flour »). Il faut les
 *                            normaliser vers le catalogue, d'où le lexique.
 *
 *   celui-ci               — recettes GÉNÉRÉES à partir du prompt du mois.
 *                            Elles utilisent déjà les identifiants du
 *                            catalogue : rien à normaliser, tout à valider.
 *
 * Passer les secondes par le premier ne donne rien de dangereux — elles
 * partent en quarantaine — mais rien d'utile non plus.
 *
 * Les portes de sécurité restent les mêmes : validateur contre le catalogue,
 * cohérence culinaire, et publication dans un lot.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));
const ecrire = (p, o) => fs.writeFileSync(path.join(racine, p), JSON.stringify(o, null, 2) + "\n");

const Valideur = require("../generation/valideur-recette.js");
const Coherence = require("../generation/coherence.js");
const Publier = require("./publier.js");

const args = process.argv.slice(2);
const fichier = args.find((a) => !a.startsWith("--"));
const sec = args.includes("--sec");
const lotDemande = (args.find((a) => a.startsWith("--lot=")) || "").split("=")[1];

const Semaines = require("./semaines.js");

function semaineCourante() { return Semaines.identifiantSemaine(new Date()); }

function corpusExistant() {
  let c = lire("donnees/recettes.json");
  for (const p of ["donnees/importees/recettes-importees.json",
                   "donnees/generees/recettes-generees.json"]) {
    try { c = c.concat(lire(p)); } catch (e) {}
  }
  return c;
}

function principal() {
  if (!fichier) {
    console.error("Usage : node outils/importer-manuel.js <fichier.json> [--lot=2026-09] [--sec]");
    console.error("Exemple : node outils/importer-manuel.js ingestion/sources/recettes-du-mois.json");
    process.exit(1);
  }

  const chemin = path.isAbsolute(fichier) ? fichier : path.join(racine, fichier);
  if (!fs.existsSync(chemin)) {
    console.error("Fichier introuvable : " + chemin);
    process.exit(1);
  }

  let brut;
  try { brut = JSON.parse(fs.readFileSync(chemin, "utf8")); }
  catch (e) {
    console.error("Ce fichier n'est pas du JSON valide : " + e.message);
    console.error("Piège fréquent : TextEdit enregistre du texte enrichi.");
    console.error("Format → Convertir au format texte, puis réenregistrer.");
    process.exit(1);
  }

  const recettes = Array.isArray(brut) ? brut : (brut.recettes || []);
  if (!recettes.length) {
    console.error("Aucune recette dans ce fichier.");
    process.exit(1);
  }

  const donnees = {
    catalogue: lire("donnees/ingredients.json"),
    substitutions: lire("donnees/substitutions.json"),
    base: lire("donnees/base.json")
  };
  const existantes = corpusExistant();
  const ids = existantes.map((r) => r.id);

  console.log("\n" + recettes.length + " recette(s) lue(s) dans " + path.basename(chemin) + "\n");

  /* --- 1. Validation contre le catalogue --- */
  console.log("Validation — catalogue, allergènes, âges");
  console.log("─".repeat(42));
  const survivantes = [];
  const rejetees = [];
  const aRevoir = [];

  recettes.forEach(function (r) {
    /* La commande n'est pas connue ici : on valide sans contrainte d'évitement
     * et on laisse le moteur juger le reste. */
    const v = Valideur.valider(r, null, donnees, ids.concat(survivantes.map((s) => s.id)));
    if (!v.ok) {
      rejetees.push({ id: r.id || "(sans id)", erreurs: v.erreurs });
      console.log("  ✕ " + (r.id || "(sans id)") + " — " + v.erreurs[0]);
      return;
    }
    if (v.avertissements.length) aRevoir.push({ id: r.id, avertissements: v.avertissements });
    survivantes.push(r);
    console.log("  ✓ " + r.id);
  });

  /* --- 2. Cohérence culinaire --- */
  console.log("\nCohérence culinaire");
  console.log("─".repeat(42));
  const gardees = [];
  survivantes.forEach(function (r) {
    const c = Coherence.verifier(r, donnees);
    if (!c.ok) {
      rejetees.push({ id: r.id, erreurs: c.erreurs });
      console.log("  ✕ " + r.id + " — " + c.erreurs[0]);
      return;
    }
    if (c.avertissements.length) aRevoir.push({ id: r.id, avertissements: c.avertissements });
    gardees.push(r);
    console.log("  ✓ " + r.id + (c.avertissements.length ? "  (" + c.avertissements.length + " réserve[s])" : ""));
  });

  if (aRevoir.length) {
    console.log("\nRéserves — acceptées, mais à regarder");
    console.log("─".repeat(42));
    aRevoir.forEach(function (a) {
      a.avertissements.forEach(function (m) { console.log("  ~ " + a.id + " : " + m); });
    });
  }

  if (!gardees.length) {
    console.log("\nRien à publier.");
    return;
  }

  /* --- 3. Publication --- */
  const lot = lotDemande || semaineCourante();
  console.log("\nPublication dans le lot " + lot);
  console.log("─".repeat(42));

  if (sec) {
    gardees.forEach(function (r) { console.log("  [à sec] " + r.nom); });
    console.log("\n" + gardees.length + " recette(s) seraient publiées. Rien n'a été écrit.");
    return;
  }

  let generees = [];
  try { generees = lire("donnees/generees/recettes-generees.json"); } catch (e) {}
  const dejaLa = new Set(generees.map((r) => r.id));
  gardees.forEach(function (r) {
    if (dejaLa.has(r.id)) return;
    const copie = JSON.parse(JSON.stringify(r));
    copie.provenance = {
      source: "génération assistée, import manuel",
      le: new Date().toISOString().slice(0, 10),
      licence: "contenu original — rédigé pour Bouchées",
      cuisineParUnHumain: false
    };
    generees.push(copie);
    console.log("  + " + r.nom);
  });
  fs.mkdirSync(path.join(racine, "donnees", "generees"), { recursive: true });
  ecrire("donnees/generees/recettes-generees.json", generees);

  const pub = lire("donnees/publication.json");
  if (!pub.lots.some((l) => l.id === lot)) {
    pub.lots.push({ id: lot, titre: "Semaine du " + lot, acces: "abonne",
                    hebdomadaire: true,
                    note: "Sept recettes visant les profils les moins servis." });
    console.log("  lot " + lot + " créé");
  }
  gardees.forEach(function (r) { pub.attribution[r.id] = lot; });
  ecrire("donnees/publication.json", pub);

  const r = Publier.publier();
  fs.mkdirSync(path.join(racine, "dist", "lots"), { recursive: true });
  fs.writeFileSync(path.join(racine, "dist", "manifeste.json"), JSON.stringify(r.manifeste, null, 2) + "\n");
  fs.writeFileSync(path.join(racine, "dist", "securite.json"), JSON.stringify(r.securite) + "\n");
  Object.keys(r.contenu).forEach(function (l) {
    fs.writeFileSync(path.join(racine, "dist", "lots", l + ".json"), JSON.stringify(r.contenu[l]) + "\n");
  });

  console.log("\nBilan");
  console.log("─".repeat(42));
  console.log("  publiées : " + gardees.length + " · rejetées : " + rejetees.length);
  r.manifeste.lots.forEach(function (l) {
    console.log("  " + l.id + "  " + (l.acces === "libre" ? "libre " : "abonné") + "  " +
      String(l.nombre).padStart(2) + " recettes");
  });
  console.log("\n  Ce qui n'est PAS vérifié : le goût, la levée, la texture réelle.");
  console.log("  Une recette non cuisinée peut être ratée — jamais dangereuse.\n");
}

if (require.main === module) principal();
module.exports = { principal: principal };
