/* The cycle log says so on every run. Le cycle du mois — une seule commande
 * node tools/cycle.js */
"use strict";
const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const read = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));
const write = (p, o) => fs.writeFileSync(path.join(racine, p), JSON.stringify(o, null, 2) + "\n");

const Trous = require("./gaps.js");
const Publier = require("./publish.js");
const PromptRecette = require("../generation/recipe-prompt.js");
const Valideur = require("../generation/recipe-validator.js");
const Coherence = require("../generation/coherence.js");
const Images = require("../generation/images.js");
const Vision = require("../generation/vision.js");
const MoteursTexte = require("../generation/text-engines.js");
const MoteursImage = require("../generation/image-engines.js");

const args = process.argv.slice(2);
const a = (n) => args.indexOf(n) !== -1;
const val = (n, d) => { const x = args.find((v) => v.startsWith(n + "=")); return x ? x.split("=")[1] : d; };

const Semaines = require("./weeks.js");

/* Batches are weekly since the rolling window: the cycle publishes into
 * the current week, not into a month. */
function currentWeek() {
  return Semaines.identifiantSemaine(new Date());
}

function title(t) { console.log("\n" + t + "\n" + "─".repeat(t.length)); }

function chargerDonnees() {
  return {
    catalogue: read("data/ingredients.json"),
    substitutions: read("data/substitutions.json"),
    base: read("data/base.json")
  };
}
function chargerCorpus() {
  let c = read("data/recipes.json");
  try { c = c.concat(read("data/imported/imported-recipes.json")); } catch (e) {}
  try { c = c.concat(read("data/generated/generated-recipes.json")); } catch (e) {}
  return c;
}

/* ---------- 1 to 5: the recipes ---------- */
async function cycleRecettes(data, options) {
  const journal = { commandees: 0, redigees: 0, acceptees: 0, rejetees: [], aRevoir: [], nouvelles: [] };
  const corpus = chargerCorpus();

  title("1 · Where recipes are missing");
  const r = Trous.report(corpus);
  fs.writeFileSync(path.join(racine, "tools", "rapport-trous.md"), "");
  const commande = r.commande;
  if (!commande.length) { console.log("  no gap under the thresholds — nothing to commission this month"); return journal; }
  commande.forEach(function (c) {
    console.log("  " + c.n + " x " + c.categories[0].toLowerCase() + " from " + c.ageMois + " months" +
      (c.passePartout ? " (works for everyone)" : " — no " + c.evite.join(", ")));
  });
  journal.commandees = commande.reduce((s, c) => s + c.n, 0);

  title("2 · Writing");
  const moteur = options.moteurTexte || MoteursTexte.choisir();
  console.log("  text engine: " + moteur.name + (moteur.name === "simule" ? "  (no API key — placeholder recipes)" : ""));
  const idsExistants = corpus.map((x) => x.id);
  let brutes = [];
  for (const ligne of commande) {
    const prompt = PromptRecette.construire(ligne, data);
    try {
      const output = await moteur.rediger(prompt);
      output.forEach(function (rec) { brutes.push({ rec: rec, commande: ligne }); });
    } catch (e) { console.log("  writing failed: " + e.message); }
  }
  journal.redigees = brutes.length;
  console.log("  " + brutes.length + " recette(s) rédigée(s)");

  title("3 · Validation — catalogue, allergens, ages");
  const survivantes = [];
  brutes.forEach(function (b) {
    const v = Valideur.valider(b.rec, b.commande, data, idsExistants.concat(survivantes.map((s) => s.rec.id)));
    if (!v.ok) { journal.rejetees.push({ id: b.rec.id, erreurs: v.erreurs }); console.log("  x  " + b.rec.id + " — " + v.erreurs[0]); return; }
    if (v.avertissements.length) journal.aRevoir.push({ id: b.rec.id, avertissements: v.avertissements });
    survivantes.push(b);
    console.log("  ok " + b.rec.id);
  });

  title("4 · Culinary coherence");
  const gardees = [];
  survivantes.forEach(function (b) {
    const c = Coherence.verifier(b.rec, data);
    if (!c.ok) { journal.rejetees.push({ id: b.rec.id, erreurs: c.erreurs }); console.log("  x  " + b.rec.id + " — " + c.erreurs[0]); return; }
    if (c.avertissements.length) journal.aRevoir.push({ id: b.rec.id, avertissements: c.avertissements });
    gardees.push(b.rec);
    console.log("  ok " + b.rec.id + (c.avertissements.length ? "  (" + c.avertissements.length + " reservation[s])" : ""));
  });
  journal.acceptees = gardees.length;
  journal.nouvelles = gardees.map((g) => g.id);

  title("5 · Publication dans un lot");
  if (!gardees.length) { console.log("  nothing to publish"); return journal; }
  const lot = options.lot || currentWeek();
  if (options.sec) { console.log("  [dry run] " + gardees.length + " recipe(s) would go into " + lot); return journal; }

  let generees = [];
  try { generees = read("data/generated/generated-recipes.json"); } catch (e) {}
  generees = generees.concat(gardees.map(function (g) {
    const copie = JSON.parse(JSON.stringify(g));
    copie.source = { source: "génération assistée", moteur: moteur.name,
                         le: new Date().toISOString().slice(0, 10),
                         license: "content original — rédigé pour Bouchées",
                         cuisineParUnHumain: false };
    return copie;
  }));
  fs.mkdirSync(path.join(racine, "data", "generated"), { recursive: true });
  write("data/generated/generated-recipes.json", generees);

  const pub = read("data/publishing.json");
  if (!pub.batches.some((l) => l.id === lot)) {
    pub.batches.push({ id: lot, title: "Semaine du " + lot, access: "subscriber",
                    weekly: true,
                    note: "Seven recipes aimed at the least-served profiles." });
  }
  gardees.forEach(function (g) { pub.assignment[g.id] = lot; });
  write("data/publishing.json", pub);
  console.log("  " + gardees.length + " recette(s) publiée(s) dans " + lot);
  return journal;
}

/* ---------- 6 to 8: the images ---------- */
async function cycleImages(data, options) {
  const journal = { generees: 0, acceptees: 0, rejetees: [] };
  const corpus = chargerCorpus();
  let manifest = {};
  try { manifest = read("generation/images/manifest.json"); } catch (e) {}

  title("6 · Images to produce");
  const plan = Images.aGenerer(corpus, data, manifest);
  if (!plan.length) { console.log("  every image is up to date"); return journal; }
  console.log("  " + plan.length + " image(s) — " +
    plan.filter((p) => p.state === "missing").length + " missing, " +
    plan.filter((p) => p.state === "stale").length + " stale");

  const mImage = options.moteurImage || MoteursImage.choisir();
  const mVision = options.moteurVision || Vision.choisir();
    /* The convention, before any image is paid for: reading the prompts takes
   * milliseconds. */
  try {
    require("child_process").execFileSync(process.execPath,
      [path.join(__dirname, "check-prompts.js")], { stdio: "inherit" });
  } catch (e) {
    console.log("");
    console.log("  ARRET — des prompts sortent de la convention.");
    console.log("  Rien n'a ete genere. Corrige, puis relance.");
    console.log("");
    process.exit(1);
  }

  console.log("  image engine: " + mImage.name + (mImage.name === "simule" ? "  (no engine — placeholder files)" : ""));

    /* A simulated run is not a run: the fallback exists so the cycle can be
   * tested offline, and it wrote 37 files of coloured rectangles on a real
   * run. */
  if (mImage.name === "simule" && !process.env.SIMULE_ASSUME) {
    console.log("");
    console.log("  ARRET — AUCUN MOTEUR D'IMAGE");
    console.log("");
    console.log("  Le mode simule ecrit des rectangles de couleur, pas des");
    console.log("  photos. Il sert aux tests hors ligne.");
    console.log("");
    console.log("  Draw Things n'a pas ete trouve. Verifie que l'app est");
    console.log("  ouverte et que API Server est allume, puis relance.");
    console.log("");
    console.log("  (SIMULE_ASSUME=1 pour forcer le mode simule volontairement)");
    console.log("");
    process.exit(1);
  }
  console.log("  vision check: " + mVision.name + (mVision.name === "absent" ? "  (no vision — everything will be rejected)" : ""));

  const limite = Number(val("--max", plan.length));
  /* Images live at the root, in images/. That is exactly what the client's
   * /images/... URL resolves to on the server — writing them anywhere else
   * donnait un 404 silencieux et un repli permanent sur l'illustration. */
  const folder = path.join(racine, "images");
  if (!options.sec) fs.mkdirSync(folder, { recursive: true });

  title("7 · Generation and verification");
  for (const p of plan.slice(0, limite)) {
    const recette = corpus.find((r) => r.id === p.id);
    let img;
        /* SQUARE, and that is the whole point: fLUX schnell is trained square,
     * and forcing a 3:2 frame through the API degrades the render. */
        /* But Draw Things is a desktop app rendering one image at a time: a
     * socket dropping between two of nineteen requests says nothing about the
     * prompt, and losing the recipe over it wastes the minutes already. */
    const specImage = {
      prompt: p.prompt, negatif: p.negatif,
      largeur: Number(process.env.DRAWTHINGS_LARGEUR || 1408),
      hauteur: Number(process.env.DRAWTHINGS_HAUTEUR || 1408)
    };
    let erreurReseau = null;
    for (let essai = 1; essai <= 2 && !img; essai++) {
      try {
        img = await mImage.generer(specImage);
      } catch (e) {
        erreurReseau = e;
        const reseau = /fetch failed|ECONNRESET|socket|timeout|aborted/i.test(e.message);
        if (!reseau || essai === 2) break;
        console.log("     " + p.name + " — connexion perdue, seconde tentative");
        await new Promise(function (r) { setTimeout(r, 20000); });
      }
    }
    if (!img) {
      const m = erreurReseau ? erreurReseau.message : "unknown";
      journal.rejetees.push({ id: p.id, reason: "génération : " + m });
      console.log("  x  " + p.name + " — " + m);
      continue;
    }
    journal.generees++;

        /* Draw Things has one renderer; firing the next call the instant the last
     * byte arrives gives it no room, and that is one of the three
     * explanations for a socket dropping mid-batch. */
    await new Promise(function (r) { setTimeout(r, 3000); });

    let verdict = await Vision.verifier(img.octets, recette, data, { moteur: mVision, typeMime: "image/png" });

        /* One retry when the render itself failed, not when the content is wrong. */
    const rendudRate = !verdict.ok && verdict.erreurs.some(function (e) {
      return /unreadable|embossed|relief|filtered/i.test(e);
    });
    if (rendudRate) {
      console.log("      the render came back broken — one retry");
      try {
        const img2 = await mImage.generer({
          prompt: p.prompt, negatif: p.negatif,
          largeur: Number(process.env.DRAWTHINGS_LARGEUR || 1408),
          hauteur: Number(process.env.DRAWTHINGS_HAUTEUR || 1408)
        });
        const v2 = await Vision.verifier(img2.octets, recette, data,
          { moteur: mVision, typeMime: "image/png" });
        if (v2.ok) { img = img2; verdict = v2; }
      } catch (e) {
        console.log("      retry failed: " + e.message);
      }
    }

    if (!verdict.ok) {
            /* Otherwise a rejection is a sentence with nothing behind it: "no
       * ingredient recognisable" reads the same whether the model drew the
       * wrong dish or the API returned a broken render. */
      const dossierRejets = path.join(racine, "images", "rejected");
      fs.mkdirSync(dossierRejets, { recursive: true });
      const filePath = path.join(dossierRejets, p.id + ".png");
      fs.writeFileSync(filePath, img.octets);

      journal.rejetees.push({ id: p.id, reason: verdict.erreurs.join(" ; "),
                              detectes: verdict.detectes, fichier: "images/rejected/" + p.id + ".png" });
      console.log("  x  " + p.name + " — " + verdict.erreurs[0]);
      console.log("      the app keeps its drawing · look at images/rejected/" + p.id + ".png");
      continue;
    }
    if (options.sec) { console.log("  ok [dry run] " + p.name); journal.acceptees++; continue; }

    const fichier = p.fichier.replace(/\.webp$/, ".png");
    fs.writeFileSync(path.join(racine, fichier), img.octets);
    manifest[p.id] = {
      fichier: fichier, empreinte: p.empreinte, largeur: img.largeur, hauteur: img.hauteur,
      moteur: img.moteur,
      revisePar: "vérification automatique (" + verdict.moteur + ")",
      verification: { moteur: verdict.moteur, le: verdict.le, detectes: verdict.detectes,
                      reconnus: verdict.reconnus, attendus: verdict.attendus,
                      avertissements: verdict.avertissements }
    };
    journal.acceptees++;
    console.log("  ok " + p.name + (verdict.avertissements.length ? "  (" + verdict.avertissements[0] + ")" : ""));

        /* The manifest is written AFTER EACH image, not at the end: they are
     * invisible to publishing, and the next run regenerates them for nothing. */
    fs.mkdirSync(path.join(racine, "generation", "images"), { recursive: true });
    write("generation/images/manifest.json", manifest);
  }

  /* Files on disk the manifest does not know about: leftovers from an
   * interrupted run. We SAY so rather than leave it to guesswork. */
  if (!options.sec) {
    const declares = new Set(Object.values(manifest).map(function (e) { return e.fichier; }));
    let orphelins = [];
    try {
      orphelins = fs.readdirSync(folder)
        .filter(function (f) { return /\.(png|webp|jpg|jpeg)$/i.test(f); })
        .filter(function (f) { return !declares.has("images/" + f); });
    } catch (e) {}
    if (orphelins.length) {
      console.log("\n  " + orphelins.length + " image(s) on disk with no vision verdict:");
      orphelins.slice(0, 5).forEach(function (f) { console.log("      " + f); });
      console.log("  They will NOT be published — an image with no verdict is never shown.");
      console.log("  Relance le cycle pour les refaire, ou supprime-les.");
      journal.orphelins = orphelins;
    }
  }
  return journal;
}

async function principal() {
  const data = chargerDonnees();
  const options = { sec: a("--sec"), lot: val("--lot", null) };
  console.log("═".repeat(64));
  console.log("  Bouchees cycle — " + new Date().toISOString().slice(0, 10) + (options.sec ? "   [DRY RUN]" : ""));
  console.log("═".repeat(64));

  let jr = null, ji = null;
  if (!a("--images-seulement")) jr = await cycleRecettes(data, options);
  if (!a("--recettes-seulement")) ji = await cycleImages(data, options);

  if (!options.sec) {
    title("8 · Republishing");
    const r = Publier.publier();
    fs.mkdirSync(path.join(racine, "dist", "batches"), { recursive: true });
    fs.writeFileSync(path.join(racine, "dist", "manifest.json"), JSON.stringify(r.manifest, null, 2) + "\n");
    fs.writeFileSync(path.join(racine, "dist", "safety.json"), JSON.stringify(r.securite) + "\n");
    Object.keys(r.content).forEach(function (lot) {
      fs.writeFileSync(path.join(racine, "dist", "batches", lot + ".json"), JSON.stringify(r.content[lot]) + "\n");
    });
    r.manifest.batches.forEach(function (l) {
      console.log("  " + l.id + "  " + (l.access === "free" ? "free      " : "subscriber") + "  " +
        String(l.count).padStart(2) + " recipes");
    });
  }

  title("Summary");
  if (jr) console.log("  recipes : " + jr.acceptees + " accepted, " + jr.rejetees.length + " rejected");
  if (ji) console.log("  images  : " + ji.acceptees + " published, " + ji.rejetees.length + " rejected");
  const revoir = (jr && jr.aRevoir.length) || 0;
  if (revoir) console.log("  flagged : " + revoir + " recipe(s) carry a warning");

  if (!options.sec) {
    write("tools/cycle-log.json", { le: new Date().toISOString(), recettes: jr, images: ji });
    console.log("  journal   : tools/cycle-log.json");
  }

    /* The three numbers that decide whether a photo reaches the app: they must
   * agree. */
  (function bilanPhotos() {
    const fsx = require("fs");
    const folder = path.join(__dirname, "..", "images");
    const surDisque = fsx.existsSync(folder)
      ? fsx.readdirSync(folder).filter(function (f) { return /\.(png|jpe?g|webp)$/i.test(f); }).length
      : 0;

    let entries = 0;
    try {
      const man = JSON.parse(fsx.readFileSync(
        path.join(__dirname, "..", "generation", "images", "manifest.json"), "utf8"));
      entries = Object.keys(man).filter(function (k) {
        return man[k] && man[k].fichier && man[k].revisePar;
      }).length;
    } catch (e) { /* none yet */ }

    let publiees = 0;
    try {
      const lots = path.join(__dirname, "..", "dist", "batches");
      fsx.readdirSync(lots).forEach(function (f) {
        JSON.parse(fsx.readFileSync(path.join(lots, f), "utf8")).forEach(function (r) {
          if (r.image) publiees++;
        });
      });
    } catch (e) { /* not published yet */ }

    console.log("");
    console.log("Photos — les trois nombres");
    console.log("──────────────────────────");
    console.log("  fichiers dans images/            " + surDisque);
    console.log("  entrees completes du manifeste   " + entries);
    console.log("  recettes publiees avec image     " + publiees);

    if (surDisque === entries && entries === publiees && surDisque > 0) {
      console.log("");
      console.log("  Les trois concordent. Pousse images/, generation/ et dist/.");
    } else if (surDisque === 0) {
      console.log("");
      console.log("  Aucune photo. Rien a pousser.");
    } else {
      console.log("");
      console.log("  ILS NE CONCORDENT PAS.");
      console.log("");
      if (entries < surDisque) {
        console.log("  Des fichiers existent sans entree au manifeste : le cycle");
        console.log("  a ete interrompu, ou la vision les a rejetes.");
      }
      if (publiees < entries) {
        console.log("  Le manifeste est en avance sur dist/ : relance le cycle");
        console.log("  pour republier, sinon l'app ne saura pas quoi demander.");
      }
      console.log("");
      console.log("  Ne pousse pas encore — l'app ne montrerait rien.");
    }
  })();

  console.log("\n  What the cycle CANNOT check: taste, rise, real texture.");
  console.log("  A recipe that was never cooked can be bad — never unsafe: safety lives");
  console.log("  in the deterministic tables, not in the kitchen test.\n");
}

if (require.main === module) {
  principal().catch(function (e) { console.error("Cycle interrompu : " + e.message); process.exit(1); });
}

module.exports = { cycleRecettes: cycleRecettes, cycleImages: cycleImages, currentWeek: currentWeek };
