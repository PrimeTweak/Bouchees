/* Normaliseur d'ingrédients — lot 3, v0.2
 * Transforme une ligne brute (« 2 cups all-purpose flour », « 1/2 tasse de
 * compote de pommes non sucrée ») en ingrédient canonique du catalogue.
 * Déterministe : lexique versionné, zéro modèle. Ce que le lexique ne
 * reconnaît pas sort en statut « inconnu » → quarantaine, jamais deviné.
 * L'IA peut PROPOSER de nouveaux alias; un humain les valide dans le
 * lexique. « L'IA propose, le lexique dispose. »
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

/* Extrait la quantité en tête de ligne : « 2 », « 1/2 », « 1 1/2 », « ½ », « 1,5 ». */
function extraireQuantite(texte) {
  let t = texte, qte = null;
  const mFrac = t.match(/^([0-9]+)?\s*([\u00bd\u2153\u2154\u00bc\u00be\u215b])\s*/);
  if (mFrac) {
    qte = (mFrac[1] ? parseInt(mFrac[1], 10) : 0) + FRACTIONS[mFrac[2]];
    t = t.slice(mFrac[0].length);
  } else {
    const mMixte = t.match(/^([0-9]+)\s+([0-9]+)\s*\/\s*([0-9]+)\s*/);
    const mSimple = t.match(/^([0-9]+)\s*\/\s*([0-9]+)\s*/);
    const mDec = t.match(/^([0-9]+(?:[.,][0-9]+)?)\s*/);
    if (mMixte) { qte = parseInt(mMixte[1], 10) + parseInt(mMixte[2], 10) / parseInt(mMixte[3], 10); t = t.slice(mMixte[0].length); }
    else if (mSimple) { qte = parseInt(mSimple[1], 10) / parseInt(mSimple[2], 10); t = t.slice(mSimple[0].length); }
    else if (mDec) { qte = parseFloat(mDec[1].replace(",", ".")); t = t.slice(mDec[0].length); }
  }
  return { qte: qte, reste: t };
}

/* Extrait l'unité au début du reste; retourne {unite, facteur, type} normalisés. */
function extraireUnite(texte, lexique) {
  const u = lexique.unites;
  const candidats = [];
  Object.keys(u.volume_ml).forEach(function (k) { candidats.push({ cle: k, type: "ml", facteur: u.volume_ml[k] }); });
  Object.keys(u.poids_g).forEach(function (k) { candidats.push({ cle: k, type: "g", facteur: u.poids_g[k] }); });
  u.unites_naturelles.forEach(function (k) { candidats.push({ cle: k, type: "unite", facteur: 1 }); });
  candidats.sort(function (a, b) { return b.cle.length - a.cle.length; });
  for (let i = 0; i < candidats.length; i++) {
    const c = candidats[i];
    const cleNette = nettoyer(c.cle);
    const re = new RegExp("^" + cleNette.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "(\\s+|$)");
    if (re.test(texte)) return { texteRestant: texte.replace(re, ""), unite: c.type, facteur: c.facteur, cleUnite: cleNette };
  }
  return { texteRestant: texte, unite: null, facteur: 1, cleUnite: null };
}

function retirerDescripteurs(texte, lexique) {
  const stop = new Set(lexique.descripteurs);
  return texte.split(" ").filter(function (mot) { return mot && !stop.has(mot); }).join(" ");
}

/* Construit l'index alias→id une seule fois (clés déjà sans accents dans le lexique). */
function construireIndex(lexique) {
  const index = {};
  Object.keys(lexique.alias).forEach(function (id) {
    lexique.alias[id].forEach(function (a) {
      index[retirerDescripteurs(nettoyer(a), lexique)] = id;
    });
  });
  return index;
}

function chercherCanonique(texte, index) {
  if (index[texte]) return { id: index[texte], confiance: "exacte" };
  if (texte.endsWith("s") && index[texte.slice(0, -1)]) return { id: index[texte.slice(0, -1)], confiance: "exacte" };
  /* correspondance par la clé la plus longue contenue dans le texte */
  let meilleure = null;
  Object.keys(index).forEach(function (cle) {
    const re = new RegExp("(^|\\s)" + cle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "($|\\s)");
    if (re.test(texte) && (!meilleure || cle.length > meilleure.length)) meilleure = cle;
  });
  if (meilleure) return { id: index[meilleure], confiance: "partielle" };
  return null;
}

/* API principale : normaliserLigne("2 cups all-purpose flour", lexique, catalogue)
 * → { statut: "reconnu"|"inconnu", id?, qte?, unite?, confiance?, texteOriginal } */
function normaliserLigne(ligne, lexique, catalogue, index) {
  index = index || construireIndex(lexique);
  const original = String(ligne);
  let t = nettoyer(original);
  const q = extraireQuantite(t);
  const u = extraireUnite(q.reste.trim(), lexique);
  const nom = retirerDescripteurs(u.texteRestant.trim(), lexique);
  const trouve = chercherCanonique(nom, index);
  if (!trouve || !catalogue[trouve.id]) {
    return { statut: "inconnu", texteOriginal: original, texteAnalyse: nom };
  }
  let qte = null, unite = null;
  if (q.qte !== null && u.unite === "ml") { qte = Math.round(q.qte * u.facteur * 10) / 10; unite = "ml"; }
  else if (q.qte !== null && u.unite === "g") { qte = Math.round(q.qte * u.facteur * 10) / 10; unite = "g"; }
  else if (q.qte !== null) { qte = q.qte; unite = u.cleUnite || "unité"; }
  return {
    statut: "reconnu",
    id: trouve.id,
    confiance: trouve.confiance,
    qte: qte,
    unite: unite,
    texteOriginal: original
  };
}

module.exports = { normaliserLigne: normaliserLigne, construireIndex: construireIndex, nettoyer: nettoyer };
