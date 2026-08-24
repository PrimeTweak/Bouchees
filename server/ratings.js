/* Ratings and ranking.
 *
 * ONE RATING PER PERSON PER RECIPE. The latest one wins: a parent who cooks
 * the dish again and changes their mind must be able to correct it.
 *
 * THE RANKING IS NOT A RAW AVERAGE.
 *
 * With few subscribers, a single five-star rating would create "the best
 * recipe in the app". A minimum vote count keeps the worst of that out, but
 * it is not enough: at five votes, a recipe rated perfectly by five people
 * would outrank an excellent one rated by two hundred.
 *
 * Hence a Bayesian average: every recipe starts weighed down by a few
 * imaginary votes at a fixed anchor, and has to earn its way up.
 */
"use strict";
const fs = require("fs");
const path = require("path");

const MIN_VOTES = 5;   /* below this, a recipe does not appear in the ranking */
const WEIGHT = 8;            /* poids de l'ancrage, en votes fictifs */

/* THE ANCHOR IS FIXED, AND THAT IS DELIBERATE.
 *
 * The usual anchor is the observed average of all ratings. That works when
 * ratings are spread out. Here they will not be: a parent mostly rates a recipe
 * they liked, so the overall average climbs toward
 * 4,5 et plus. L'ancrage se retrouverait au level des bonnes recettes, et ne
 * freinerait plus rien.
 *
 * Measured on test data: with a moving anchor, a recipe rated 5/5 by five
 * people came AHEAD of one rated 4.8 by sixty. That
 * n'est pas le ranking qu'on veut montrer.
 *
 * With a fixed anchor at 3.5, a recipe has to convince more than five
 * personnes pour monter — ce qui est exactement l'intention. */
const ANCHOR = 3.5;

const FILE = process.env.BOUCHEES_NOTES || path.join(__dirname, "ratings.json");

function read() {
  try { return JSON.parse(fs.readFileSync(FILE, "utf8")); }
  catch (e) { return { ratings: {} }; }
}
function write(db) {
  fs.writeFileSync(FILE, JSON.stringify(db, null, 2));
}

/* ratings[recipeId][email] = { rating, le } */
function rate(recipeId, email, rating) {
  const n = Number(rating);
  if (!Number.isInteger(n) || n < 1 || n > 5) {
    return { ok: false, reason: "la rating doit être un entier de 1 à 5" };
  }
  if (!recipeId || !email) return { ok: false, reason: "recette ou account manquant" };

  const db = read();
  if (!db.ratings[recipeId]) db.ratings[recipeId] = {};
  db.ratings[recipeId][email] = { rating: n, le: new Date().toISOString() };
  write(db);
  return { ok: true, aggregate: aggregate(recipeId, db) };
}

function removeRating(recipeId, email) {
  const db = read();
  if (db.ratings[recipeId]) {
    delete db.ratings[recipeId][email];
    if (!Object.keys(db.ratings[recipeId]).length) delete db.ratings[recipeId];
    write(db);
  }
  return { ok: true, aggregate: aggregate(recipeId, db) };
}

function ratingBy(recipeId, email, db) {
  db = db || read();
  const r = db.ratings[recipeId];
  return r && r[email] ? r[email].rating : null;
}

function aggregate(recipeId, db) {
  db = db || read();
  const r = db.ratings[recipeId] || {};
  const values = Object.values(r).map((x) => x.rating);
  if (!values.length) return { recipeId: recipeId, votes: 0, average: null, score: null };
  const checksum = values.reduce((a, b) => a + b, 0);
  return {
    recipeId: recipeId,
    votes: values.length,
    average: Math.round((checksum / values.length) * 10) / 10
  };
}

/* Overall average, kept for observation and reporting — no longer used
 * comme ancrage, voir le commentaire au-dessus de ANCHOR. */
function overallAverage(db) {
  let checksum = 0, n = 0;
  Object.values(db.ratings).forEach(function (byAccount) {
    Object.values(byAccount).forEach(function (x) { checksum += x.rating; n++; });
  });
  return n ? checksum / n : 3.5;
}

/* Le ranking. Retourne des identifiants et des scores; c'est l'appelant
 * that fetches the recipe content — the ranking knows nothing about
 * recettes, seulement les votes. */
function ranking(limit) {
  const db = read();
  const out = [];

  Object.keys(db.ratings).forEach(function (recipeId) {
    const a = aggregate(recipeId, db);
    if (a.votes < MIN_VOTES) return;
    const checksum = Object.values(db.ratings[recipeId]).reduce((s, x) => s + x.rating, 0);
    /* Bayesian average: (weight * anchor + total) / (weight + votes) */
    const score = (WEIGHT * ANCHOR + checksum) / (WEIGHT + a.votes);
    out.push({
      recipeId: recipeId,
      votes: a.votes,
      average: a.average,
      score: Math.round(score * 1000) / 1000
    });
  });

  out.sort(function (a, b) {
    if (b.score !== a.score) return b.score - a.score;
    if (b.votes !== a.votes) return b.votes - a.votes;
    return a.recipeId < b.recipeId ? -1 : 1;
  });
  return limit ? out.slice(0, limit) : out;
}

/* Summaries for several recipes at once, for list display. */
function aggregates(ids, email) {
  const db = read();
  const out = {};
  (ids || []).forEach(function (id) {
    const a = aggregate(id, db);
    if (email) a.myRating = ratingBy(id, email, db);
    out[id] = a;
  });
  return out;
}

/* Combien de recettes approchent du seuil — utile pour savoir si le
 * ranking va se remplir ou rester vide. */
function progress() {
  const db = read();
  const account = { none: 0, onTheWay: 0, ranked: 0 };
  Object.keys(db.ratings).forEach(function (id) {
    const n = Object.keys(db.ratings[id]).length;
    if (n >= MIN_VOTES) account.ranked++;
    else if (n > 0) account.onTheWay++;
  });
  return account;
}

module.exports = {
  MIN_VOTES: MIN_VOTES, WEIGHT: WEIGHT, ANCHOR: ANCHOR,
  rate: rate, removeRating: removeRating, ratingBy: ratingBy,
  aggregate: aggregate, aggregates: aggregates, ranking: ranking,
  overallAverage: overallAverage, progress: progress
};
