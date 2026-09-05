"use strict";
/* Check the offline product pack: this checker exists for the same reason
 * check-repo.js does: a rule that lives only in a person's head gets broken
 * by the next tired evening. */

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

const problems = [];
const report = [];

function main() {
  if (!fs.existsSync(packDir)) {
    console.log("No pack/ folder — nothing to check.");
    console.log("Build one with PAQUET.command, or with:");
    console.log("  node tools/build-product-pack.js --usda <csv> --off <jsonl.gz>");
    process.exit(0);
  }

  const manifestePath = path.join(packDir, "manifest.json");
  if (!fs.existsSync(manifestePath)) {
    problems.push("pack/manifest.json is missing — the pack carries no notices");
    return finish();
  }
  const manifest = JSON.parse(fs.readFileSync(manifestePath, "utf8"));

  /* 2. The notices. */
  for (const key of ["us", "ca"]) {
    const n = (manifest.notices || {})[key];
    if (!n) problems.push("manifest.json carries no notice for the " + key + " half");
  }
  const avisCA = (manifest.notices || {}).ca || "";
  if (avisCA && avisCA.indexOf("Open Database License") < 0) {
    problems.push("the Canadian notice does not name the Open Database License");
  }
  const avisUS = (manifest.notices || {}).us || "";
  if (avisUS && avisUS.indexOf("FoodData Central") < 0) {
    problems.push("the American notice does not name FoodData Central");
  }

  /* 3. No third products file. */
  for (const f of fs.readdirSync(packDir)) {
    if (!/^products.*\.jsonl\.gz$/.test(f)) continue;
    if (!ATTENDUS[f]) {
      problems.push(f + " is a products file we do not recognise — if it " +
                     "joins the two sources, the pack is a derivative database");
    }
  }

  const chain = Object.keys(ATTENDUS).map(function (name) {
    return function () { return checkFile(name, manifest); };
  });

  return chain.reduce(function (p, f) { return p.then(f); }, Promise.resolve())
    .then(finish);
}

async function checkFile(name, manifest) {
  const filePath = path.join(packDir, name);
  if (!fs.existsSync(filePath)) {
    report.push(name + " — absent (this half was not built)");
    return;
  }

  const expected = ATTENDUS[name];
  const flux = readline.createInterface({
    input: fs.createReadStream(filePath).pipe(zlib.createGunzip()),
    crlfDelay: Infinity
  });

  const seen = new Set();
  let lines = 0, wrongSource = 0, withoutText = 0, duplicates = 0, unreadable = 0;

  for await (const ligne of flux) {
    if (!ligne.trim()) continue;
    lines++;
    let r;
    try { r = JSON.parse(ligne); } catch (e) { unreadable++; continue; }

    /* 1. One source per file. */
    if (r.s !== expected.source) wrongSource++;

    /* 4. Every record answers the question it exists for. */
    if (!r.i || !String(r.i).trim()) withoutText++;

    if (seen.has(r.c)) duplicates++; else seen.add(r.c);
  }

  if (wrongSource > 0) {
    problems.push(name + ": " + wrongSource + " record(s) tagged with " +
                   "another source — one source per file, this is the licence " +
                   "boundary, not a style rule");
  }
  if (unreadable > 0) problems.push(name + ": " + unreadable + " unreadable line(s)");
  if (withoutText > 0) {
    problems.push(name + ": " + withoutText + " record(s) with no ingredient " +
                   "text — weight that answers nothing");
  }
  if (duplicates > 0) {
    problems.push(name + ": " + duplicates + " repeated barcode(s) — one row " +
                   "per barcode, or a lookup reads whichever version it " +
                   "reaches first and a reformulated product can still " +
                   "answer with its old ingredient list");
  }

  const declare = ((manifest.files || {})[name] || {}).records;
  if (typeof declare === "number" && declare !== lines) {
    problems.push(name + ": manifest declares " + declare + " records, the " +
                   "file holds " + lines);
  }
  const licence = ((manifest.files || {})[name] || {}).licence;
  if (licence && licence !== expected.licence) {
    problems.push(name + ": manifest says " + licence + ", expected " + expected.licence);
  }

  const mo = (fs.statSync(filePath).size / 1048576).toFixed(1);
  report.push(name + " — " + lines + " products, " + seen.size +
               " distinct barcodes, " + mo + " Mo");
}

function finish() {
  console.log("");
  for (const l of report) console.log("  " + l);
  console.log("");
  if (problems.length) {
    console.log("PROBLEMS");
    for (const p of problems) console.log("  x " + p);
    console.log("");
    process.exit(1);
  }
  console.log("Pack check passed — one source per file, both notices present.");
}

Promise.resolve().then(main).catch(function (e) {
  console.error("check-pack failed: " + e.message);
  process.exit(1);
});
