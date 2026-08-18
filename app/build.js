/* Build de l'app parents : node app/build.js
 * Corpus = recettes témoins + recettes importées (sortie de l'importeur).
 * Une seule source de vérité : moteur et données injectés tels quels. */
"use strict";
const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const lire = (p) => fs.readFileSync(path.join(racine, p), "utf8");
const lireJson = (p) => JSON.parse(lire(p));

const temoins = lireJson("donnees/recettes.json");
let importees = [];
try { importees = lireJson("donnees/importees/recettes-importees.json"); }
catch (e) { console.warn("Aucune recette importée (exécuter ingestion/importer.js d'abord)."); }

const donnees = {
  ingredients: lireJson("donnees/ingredients.json"),
  substitutions: lireJson("donnees/substitutions.json"),
  base: lireJson("donnees/base.json"),
  recettes: temoins.concat(importees)
};

let html = lire("app/gabarit-app.html");
html = html.replace("/*__MOTEUR__*/", lire("moteur/moteur.js"));
html = html.replace("/*__ILLUSTRATION__*/", lire("app/illustration.js"));
html = html.replace("/*__PUBLICATION__*/", "var PUBLICATION = " + JSON.stringify(lireJson("donnees/publication.json")) + ";");
html = html.replace("/*__DONNEES__*/", "var DONNEES = " + JSON.stringify(donnees) + ";");

const sortie = path.join(racine, "app", "index.html");
fs.writeFileSync(sortie, html);
console.log("Écrit : " + sortie + " (" + Math.round(html.length / 1024) + " ko, " + donnees.recettes.length + " recettes)");
