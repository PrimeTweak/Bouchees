/* Ingredient normaliser
 * Transforme une ligne brute (« 2 cups all-purpose flour », « 1/2 tasse de
 * unsweetened applesauce") into a canonical catalogue ingredient.
 * Deterministic: versioned lexicon, no model. Anything the lexicon does not
 * recognise comes out as status "unknown" -> quarantine, never guessed.
 * L'IA peut PROPOSER de nouveaux alias; un humain les valide dans le
 * lexicon. « L'IA propose, le lexicon dispose. »
 */
"use strict";

const FRACTIONS = { "\u00bd": 0.5, "\u2153": 1 / 3, "\u2154": 2 / 3, "\u00bc": 0.25, "\u00be": 0.75, "\u215b": 0.125 };

function sansAccents(t) {
  return t.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

function nettoyer(t) {
  return sansAccents(String(t).toLowerCase())
    .replace(/\(.*?\)/g, " ")
    .replace(/['\u2019\u2013\u2014-]/g, " ")
    .replace(/[,;.!]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/* Pulls the quantity from the start of the line: 2, 1/2, 1 1/2, one-half, 1.5. */
function extraireQuantite(texte) {
  let t = texte, qty = null;
  const mFrac = t.match(/^([0-9]+)?\s*([\u00bd\u2153\u2154\u00bc\u00be\u215b])\s*/);
  if (mFrac) {
    qty = (mFrac[1] ? parseInt(mFrac[1], 10) : 0) + FRACTIONS[mFrac[2]];
    t = t.slice(mFrac[0].length);
  } else {
    const mMixte = t.match(/^([0-9]+)\s+([0-9]+)\s*\/\s*([0-9]+)\s*/);
    const mSimple = t.match(/^([0-9]+)\s*\/\s*([0-9]+)\s*/);
    const mDec = t.match(/^([0-9]+(?:[.,][0-9]+)?)\s*/);
    if (mMixte) { qty = parseInt(mMixte[1], 10) + parseInt(mMixte[2], 10) / parseInt(mMixte[3], 10); t = t.slice(mMixte[0].length); }
    else if (mSimple) { qty = parseInt(mSimple[1], 10) / parseInt(mSimple[2], 10); t = t.slice(mSimple[0].length); }
    else if (mDec) { qty = parseFloat(mDec[1].replace(",", ".")); t = t.slice(mDec[0].length); }
  }
  return { qty: qty, reste: t };
}

/* Pulls the unit from what is left; returns a normalised {unit, factor, type}. */
function extraireUnite(texte, lexicon) {
  const u = lexicon.units;
  const candidats = [];
  Object.keys(u.volume_ml).forEach(function (k) { candidats.push({ cle: k, type: "ml", facteur: u.volume_ml[k] }); });
  Object.keys(u.poids_g).forEach(function (k) { candidats.push({ cle: k, type: "g", facteur: u.poids_g[k] }); });
  u.natural_units.forEach(function (k) { candidats.push({ cle: k, type: "unit", facteur: 1 }); });
  candidats.sort(function (a, b) { return b.cle.length - a.cle.length; });
  for (let i = 0; i < candidats.length; i++) {
    const c = candidats[i];
    const cleNette = nettoyer(c.cle);
    const re = new RegExp("^" + cleNette.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "(\\s+|$)");
    if (re.test(texte)) return { texteRestant: texte.replace(re, ""), unit: c.type, facteur: c.facteur, cleUnite: cleNette };
  }
  return { texteRestant: texte, unit: null, facteur: 1, cleUnite: null };
}

function retirerDescripteurs(texte, lexicon) {
  const stop = new Set(lexicon.descriptors);
  return texte.split(" ").filter(function (mot) { return mot && !stop.has(mot); }).join(" ");
}

/* Builds the alias-to-id index once (keys are already unaccented in the lexicon). */
function construireIndex(lexicon) {
  const index = {};
  Object.keys(lexicon.aliases).forEach(function (id) {
    lexicon.aliases[id].forEach(function (a) {
      index[retirerDescripteurs(nettoyer(a), lexicon)] = id;
    });
  });
  return index;
}

function chercherCanonique(texte, index) {
  if (index[texte]) return { id: index[texte], confidence: "exacte" };
  if (texte.endsWith("s") && index[texte.slice(0, -1)]) return { id: index[texte.slice(0, -1)], confidence: "exacte" };
  /* match on the longest key contained in the text */
  let meilleure = null;
  Object.keys(index).forEach(function (cle) {
    const re = new RegExp("(^|\\s)" + cle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "($|\\s)");
    if (re.test(texte) && (!meilleure || cle.length > meilleure.length)) meilleure = cle;
  });
  if (meilleure) return { id: index[meilleure], confidence: "partielle" };
  return null;
}

/* API principale : normalizeLine("2 cups all-purpose flour", lexicon, catalogue)
 * → { status: "recognized"|"unknown", id?, qty?, unit?, confidence?, originalText } */
function normalizeLine(ligne, lexicon, catalogue, index) {
  index = index || construireIndex(lexicon);
  const original = String(ligne);
  let t = nettoyer(original);
  const q = extraireQuantite(t);
  const u = extraireUnite(q.reste.trim(), lexicon);
  const name = retirerDescripteurs(u.texteRestant.trim(), lexicon);
  const trouve = chercherCanonique(name, index);
  if (!trouve || !catalogue[trouve.id]) {
    return { status: "unknown", originalText: original, texteAnalyse: name };
  }
  let qty = null, unit = null;
  if (q.qty !== null && u.unit === "ml") { qty = Math.round(q.qty * u.facteur * 10) / 10; unit = "ml"; }
  else if (q.qty !== null && u.unit === "g") { qty = Math.round(q.qty * u.facteur * 10) / 10; unit = "g"; }
  else if (q.qty !== null) { qty = q.qty; unit = u.cleUnite || "unité"; }
  return {
    status: "recognized",
    id: trouve.id,
    confidence: trouve.confidence,
    qty: qty,
    unit: unit,
    originalText: original
  };
}

module.exports = { normalizeLine: normalizeLine, construireIndex: construireIndex, nettoyer: nettoyer };
