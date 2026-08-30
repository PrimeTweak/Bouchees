/* Barcode normalisation.
 *
 * Pure arithmetic — no network, no state, fully testable offline. That
 * matters, because this is where a scan silently failed: the camera reads a
 * compressed UPC-E and we sent it to a database that stores the long form.
 *
 * François's beer, 7697600153, is in Open Food Facts. We asked for a key that
 * does not exist.
 */
"use strict";

/* UPC-E packs a 12-digit UPC-A into 6 by dropping runs of zeros. The last
 * digit of the compressed form says which run was dropped, so expanding is a
 * lookup, not a guess. */
function expandUPCE(code) {
  var c = String(code).replace(/\D/g, "");

  /* Accept 6, 7 or 8 digits: bare payload, with number system, or with both
   * number system and check digit. */
  var systeme = "0";
  var corps;
  if (c.length === 6) {
    corps = c;
  } else if (c.length === 7) {
    systeme = c[0];
    corps = c.slice(1);
  } else if (c.length === 8) {
    systeme = c[0];
    corps = c.slice(1, 7);
  } else {
    return null;
  }
  if (systeme !== "0" && systeme !== "1") return null;

  var d = corps.split("");
  var dernier = d[5];
  var milieu;

  if (dernier === "0" || dernier === "1" || dernier === "2") {
    milieu = d[0] + d[1] + dernier + "0000" + d[2] + d[3] + d[4];
  } else if (dernier === "3") {
    milieu = d[0] + d[1] + d[2] + "00000" + d[3] + d[4];
  } else if (dernier === "4") {
    milieu = d[0] + d[1] + d[2] + d[3] + "00000" + d[4];
  } else {
    milieu = d[0] + d[1] + d[2] + d[3] + d[4] + "0000" + dernier;
  }

  var onze = systeme + milieu;
  return onze + checkDigit(onze);
}

/* The standard modulo-10 check digit, for any length. */
function checkDigit(partiel) {
  var somme = 0;
  var chiffres = String(partiel).split("").reverse();
  for (var i = 0; i < chiffres.length; i++) {
    var n = parseInt(chiffres[i], 10);
    somme += (i % 2 === 0) ? n * 3 : n;
  }
  return String((10 - (somme % 10)) % 10);
}

/* Every form of a code worth trying, most likely first, no duplicates.
 *
 * Open Food Facts indexes mostly in EAN-13. A North American UPC-A is the
 * same product with a leading zero — two different keys for one barcode, and
 * we only ever tried one of them. */
function formes(brut) {
  var c = String(brut || "").replace(/\D/g, "");
  if (!c) return [];

  var out = [c];

  /* UPC-E expands to UPC-A, which pads to EAN-13. */
  if (c.length === 6 || c.length === 7 || c.length === 8) {
    var upca = expandUPCE(c);
    if (upca) {
      out.push(upca);
      out.push("0" + upca);
    }
  }

  /* UPC-A pads to EAN-13. */
  if (c.length === 12) out.push("0" + c);

  /* EAN-13 with a leading zero IS a UPC-A. */
  if (c.length === 13 && c[0] === "0") out.push(c.slice(1));

  /* ITF-14 wraps an EAN-13: drop the packaging indicator and the check. */
  if (c.length === 14) {
    var interieur = c.slice(1, 13);
    out.push(interieur + checkDigit(interieur));
    out.push(c.slice(1));
  }

  return out.filter(function (v, i, a) { return v && a.indexOf(v) === i; });
}

module.exports = { formes: formes, expandUPCE: expandUPCE, checkDigit: checkDigit };
