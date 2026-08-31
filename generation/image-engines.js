/* Moteurs d'image
 *
 *   drawthings — Draw Things' local HTTP API on your Mac (no cost, no data
 *                leaving the machine). AUTOMATIC1111-compatible endpoint.
 *   openai     — OPENAI_API_KEY, if you would rather pay per image
 *   simule     — offline: writes a tiny but valid PNG so the whole cycle can
 *                be tested with no network
 *
 * Chaque adaptateur retourne { octets, largeur, hauteur, moteur }.
 */
"use strict";
const zlib = require("zlib");
const crypto = require("crypto");

/* Reads the real dimensions out of the image header. No dependency: PNG,
 * JPEG and WebP all state their size in the first bytes. */
function tailleImage(buf) {
  if (!buf || buf.length < 32) return null;

  /* PNG: IHDR at byte 16, width and height as big-endian 32-bit */
  if (buf[0] === 0x89 && buf.toString("ascii", 1, 4) === "PNG") {
    return { largeur: buf.readUInt32BE(16), hauteur: buf.readUInt32BE(20) };
  }

  /* WebP: "RIFF" .... "WEBP" */
  if (buf.toString("ascii", 0, 4) === "RIFF" && buf.toString("ascii", 8, 12) === "WEBP") {
    const type = buf.toString("ascii", 12, 16);
    if (type === "VP8X") return { largeur: buf.readUIntLE(24, 3) + 1, hauteur: buf.readUIntLE(27, 3) + 1 };
    if (type === "VP8 ") return { largeur: buf.readUInt16LE(26) & 0x3fff, hauteur: buf.readUInt16LE(28) & 0x3fff };
    if (type === "VP8L") {
      const b = buf.readUInt32LE(21);
      return { largeur: (b & 0x3fff) + 1, hauteur: ((b >> 14) & 0x3fff) + 1 };
    }
    return null;
  }

  /* JPEG: walk the segments to the first SOF marker */
  if (buf[0] === 0xff && buf[1] === 0xd8) {
    let i = 2;
    while (i < buf.length - 9) {
      if (buf[i] !== 0xff) { i++; continue; }
      const marqueur = buf[i + 1];
      if (marqueur >= 0xc0 && marqueur <= 0xcf && marqueur !== 0xc4 && marqueur !== 0xc8 && marqueur !== 0xcc) {
        return { hauteur: buf.readUInt16BE(i + 5), largeur: buf.readUInt16BE(i + 7) };
      }
      i += 2 + buf.readUInt16BE(i + 2);
    }
  }
  return null;
}

const drawthings = {
  name: "drawthings",
  disponible: function () { return !!(process.env.DRAWTHINGS_URL || process.env.DRAWTHINGS_ACTIF); },
  generer: async function (spec) {
    const base = process.env.DRAWTHINGS_URL || "http://127.0.0.1:7860";
    /* SEND THE PROMPT AND THE SIZE. NOTHING ELSE.
     *
     * Draw Things knows what its own model needs — "Try recommended settings"
     * fills them in. For FLUX.1 schnell that is 4 steps, Euler A Trailing,
     * guidance 4.5. I was overriding all three from here with SDXL values
     * (30 steps, DPM++ 2M Karras, cfg 6), and a distilled 4-step model driven
     * by an SDXL solver never finishes denoising. The result is the embossed
     * anaglyph, every time.
     *
     * So: steps, sampler and guidance are no longer sent. Whatever is set in
     * the app is what runs, which is the configuration that works. The three
     * environment variables still exist for a deliberate override, but they
     * are off by default now. */
    const corps = Object.assign({
      prompt: spec.prompt,
      width: spec.largeur || Number(process.env.DRAWTHINGS_LARGEUR || 1408),
      height: spec.hauteur || Number(process.env.DRAWTHINGS_HAUTEUR || 1408)
    },
      /* NO negative_prompt on FLUX.
       *
       * Proven by isolation: same transport, same prompt, same size. With the
       * negative prompt the response is an embossed relief; without it the
       * photo is clean. FLUX schnell is distilled without negative guidance,
       * and Draw Things ends up SUBTRACTING the negative instead of steering
       * away from it.
       *
       * Set DRAWTHINGS_NEGATIF=1 to send it on a model that supports one
       * (SDXL does). Off by default. */
      process.env.DRAWTHINGS_NEGATIF && spec.negatif ? { negative_prompt: spec.negatif } : {},
      process.env.DRAWTHINGS_ETAPES ? { steps: Number(process.env.DRAWTHINGS_ETAPES) } : {},
      process.env.DRAWTHINGS_CFG ? { cfg_scale: Number(process.env.DRAWTHINGS_CFG) } : {},
      process.env.DRAWTHINGS_SAMPLER ? { sampler_name: process.env.DRAWTHINGS_SAMPLER } : {},
      spec.graine !== undefined ? { seed: spec.graine } : {},
      /* NAME THE MODEL, OPTIONALLY.
       *
       * Steps and sampler still come from the app — that lesson holds: an
       * SDXL solver on a distilled model produces the embossed anaglyph.
       * But WHICH model is a different question, and leaving it to whatever
       * happened to be selected is how a batch ran on Krea 2 Raw at 52 steps.
       *
       * MEASURED CAVEAT: Draw Things implements txt2img and img2img and
       * skips the introspection endpoints AUTOMATIC1111 exposes. There is no
       * published confirmation that it honours override_settings either, so
       * this may be ignored silently. The preflight reads the model actually
       * loaded and refuses Raw regardless, which is the check that holds.
       *
       * Set DRAWTHINGS_MODELE to pin it. Unset, nothing changes. */
      process.env.DRAWTHINGS_MODELE
        ? { override_settings: { sd_model_checkpoint: process.env.DRAWTHINGS_MODELE } }
        : {}
    );

    if (process.env.DRAWTHINGS_TRACE) {
      console.log("\n--- request sent to " + base + "/sdapi/v1/txt2img ---");
      console.log(JSON.stringify(corps, null, 2));
      console.log("--- end of request ---\n");
    }

    /* Noted before the request so only a file written afterwards counts. */
    const avant = Date.now();

    const rep = await fetch(base + "/sdapi/v1/txt2img", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(corps)
    });
    const d = await rep.json();
    if (!rep.ok || !d.images || !d.images.length) {
      const detail = d.errors || d.detail || d.error || rep.status;
      throw new Error("Draw Things refused the request: " +
        (typeof detail === "string" ? detail : JSON.stringify(detail)) +
        "  (asked for " + (spec.largeur || 1664) + "x" + (spec.hauteur || 1104) +
        ", " + Number(process.env.DRAWTHINGS_ETAPES || 8) + " steps" +
        (process.env.DRAWTHINGS_CFG ? ", cfg " + process.env.DRAWTHINGS_CFG : "") +
        (process.env.DRAWTHINGS_SAMPLER ? ", sampler " + process.env.DRAWTHINGS_SAMPLER : "") + ")");
    }
    /* THE IMAGE COMES FROM THE FOLDER, NOT FROM THE RESPONSE.
     *
     * Measured, watching the app while the cycle runs: Draw Things renders a
     * clean photo on screen and returns an embossed relief over the API. Same
     * generation, two different results. Nothing in the request changes it —
     * prompt, negative prompt, steps, sampler and size were each isolated and
     * ruled out.
     *
     * The app writes the real image itself, through its "Save Generated Media
     * to" setting. Reading that file is not a workaround: it is the only way
     * to obtain what was actually generated.
     *
     * DRAWTHINGS_DOSSIER points at that folder. Unset, the API response is
     * used as before — so a build where the API behaves is unaffected. */
    let octets = Buffer.from(d.images[0], "base64");

    const dossierApp = process.env.DRAWTHINGS_DOSSIER;
    if (dossierApp) {
      const fsApp = require("fs");
      const pathApp = require("path");

      /* The app writes its file AFTER answering, so we wait for one to appear
       * that is newer than the moment the request went out. Matching on the
       * name is brittle — the app names files after the prompt — but a
       * timestamp is not. */
      function plusRecent() {
        let trouve = null;
        fsApp.readdirSync(dossierApp)
          .filter(function (f) { return /\.(png|jpe?g|webp)$/i.test(f); })
          .forEach(function (f) {
            const st = fsApp.statSync(pathApp.join(dossierApp, f));
            if (st.mtimeMs <= avant) return;
            if (!trouve || st.mtimeMs > trouve.t) trouve = { f: f, t: st.mtimeMs, taille: st.size };
          });
        return trouve;
      }

      let recent = null;
      const limite = Date.now() + 8 * 60 * 1000;   /* a large image can take minutes */
      while (Date.now() < limite) {
        try { recent = plusRecent(); }
        catch (e) {
          throw new Error("DRAWTHINGS_DOSSIER points at " + dossierApp +
            " which cannot be read: " + e.message);
        }
        /* Wait for the size to settle: a file caught mid-write is truncated. */
        if (recent) {
          await new Promise(function (r) { setTimeout(r, 1500); });
          const st = fsApp.statSync(pathApp.join(dossierApp, recent.f));
          if (st.size === recent.taille && st.size > 0) break;
          recent = null;
        }
        await new Promise(function (r) { setTimeout(r, 1000); });
      }

      if (!recent) {
        throw new Error("no new image appeared in " + dossierApp + " — check that " +
          "Save Generated Media is enabled in Draw Things and points there");
      }
      octets = fsApp.readFileSync(pathApp.join(dossierApp, recent.f));
      if (process.env.DRAWTHINGS_TRACE) console.log("      taken from " + recent.f);
    }

    /* Read the size FROM THE PNG, never from what we asked for.
     *
     * Draw Things silently clamps to whatever the selected model and the
     * machine allow. Recording the requested size meant the manifest claimed
     * 1664 px while the file on disk was far smaller — and the size gate,
     * reading the manifest, waved it through. Measure the artifact. */
    const reelle = tailleImage(octets);
    const demandee = { largeur: spec.largeur || Number(process.env.DRAWTHINGS_LARGEUR || 1408),
                       hauteur: spec.hauteur || Number(process.env.DRAWTHINGS_HAUTEUR || 1408) };
    if (reelle && reelle.largeur < demandee.largeur) {
      console.log("      Draw Things returned " + reelle.largeur + "x" + reelle.hauteur +
                  " for a request of " + demandee.largeur + "x" + demandee.hauteur +
                  " — the model or the app is clamping the size");
    }
    return { octets: octets,
             largeur: reelle ? reelle.largeur : demandee.largeur,
             hauteur: reelle ? reelle.hauteur : demandee.hauteur,
             moteur: "drawthings" };
  }
};

const openai = {
  name: "openai",
  disponible: function () { return !!process.env.OPENAI_API_KEY; },
  generer: async function (spec) {
    /* Image models have no negative field: it is folded
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

/* A valid PNG built with no dependency: colour bands derived from the prompt.
 * This is not a recipe photo — it is a real file so the rest of the cycle
 * (writing, fingerprint, manifest, publishing) is genuinely tested. */
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
