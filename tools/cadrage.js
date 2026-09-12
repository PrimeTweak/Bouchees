"use strict";
/* Where the dish sits in a square photo, as a fraction of the height.
 * The subject is the sharp, saturated part; the background is blurred and
 * dull. The hero shows the square under a title that covers its lower
 * 45 per cent, so a dish that ends too low is cut. */

const fs = require("fs");
const Thumbs = require("./thumbs.js");

/* 0.70 of the peak keeps the dish and drops the faint texture of the cloth
 * around it — the veil covers that without harm. */
const SEUIL_COEUR = 0.70;
/* 0.55, not 0.35: a blurred counter edge or a bright window reaches a third
 * of the peak and was read as the start of the dish — the white bean stew
 * measured 0.146 while its bowl actually begins at 0.50. */
const SEUIL_SUJET = 0.55;

/* Where the subject may start, as a fraction of the height. Set from two
 * photos judged good (0.202, 0.343) and two judged bad (0.495, 0.551);
 * 0.45 separates them: the white bean stew, judged bad, measures 0.495. */
const DEPART_MAX = 0.45;

function profil(chemin) {
  const img = Thumbs.scale(Thumbs.decode(fs.readFileSync(chemin)), 200);
  const w = img.width, h = img.height, c = img.channels, px = img.px;
  const lignes = [];
  for (let y = 1; y < h - 1; y++) {
    let net = 0, sat = 0, n = 0;
    for (let x = 1; x < w - 1; x++) {
      const i = (y * w + x) * c;
      const g = (px[i] + px[i + 1] + px[i + 2]) / 3;
      const gx = (px[i + c] + px[i + c + 1] + px[i + c + 2]) / 3;
      const gy = (px[i + w * c] + px[i + w * c + 1] + px[i + w * c + 2]) / 3;
      net += Math.abs(g - gx) + Math.abs(g - gy);
      sat += Math.max(px[i], px[i + 1], px[i + 2]) - Math.min(px[i], px[i + 1], px[i + 2]);
      n++;
    }
    lignes.push((net / n) * (sat / n + 8));
  }
  return lignes;
}

function bornes(lignes, fraction) {
  const max = Math.max.apply(null, lignes), seuil = max * fraction;
  const dedans = lignes.map(function (v) { return v >= seuil; });
  const haut = dedans.indexOf(true), bas = dedans.lastIndexOf(true);
  return { haut: haut / lignes.length, bas: bas / lignes.length };
}

/* haut/bas of the whole subject, and of its dense core. */
function mesurer(chemin) {
  const lignes = profil(chemin);
  const sujet = bornes(lignes, SEUIL_SUJET);
  const coeur = bornes(lignes, SEUIL_COEUR);
  return {
    sujetHaut: +sujet.haut.toFixed(3), sujetBas: +sujet.bas.toFixed(3),
    coeurHaut: +coeur.haut.toFixed(3), coeurBas: +coeur.bas.toFixed(3)
  };
}

/* True when the dish starts too low: it then sits inside the band the
 * title covers, and the hero shows a bowl rim and a counter. */
function tropBas(chemin) { return mesurer(chemin).sujetHaut >= DEPART_MAX; }

module.exports = { mesurer, tropBas, profil, bornes, DEPART_MAX };
