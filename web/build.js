/* Build de l'app parents : node web/build.js
 * Corpus = recettes témoins + recettes importées (sortie de l'importeur).
 * Une seule source de vérité : moteur et données injectés tels quels. */
"use strict";
const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const lire = (p) => fs.readFileSync(path.join(racine, p), "utf8");
const lireJson = (p) => JSON.parse(lire(p));

const temoins = lireJson("data/recipes.json");
let importees = [];
try { importees = lireJson("data/imported/imported-recipes.json"); }
catch (e) { console.warn("Aucune recette importée (exécuter ingest/importer.js d'abord)."); }

const donnees = {
  ingredients: lireJson("data/ingredients.json"),
  substitutions: lireJson("data/substitutions.json"),
  base: lireJson("data/base.json"),
  recettes: temoins.concat(importees)
};

let html = lire("web/template.html");
html = html.replace("/*__MOTEUR__*/", lire("engine/engine.js"));
html = html.replace("/*__ILLUSTRATION__*/", lire("web/illustration.js"));
html = html.replace("/*__PUBLICATION__*/", "var PUBLICATION = " + JSON.stringify(lireJson("data/publishing.json")) + ";");
html = html.replace("/*__DONNEES__*/", "var DONNEES = " + JSON.stringify(donnees) + ";");

const sortie = path.join(racine, "web", "index.html");
fs.writeFileSync(sortie, html);
console.log("Écrit : " + sortie + " (" + Math.round(html.length / 1024) + " ko, " + donnees.recettes.length + " recettes)");
