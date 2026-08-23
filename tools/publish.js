/* Publication — bloc A
 * node tools/publish.js  →  écrit dist/manifest.json et dist/batches/<lot>.json
 *
 * Le corpus sort du fichier HTML. À partir d'ici, l'app charge des batches
 * versionnés, et le serveur ne remet QUE les batches auxquels le account a droit.
 * Un mur payant côté client se contourne en dix secondes; le seul mur qui
 * tient est celui qui n'envoie pas les données.
 *
 * Ce qui n'est JAMAIS derrière le mur : le moteur, les substitutions, les
 * règles d'âge. Un parent qui reçoit un diagnostic un mardi soir ne doit pas
 * buter sur un écran de paiement.
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
    /* Les recettes générées comptent comme les autres — les oublier ici les
     * rendait invisibles au manifeste alors qu'elles étaient bien publiées. */
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
    /* Une photo n'est publiée que si elle est révisée ET présente sur le
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
    base: lire("data/base.json")
  };

  /* La fenêtre glissante : un abonné voit la semaine courante et les deux
   * précédentes. Les batches free ne tournent jamais — c'est le socle qu'un
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
      /* Le client sait quels batches existent et lesquels sont verrouillés,
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
  console.log("Publié — version " + r.manifeste.version);
  r.manifeste.batches.forEach(function (l) {
    console.log("  " + l.id + "  " + (l.access === "free" ? "libre " : "abonné") + "  " +
      String(l.count).padStart(2) + " recettes  " + l.title);
  });
  if (r.orphans.length) console.log("  ATTENTION — sans lot : " + r.orphans.join(", "));
}

module.exports = { publier: publier };
