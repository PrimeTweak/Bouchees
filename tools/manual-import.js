/* There are two entry gates, and they are not alike: Manual import of
 * generated recipes node tools/manual-import.js <fichier.json>
 * [--sec] */
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
    console.error("Usage: node tools/manual-import.js <file.json> [--sec]");
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

  /* --- 3. Into the pool --- */
  console.log("\nInto the pool");
  console.log("\u2500".repeat(42));

  if (sec) {
    gardees.forEach(function (r) { console.log("  [dry run] " + r.name); });
    console.log("\n" + gardees.length + " recipe(s) would join the pool. Nothing written.");
    return;
  }

  let generees = [];
  try { generees = read("data/generated/generated-recipes.json"); } catch (e) {}
  const dejaLa = new Set(generees.map((r) => r.id));
  gardees.forEach(function (r) {
    if (dejaLa.has(r.id)) return;
    const copie = JSON.parse(JSON.stringify(r));
    copie.source = {
      source: "assisted generation, manual import",
      on: new Date().toISOString().slice(0, 10),
      license: "original content, written for Bouchees",
      cookedByAHuman: false
    };
    generees.push(copie);
    console.log("  + " + r.name);
  });
  fs.mkdirSync(path.join(racine, "data", "generated"), { recursive: true });
  write("data/generated/generated-recipes.json", generees);

  const r = Publier.publier();
  const dist = path.join(racine, "dist");
  fs.rmSync(path.join(dist, "batches"), { recursive: true, force: true });
  fs.mkdirSync(path.join(dist, "recipes"), { recursive: true });
  fs.writeFileSync(path.join(dist, "manifest.json"), JSON.stringify(r.manifest, null, 2) + "\n");
  fs.writeFileSync(path.join(dist, "safety.json"), JSON.stringify(r.securite) + "\n");
  fs.writeFileSync(path.join(dist, "catalogue.json"), JSON.stringify(r.catalogue) + "\n");
  Object.keys(r.bodies).forEach(function (id) {
    fs.writeFileSync(path.join(dist, "recipes", id + ".json"), JSON.stringify(r.bodies[id]) + "\n");
  });

  console.log("\nSummary");
  console.log("\u2500".repeat(42));
  console.log("  published: " + gardees.length + " \u00b7 rejected: " + rejetees.length);
  console.log("  pool: " + r.manifest.counts.Meal + " meals, " + r.manifest.counts.Snack + " snacks");
  console.log("\n  What is NOT checked: taste, rise, real texture.");
  console.log("  A recipe that was never cooked can be bad — never unsafe.\n");
}

if (require.main === module) principal();
module.exports = { principal: principal };
