/* This runs first, costs a second, and names the missing file instead of
 * letting a MODULE_NOT_FOUND surface thirty minutes into a build. Repository
 * integrity check. node tools/check-repo.js */
"use strict";
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");

const REQUIRED = [
  "engine/engine.js", "engine/native-bridge.js",
  "data/ingredients.json", "data/substitutions.json", "data/base.json", "data/label-lexicon.json", "tools/preflight.js", "PHOTOS.command", "tools/check-prompts.js", "docs/PROMPT-CONVENTION.md",
  "data/recipes.json", "data/publishing.json",
  "data/imported/imported-recipes.json", "data/generated/generated-recipes.json",
  "tools/gaps.js", "tools/publish.js", "tools/cycle.js",
  "tools/manual-import.js", "tools/check-swift.py", "tools/check-repo.js", "tools/check-decoding.js", "BUILD.json", "tools/check-agreement.js", "tools/image-sizes.js", "tools/probe-drawthings.js", "tools/check-bundle-names.js", "tools/build-product-pack.js", "tools/check-pack.js", "PAQUET.command", "docs/DATA-SOURCES.md", "ios/App/App/PrivacyInfo.xcprivacy", "ios/App/App/Services/WeeklyReminder.swift", "PHOTOS-REDUIRE.command", "ios/App/App/Localization/en.lproj/InfoPlist.strings", "ios/App/App/Localization/fr.lproj/InfoPlist.strings",
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
/* Names Apple reserves inside a bundle: the app then reads as unreadable to
 * an installer even though every file is correct. */
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
    /* Three builds in a row failed on errors that were already fixed, because
   * the zip had not been applied — emptying the folder in the Finder leaves
   * .github and other hidden files behind, and nothing said so. */
/* Forbidden fetch headers: node strips or rejects them and the behaviour
 * varies by version, so setting one turns a working request into "fetch
 * failed" with no explanation. */
(function enTetesInterdits() {
const INTERDITS = ["connection", "accept-encoding", "keep-alive", "host",
                   "content-length", "transfer-encoding", "upgrade",
                   "te", "trailer", "expect"];
  const fautes = [];
const fichiers = [];
(function marcher(dir) {
  fs.readdirSync(dir, { withFileTypes: true }).forEach(function (e) {
    if (e.name === "node_modules" || e.name.startsWith(".")) return;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) marcher(p);
    else if (e.name.endsWith(".js")) fichiers.push(p);
  });
})(root);

fichiers.forEach(function (f) {
  const code = fs.readFileSync(f, "utf8");
  if (code.indexOf("fetch(") === -1) return;

    /* server.js writes content-length on its RESPONSES — that is its job, and
   * the restriction applies to what a client SENDS. probe-drawthings exists
   * precisely to test these headers with raw http, which is the. */
  if (/writeHead|createServer|setHeader/.test(code)) return;
  if (f.indexOf("probe-") !== -1) return;

  /* node:http REQUIRES Content-Length on a POST — the restriction is about
   * what fetch forbids, and a file that uses http.request is not using
   * fetch for that call. */
  if (/http\.request\(/.test(code)) return;
  INTERDITS.forEach(function (h) {
    const motif = new RegExp('["\']' + h + '["\']\\s*:', "i");
    if (motif.test(code)) {
      fautes.push(path.relative(root, f) + ' sets "' + h + '"');
    }
  });
});

  if (fautes.length) {
    console.error("\nFORBIDDEN FETCH HEADER");
    fautes.forEach(function (f) { console.error("  x " + f); });
    console.error("");
    console.error("The specification forbids these — the runtime owns them.");
    console.error("Node strips or rejects them, and a working request");
    console.error("becomes \"fetch failed\" with no explanation.\n");
    process.exit(1);
  }
})();

/* Fetch() on a local renderer: the limit is internal: an AbortSignal does not
 * reach it, and mine was set to fifteen while undici cut at five. */
(function fetchSurRenduLocal() {
  const f = path.join(root, "generation", "image-engines.js");
  if (!fs.existsSync(f)) return;
  const code = fs.readFileSync(f, "utf8");
  const bloc = code.slice(code.indexOf("const drawthings"),
                          code.indexOf("const openai"));
  if (/\bfetch\(/.test(bloc)) {
    console.error("\nfetch() ON THE LOCAL RENDERER");
    console.error("  x generation/image-engines.js uses fetch for Draw Things");
    console.error("");
    console.error("undici cuts after five minutes waiting for the first");
    console.error("header, and no AbortSignal reaches that limit. A large");
    console.error("render takes longer. Use node:http.\n");
    process.exit(1);
  }
})();

try {
  const b = JSON.parse(fs.readFileSync(path.join(root, "BUILD.json"), "utf8"));
console.log("Build " + b.build + " — " + b.date);
} catch (e) {
  console.log("Build unknown — BUILD.json missing");
}

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
