/* Rolling weekly window.
 *
 * THE MODEL
 *
 * Batches are weekly. A subscriber sees the current week plus the TWO before
 * it — three weeks in all. Beyond that, recipes leave the view.
 *
 * Three things bring them back:
 *   - the Top rated tab, for those that gathered enough ratings;
 *   - saved recipes, kept on the device, outside the window, for good;
 *   - nothing else. No artificial rotation: a recipe returns because parents
 *     liked it, not because a script fished it out.
 *
 * Free batches never rotate. That is the floor a parent keeps without paying,
 * and it must not slip away from them.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));
const ecrire = (p, o) => fs.writeFileSync(path.join(racine, p), JSON.stringify(o, null, 2) + "\n");

const FENETRE = 3;   /* semaines visible, la courante comprise */

/* ---------- semaines ISO ---------- */

function numeroSemaine(date) {
  const t = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
  const debutAnnee = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return { annee: t.getUTCFullYear(), semaine: Math.ceil(((t - debutAnnee) / 86400000 + 1) / 7) };
}

function identifiantSemaine(date) {
  const { annee, semaine } = numeroSemaine(date || new Date());
  return annee + "-S" + String(semaine).padStart(2, "0");
}

/* Semaines précédentes, en remontant. Gère le passage d'année. */
function semainesPrecedentes(depuis, combien) {
  const out = [];
  const d = new Date(depuis || Date.now());
  for (let i = 0; i < combien; i++) {
    out.push(identifiantSemaine(d));
    d.setDate(d.getDate() - 7);
  }
  return out;
}

/* Ordre chronologique d'un identifiant de semaine, pour trier sans ambiguïté. */
function rang(id) {
  const m = /^(\d{4})-S(\d{1,2})$/.exec(id);
  return m ? Number(m[1]) * 100 + Number(m[2]) : -1;
}

/* ---------- la fenêtre ---------- */

/* Les batches visible aujourd'hui : tous les free, plus les FENETRE batches
 * hebdomadaires les plus récents qui existent réellement. On ne se fie pas à
 * la date du jour seule — si aucun lot n'a été publié depuis un mois, le
 * dernier reste visible plutôt que de laisser l'app vide. */
function fenetreCourante(batches, maintenant) {
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
  const pub = lire("data/publishing.json");
  let corpus = lire("data/recipes.json");
  for (const p of ["data/imported/imported-recipes.json",
                   "data/generated/generated-recipes.json"]) {
    try { corpus = corpus.concat(lire(p)); } catch (e) {}
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

  /* Le paquet le plus récent devient la semaine courante; on remonte pour les
   * autres, pour que l'historique existant reste cohérent. */
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
      note: "Sept recettes visant les profils les moins servis.",
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

  ecrire("data/publishing.json", pub);
  return pub;
}

/* ---------- affichage ---------- */

function etat() {
  const pub = lire("data/publishing.json");
  const f = fenetreCourante(pub.batches, Date.now());
  const account = {};
  Object.values(pub.assignment).forEach(function (l) { account[l] = (account[l] || 0) + 1; });

  console.log("Semaine courante : " + identifiantSemaine(new Date()));
  console.log("Fenêtre : " + FENETRE + " semaines\n");
  console.log("Toujours visible (free)");
  f.free.forEach(function (id) { console.log("  " + id + "  " + (account[id] || 0) + " recettes"); });
  console.log("\nDans la fenêtre (abonnés)");
  f.window.forEach(function (id) { console.log("  " + id + "  " + (account[id] || 0) + " recettes"); });
  if (f.horsFenetre.length) {
    console.log("\nSorties de vue — reviennent par les Meilleures ou les favoris");
    f.horsFenetre.forEach(function (id) { console.log("  " + id + "  " + (account[id] || 0) + " recettes"); });
  }
  const visible = f.free.concat(f.window).reduce((s, id) => s + (account[id] || 0), 0);
  console.log("\n  " + visible + " recettes visible pour un abonné aujourd'hui");
}

if (require.main === module) {
  if (process.argv.includes("--convertir")) {
    const pub = convertir();
    console.log("Converti en batches hebdomadaires.\n");
    pub.batches.forEach(function (l) {
      const n = Object.values(pub.assignment).filter((x) => x === l.id).length;
      console.log("  " + l.id + "  " + (l.access === "free" ? "libre " : "abonné") + "  " + n + " recettes");
    });
    console.log("");
    etat();
  } else {
    etat();
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
