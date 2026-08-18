/* Publication — bloc A
 * node outils/publier.js  →  écrit dist/manifeste.json et dist/lots/<lot>.json
 *
 * Le corpus sort du fichier HTML. À partir d'ici, l'app charge des lots
 * versionnés, et le serveur ne remet QUE les lots auxquels le compte a droit.
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
const somme = (o) => crypto.createHash("sha1").update(JSON.stringify(o)).digest("hex").slice(0, 12);

function publier(options) {
  options = options || {};
  const pub = options.publication || lire("donnees/publication.json");
  let corpus = options.corpus;
  if (!corpus) {
    corpus = lire("donnees/recettes.json");
    try { corpus = corpus.concat(lire("donnees/importees/recettes-importees.json")); } catch (e) {}
  }
  let manifesteImages = options.images || {};
  if (!options.images) { try { manifesteImages = lire("generation/images/manifeste.json"); } catch (e) {} }

  const parLot = {};
  const orphelines = [];
  pub.lots.forEach(function (l) { parLot[l.id] = []; });

  corpus.forEach(function (r) {
    const lot = pub.attribution[r.id];
    if (!lot || !parLot[lot]) { orphelines.push(r.id); return; }
    const copie = JSON.parse(JSON.stringify(r));
    copie.lot = lot;
    const img = manifesteImages[r.id];
    if (img && img.revisePar) copie.image = img.fichier;
    parLot[lot].push(copie);
  });

  /* Les tables de sécurité voyagent avec CHAQUE réponse, libre ou non. */
  const securite = {
    ingredients: lire("donnees/ingredients.json"),
    substitutions: lire("donnees/substitutions.json"),
    base: lire("donnees/base.json")
  };

  const lots = pub.lots.map(function (l) {
    const recettes = parLot[l.id];
    return {
      id: l.id, titre: l.titre, date: l.date, acces: l.acces, note: l.note,
      nombre: recettes.length, somme: somme(recettes)
    };
  });

  return {
    manifeste: {
      version: new Date().toISOString().slice(0, 10),
      sommeSecurite: somme(securite),
      lots: lots,
      /* Le client sait quels lots existent et lesquels sont verrouillés,
       * sans jamais recevoir leur contenu. */
      libres: lots.filter(function (l) { return l.acces === "libre"; }).map(function (l) { return l.id; })
    },
    securite: securite,
    contenu: parLot,
    orphelines: orphelines
  };
}

if (require.main === module) {
  const r = publier();
  const dist = path.join(racine, "dist");
  fs.mkdirSync(path.join(dist, "lots"), { recursive: true });
  fs.writeFileSync(path.join(dist, "manifeste.json"), JSON.stringify(r.manifeste, null, 2) + "\n");
  fs.writeFileSync(path.join(dist, "securite.json"), JSON.stringify(r.securite) + "\n");
  Object.keys(r.contenu).forEach(function (lot) {
    fs.writeFileSync(path.join(dist, "lots", lot + ".json"), JSON.stringify(r.contenu[lot]) + "\n");
  });
  console.log("Publié — version " + r.manifeste.version);
  r.manifeste.lots.forEach(function (l) {
    console.log("  " + l.id + "  " + (l.acces === "libre" ? "libre " : "abonné") + "  " +
      String(l.nombre).padStart(2) + " recettes  " + l.titre);
  });
  if (r.orphelines.length) console.log("  ATTENTION — sans lot : " + r.orphelines.join(", "));
}

module.exports = { publier: publier };
