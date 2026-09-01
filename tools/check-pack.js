"use strict";
/*
 * CHECK THE OFFLINE PRODUCT PACK.
 *
 * This checker exists for the same reason check-repo.js does: a rule that
 * lives only in a person's head gets broken by the next tired evening. Here
 * the rule is a licence condition, so breaking it costs more than a build.
 *
 * What it refuses:
 *
 *   1. A record in the wrong file. One source per file — an American record
 *      in the Canadian file, or the reverse, turns a collective database into
 *      a derivative one and pulls the whole pack under share-alike.
 *
 *   2. A missing notice. Both halves must carry their attribution in the
 *      manifest, so the pack still says where it came from wherever it lands.
 *
 *   3. A merged file. Any third products file means someone joined them.
 *
 *   4. A record with no ingredient text. The pack exists to answer an
 *      allergen question; an entry that cannot answer it is weight.
 *
 *   5. A repeated barcode. This started as a note and passed a pack that had
 *      no business passing: USDA ships every historical version of a product,
 *      so a repeat is not a curiosity, it is an ingredient list that stopped
 *      being true. Whichever row a lookup happens to reach first decides what
 *      a parent is told. It refuses now.
 *
 * What it reports rather than refuses: the coverage per source. That number
 * is the one worth watching over time.
 */

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const readline = require("readline");

const root = path.join(__dirname, "..");
const packDir = path.join(root, "pack");

const ATTENDUS = {
  "products-us.jsonl.gz": { source: "us", licence: "CC0-1.0" },
  "products-ca.jsonl.gz": { source: "ca", licence: "ODbL-1.0" }
};

const problemes = [];
const rapport = [];

function main() {
  if (!fs.existsSync(packDir)) {
    console.log("No pack/ folder — nothing to check.");
    console.log("Build one with PAQUET.command, or with:");
    console.log("  node tools/build-product-pack.js --usda <csv> --off <jsonl.gz>");
    process.exit(0);
  }

  const manifestePath = path.join(packDir, "manifest.json");
  if (!fs.existsSync(manifestePath)) {
    problemes.push("pack/manifest.json is missing — the pack carries no notices");
    return fin();
  }
  const manifeste = JSON.parse(fs.readFileSync(manifestePath, "utf8"));

  /* 2. The notices. */
  for (const cle of ["us", "ca"]) {
    const n = (manifeste.notices || {})[cle];
    if (!n) problemes.push("manifest.json carries no notice for the " + cle + " half");
  }
  const avisCA = (manifeste.notices || {}).ca || "";
  if (avisCA && avisCA.indexOf("Open Database License") < 0) {
    problemes.push("the Canadian notice does not name the Open Database License");
  }
  const avisUS = (manifeste.notices || {}).us || "";
  if (avisUS && avisUS.indexOf("FoodData Central") < 0) {
    problemes.push("the American notice does not name FoodData Central");
  }

  /* 3. No third products file. */
  for (const f of fs.readdirSync(packDir)) {
    if (!/^products.*\.jsonl\.gz$/.test(f)) continue;
    if (!ATTENDUS[f]) {
      problemes.push(f + " is a products file we do not recognise — if it " +
                     "joins the two sources, the pack is a derivative database");
    }
  }

  const chaine = Object.keys(ATTENDUS).map(function (nom) {
    return function () { return verifierFichier(nom, manifeste); };
  });

  return chaine.reduce(function (p, f) { return p.then(f); }, Promise.resolve())
    .then(fin);
}

async function verifierFichier(nom, manifeste) {
  const chemin = path.join(packDir, nom);
  if (!fs.existsSync(chemin)) {
    rapport.push(nom + " — absent (this half was not built)");
    return;
  }

  const attendu = ATTENDUS[nom];
  const flux = readline.createInterface({
    input: fs.createReadStream(chemin).pipe(zlib.createGunzip()),
    crlfDelay: Infinity
  });

  const vus = new Set();
  let lignes = 0, mauvaiseSource = 0, sansTexte = 0, doublons = 0, illisibles = 0;

  for await (const ligne of flux) {
    if (!ligne.trim()) continue;
    lignes++;
    let r;
    try { r = JSON.parse(ligne); } catch (e) { illisibles++; continue; }

    /* 1. One source per file. */
    if (r.s !== attendu.source) mauvaiseSource++;

    /* 4. Every record answers the question it exists for. */
    if (!r.i || !String(r.i).trim()) sansTexte++;

    if (vus.has(r.c)) doublons++; else vus.add(r.c);
  }

  if (mauvaiseSource > 0) {
    problemes.push(nom + ": " + mauvaiseSource + " record(s) tagged with " +
                   "another source — one source per file, this is the licence " +
                   "boundary, not a style rule");
  }
  if (illisibles > 0) problemes.push(nom + ": " + illisibles + " unreadable line(s)");
  if (sansTexte > 0) {
    problemes.push(nom + ": " + sansTexte + " record(s) with no ingredient " +
                   "text — weight that answers nothing");
  }
  if (doublons > 0) {
    problemes.push(nom + ": " + doublons + " repeated barcode(s) — one row " +
                   "per barcode, or a lookup reads whichever version it " +
                   "reaches first and a reformulated product can still " +
                   "answer with its old ingredient list");
  }

  const declare = ((manifeste.files || {})[nom] || {}).records;
  if (typeof declare === "number" && declare !== lignes) {
    problemes.push(nom + ": manifest declares " + declare + " records, the " +
                   "file holds " + lignes);
  }
  const licence = ((manifeste.files || {})[nom] || {}).licence;
  if (licence && licence !== attendu.licence) {
    problemes.push(nom + ": manifest says " + licence + ", expected " + attendu.licence);
  }

  const mo = (fs.statSync(chemin).size / 1048576).toFixed(1);
  rapport.push(nom + " — " + lignes + " products, " + vus.size +
               " distinct barcodes, " + mo + " Mo");
}

function fin() {
  console.log("");
  for (const l of rapport) console.log("  " + l);
  console.log("");
  if (problemes.length) {
    console.log("PROBLEMS");
    for (const p of problemes) console.log("  x " + p);
    console.log("");
    process.exit(1);
  }
  console.log("Pack check passed — one source per file, both notices present.");
}

Promise.resolve().then(main).catch(function (e) {
  console.error("check-pack failed: " + e.message);
  process.exit(1);
});
