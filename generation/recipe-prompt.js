/* Everything else (allergens, ages, substitutions) is already deterministic —
 * the model decides no safety question. */
"use strict";
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const read = (p) => JSON.parse(fs.readFileSync(path.join(root, p), "utf8"));

function ingredientsAutorises(catalogue, evite) {
  return Object.keys(catalogue).filter(function (id) {
    return catalogue[id].allergens.every(function (a) { return evite.indexOf(a) === -1; });
  });
}

function tableIngredients(catalogue, ids) {
  return ids.map(function (id) {
    const d = catalogue[id];
    return "  " + id + "  —  " + d.name + "  [rôles : " + d.roles.join(", ") + "]";
  }).join("\n");
}

function construire(ligne, data) {
  const catalogue = data.catalogue;
  const base = data.base;
  const autorises = ingredientsAutorises(catalogue, ligne.evite);
  const interditsAge = base.ageRules
    .filter(function (r) { return ligne.ageMois < r.beforeMonths; })
    .map(function (r) {
      const d = catalogue[r.target];
      return "  " + r.target + " (" + (d ? d.name : r.target) + ") — " + r.reason;
    });

  const nomsEvites = ligne.evite.map(function (id) {
    const a = base.allergens.find(function (x) { return x.id === id; });
    return a ? a.name : id;
  });

  return [
"You write recipes for Bouchees, an app for parents of children with food",
"allergies. Safety is handled elsewhere, by deterministic tables: your job is",
"the cooking writing, not the safety decision. Write in ENGLISH only.",
"",
"BRIEF",
"  " + ligne.n + " recipe(s) of category \"" + ligne.categories[0] + "\"",
"  Minimum age: " + ligne.ageMois + " months",
"  Must be free of: " + (nomsEvites.length ? nomsEvites.join(", ") : "no allergen constraint"),
"  Why: " + ligne.reason,
"",
"ABSOLUTE RULE",
"  Use ONLY ingredient ids from the list below. No invented ingredient, no",
"  free-text name, no spelling variant. A recipe with an id outside the list",
"  is rejected automatically.",
"",
"INGREDIENTS ALLOWED  (id  —  name to use in the steps  [roles])",
tableIngredients(catalogue, autorises),
"",
"TO AVOID AT THIS AGE (usable later, not here)",
interditsAge.length ? interditsAge.join("\n") : "  none",
"",
"THE STEP STANDARD (docs/RECIPE-STANDARD.md) — a recipe is rejected otherwise",
"  1. Every ingredient is named in a step, using EXACTLY the name from the",
"     list above (write \"sweet potato\", not \"potato\" or \"yam\"), with its",
"     preparation: peeled and grated, minced, drained.",
"  2. Preparation before cooking: oven on, sheet lined, vegetables cut.",
"  3. Equipment and sizes: a 23 x 13 cm loaf pan, a large bowl, a 12-cup tin.",
"  4. Temperatures in both units: 200 \u00b0C (400 \u00b0F).",
"  5. Every step that cooks has a duration AND a doneness cue:",
"     \"18 to 20 minutes, until browned on top and no pink remains\".",
"  6. One action per step. Six to ten steps. HARD LIMIT: 18 words per step.",
"     Imperative, present tense.",
"  7. Yield in family portions (\"20 meatballs \u00b7 4 family portions\"), and a",
"     keeping note in the last step. Never \"mix all the ingredients\".",
"",
"CATEGORY",
"  Meal: the evening dish, the one that gets cooked.",
"  Snack: the snack in the broad sense — bite, muffin, oatmeal, prepared",
"  fruit, simple dessert, anything eaten at 10 or at 3. No breakfast: what",
"  looks like a breakfast is a snack.",
"",
"OUTPUT FORMAT",
"  A JSON array, nothing else — no text before or after, no code fences.",
"  Each object:",
"  {",
'    "id": "lowercase-ascii-words-with-hyphens",',
'    "name": "English name, appetising, no superlative",',
'    "category": "' + ligne.categories[0] + '",',
'    "servings": "4 family portions",',
'    "minAgeMonths": ' + ligne.ageMois + ",",
'    "timeMinutes": 30,',
'    "ingredients": [',
'      { "id": "catalogue_id", "qty": 250, "unit": "ml", "role": "flour" }',
"    ],",
'    "steps": ["Imperative sentence.", "..."]',
"  }",
"",
"WRITING",
"  - The role field is required whenever an ingredient plays a structural part",
"    (binder, fat, flour, liquid, dairy, protein): it drives substitutions.",
"  - Metric units: ml, g, or a natural unit (unit, clove, slice).",
"  - No added salt before 12 months, no added sugar before 24 months.",
"  - A recipe a busy parent can make on a Tuesday night.",
"",
"REMINDER",
"  Your output goes through an automatic validator, then to a person who",
"  cooks the recipe for real before publication. Write to be cooked, not to",
"  impress."
  ].join("\n");
}

function construireTout(brief, data) {
  return brief.map(function (l) { return construire(l, data); });
}

if (require.main === module) {
  const data = {
    catalogue: read("data/ingredients.json"),
    substitutions: read("data/substitutions.json"),
    base: read("data/base.json")
  };
  let brief;
  try {
    brief = read("tools/gap-report.json").commande;
  } catch (e) {
    console.error("Lance d'abord : node tools/gaps.js");
    process.exit(1);
  }
  if (!brief.length) {
    console.log("Aucun trou sous les seuils — pas de commande à générer ce mois-ci.");
    process.exit(0);
  }
  const prompts = construireTout(brief, data);
  const output = prompts.map(function (p, i) {
    return "═".repeat(72) + "\nPROMPT " + (i + 1) + " / " + prompts.length + "\n" + "═".repeat(72) + "\n\n" + p;
  }).join("\n\n\n");
  fs.writeFileSync(path.join(root, "generation", "prompt-du-mois.txt"), output + "\n");
  console.log("Écrit : generation/monthly-prompt.txt (" + prompts.length + " prompt(s), " +
    brief.reduce((s, c) => s + c.n, 0) + " recettes commandées)");
}

module.exports = { construire: construire, construireTout: construireTout, ingredientsAutorises: ingredientsAutorises };
