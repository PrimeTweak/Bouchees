/* Publishes the pool: a public catalogue, one body file per recipe, and the
 * safety tables. The server hands bodies only to the entitled. */

const fs = require("fs");
const Vignettes = require("./thumbs.js");
const path = require("path");
const crypto = require("crypto");
const root = path.join(__dirname, "..");
const read = (p) => JSON.parse(fs.readFileSync(path.join(root, p), "utf8"));
const checksum = (o) => crypto.createHash("sha1").update(JSON.stringify(o)).digest("hex").slice(0, 12);
const Engine = require("../engine/engine.js");

const FAMILIES = ["milk", "egg", "peanut", "tree_nut", "wheat", "soy", "sesame",
                  "fish", "shellfish", "mustard", "sulphites"];

/* The public half of a recipe: everything but the ingredients and the steps. */
const PUBLIC = ["id", "name", "category", "servings", "minAgeMonths", "timeMinutes",
                "image", "thumb", "source"];

/* What the engine says for each allergen family on its own: as_is, adapted or
 * blocked. Computed here so a locked recipe can still show a true verdict. */
function matrix(recipe, data) {
  const out = {};
  FAMILIES.forEach(function (f) {
    try {
      const r = Engine.adapterRecette(recipe, { allergens: [f], ageMois: recipe.minAgeMonths || 6 }, data);
      out[f] = r.status;
    } catch (e) { out[f] = "not_adaptable"; }
  });
  return out;
}

function publier(options) {
  options = options || {};
  const pub = options.publishing || read("data/publishing.json");
  let corpus = options.corpus;
  if (!corpus) {
    corpus = read("data/recipes.json");
    try { corpus = corpus.concat(read("data/imported/imported-recipes.json")); } catch (e) {}
    try { corpus = corpus.concat(read("data/generated/generated-recipes.json")); } catch (e) {}
  }
  let manifesteImages = options.images || {};
  if (!options.images) { try { manifesteImages = read("generation/images/manifest.json"); } catch (e) {} }

  const securite = {
    ingredients: read("data/ingredients.json"),
    substitutions: read("data/substitutions.json"),
    base: read("data/base.json"),
    lexicon: read("data/label-lexicon.json")
  };
  const data = { catalogue: securite.ingredients, substitutions: securite.substitutions, base: securite.base };

  const free = new Set(pub.free || []);
  const catalogue = [];
  const bodies = {};
  const unknownCategory = [];

  corpus.forEach(function (r) {
    if (r.category !== "Meal" && r.category !== "Snack") unknownCategory.push(r.id);
    const copie = JSON.parse(JSON.stringify(r));
    const img = manifesteImages[r.id];
    /* A photo is published only when reviewed AND present on disk. */
    if (img && img.revisePar && img.fichier && fs.existsSync(path.join(root, img.fichier))) {
      copie.image = img.fichier;
      /* Made here, so a photo pushed from anywhere ships with its thumbnail;
       * a client without one downloaded 2 MB per 66-point square. */
      Vignettes.thumbnail(root, img.fichier);
      const vignette = img.fichier.replace(/^images\//, "images/thumbs/");
      if (fs.existsSync(path.join(root, vignette))) copie.thumb = vignette;
    }
    const card = {};
    PUBLIC.forEach(function (k) { if (copie[k] !== undefined) card[k] = copie[k]; });
    card.free = free.has(r.id);
    card.allergens = Engine.allergenesDe(r.ingredients, data.catalogue);
    card.adaptability = matrix(r, data);
    catalogue.push(card);
    bodies[r.id] = { id: r.id, ingredients: copie.ingredients, steps: copie.steps };
  });

  const counts = { Meal: 0, Snack: 0 };
  catalogue.forEach(function (c) { if (counts[c.category] !== undefined) counts[c.category]++; });

  return {
    manifest: {
      version: new Date().toISOString().slice(0, 10),
      safetyChecksum: checksum(securite),
      catalogueChecksum: checksum(catalogue),
      rotationWeeks: pub.rotationWeeks || 16,
      counts: counts,
      target: pub.target || { Meal: 112, Snack: 112 },
      free: Array.from(free)
    },
    securite: securite,
    catalogue: catalogue,
    bodies: bodies,
    unknownCategory: unknownCategory
  };
}

if (require.main === module) {
  const r = publier();
  const dist = path.join(root, "dist");
  fs.rmSync(path.join(dist, "batches"), { recursive: true, force: true });
  fs.mkdirSync(path.join(dist, "recipes"), { recursive: true });
  fs.writeFileSync(path.join(dist, "manifest.json"), JSON.stringify(r.manifest, null, 2) + "\n");
  fs.writeFileSync(path.join(dist, "safety.json"), JSON.stringify(r.securite) + "\n");
  fs.writeFileSync(path.join(dist, "catalogue.json"), JSON.stringify(r.catalogue) + "\n");
  Object.keys(r.bodies).forEach(function (id) {
    fs.writeFileSync(path.join(dist, "recipes", id + ".json"), JSON.stringify(r.bodies[id]) + "\n");
  });
  console.log("Published — version " + r.manifest.version);
  console.log("  pool       " + r.manifest.counts.Meal + " meals, " + r.manifest.counts.Snack +
              " snacks   (target " + r.manifest.target.Meal + " + " + r.manifest.target.Snack + ")");
  console.log("  free       " + r.manifest.free.length + " recipes");
  console.log("  rotation   " + r.manifest.rotationWeeks + " weeks");
  if (r.unknownCategory.length) console.log("  WARNING — neither Meal nor Snack: " + r.unknownCategory.join(", "));
}

module.exports = { publier: publier, FAMILIES: FAMILIES };
