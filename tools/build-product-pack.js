"use strict";
/*
 * BUILD THE OFFLINE PRODUCT PACK.
 *
 * Two sources, two files, never merged. That separation is not tidiness — it
 * is the licence.
 *
 *   United States  USDA FoodData Central, Branded Foods.
 *                  Public domain, CC0 1.0. No permission needed. USDA asks,
 *                  as a courtesy, to be named as the source.
 *
 *   Canada         Open Food Facts, filtered on Canada.
 *                  ODbL. Attribution and share-alike.
 *
 * The ODbL treats a collection of otherwise independent databases as a
 * COLLECTIVE database, which is explicitly not a derivative one, and its
 * share-alike reaches only the part that came from them. Fusing their text
 * into our catalogue, or into the American file, would make one derivative
 * database out of three sources and pull everything else in with it.
 *
 * So: one file per source, one source per file, and a checker that refuses a
 * pack where a record sits in the wrong one.
 *
 * THE PACK IS DUMB ON PURPOSE. It carries the ingredient text as printed and
 * derives nothing. The allergens are worked out at run time, by our own
 * catalogue, against the child in front of the phone. Precomputing them here
 * would freeze the reading at build time — and a frozen reading on a safety
 * path is worse than a large file.
 *
 * Usage:
 *   node tools/build-product-pack.js --usda <branded_food.csv> --off <products.jsonl.gz>
 *
 * Either source may be omitted; the pack is then built from the other one.
 */

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const readline = require("readline");

const root = path.join(__dirname, "..");
const outDir = path.join(root, "pack");

/* Open Food Facts asks every caller to identify itself. The same courtesy
 * applies to a bulk download. */
const UA = process.env.OFF_USER_AGENT ||
           "Bouchees/1.0 (https://bouchees.onrender.com)";

/* ------------------------------------------------------------------ barcode */

/* One key per product, so a lookup never has to guess which form was printed.
 * A North American UPC-A is an EAN-13 with a leading zero; both are stored
 * pointing at the same record, and the scanner can hand over either. */
function normalise(code) {
  const chiffres = String(code || "").replace(/[^0-9]/g, "");
  if (chiffres.length < 8 || chiffres.length > 14) return null;
  /* Strip leading zeros down to 13, the form Open Food Facts indexes. */
  let n = chiffres;
  while (n.length > 13 && n[0] === "0") n = n.slice(1);
  if (n.length === 12) n = "0" + n;
  return n;
}

/* --------------------------------------------------------------- CSV reader */

/* USDA ships CSV with quoted fields that contain commas and doubled quotes.
 * A split on "," loses half the ingredient statements, which are exactly the
 * field this pack exists for. */
function parseCSVLine(ligne) {
  const out = [];
  let champ = "";
  let dansGuillemets = false;
  for (let i = 0; i < ligne.length; i++) {
    const c = ligne[i];
    if (dansGuillemets) {
      if (c === '"') {
        if (ligne[i + 1] === '"') { champ += '"'; i++; }
        else dansGuillemets = false;
      } else champ += c;
    } else if (c === '"') {
      dansGuillemets = true;
    } else if (c === ",") {
      out.push(champ); champ = "";
    } else champ += c;
  }
  out.push(champ);
  return out;
}

/* ------------------------------------------------------------------ sources */

async function lireUSDA(fichier, ecrire) {
  const flux = readline.createInterface({
    input: fs.createReadStream(fichier),
    crlfDelay: Infinity
  });

  let entetes = null;
  let col = {};
  let lus = 0, gardes = 0, sansIngredients = 0;

  for await (const ligne of flux) {
    if (!ligne.trim()) continue;
    if (!entetes) {
      entetes = parseCSVLine(ligne).map(function (h) {
        return h.trim().toLowerCase().replace(/^\ufeff/, "");
      });
      col = {
        code: entetes.indexOf("gtin_upc"),
        marque: entetes.indexOf("brand_owner"),
        nom: entetes.indexOf("description"),
        ingredients: entetes.indexOf("ingredients")
      };
      if (col.code < 0 || col.ingredients < 0) {
        throw new Error("USDA CSV is missing gtin_upc or ingredients. " +
                        "Columns seen: " + entetes.slice(0, 12).join(", "));
      }
      continue;
    }

    lus++;
    const champs = parseCSVLine(ligne);
    const code = normalise(champs[col.code]);
    if (!code) continue;

    const texte = (champs[col.ingredients] || "").trim();
    if (!texte) { sansIngredients++; continue; }

    ecrire({
      c: code,
      n: (champs[col.nom] || "").trim() || null,
      b: col.marque >= 0 ? (champs[col.marque] || "").trim() || null : null,
      i: texte,
      s: "us"
    });
    gardes++;
  }

  return { lus: lus, gardes: gardes, sansIngredients: sansIngredients };
}

async function lireOFF(fichier, ecrire) {
  const brut = fs.createReadStream(fichier);
  const source = fichier.endsWith(".gz") ? brut.pipe(zlib.createGunzip()) : brut;
  const flux = readline.createInterface({ input: source, crlfDelay: Infinity });

  let lus = 0, canadiens = 0, gardes = 0, sansIngredients = 0;

  for await (const ligne of flux) {
    if (!ligne.trim()) continue;
    lus++;

    let p;
    try { p = JSON.parse(ligne); } catch (e) { continue; }

    /* The country tags carry the markets a product is sold in. */
    const pays = [].concat(p.countries_tags || []);
    if (pays.indexOf("en:canada") < 0) continue;
    canadiens++;

    const code = normalise(p.code);
    if (!code) continue;

    const texte = (p.ingredients_text_fr || p.ingredients_text || "").trim();
    if (!texte) { sansIngredients++; continue; }

    ecrire({
      c: code,
      n: (p.product_name_fr || p.product_name || "").trim() || null,
      b: (p.brands || "").trim() || null,
      i: texte,
      /* Kept as INDICATIVE only. Every verdict is re-derived from `i` by our
       * own catalogue; these tags are never the answer on their own. */
      a: p.allergens_tags || [],
      t: p.traces_tags || [],
      s: "ca"
    });
    gardes++;
  }

  return { lus: lus, canadiens: canadiens, gardes: gardes,
           sansIngredients: sansIngredients };
}

/* -------------------------------------------------------------------- write */

function sortie(nom) {
  const gz = zlib.createGzip({ level: 9 });
  const fichier = fs.createWriteStream(path.join(outDir, nom));
  gz.pipe(fichier);
  return {
    ecrire: function (rec) { gz.write(JSON.stringify(rec) + "\n"); },
    fermer: function () {
      return new Promise(function (res) {
        fichier.on("close", res);
        gz.end();
      });
    }
  };
}

/* --------------------------------------------------------------------- main */

async function main() {
  const args = process.argv.slice(2);
  function opt(nom) {
    const i = args.indexOf(nom);
    return i >= 0 ? args[i + 1] : null;
  }
  const fUSDA = opt("--usda");
  const fOFF = opt("--off");

  if (!fUSDA && !fOFF) {
    console.log("");
    console.log("  Rien à lire.");
    console.log("");
    console.log("  node tools/build-product-pack.js --usda <fichier.csv> --off <fichier.jsonl.gz>");
    console.log("");
    process.exit(1);
  }

  fs.mkdirSync(outDir, { recursive: true });

  const manifeste = {
    built: new Date().toISOString().slice(0, 10),
    userAgent: UA,
    files: {},
    /* The notices travel WITH the data. A pack that gets copied somewhere
     * else still says where each half came from and under what terms. */
    notices: {
      us: "Data from USDA FoodData Central, Branded Foods. Public domain, " +
          "CC0 1.0. Suggested citation: U.S. Department of Agriculture, " +
          "Agricultural Research Service. FoodData Central, fdc.nal.usda.gov",
      ca: "Contains information from Open Food Facts, which is made available " +
          "here under the Open Database License (ODbL). " +
          "opendatacommons.org/licenses/odbl/1-0/"
    },
    rule: "One source per file. These files are never merged with each other " +
          "or with the Bouchees catalogue: kept apart they form a collective " +
          "database, and the ODbL share-alike reaches only the Canadian file."
  };

  if (fUSDA) {
    console.log("");
    console.log("  ETATS-UNIS — USDA FoodData Central");
    const out = sortie("products-us.jsonl.gz");
    const stats = await lireUSDA(fUSDA, out.ecrire);
    await out.fermer();
    manifeste.files["products-us.jsonl.gz"] = {
      source: "USDA FoodData Central, Branded Foods",
      licence: "CC0-1.0",
      records: stats.gardes
    };
    console.log("    lignes lues            " + stats.lus);
    console.log("    sans ingrédients       " + stats.sansIngredients + "  (écartées)");
    console.log("    gardées                " + stats.gardes);
  }

  if (fOFF) {
    console.log("");
    console.log("  CANADA — Open Food Facts");
    const out = sortie("products-ca.jsonl.gz");
    const stats = await lireOFF(fOFF, out.ecrire);
    await out.fermer();
    manifeste.files["products-ca.jsonl.gz"] = {
      source: "Open Food Facts, filtered on Canada",
      licence: "ODbL-1.0",
      records: stats.gardes
    };
    console.log("    lignes lues            " + stats.lus);
    console.log("    étiquetées Canada      " + stats.canadiens);
    console.log("    sans ingrédients       " + stats.sansIngredients + "  (écartées)");
    console.log("    gardées                " + stats.gardes);
  }

  for (const nom of Object.keys(manifeste.files)) {
    const p = path.join(outDir, nom);
    manifeste.files[nom].bytes = fs.statSync(p).size;
  }

  fs.writeFileSync(path.join(outDir, "manifest.json"),
                   JSON.stringify(manifeste, null, 2));

  console.log("");
  console.log("  PAQUET ECRIT DANS  pack/");
  let total = 0, octets = 0;
  for (const nom of Object.keys(manifeste.files)) {
    const f = manifeste.files[nom];
    total += f.records;
    octets += f.bytes;
    console.log("    " + nom.padEnd(24) + String(f.records).padStart(9) +
                " produits   " + (f.bytes / 1048576).toFixed(1) + " Mo");
  }
  console.log("    " + "TOTAL".padEnd(24) + String(total).padStart(9) +
              " produits   " + (octets / 1048576).toFixed(1) + " Mo");
  console.log("");
}

main().catch(function (e) {
  console.error("");
  console.error("  ECHEC : " + e.message);
  console.error("");
  process.exit(1);
});
