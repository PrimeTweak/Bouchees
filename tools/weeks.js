/* Rolling weekly window: batches are weekly. */
"use strict";
const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const read = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));
const write = (p, o) => fs.writeFileSync(path.join(racine, p), JSON.stringify(o, null, 2) + "\n");

const FENETRE = 3;   /* semaines visible, la courante comprise */

/* ---------- semaines ISO ---------- */

function numeroSemaine(date) {
  const t = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
  const debutAnnee = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return { annee: t.getUTCFullYear(), week: Math.ceil(((t - debutAnnee) / 86400000 + 1) / 7) };
}

function identifiantSemaine(date) {
  const { annee, week } = numeroSemaine(date || new Date());
  return annee + "-S" + String(week).padStart(2, "0");
}

/* Previous weeks, walking back. Handles the year boundary. */
function semainesPrecedentes(since, count) {
  const out = [];
  const d = new Date(since || Date.now());
  for (let i = 0; i < count; i++) {
    out.push(identifiantSemaine(d));
    d.setDate(d.getDate() - 7);
  }
  return out;
}

/* Chronological order of a week identifier, for unambiguous sorting. */
function rang(id) {
  const m = /^(\d{4})-S(\d{1,2})$/.exec(id);
  return m ? Number(m[1]) * 100 + Number(m[2]) : -1;
}

/* ---------- the window ---------- */

/* Today's date alone is not trusted — if nothing has been published for a
 * month, the last batch stays visible rather than leaving the app empty. */
function fenetreCourante(batches, now) {
  const free = batches.filter((l) => l.access === "free").map((l) => l.id);
  const hebdo = batches
    .filter((l) => l.access !== "free" && rang(l.id) > 0)
    .sort((a, b) => rang(b.id) - rang(a.id))
    .slice(0, FENETRE)
    .map((l) => l.id);
  const autres = batches
    .filter((l) => l.access !== "free" && rang(l.id) <= 0)
    .map((l) => l.id);
  return { free: free, window: hebdo, horsFenetre: autres.concat(
    batches.filter((l) => l.access !== "free" && rang(l.id) > 0 && hebdo.indexOf(l.id) === -1)
        .map((l) => l.id)) };
}

/* ---------- conversion ---------- */

function convertir() {
  const pub = read("data/publishing.json");
  let corpus = read("data/recipes.json");
  for (const p of ["data/imported/imported-recipes.json",
                   "data/generated/generated-recipes.json"]) {
    try { corpus = corpus.concat(read(p)); } catch (e) {}
  }

  const idsLibres = new Set();
  pub.batches.filter((l) => l.access === "free").forEach(function (l) {
    Object.keys(pub.assignment).forEach(function (id) {
      if (pub.assignment[id] === l.id) idsLibres.add(id);
    });
  });

  const abonnes = corpus.map((r) => r.id).filter((id) => !idsLibres.has(id));
  const paquets = [];
  for (let i = 0; i < abonnes.length; i += 7) paquets.push(abonnes.slice(i, i + 7));

  /* The most recent bundle becomes the current week; the others walk back, so
   * the existing history stays coherent. */
  const semaines = semainesPrecedentes(Date.now(), paquets.length).reverse();

  const nouveauxLots = pub.batches.filter((l) => l.access === "free");
  const attribution = {};
  Object.keys(pub.assignment).forEach(function (id) {
    if (idsLibres.has(id)) attribution[id] = pub.assignment[id];
  });

  paquets.forEach(function (paquet, i) {
    const id = semaines[i];
    nouveauxLots.push({
      id: id,
      title: "Semaine du " + id,
      access: "subscriber",
      note: "Seven recipes aimed at the least-served profiles.",
      weekly: true
    });
    paquet.forEach(function (r) { attribution[r] = id; });
  });

  pub.batches = nouveauxLots;
  pub.assignment = attribution;
  pub.window = FENETRE;
  pub._doc = "Lots hebdomadaires. Un abonné voit la semaine courante et les " +
    (FENETRE - 1) + " précédentes. Les batches free ne tournent jamais. " +
    "Les recettes sorties de la fenêtre reviennent par l'onglet Meilleures " +
    "(5 votes ou plus) ou par les favoris gardés sur l'appareil.";

  write("data/publishing.json", pub);
  return pub;
}

/* ---------- affichage ---------- */

function state() {
  const pub = read("data/publishing.json");
  const f = fenetreCourante(pub.batches, Date.now());
  const account = {};
  Object.values(pub.assignment).forEach(function (l) { account[l] = (account[l] || 0) + 1; });

  console.log("Semaine courante : " + identifiantSemaine(new Date()));
  console.log("Window: " + FENETRE + " weeks\n");
  console.log("Toujours visible (free)");
  f.free.forEach(function (id) { console.log("  " + id + "  " + (account[id] || 0) + " recipes"); });
  console.log("\nInside the window (subscribers)");
  f.window.forEach(function (id) { console.log("  " + id + "  " + (account[id] || 0) + " recipes"); });
  if (f.horsFenetre.length) {
    console.log("\nSorties de vue — reviennent par les Meilleures ou les favoris");
    f.horsFenetre.forEach(function (id) { console.log("  " + id + "  " + (account[id] || 0) + " recipes"); });
  }
  const visible = f.free.concat(f.window).reduce((s, id) => s + (account[id] || 0), 0);
  console.log("\n  " + visible + " recipes visible to a subscriber today");
}

if (require.main === module) {
  if (process.argv.includes("--convertir")) {
    const pub = convertir();
    console.log("Converti en batches hebdomadaires.\n");
    pub.batches.forEach(function (l) {
      const n = Object.values(pub.assignment).filter((x) => x === l.id).length;
      console.log("  " + l.id + "  " + (l.access === "free" ? "free      " : "subscriber") + "  " + n + " recipes");
    });
    console.log("");
    state();
  } else {
    state();
  }
}

module.exports = {
  FENETRE: FENETRE,
  identifiantSemaine: identifiantSemaine,
  semainesPrecedentes: semainesPrecedentes,
  fenetreCourante: fenetreCourante,
  rang: rang,
  convertir: convertir
};
