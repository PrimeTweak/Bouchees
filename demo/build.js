/* Build du banc d'essai : node demo/build.js
 * Une seule source de vérité — le moteur et les données sont injectés
 * tels quels dans le gabarit. Produit demo/index.html autonome. */
"use strict";
const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const lire = (p) => fs.readFileSync(path.join(racine, p), "utf8");

const donnees = {
  ingredients: JSON.parse(lire("data/ingredients.json")),
  substitutions: JSON.parse(lire("data/substitutions.json")),
  base: JSON.parse(lire("data/base.json")),
  recettes: JSON.parse(lire("data/recipes.json"))
};

let html = lire("demo/template.html");
html = html.replace("/*__MOTEUR__*/", lire("engine/engine.js"));
html = html.replace("/*__DONNEES__*/", "var DONNEES = " + JSON.stringify(donnees) + ";");

const sortie = path.join(racine, "demo", "index.html");
fs.writeFileSync(sortie, html);
console.log("Écrit : " + sortie + " (" + Math.round(html.length / 1024) + " ko)");
