"use strict";
/* Withholds the photos whose dish starts too low in the square. The hero
 * shows that square under a title covering its lower third, so those read
 * as a bowl rim and a counter. Nothing is deleted: the file moves to
 * images/rejected/ and the next PHOTOS.command run makes a new one. */

const fs = require("fs");
const path = require("path");
const Cadrage = require("./cadrage.js");

const root = path.join(__dirname, "..");
const CHEMIN_MANIFESTE = path.join(root, "generation/images/manifest.json");
const sec = process.argv.indexOf("--sec") !== -1;

const manifeste = JSON.parse(fs.readFileSync(CHEMIN_MANIFESTE, "utf8"));
const rejets = path.join(root, "images", "rejected");

const mesures = [];
Object.keys(manifeste).forEach(function (id) {
  const e = manifeste[id];
  if (!e || !e.fichier) return;
  const chemin = path.join(root, e.fichier);
  if (!fs.existsSync(chemin)) return;
  try {
    mesures.push({ id: id, fichier: e.fichier, chemin: chemin, depart: Cadrage.mesurer(chemin).sujetHaut });
  } catch (err) { /* unreadable: left alone */ }
});

mesures.sort(function (a, b) { return b.depart - a.depart; });
const aRetirer = mesures.filter(function (m) { return m.depart >= Cadrage.DEPART_MAX; });

console.log(mesures.length + " photos measured, threshold " + Cadrage.DEPART_MAX);
console.log(aRetirer.length + " start too low:");
aRetirer.forEach(function (m) { console.log("  " + m.depart.toFixed(3) + "  " + m.id); });

if (sec) {
  console.log("\n--sec: nothing moved.");
} else if (aRetirer.length) {
  fs.mkdirSync(rejets, { recursive: true });
  aRetirer.forEach(function (m) {
    fs.renameSync(m.chemin, path.join(rejets, path.basename(m.chemin)));
    const vignette = path.join(root, m.fichier.replace("images/", "images/thumbs/"));
    if (fs.existsSync(vignette)) fs.unlinkSync(vignette);
    delete manifeste[m.id];
  });
  fs.writeFileSync(CHEMIN_MANIFESTE, JSON.stringify(manifeste, null, 2) + "\n");
  console.log("\nMoved to images/rejected/. Run publish, then PHOTOS.command to make new ones.");
}
