#!/usr/bin/env node
/* Does every prompt follow docs/PROMPT-CONVENTION.md ?
 *
 *   node tools/check-prompts.js
 *
 * WHY THIS EXISTS. The convention was written down after the third time a
 * prompt drifted: a room instead of a dish, twelve muffins instead of three,
 * a grey windowsill instead of a kitchen. A written rule nobody checks drifts
 * again — this reads every recipe in the corpus and verifies the shape.
 *
 * The check that earns its place is the last one: the positive and the
 * negative asking for opposite things. That is what produced the flat grey
 * light, and no amount of reading the file caught it.
 */
"use strict";

const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));

const Images = require(path.join(racine, "generation", "images.js"));
const construire = Object.values(Images)
  .find((v) => typeof v === "function" && v.length >= 2);

const donnees = {
  catalogue: lire("data/ingredients.json"),
  base: lire("data/base.json")
};

let corpus = lire("data/recipes.json");
try {
  corpus = corpus.concat(lire("data/generated/generated-recipes.json"));
} catch (e) { /* none yet */ }

const problemes = [];
const LIMITE = 500;

/* Pairs that must never appear together. Each one has been observed. */
const CONTRADICTIONS = [
  [/\bcool\b|overcast|morning light|daylight|blue hour|north light/i,
   /\bwarm\b/i,
   "cool light and warm light in the same prompt — this is what produced " +
   "the flat grey windowsill"],
  [/wide shot|from across|whole room|entire kitchen/i,
   /close-?up|very close|close enough|tight/i,
   "a wide framing and a close framing in the same prompt"],
  [/studio light/i, /candid|handheld/i,
   "studio lighting and a candid photo are not the same picture"]
];

corpus.forEach(function (recette) {
  const p = construire(recette, donnees);
  const nom = recette.id;
  const parts = p.positif.split(". ");

  /* 1. Length. Both engines stop reading well before this. */
  if (p.positif.length > LIMITE) {
    problemes.push(nom + ": prompt is " + p.positif.length + " characters, " +
      "over the " + LIMITE + " limit — the last clause is the style, and it " +
      "is what gets dropped");
  }

  /* 2. The dish is named, not only its ingredients. */
  if (!/cooked and ready to eat/i.test(p.positif)) {
    problemes.push(nom + ": the prompt does not say the dish is cooked — " +
      "a prompt of ingredients alone draws raw ingredients");
  }

  /* 3. The presentation carries a count. */
  const presentation = parts[1] || "";
  if (!/\b(one|two|three|four|five|a short stack|a loaf)\b/i.test(presentation)) {
    problemes.push(nom + ": the presentation names no count (\"" +
      presentation.slice(0, 46) + "\") — without one the model draws a whole " +
      "batch, each item too small to see");
  }

  /* 4. The framing states a distance. */
  const cadrage = parts.find(function (x) {
    return /close|overhead|eye-level|angle/i.test(x);
  }) || "";
  if (!/close|30 cm|tight|very close/i.test(cadrage)) {
    problemes.push(nom + ": the framing states no distance (\"" +
      cadrage.slice(0, 46) + "\") — the model then shows everything the " +
      "prompt names, and the prompt names a surface");
  }

  /* 5. A surface is named. */
  if (!parts.some(function (x) { return /^on a /i.test(x); })) {
    problemes.push(nom + ": no surface — with the room banned and nothing " +
      "named, the model invents the one background left to it");
  }

  /* 6. The light is warm. */
  const lumiere = parts.filter(function (x) { return /light/i.test(x); });
  if (!lumiere.some(function (x) { return /warm/i.test(x); })) {
    problemes.push(nom + ": no warm light — a kitchen that reads as " +
      "professional is lit, not merely daylit");
  }

  /* 7. The negatives do not ban the background itself. */
  ["no wall", "no furniture", "no window frame", "no background"].forEach(function (n) {
    if (p.negatif.indexOf(n) !== -1) {
      problemes.push(nom + ": the negative contains \"" + n + "\" — banning " +
        "the background empties the frame; ban the WIDE SHOT instead");
    }
  });

  /* 8. THE ONE THAT MATTERS: the prompt contradicting itself. */
  CONTRADICTIONS.forEach(function (paire) {
    if (paire[0].test(p.positif) && paire[1].test(p.positif)) {
      problemes.push(nom + ": " + paire[2]);
    }
  });
});

/* 9. Determinism. The same recipe must always give the same prompt. */
const temoin = corpus[0];
if (temoin) {
  const a = construire(temoin, donnees).positif;
  const b = construire(temoin, donnees).positif;
  if (a !== b) {
    problemes.push("the prompt is not deterministic — a parent reopening a " +
      "recipe would see a different picture each time");
  }
}

if (problemes.length) {
  console.error("");
  console.error("PROMPTS OUTSIDE THE CONVENTION (" + problemes.length + ")");
  const vus = {};
  problemes.forEach(function (p) {
    /* One line per distinct fault, with a count — 38 identical lines say
     * nothing that one line and a number do not. */
    const cle = p.replace(/^[a-z0-9-]+: /, "");
    vus[cle] = (vus[cle] || 0) + 1;
  });
  Object.keys(vus).forEach(function (k) {
    console.error("  x " + k + (vus[k] > 1 ? "   (" + vus[k] + " recipes)" : ""));
  });
  console.error("");
  console.error("See docs/PROMPT-CONVENTION.md — every rule there exists");
  console.error("because something drifted.");
  console.error("");
  process.exit(1);
}

console.log("Prompts follow the convention — " + corpus.length +
  " recipes, 7 parts each, no contradictions.");
