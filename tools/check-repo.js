/* Repository integrity check.
 *   node tools/check-repo.js
 *
 * WHY THIS EXISTS
 *
 * Dragging one folder onto another in the Finder REPLACES it whole instead of
 * merging. A partial delivery therefore deletes every file it does not carry,
 * silently. That has now cost three builds: engine.js once, the Swift sources
 * once, and the tools folder once.
 *
 * This runs first, costs a second, and names the missing file instead of
 * letting a MODULE_NOT_FOUND surface thirty minutes into a build.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");

const REQUIRED = [
  "engine/engine.js", "engine/native-bridge.js",
  "data/ingredients.json", "data/substitutions.json", "data/base.json",
  "data/recipes.json", "data/publishing.json",
  "data/imported/imported-recipes.json", "data/generated/generated-recipes.json",
  "tools/gaps.js", "tools/publish.js", "tools/weeks.js", "tools/cycle.js",
  "tools/manual-import.js", "tools/check-swift.py", "tools/check-repo.js", "tools/check-decoding.js", "tools/check-bundle-names.js",
  "server/server.js", "server/ratings.js", "server/apple.js", "server/stripe.js",
  "server/legal-pages.js",
  "ingest/importer.js", "ingest/adapters.js", "ingest/normalizer.js",
  "ingest/lexicon.json", "ingest/curation.json",
  "generation/images.js", "generation/vision.js", "generation/coherence.js",
  "generation/recipe-validator.js", "generation/recipe-prompt.js",
  "generation/text-engines.js", "generation/image-engines.js",
  "web/build.js", "web/illustration.js", "web/template.html",
  "tests/test.js", "ios/project.yml", "ios/App/App/Info.plist",
  "ios/App/App/App.entitlements",
  ".github/workflows/ipa.yml"
];

/* Folders with a known floor. Fewer files than this means one was replaced
 * rather than merged. */
/* Names Apple reserves inside a bundle. A folder called "Resources" at the
 * root of an iOS .app makes a bundle reader fall back to the macOS layout and
 * look for Info.plist under Contents/ — which does not exist. The app then
 * reads as unreadable to an installer even though every file is correct.
 * Measured: renaming Ressources -> Resources during the English conversion is
 * what broke sideloading. */
const RESERVED_BUNDLE_DIRS = ["Resources", "Contents", "Frameworks", "PlugIns",
                              "SharedFrameworks", "XPCServices", "_CodeSignature"];

const FLOORS = [
  { dir: "ios/App/App", ext: ".swift", min: 12, recursive: true },
  { dir: "tools", ext: ".js", min: 5, recursive: false },
  { dir: "server", ext: ".js", min: 5, recursive: false },
  { dir: "generation", ext: ".js", min: 7, recursive: false }
];

function countFiles(dir, ext, recursive) {
  const full = path.join(root, dir);
  if (!fs.existsSync(full)) return 0;
  let n = 0;
  for (const entry of fs.readdirSync(full, { withFileTypes: true })) {
    if (entry.isDirectory() && recursive) n += countFiles(path.join(dir, entry.name), ext, true);
    else if (entry.isFile() && entry.name.endsWith(ext)) n++;
  }
  return n;
}

const bundleRoot = path.join(root, "ios", "App", "App");
const reserved = fs.existsSync(bundleRoot)
  ? fs.readdirSync(bundleRoot, { withFileTypes: true })
      .filter((e) => e.isDirectory() && RESERVED_BUNDLE_DIRS.indexOf(e.name) !== -1)
      .map((e) => e.name)
  : [];

const missing = REQUIRED.filter((f) => !fs.existsSync(path.join(root, f)));
const thin = FLOORS
  .map((f) => ({ ...f, found: countFiles(f.dir, f.ext, f.recursive) }))
  .filter((f) => f.found < f.min);

if (reserved.length) {
  console.error("\nRESERVED BUNDLE DIRECTORY NAME");
  reserved.forEach((n) => console.error("  x ios/App/App/" + n +
    " — Apple reserves this name inside a bundle; an installer will fail to read the app"));
  console.error("\nRename it to something neutral (Bundled, AppData, Content).\n");
  process.exit(1);
}

if (!missing.length && !thin.length) {
  console.log("Repository complete — " + REQUIRED.length + " required files, all folders above their floor.");
  process.exit(0);
}

if (missing.length) {
  console.error("\nMISSING FILES (" + missing.length + ")");
  missing.forEach((f) => console.error("  x " + f));
}
if (thin.length) {
  console.error("\nFOLDERS BELOW THEIR FLOOR");
  thin.forEach((f) => console.error("  x " + f.dir + "/*" + f.ext + " — " + f.found +
    " found, expected at least " + f.min));
}
console.error("\nA folder was almost certainly REPLACED instead of merged.");
console.error("Ask for the complete folder rather than the individual files.\n");
process.exit(1);
