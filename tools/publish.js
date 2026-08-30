/* Publication — bloc A
 * node tools/publish.js  ->  writes dist/manifest.json and dist/batches/<batch>.json
 *
 * The corpus leaves the HTML file. From here the app loads versioned batches,
 * and the server hands over ONLY the batches the account is entitled to. A
 * paywall on the client is bypassed in ten seconds; the only wall that holds
 * is the one that does not send the data.
 *
 * What is NEVER behind the wall: the engine, the substitutions, the age rules.
 * A parent handed a diagnosis on a Tuesday evening must not hit a payment
 * screen.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));
const checksum = (o) => crypto.createHash("sha1").update(JSON.stringify(o)).digest("hex").slice(0, 12);
const Semaines = require("./weeks.js");

function publier(options) {
  options = options || {};
  const pub = options.publishing || lire("data/publishing.json");
  let corpus = options.corpus;
  if (!corpus) {
    corpus = lire("data/recipes.json");
    try { corpus = corpus.concat(lire("data/imported/imported-recipes.json")); } catch (e) {}
    /* Generated recipes count like any other — leaving them out here made them
     * invisible to the manifest even though they were properly published. */
    try { corpus = corpus.concat(lire("data/generated/generated-recipes.json")); } catch (e) {}
  }
  let manifesteImages = options.images || {};
  if (!options.images) { try { manifesteImages = lire("generation/images/manifest.json"); } catch (e) {} }

  const parLot = {};
  const orphans = [];
  pub.batches.forEach(function (l) { parLot[l.id] = []; });

  corpus.forEach(function (r) {
    const lot = pub.assignment[r.id];
    if (!lot || !parLot[lot]) { orphans.push(r.id); return; }
    const copie = JSON.parse(JSON.stringify(r));
    copie.batch = lot;
    const img = manifesteImages[r.id];
    /* A photo is published only if it was reviewed AND is present on
     * disque. Sinon l'app demanderait un fichier qui n'existe pas et
     * retomberait silencieusement sur l'illustration. */
    if (img && img.revisePar && img.fichier &&
        fs.existsSync(path.join(racine, img.fichier))) {
      copie.image = img.fichier;
    }
    parLot[lot].push(copie);
  });

  /* The safety tables travel with EVERY response, free or not. */
  const securite = {
    ingredients: lire("data/ingredients.json"),
    substitutions: lire("data/substitutions.json"),
    base: lire("data/base.json"),
    /* The scanner's label vocabulary. Ships beside the safety tables, never
     * behind the paywall: reading a label is the free promise. */
    lexicon: lire("data/label-lexicon.json")
  };

  /* The rolling window: a subscriber sees the current week and the two before
   * it. Free batches never rotate — that is the floor a
   * parent doit garder sans payer. */
  const f = Semaines.fenetreCourante(pub.batches, Date.now());
  const visible = new Set(f.free.concat(f.window));

  const batches = pub.batches.map(function (l) {
    const recettes = parLot[l.id];
    return {
      id: l.id, title: l.title, date: l.date, access: l.access, note: l.note,
      count: recettes.length, checksum: checksum(recettes),
      weekly: !!l.weekly,
      inWindow: visible.has(l.id)
    };
  });

  return {
    manifeste: {
      version: new Date().toISOString().slice(0, 10),
      safetyChecksum: checksum(securite),
      batches: batches,
      /* The client knows which batches exist and which are locked,
       * sans jamais recevoir leur content. */
      free: batches.filter(function (l) { return l.access === "free"; }).map(function (l) { return l.id; }),
      window: f.window,
      currentWeek: Semaines.identifiantSemaine(new Date()),
      windowSize: Semaines.FENETRE
    },
    securite: securite,
    content: parLot,
    visible: Array.from(visible),
    orphans: orphans
  };
}

if (require.main === module) {
  const r = publier();
  const dist = path.join(racine, "dist");
  fs.mkdirSync(path.join(dist, "batches"), { recursive: true });
  fs.writeFileSync(path.join(dist, "manifest.json"), JSON.stringify(r.manifeste, null, 2) + "\n");
  fs.writeFileSync(path.join(dist, "safety.json"), JSON.stringify(r.securite) + "\n");
  Object.keys(r.content).forEach(function (lot) {
    fs.writeFileSync(path.join(dist, "batches", lot + ".json"), JSON.stringify(r.content[lot]) + "\n");
  });
  console.log("Published — version " + r.manifeste.version);
  r.manifeste.batches.forEach(function (l) {
    console.log("  " + l.id + "  " + (l.access === "free" ? "free      " : "subscriber") + "  " +
      String(l.count).padStart(2) + " recipes  " + l.title);
  });
  if (r.orphans.length) console.log("  WARNING — no batch assigned: " + r.orphans.join(", "));
}

module.exports = { publier: publier };
