"use strict";
/* Lists the published photos the vision flagged for a human look, with
 * the reason. Run after PHOTOS.command; delete a bad one from images/ and
 * the next run remakes it. */

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const manifest = JSON.parse(fs.readFileSync(path.join(root, "generation/images/manifest.json"), "utf8"));

const aRevoir = [];
Object.keys(manifest).forEach(function (id) {
  const v = manifest[id] && manifest[id].verification;
  const motifs = ((v && v.avertissements) || []).filter(function (m) { return /^to review|look-alike/.test(m); });
  if (motifs.length) aRevoir.push({ id: id, fichier: manifest[id].fichier, motifs: motifs });
});

if (!aRevoir.length) { console.log("Nothing to review: every published photo passed clean."); }
else {
  console.log(aRevoir.length + " photo(s) to look at. Open each; delete the file if the picture is wrong.");
  console.log("");
  aRevoir.forEach(function (p) {
    console.log("  " + p.id);
    p.motifs.forEach(function (m) { console.log("      " + m.replace(/^to review — /, "")); });
    console.log("      " + p.fichier);
  });
}
