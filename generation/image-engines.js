/* Moteurs d'image
 *
 *   drawthings — l'API HTTP locale de Draw Things sur ton Mac (aucun coût,
 *                aucune donnée qui sort). Endpoint compatible AUTOMATIC1111.
 *   openai     — OPENAI_API_KEY, si tu préfères payer à l'image
 *   simule     — hors ligne : écrit un PNG minuscule mais valide, pour que le
 *                cycle complet soit testable sans réseau
 *
 * Chaque adaptateur retourne { octets, largeur, hauteur, moteur }.
 */
"use strict";
const zlib = require("zlib");
const crypto = require("crypto");

const drawthings = {
  name: "drawthings",
  disponible: function () { return !!(process.env.DRAWTHINGS_URL || process.env.DRAWTHINGS_ACTIF); },
  generer: async function (spec) {
    const base = process.env.DRAWTHINGS_URL || "http://127.0.0.1:7860";
    const rep = await fetch(base + "/sdapi/v1/txt2img", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        prompt: spec.prompt,
        negative_prompt: spec.negatif,
        width: spec.largeur || Number(process.env.DRAWTHINGS_LARGEUR || 1216),
        height: spec.hauteur || Number(process.env.DRAWTHINGS_HAUTEUR || 832),
        steps: Number(process.env.DRAWTHINGS_ETAPES || 30),
        cfg_scale: Number(process.env.DRAWTHINGS_CFG || 6),
        seed: spec.graine === undefined ? -1 : spec.graine,
        sampler_name: process.env.DRAWTHINGS_SAMPLER || "DPM++ 2M Karras"
      })
    });
    const d = await rep.json();
    if (!rep.ok || !d.images || !d.images.length) {
      throw new Error("Draw Things a refusé : " + (d.error || rep.status) +
        " — vérifie que l'API HTTP est activée dans les réglages de l'app");
    }
    return { octets: Buffer.from(d.images[0], "base64"),
             largeur: spec.largeur || Number(process.env.DRAWTHINGS_LARGEUR || 1216),
             hauteur: spec.hauteur || Number(process.env.DRAWTHINGS_HAUTEUR || 832),
             moteur: "drawthings" };
  }
};

const openai = {
  name: "openai",
  disponible: function () { return !!process.env.OPENAI_API_KEY; },
  generer: async function (spec) {
    /* Les modèles d'image n'ont pas de champ « négatif » : on le replie
     * dans le prompt, en formulation positive quand c'est possible. */
    const rep = await fetch("https://api.openai.com/v1/images/generations", {
      method: "POST",
      headers: { Authorization: "Bearer " + process.env.OPENAI_API_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: process.env.MODELE_IMAGE || "gpt-image-1",
        prompt: spec.prompt + ". Contraintes strictes : " + spec.negatif,
        size: "1024x1024"
      })
    });
    const d = await rep.json();
    if (!rep.ok || !d.data || !d.data.length) throw new Error(d.error && d.error.message || "réponse " + rep.status);
    return { octets: Buffer.from(d.data[0].b64_json, "base64"), largeur: 1024, hauteur: 1024, moteur: "openai" };
  }
};

/* PNG valide, généré sans dépendance : bandes de couleur dérivées du prompt.
 * Ce n'est pas une image de recette — c'est un fichier réel pour que le reste
 * du cycle (écriture, empreinte, manifeste, publication) soit testé pour vrai. */
function pngSimple(largeur, hauteur, couleurs) {
  const lignes = [];
  for (let y = 0; y < hauteur; y++) {
    const c = couleurs[Math.floor(y / hauteur * couleurs.length)] || [200, 200, 200];
    const ligne = Buffer.alloc(1 + largeur * 3);
    for (let x = 0; x < largeur; x++) {
      ligne[1 + x * 3] = c[0]; ligne[2 + x * 3] = c[1]; ligne[3 + x * 3] = c[2];
    }
    lignes.push(ligne);
  }
  const brut = zlib.deflateSync(Buffer.concat(lignes));
  const morceau = function (type, data) {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const corps = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(corps) >>> 0);
    return Buffer.concat([len, corps, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(largeur, 0); ihdr.writeUInt32BE(hauteur, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    morceau("IHDR", ihdr), morceau("IDAT", brut), morceau("IEND", Buffer.alloc(0))
  ]);
}
let TABLE_CRC = null;
function crc32(buf) {
  if (!TABLE_CRC) {
    TABLE_CRC = [];
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      TABLE_CRC[n] = c >>> 0;
    }
  }
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = TABLE_CRC[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

const simule = {
  name: "simule",
  disponible: function () { return true; },
  generer: async function (spec) {
    const h = crypto.createHash("sha1").update(spec.prompt).digest();
    const couleurs = [[h[0], h[1], h[2]], [h[3], h[4], h[5]], [h[6], h[7], h[8]]];
    return { octets: pngSimple(spec.largeur || 1024, spec.hauteur || 768, couleurs),
             largeur: spec.largeur || 1024, hauteur: spec.hauteur || 768, moteur: "simule" };
  }
};

const MOTEURS = { drawthings: drawthings, openai: openai, simule: simule };

function choisir(name) {
  const target = name || process.env.MOTEUR_IMAGE || "";
  if (target && MOTEURS[target]) return MOTEURS[target];
  if (drawthings.disponible()) return drawthings;
  if (openai.disponible()) return openai;
  return simule;
}

module.exports = { choisir: choisir, MOTEURS: MOTEURS, pngSimple: pngSimple };
