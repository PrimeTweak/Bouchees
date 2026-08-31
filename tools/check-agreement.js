#!/usr/bin/env node
/* Cross-module agreement check.
 *   node tools/check-agreement.js
 *
 * WHY THIS EXISTS
 *
 * Four separate breakages tonight came from the same shape of mistake: two
 * pieces of code that must use the same word, renamed on one side only.
 *
 *   the bridge exposed `charger`, Swift called `load`     -> app would not start
 *   the JSON said `stages`, Swift wanted `stades`         -> tables would not decode
 *   the engine emitted `as_is`, Swift declared `telle_quelle`  -> recipes vanished
 *   the vision answered in French, the catalogue was English   -> every photo rejected
 *
 * None of them is a syntax error. Both sides compile, both sides look right,
 * and the failure surfaces at runtime with a message that names nothing.
 *
 * This walks every place where two modules have to agree on a literal value
 * and fails when they do not.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const read = (p) => fs.readFileSync(path.join(root, p), "utf8");
const readJSON = (p) => JSON.parse(read(p));

const problems = [];
const checked = [];

function agree(label, produced, accepted, where) {
  checked.push(label);
  produced.forEach(function (v) {
    if (accepted.indexOf(v) === -1) {
      problems.push(label + ': "' + v + '" is produced but ' + where +
        " does not accept it  (accepted: " + accepted.join(", ") + ")");
    }
  });
}

/* ---------- 1. image states: images.js produces, cycle.js compares ---------- */
const imagesSrc = read("generation/images.js");
const cycleSrc = read("tools/cycle.js");
const statesProduced = (imagesSrc.match(/etat = [^;]+;/s) || [""])[0]
  .match(/"([^"]+)"/g) || [];
const statesCompared = (cycleSrc.match(/p\.etat === "([^"]+)"/g) || [])
  .map(function (m) { return m.match(/"([^"]+)"/)[1]; });
statesCompared.forEach(function (v) {
  const clean = statesProduced.map(function (s) { return s.replace(/"/g, ""); });
  if (clean.indexOf(v) === -1) {
    problems.push('image state: cycle.js compares against "' + v +
      '" which images.js never produces  (it produces: ' + clean.join(", ") + ")");
  }
});
checked.push("image states");

/* ---------- 2. the vision must name food in the catalogue's language ------- */
const visionSrc = read("generation/vision.js");
const catalogue = readJSON("data/ingredients.json");
const firstName = catalogue[Object.keys(catalogue)[0]].name;
const catalogueIsEnglish = !/[éèêàçùâîôœ]/.test(
  Object.keys(catalogue).map(function (k) { return catalogue[k].name; }).join(" "));
/* Read the language out of the aliments field of the prompt, which is the line
 * that actually tells the model what to answer. */
const ligneAliments = (visionSrc.match(/"aliments":\s*\[[^\]]*\]/) || [""])[0];
const visionAsksEnglish = /in English/i.test(ligneAliments);
const visionAsksFrench = /en fran[cç]ais/i.test(ligneAliments);
if (!visionAsksEnglish && !visionAsksFrench) {
  problems.push("vision language: the prompt does not state which language the " +
    "food names should come back in — the comparison against the catalogue " +
    "then depends on luck");
}
checked.push("vision language");
if (catalogueIsEnglish !== visionAsksEnglish) {
  problems.push("vision language: the catalogue names food in " +
    (catalogueIsEnglish ? "English" : "French") + ' (e.g. "' + firstName +
    '") but the vision prompt asks for ' + (visionAsksEnglish ? "English" : "French") +
    " — nothing will ever match and every photo gets rejected");
}

/* ---------- 3. roles: the catalogue produces, substitutions consume -------- */
const rolesInCatalogue = new Set();
Object.keys(catalogue).forEach(function (k) {
  (catalogue[k].roles || []).forEach(function (r) { rolesInCatalogue.add(r); });
});
const rolesInSubs = new Set();
readJSON("data/substitutions.json").forEach(function (s) {
  if (s.role) rolesInSubs.add(s.role);
});
agree("roles", Array.from(rolesInSubs), Array.from(rolesInCatalogue), "the catalogue");

/* ---------- 4. allergens: base.json declares, the catalogue references ----- */
const allergensDeclared = readJSON("data/base.json").allergens.map(function (a) { return a.id; });
const allergensUsed = new Set();
Object.keys(catalogue).forEach(function (k) {
  (catalogue[k].allergens || []).forEach(function (a) { allergensUsed.add(a); });
});
agree("allergens", Array.from(allergensUsed), allergensDeclared, "base.json");

/* ---------- 5. the vision vocabulary must cover every allergen family ------ */
const vocabFamilies = (visionSrc.match(/^\s{2}(\w+):\s*\[/gm) || [])
  .map(function (m) { return m.trim().replace(":", "").replace("[", "").trim(); });
allergensDeclared.forEach(function (a) {
  if (vocabFamilies.indexOf(a) === -1) {
    problems.push('vision vocabulary: allergen family "' + a +
      '" is declared in base.json but has no entry in vision.js — an intruder ' +
      "from that family would never be caught");
  }
});
checked.push("vision vocabulary");

/* ---------- 6. age rules must target ingredients that exist ---------------- */
readJSON("data/base.json").ageRules.forEach(function (r) {
  if (!catalogue[r.target]) {
    problems.push('age rule: targets "' + r.target + '" which is not in the catalogue');
  }
  if (r.action && r.action.to && !catalogue[r.action.to]) {
    problems.push('age rule: swaps to "' + r.action.to + '" which is not in the catalogue');
  }
});
checked.push("age rules");

/* ---------- 7. image aspect ratio: FLUX is trained square ------------------ */
const engineSrc = read("generation/image-engines.js");
const w = (engineSrc.match(/DRAWTHINGS_LARGEUR \|\| (\d+)/) || [])[1];
const h = (engineSrc.match(/DRAWTHINGS_HAUTEUR \|\| (\d+)/) || [])[1];
checked.push("image aspect");
if (w && h && w !== h) {
  problems.push("image aspect: the default is " + w + "x" + h + ", which is not square. " +
    "FLUX schnell is trained at 1:1 and a forced 3:2 frame comes back as an " +
    "embossed relief through the API. Measured, at length. Keep width and " +
    "height equal.");
}
/* And wide enough that a card crop is not upscaled on an iPhone Pro Max. */
if (w && Number(w) < 1320) {
  problems.push("image aspect: " + w + " px is below the 1320 px an iPhone Pro Max " +
    "needs, so every card would be upscaled on screen");
}

/* ---------- report -------------------------------------------------------- */

/* THE LEXICON MUST COVER EVERY ALLERGEN THE APP CLAIMS TO CATCH.
 *
 * The scanner promised eleven families and the recipe catalogue was the only
 * vocabulary behind it — 92 cooking ingredients against a world of industrial
 * label terms. A family with no term in the lexicon is a family the scanner
 * silently cannot see. */
(function lexiqueComplet() {
  var lexPath = path.join(__dirname, "..", "data", "label-lexicon.json");
  if (!fs.existsSync(lexPath)) {
    problems.push("data/label-lexicon.json is missing — the scanner falls back " +
                  "to the recipe catalogue and cannot read a product label");
    return;
  }
  var lex = JSON.parse(fs.readFileSync(lexPath, "utf8"));
  var base = JSON.parse(fs.readFileSync(
    path.join(__dirname, "..", "data", "base.json"), "utf8"));
  var couvertes = {};
  Object.keys(lex.allergens || {}).forEach(function (t) {
    couvertes[lex.allergens[t]] = (couvertes[lex.allergens[t]] || 0) + 1;
  });
  (base.allergens || []).forEach(function (a) {
    if (!couvertes[a.id]) {
      problems.push("allergen '" + a.id + "' has no term in the label lexicon — " +
                    "the scanner cannot detect it on a package");
    }
  });
})();

checked.push("label lexicon");

/* EVERY ALLERGEN NEEDS A GLYPH.
 *
 * AllergenGlyphs.swift matched on "lait", "oeuf", "arachide" while base.json
 * says milk, egg, peanut. One case in eleven matched — sesame, spelled the
 * same in both languages — so onboarding drew one icon and ten empty circles.
 *
 * Nothing failed: an unmatched id falls through to a default circle. A silent
 * default is exactly how this reached a device. */
(function glyphesAllergenes() {
  const swift = path.join(__dirname, "..", "ios", "App", "App",
                          "Illustration", "AllergenGlyphs.swift");
  if (!fs.existsSync(swift)) return;
  const code = fs.readFileSync(swift, "utf8");
  const cas = (code.match(/case "[a-z_]+"/g) || [])
    .map(function (c) { return c.slice(6, -1); });

  const base = JSON.parse(fs.readFileSync(
    path.join(__dirname, "..", "data", "base.json"), "utf8"));

  (base.allergens || []).forEach(function (a) {
    if (cas.indexOf(a.id) === -1) {
      problems.push("allergen '" + a.id + "' has no glyph in AllergenGlyphs.swift " +
        "— it falls through to a plain circle, silently");
    }
  });
})();

checked.push("allergen glyphs");

if (!problems.length) {
  console.log("Agreement check passed — " + checked.length + " vocabularies line up: " +
    checked.join(", ") + ".");
  process.exit(0);
}
console.error("\nCROSS-MODULE DISAGREEMENT (" + problems.length + ")");
problems.forEach(function (p) { console.error("  x " + p); });
console.error("\nBoth sides are valid on their own. The failure only shows at runtime.\n");
process.exit(1);
