/* Bundled resource names: does the Swift ask for what the workflow copies?
 *   node tools/check-bundle-names.js
 *
 * WHY THIS EXISTS
 *
 * The Swift loads bundled files by NAME, as string literals. Renaming
 * moteur.js to engine.js in the repository does not rename the literal
 * ["moteur", "pont-natif"] inside RecipeEngine.swift. Nothing catches that:
 * the project builds, the IPA installs, and the app fails on the first
 * launch with "Fichier moteur manquant".
 *
 * This compares the two sides and names the mismatch in one second.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");

/* What the workflow copies into the bundle. */
const workflow = fs.readFileSync(path.join(root, ".github/workflows/ipa.yml"), "utf8");
const copied = new Set();
for (const m of workflow.matchAll(/cp\s+((?:\S+\s+)+)"\$R\/"/g)) {
  for (const f of m[1].trim().split(/\s+/)) copied.add(path.basename(f));
}

/* What the Swift asks for. */
const swiftDir = path.join(root, "ios/App/App");
const asked = new Set();
function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (e.name.endsWith(".swift")) {
      const src = fs.readFileSync(p, "utf8");
      for (const m of src.matchAll(/Resources\.(?:url|data)\("([^"]+)",\s*"([^"]+)"\)/g))
        asked.add(m[1] + "." + m[2]);
      /* The engine scripts are loaded from a literal array. */
      for (const m of src.matchAll(/for\s+\w+\s+in\s+\[((?:"[^"]+",?\s*)+)\]/g))
        for (const n of m[1].match(/"([^"]+)"/g) || [])
          asked.add(n.replace(/"/g, "") + ".js");
    }
  }
}
walk(swiftDir);

const missing = [...asked].filter((f) => !copied.has(f));
if (!missing.length) {
  console.log("Bundled names match — the Swift asks for " + asked.size +
              " file(s), the workflow copies all of them.");
  process.exit(0);
}
console.error("\nTHE APP ASKS FOR FILES THE BUILD DOES NOT BUNDLE");
missing.forEach((f) => console.error("  x " + f));
console.error("\nThe workflow copies: " + [...copied].sort().join(", "));
console.error("This fails at first launch, not at build time.\n");
process.exit(1);
