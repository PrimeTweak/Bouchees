/* Notes et classement — blocs X et Y
 *
 * UNE NOTE PAR PERSONNE PAR RECETTE. On garde la dernière : un parent qui
 * refait la recette et change d'avis doit pouvoir corriger.
 *
 * LE CLASSEMENT N'EST PAS UNE MOYENNE BRUTE.
 *
 * Avec peu d'abonnés, une seule note de 5 créerait « la meilleure recette de
 * l'app ». Le seuil de 5 votes écarte le pire, mais ne suffit pas : à
 * 5 votes, une recette parfaite sur cinq personnes passerait devant une
 * recette excellente sur deux cents.
 *
 * D'où la moyenne bayésienne : chaque recette part avec un lest de quelques
 * votes à la moyenne générale, et doit gagner sa place. Une recette à 5 votes
 * peut entrer au classement, mais elle ne domine pas tant qu'elle n'a pas
 * convaincu plus de monde.
 */
"use strict";
const fs = require("fs");
const path = require("path");

const VOTES_MINIMUM = 5;   /* en deçà, la recette n'apparaît pas au classement */
const LEST = 8;            /* poids de l'ancrage, en votes fictifs */

/* ANCRAGE FIXE, ET C'EST DÉLIBÉRÉ.
 *
 * L'ancrage habituel est la moyenne observée de toutes les notes. Ça marche
 * quand les notes sont étalées. Ici, elles ne le seront pas : un parent note
 * surtout une recette qu'il a aimée, alors la moyenne générale montera vers
 * 4,5 et plus. L'ancrage se retrouverait au niveau des bonnes recettes, et ne
 * freinerait plus rien.
 *
 * Mesuré sur des données d'essai : avec l'ancrage mobile, une recette notée
 * 5/5 par cinq personnes passait DEVANT une recette à 4,8 sur soixante. Ce
 * n'est pas le classement qu'on veut montrer.
 *
 * Avec un ancrage fixe à 3,5, une recette doit convaincre plus de cinq
 * personnes pour monter — ce qui est exactement l'intention. */
const ANCRAGE = 3.5;

const FICHIER = process.env.BOUCHEES_NOTES || path.join(__dirname, "notes.json");

function lire() {
  try { return JSON.parse(fs.readFileSync(FICHIER, "utf8")); }
  catch (e) { return { notes: {} }; }
}
function ecrire(db) {
  fs.writeFileSync(FICHIER, JSON.stringify(db, null, 2));
}

/* notes[recetteId][courriel] = { note, le } */
function noter(recetteId, courriel, note) {
  const n = Number(note);
  if (!Number.isInteger(n) || n < 1 || n > 5) {
    return { ok: false, raison: "la note doit être un entier de 1 à 5" };
  }
  if (!recetteId || !courriel) return { ok: false, raison: "recette ou compte manquant" };

  const db = lire();
  if (!db.notes[recetteId]) db.notes[recetteId] = {};
  db.notes[recetteId][courriel] = { note: n, le: new Date().toISOString() };
  ecrire(db);
  return { ok: true, agregat: agregat(recetteId, db) };
}

function retirerNote(recetteId, courriel) {
  const db = lire();
  if (db.notes[recetteId]) {
    delete db.notes[recetteId][courriel];
    if (!Object.keys(db.notes[recetteId]).length) delete db.notes[recetteId];
    ecrire(db);
  }
  return { ok: true, agregat: agregat(recetteId, db) };
}

function noteDe(recetteId, courriel, db) {
  db = db || lire();
  const r = db.notes[recetteId];
  return r && r[courriel] ? r[courriel].note : null;
}

function agregat(recetteId, db) {
  db = db || lire();
  const r = db.notes[recetteId] || {};
  const valeurs = Object.values(r).map((x) => x.note);
  if (!valeurs.length) return { recetteId: recetteId, votes: 0, moyenne: null, score: null };
  const somme = valeurs.reduce((a, b) => a + b, 0);
  return {
    recetteId: recetteId,
    votes: valeurs.length,
    moyenne: Math.round((somme / valeurs.length) * 10) / 10
  };
}

/* Moyenne générale, gardée pour l'observation et les rapports — plus utilisée
 * comme ancrage, voir le commentaire au-dessus de ANCRAGE. */
function moyenneGenerale(db) {
  let somme = 0, n = 0;
  Object.values(db.notes).forEach(function (parCompte) {
    Object.values(parCompte).forEach(function (x) { somme += x.note; n++; });
  });
  return n ? somme / n : 3.5;
}

/* Le classement. Retourne des identifiants et des scores; c'est l'appelant
 * qui va chercher le contenu des recettes — le classement ne connaît pas les
 * recettes, seulement les votes. */
function classement(limite) {
  const db = lire();
  const out = [];

  Object.keys(db.notes).forEach(function (recetteId) {
    const a = agregat(recetteId, db);
    if (a.votes < VOTES_MINIMUM) return;
    const somme = Object.values(db.notes[recetteId]).reduce((s, x) => s + x.note, 0);
    /* Moyenne bayésienne : (lest × ancrage + somme) / (lest + votes) */
    const score = (LEST * ANCRAGE + somme) / (LEST + a.votes);
    out.push({
      recetteId: recetteId,
      votes: a.votes,
      moyenne: a.moyenne,
      score: Math.round(score * 1000) / 1000
    });
  });

  out.sort(function (a, b) {
    if (b.score !== a.score) return b.score - a.score;
    if (b.votes !== a.votes) return b.votes - a.votes;
    return a.recetteId < b.recetteId ? -1 : 1;
  });
  return limite ? out.slice(0, limite) : out;
}

/* Agrégats de plusieurs recettes d'un coup, pour l'affichage d'une liste. */
function agregats(ids, courriel) {
  const db = lire();
  const out = {};
  (ids || []).forEach(function (id) {
    const a = agregat(id, db);
    if (courriel) a.maNote = noteDe(id, courriel, db);
    out[id] = a;
  });
  return out;
}

/* Combien de recettes approchent du seuil — utile pour savoir si le
 * classement va se remplir ou rester vide. */
function progression() {
  const db = lire();
  const compte = { aucune: 0, enRoute: 0, classees: 0 };
  Object.keys(db.notes).forEach(function (id) {
    const n = Object.keys(db.notes[id]).length;
    if (n >= VOTES_MINIMUM) compte.classees++;
    else if (n > 0) compte.enRoute++;
  });
  return compte;
}

module.exports = {
  VOTES_MINIMUM: VOTES_MINIMUM, LEST: LEST, ANCRAGE: ANCRAGE,
  noter: noter, retirerNote: retirerNote, noteDe: noteDe,
  agregat: agregat, agregats: agregats, classement: classement,
  moyenneGenerale: moyenneGenerale, progression: progression
};
