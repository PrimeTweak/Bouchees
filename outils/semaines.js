/* Semaines glissantes — bloc V
 *   node outils/semaines.js --convertir     transforme les lots en hebdomadaires
 *   node outils/semaines.js                 montre l'état de la fenêtre
 *
 * LE MODÈLE
 *
 * Les lots deviennent hebdomadaires. Un abonné voit la semaine courante plus
 * les DEUX précédentes — trois semaines au total. Au-delà, les recettes
 * sortent de vue.
 *
 * Trois choses les ramènent :
 *   - l'onglet Meilleures, pour celles qui ont récolté 5 votes ou plus;
 *   - les favoris, gardés sur l'appareil, hors fenêtre, pour toujours;
 *   - rien d'autre. Pas de rotation artificielle : une recette revient parce
 *     que des parents l'ont aimée, pas parce qu'un script l'a repêchée.
 *
 * Les lots LIBRES ne tournent jamais. C'est le socle qu'un parent doit avoir
 * sans payer, et il ne doit pas lui glisser entre les doigts.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));
const ecrire = (p, o) => fs.writeFileSync(path.join(racine, p), JSON.stringify(o, null, 2) + "\n");

const FENETRE = 3;   /* semaines visibles, la courante comprise */

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

/* Les lots visibles aujourd'hui : tous les libres, plus les FENETRE lots
 * hebdomadaires les plus récents qui existent réellement. On ne se fie pas à
 * la date du jour seule — si aucun lot n'a été publié depuis un mois, le
 * dernier reste visible plutôt que de laisser l'app vide. */
function fenetreCourante(lots, maintenant) {
  const libres = lots.filter((l) => l.acces === "libre").map((l) => l.id);
  const hebdo = lots
    .filter((l) => l.acces !== "libre" && rang(l.id) > 0)
    .sort((a, b) => rang(b.id) - rang(a.id))
    .slice(0, FENETRE)
    .map((l) => l.id);
  const autres = lots
    .filter((l) => l.acces !== "libre" && rang(l.id) <= 0)
    .map((l) => l.id);
  return { libres: libres, fenetre: hebdo, horsFenetre: autres.concat(
    lots.filter((l) => l.acces !== "libre" && rang(l.id) > 0 && hebdo.indexOf(l.id) === -1)
        .map((l) => l.id)) };
}

/* ---------- conversion ---------- */

function convertir() {
  const pub = lire("donnees/publication.json");
  let corpus = lire("donnees/recettes.json");
  for (const p of ["donnees/importees/recettes-importees.json",
                   "donnees/generees/recettes-generees.json"]) {
    try { corpus = corpus.concat(lire(p)); } catch (e) {}
  }

  const idsLibres = new Set();
  pub.lots.filter((l) => l.acces === "libre").forEach(function (l) {
    Object.keys(pub.attribution).forEach(function (id) {
      if (pub.attribution[id] === l.id) idsLibres.add(id);
    });
  });

  const abonnes = corpus.map((r) => r.id).filter((id) => !idsLibres.has(id));
  const paquets = [];
  for (let i = 0; i < abonnes.length; i += 7) paquets.push(abonnes.slice(i, i + 7));

  /* Le paquet le plus récent devient la semaine courante; on remonte pour les
   * autres, pour que l'historique existant reste cohérent. */
  const semaines = semainesPrecedentes(Date.now(), paquets.length).reverse();

  const nouveauxLots = pub.lots.filter((l) => l.acces === "libre");
  const attribution = {};
  Object.keys(pub.attribution).forEach(function (id) {
    if (idsLibres.has(id)) attribution[id] = pub.attribution[id];
  });

  paquets.forEach(function (paquet, i) {
    const id = semaines[i];
    nouveauxLots.push({
      id: id,
      titre: "Semaine du " + id,
      acces: "abonne",
      note: "Sept recettes visant les profils les moins servis.",
      hebdomadaire: true
    });
    paquet.forEach(function (r) { attribution[r] = id; });
  });

  pub.lots = nouveauxLots;
  pub.attribution = attribution;
  pub.fenetre = FENETRE;
  pub._doc = "Lots hebdomadaires. Un abonné voit la semaine courante et les " +
    (FENETRE - 1) + " précédentes. Les lots libres ne tournent jamais. " +
    "Les recettes sorties de la fenêtre reviennent par l'onglet Meilleures " +
    "(5 votes ou plus) ou par les favoris gardés sur l'appareil.";

  ecrire("donnees/publication.json", pub);
  return pub;
}

/* ---------- affichage ---------- */

function etat() {
  const pub = lire("donnees/publication.json");
  const f = fenetreCourante(pub.lots, Date.now());
  const compte = {};
  Object.values(pub.attribution).forEach(function (l) { compte[l] = (compte[l] || 0) + 1; });

  console.log("Semaine courante : " + identifiantSemaine(new Date()));
  console.log("Fenêtre : " + FENETRE + " semaines\n");
  console.log("Toujours visibles (libres)");
  f.libres.forEach(function (id) { console.log("  " + id + "  " + (compte[id] || 0) + " recettes"); });
  console.log("\nDans la fenêtre (abonnés)");
  f.fenetre.forEach(function (id) { console.log("  " + id + "  " + (compte[id] || 0) + " recettes"); });
  if (f.horsFenetre.length) {
    console.log("\nSorties de vue — reviennent par les Meilleures ou les favoris");
    f.horsFenetre.forEach(function (id) { console.log("  " + id + "  " + (compte[id] || 0) + " recettes"); });
  }
  const visibles = f.libres.concat(f.fenetre).reduce((s, id) => s + (compte[id] || 0), 0);
  console.log("\n  " + visibles + " recettes visibles pour un abonné aujourd'hui");
}

if (require.main === module) {
  if (process.argv.includes("--convertir")) {
    const pub = convertir();
    console.log("Converti en lots hebdomadaires.\n");
    pub.lots.forEach(function (l) {
      const n = Object.values(pub.attribution).filter((x) => x === l.id).length;
      console.log("  " + l.id + "  " + (l.acces === "libre" ? "libre " : "abonné") + "  " + n + " recettes");
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
