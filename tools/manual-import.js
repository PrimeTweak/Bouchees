/* There are two entry gates, and they are not alike: Manual import of
 * generated recipes node tools/manual-import.js <fichier.json>
 * [--lot=2026-09] [--sec] */
"use strict";
const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const read = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));
const write = (p, o) => fs.writeFileSync(path.join(racine, p), JSON.stringify(o, null, 2) + "\n");

const Valideur = require("../generation/recipe-validator.js");
const Coherence = require("../generation/coherence.js");
const Publier = require("./publish.js");

const args = process.argv.slice(2);
const fichier = args.find((a) => !a.startsWith("--"));
const sec = args.includes("--sec");
const lotDemande = (args.find((a) => a.startsWith("--lot=")) || "").split("=")[1];

const Semaines = require("./weeks.js");

function currentWeek() { return Semaines.identifiantSemaine(new Date()); }

function corpusExistant() {
  let c = read("data/recipes.json");
  for (const p of ["data/imported/imported-recipes.json",
                   "data/generated/generated-recipes.json"]) {
    try { c = c.concat(read(p)); } catch (e) {}
  }
  return c;
}

function principal() {
  if (!fichier) {
    console.error("Usage : node tools/manual-import.js <fichier.json> [--lot=2026-09] [--sec]");
    console.error("Example: node tools/manual-import.js ingest/sources/recipes-of-the-month.json");
    process.exit(1);
  }

  const filePath = path.isAbsolute(fichier) ? fichier : path.join(racine, fichier);
  if (!fs.existsSync(filePath)) {
    console.error("Fichier introuvable : " + filePath);
    process.exit(1);
  }

  let raw;
  try { raw = JSON.parse(fs.readFileSync(filePath, "utf8")); }
  catch (e) {
    console.error("Ce fichier n'est pas du JSON valide : " + e.message);
    console.error("Common trap: TextEdit saves rich text by default.");
    console.error("Format -> Make Plain Text, then save again.");
    process.exit(1);
  }

  const recettes = Array.isArray(raw) ? raw : (raw.recettes || []);
  if (!recettes.length) {
    console.error("Aucune recette dans ce fichier.");
    process.exit(1);
  }

  const data = {
    catalogue: read("data/ingredients.json"),
    substitutions: read("data/substitutions.json"),
    base: read("data/base.json")
  };
  const existantes = corpusExistant();
  const ids = existantes.map((r) => r.id);

  console.log("\n" + recettes.length + " recipe(s) read from " + path.basename(filePath) + "\n");

  /* --- 1. Validation contre le catalogue --- */
  console.log("Validation — catalogue, allergens, ages");
  console.log("─".repeat(42));
  const survivantes = [];
  const rejetees = [];
  const aRevoir = [];

  recettes.forEach(function (r) {
    /* The brief is not known here: validation runs with no avoided allergen
     * and the engine judges the rest. */
    const v = Valideur.valider(r, null, data, ids.concat(survivantes.map((s) => s.id)));
    if (!v.ok) {
      rejetees.push({ id: r.id || "(no id)", erreurs: v.erreurs });
      console.log("  x  " + (r.id || "(no id)") + " — " + v.erreurs[0]);
      return;
    }
    if (v.avertissements.length) aRevoir.push({ id: r.id, avertissements: v.avertissements });
    survivantes.push(r);
    console.log("  ok " + r.id);
  });

  /* --- 2. Culinary coherence --- */
  console.log("\nCulinary coherence");
  console.log("─".repeat(42));
  const gardees = [];
  survivantes.forEach(function (r) {
    const c = Coherence.verifier(r, data);
    if (!c.ok) {
      rejetees.push({ id: r.id, erreurs: c.erreurs });
      console.log("  x  " + r.id + " — " + c.erreurs[0]);
      return;
    }
    if (c.avertissements.length) aRevoir.push({ id: r.id, avertissements: c.avertissements });
    gardees.push(r);
    console.log("  ok " + r.id + (c.avertissements.length ? "  (" + c.avertissements.length + " reservation[s])" : ""));
  });

  if (aRevoir.length) {
    console.log("\nReservations — accepted, but worth a look");
    console.log("─".repeat(42));
    aRevoir.forEach(function (a) {
      a.avertissements.forEach(function (m) { console.log("  ~ " + a.id + " : " + m); });
    });
  }

  if (!gardees.length) {
    console.log("\nNothing to publish.");
    return;
  }

  /* --- 3. Publication --- */
  const lot = lotDemande || currentWeek();
  console.log("\nPublication dans le lot " + lot);
  console.log("─".repeat(42));

  if (sec) {
    gardees.forEach(function (r) { console.log("  [dry run] " + r.name); });
    console.log("\n" + gardees.length + " recette(s) seraient publiées. Rien n'a été écrit.");
    return;
  }

  let generees = [];
  try { generees = read("data/generated/generated-recipes.json"); } catch (e) {}
  const dejaLa = new Set(generees.map((r) => r.id));
  gardees.forEach(function (r) {
    if (dejaLa.has(r.id)) return;
    const copie = JSON.parse(JSON.stringify(r));
    copie.source = {
      source: "génération assistée, import manuel",
      le: new Date().toISOString().slice(0, 10),
      license: "content original — rédigé pour Bouchées",
      cuisineParUnHumain: false
    };
    generees.push(copie);
    console.log("  + " + r.name);
  });
  fs.mkdirSync(path.join(racine, "data", "generated"), { recursive: true });
  write("data/generated/generated-recipes.json", generees);

  const pub = read("data/publishing.json");
  if (!pub.batches.some((l) => l.id === lot)) {
    pub.batches.push({ id: lot, title: "Semaine du " + lot, access: "subscriber",
                    weekly: true,
                    note: "Seven recipes aimed at the least-served profiles." });
    console.log("  batch " + lot + " created");
  }
  gardees.forEach(function (r) { pub.assignment[r.id] = lot; });
  write("data/publishing.json", pub);

  const r = Publier.publier();
  fs.mkdirSync(path.join(racine, "dist", "batches"), { recursive: true });
  fs.writeFileSync(path.join(racine, "dist", "manifest.json"), JSON.stringify(r.manifest, null, 2) + "\n");
  fs.writeFileSync(path.join(racine, "dist", "safety.json"), JSON.stringify(r.securite) + "\n");
  Object.keys(r.content).forEach(function (l) {
    fs.writeFileSync(path.join(racine, "dist", "batches", l + ".json"), JSON.stringify(r.content[l]) + "\n");
  });

  console.log("\nBilan");
  console.log("─".repeat(42));
  console.log("  published: " + gardees.length + " · rejected: " + rejetees.length);
  r.manifest.batches.forEach(function (l) {
    console.log("  " + l.id + "  " + (l.access === "free" ? "free      " : "subscriber") + "  " +
      String(l.count).padStart(2) + " recipes");
  });
  console.log("\n  What is NOT checked: taste, rise, real texture.");
  console.log("  A recipe that was never cooked can be bad — never unsafe.\n");
}

if (require.main === module) principal();
module.exports = { principal: principal };
