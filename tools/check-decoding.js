/* Decoding check — Swift Codable structs against the real JSON.
 *   node tools/check-decoding.js
 *
 * WHY THIS EXISTS
 *
 * A Swift struct declares a non-optional field. The JSON does not carry it, or
 * carries it under another name. Everything compiles, the IPA installs, and
 * the app dies on first launch with "The data couldn't be read because it is
 * missing" — a message that names nothing.
 *
 * That has now happened twice: once on the bridge function names, once on
 * `stades` versus `stages`. Nothing in the build could catch it, because
 * neither side is wrong on its own; they simply disagree.
 *
 * This reads every Codable struct in Models.swift, matches it against a real
 * sample of the JSON that will be served, and fails when a required field has
 * nowhere to come from.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const read = (p) => JSON.parse(fs.readFileSync(path.join(root, p), "utf8"));

const swift = fs.readFileSync(path.join(root, "ios/App/App/Models/Models.swift"), "utf8");

/* Fields of a Swift struct: name, and whether it is optional. Lines inside a
 * nested enum or a CodingKeys block are skipped — they are not stored
 * properties. */
function fieldsOf(structName) {
  /* Match to the FIRST closing brace at column 0, and stop at the next
   * top-level declaration — otherwise two adjacent structs bleed into one. */
  const start = swift.search(new RegExp("^struct\\s+" + structName + "\\b", "m"));
  if (start === -1) return null;
  const after = swift.slice(start);
  const end = after.search(/\n\}/);
  if (end === -1) return null;
  let body = after.slice(after.indexOf("{") + 1, end);
  body = body.replace(/enum\s+CodingKeys(?:.|\n)*?\n\s*\}/g, "");
  const out = [];
  /* Only STORED properties are decoded. A computed one is followed by "{" on
   * the same line or the next, and carries no value from the JSON. */
  const lines = body.split("\n");
  lines.forEach(function (line, idx) {
    const f = line.match(/^\s*(?:let|var)\s+(\w+)\s*:\s*(.+)$/);
    if (!f) return;
    const rest = f[2].trim();
    const suivante = (lines[idx + 1] || "").trim();
    if (rest.endsWith("{") || suivante.startsWith("{")) return;   /* computed */
    if (rest.includes("=")) return;                                /* has a default */
    out.push({ name: f[1], optional: rest.replace(/\s*\{.*$/, "").trim().endsWith("?") });
  });
  return out;
}

/* Samples of exactly what the app will decode. */
const base = read("data/base.json");
const catalogue = read("data/ingredients.json");
const corpus = read("data/recipes.json");
const firstIngredientKey = Object.keys(catalogue)[0];

const CASES = [
  { struct: "ReferenceTables", sample: base, label: "base.json" },
  { struct: "Allergen", sample: base.allergens[0], label: "allergen" },
  { struct: "TextureStage", sample: base.stages[0], label: "stage, with note" },
  { struct: "TextureStage", sample: base.stages[base.stages.length - 1], label: "stage, no note" },
  { struct: "IngredientDefinition", sample: catalogue[firstIngredientKey], label: "ingredient" },
  { struct: "Recipe", sample: corpus[0], label: "recipe" },
  { struct: "RecipeIngredient", sample: corpus[0].ingredients[0], label: "recipe ingredient" }
];

const problems = [];
CASES.forEach(function (c) {
  const fields = fieldsOf(c.struct);
  if (!fields) { problems.push("struct " + c.struct + " not found in Models.swift"); return; }
  fields.forEach(function (f) {
    if (!f.optional && !(f.name in c.sample)) {
      const near = Object.keys(c.sample).find(function (k) {
        return k.toLowerCase().startsWith(f.name.slice(0, 4).toLowerCase());
      });
      problems.push(c.struct + "." + f.name + " is required but absent from " + c.label +
        (near ? "  (the JSON has \"" + near + "\" — a rename that did not reach both sides?)" : ""));
    }
  });
});

/* Enum raw values. This is the case a field-by-field check cannot see: the
 * property is present, the type is right, and an unrecognised value falls back
 * to `unknown`. Every recipe then lands outside every section and the list goes
 * silently empty. Measured once, in production. */
function enumValues(enumName) {
  const m = swift.match(new RegExp("enum\\s+" + enumName + "[^{]*\\{((?:.|\\n)*?)\\n\\}"));
  if (!m) return null;
  const out = [];
  const re = /^\s*case\s+(\w+)(?:\s*=\s*"([^"]+)")?/gm;
  let f;
  while ((f = re.exec(m[1])) !== null) out.push(f[2] || f[1]);
  return out;
}

const Engine = require(path.join(root, "engine/engine.js"));
const data = { catalogue: catalogue, substitutions: read("data/substitutions.json"), base: base };

/* Run the engine over a spread of profiles and collect every value it can
 * actually emit, then check each one has a home in the Swift enum. */
const emitted = { status: new Set(), ingredientStatus: new Set(), level: new Set() };
[[[], 6], [["milk"], 9], [["egg", "milk", "peanut"], 24], [["wheat", "soy"], 12],
 [["tree_nut"], 48], [["fish", "shellfish"], 18]].forEach(function (p) {
  corpus.forEach(function (r) {
    const res = Engine.adapterRecette(r, { allergens: p[0], ageMois: p[1] }, data);
    emitted.status.add(res.status);
    (res.ingredients || []).forEach(function (i) { if (i.status) emitted.ingredientStatus.add(i.status); });
    (res.alerts || []).forEach(function (a) { if (a.level) emitted.level.add(a.level); });
  });
});

[["RecipeStatus", emitted.status], ["IngredientStatus", emitted.ingredientStatus],
 ["AlertLevel", emitted.level]].forEach(function (pair) {
  const declared = enumValues(pair[0]);
  if (!declared) { problems.push("enum " + pair[0] + " not found in Models.swift"); return; }
  Array.from(pair[1]).forEach(function (v) {
    if (declared.indexOf(v) === -1) {
      problems.push("the engine emits " + pair[0] + " \"" + v + "\", which Swift does not declare" +
        "  (it declares: " + declared.join(", ") + ")");
    }
  });
});

/* The bridge and the Swift side have to agree on function names too. */
const bridge = fs.readFileSync(path.join(root, "engine/native-bridge.js"), "utf8");
const engineSwift = fs.readFileSync(path.join(root, "ios/App/App/Core/RecipeEngine.swift"), "utf8");
const exposed = (bridge.match(/^\s{4}(\w+): function/gm) || []).map(function (l) {
  return l.trim().split(":")[0];
});
const called = Array.from(new Set((engineSwift.match(/appeler\("(\w+)"/g) || []).map(function (l) {
  return l.match(/"(\w+)"/)[1];
})));
called.forEach(function (nameCalled) {
  if (exposed.indexOf(nameCalled) === -1) {
    problems.push("the Swift calls PONT." + nameCalled + "(), which the bridge does not expose" +
      "  (it exposes: " + exposed.join(", ") + ")");
  }
});

/* ---------- the scanner verdict, nested inside a struct ------------------- */
/* The enum walk above only finds TOP-LEVEL enums, so ProductVerdict.Statut
 * escaped it — and it had drifted exactly like the others: the bridge emits
 * safe/avoid/uncertain while Swift declared sur/a_eviter/incertain. Every
 * scanned product fell through to the fallback and came back "uncertain".
 * Nothing crashed, because the fallback is deliberate. */
const bridgeSrc = fs.readFileSync(path.join(root, "engine/native-bridge.js"), "utf8");
const statutsEmis = Array.from(new Set(
  (bridgeSrc.match(/status\s*=\s*"(\w+)"/g) || []).map(function (m) { return m.match(/"(\w+)"/)[1]; })
));
const blocStatut = swift.match(/enum Statut[^{]*\{((?:.|\n)*?)\n\s*\}/);
if (!blocStatut) {
  problems.push("enum Statut not found in Models.swift");
} else {
  const declares = blocStatut[1]
    .split("\n").filter(function (l) { return /^\s*case\s/.test(l); }).join(" ")
    .replace(/case|=/g, " ").split(/[\s,]+/)
    .map(function (w) { return w.replace(/"/g, "").trim(); }).filter(Boolean);
  statutsEmis.forEach(function (v) {
    if (declares.indexOf(v) === -1) {
      problems.push('scanner verdict: the bridge emits "' + v + '" which ProductVerdict.Statut ' +
        "does not declare  (it declares: " + declares.join(", ") + ") — every scan would " +
        "fall through to the fallback");
    }
  });
}

/* A SWIFT FIELD THAT MATCHES NOTHING IN THE DATA.
 *
 * `Recipe.lot` decoded to nil on every recipe because the published field is
 * called `batch`. Optionals fail silently, so nothing ever said so — the app
 * simply behaved as if no recipe belonged to any week.
 *
 * Any optional Swift field absent from EVERY data file is almost always a
 * typo. Fields the app fills in itself are listed rather than guessed. */
(function champsOrphelins() {
  var swiftPath = path.join(__dirname, "..", "ios/App/App/Models/Models.swift");
  if (!fs.existsSync(swiftPath)) return;

  var swift = fs.readFileSync(swiftPath, "utf8");
  /* `struct Recipe[^{]*` also matched RecipeIngredient, so a field that is
   * perfectly valid there was reported as orphaned. The word boundary keeps
   * it to the type we mean. */
  var bloc = swift.match(/struct Recipe(?![A-Za-z])[^{]*\{([\s\S]*?)\n\}/);
  if (!bloc) return;

  var champs = [];
  var re = /^\s*let (\w+): ([\w\[\]?]+)/gm, m;
  while ((m = re.exec(bloc[1])) !== null) {
    if (m[2].slice(-1) === "?") champs.push(m[1]);
  }

  /* Filled by the app or the ratings endpoint, never by the corpus. */
  var locaux = ["source", "image", "imageReviewed", "stepsOriginal",
                "votes", "average", "myRating"];
  var vus = {};

  function scan(f) {
    if (!fs.existsSync(f)) return;
    var c = JSON.parse(fs.readFileSync(f, "utf8"));
    var arr = Array.isArray(c) ? c : (c.recipes || []);
    arr.forEach(function (r) {
      Object.keys(r).forEach(function (k) { vus[k] = true; });
    });
  }

  scan(path.join(__dirname, "..", "data/recipes.json"));
  var dir = path.join(__dirname, "..", "dist/batches");
  if (fs.existsSync(dir)) {
    fs.readdirSync(dir).forEach(function (f) {
      if (f.slice(-5) === ".json") scan(path.join(dir, f));
    });
  }

  champs.forEach(function (c) {
    if (!vus[c] && locaux.indexOf(c) === -1) {
      problems.push("Recipe." + c + " matches no field in any data file — an " +
        "optional that matches nothing decodes to nil in silence");
    }
  });
})();

if (!problems.length) {
  console.log("Decoding check passed — " + CASES.length + " structs match the JSON, " +
    exposed.length + " bridge functions match the Swift calls.");
  process.exit(0);
}

console.error("\nDECODING MISMATCH (" + problems.length + ")");
problems.forEach(function (p) { console.error("  x " + p); });
console.error("\nThe build would succeed and the app would die on first launch.\n");
process.exit(1);
