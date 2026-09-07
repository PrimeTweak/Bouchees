"use strict";
/* Photos the vision would have rejected, published because the recipe holds
 * something that photographs like what the model named. They are the ones
 * worth a human glance: the check let them through on a resemblance. */

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const manifest = JSON.parse(fs.readFileSync(path.join(root, "generation/images/manifest.json"), "utf8"));

const surSosie = [];
Object.keys(manifest).forEach(function (id) {
  const v = manifest[id] && manifest[id].verification;
  const mots = (v && v.avertissements) || [];
  const sosies = mots.filter(function (m) { return /look-alike/.test(m); });
  if (sosies.length) surSosie.push({ id: id, fichier: manifest[id].fichier, mots: sosies });
});

if (!surSosie.length) {
  console.log("No photo was published on a look-alike.");
} else {
  console.log(surSosie.length + " photo(s) published because the recipe holds a look-alike.");
  console.log("Open them and check the picture shows no ingredient the recipe lacks.");
  console.log("");
  surSosie.forEach(function (p) {
    console.log("  " + p.id);
    p.mots.forEach(function (m) { console.log("      " + m); });
    console.log("      " + p.fichier);
  });
}
