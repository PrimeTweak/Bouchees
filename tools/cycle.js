/* The cycle: one run commissions, writes, validates and publishes. */
"use strict";
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const read = (p) => JSON.parse(fs.readFileSync(path.join(root, p), "utf8"));
const write = (p, o) => fs.writeFileSync(path.join(root, p), JSON.stringify(o, null, 2) + "\n");

const Gaps = require("./gaps.js");
const Publisher = require("./publish.js");
const RecipePrompt = require("../generation/recipe-prompt.js");
const Validator = require("../generation/recipe-validator.js");
const Coherence = require("../generation/coherence.js");
const Images = require("../generation/images.js");
const Vision = require("../generation/vision.js");
const Cadrage = require("./cadrage.js");
const MoteursTexte = require("../generation/text-engines.js");
const MoteursImage = require("../generation/image-engines.js");

const args = process.argv.slice(2);
const a = (n) => args.indexOf(n) !== -1;
const val = (n, d) => { const x = args.find((v) => v.startsWith(n + "=")); return x ? x.split("=")[1] : d; };


/* Batches are weekly since the rolling window: the cycle publishes into
 * the current week, not into a month. */
function title(t) { console.log("\n" + t + "\n" + "─".repeat(t.length)); }

/* Products the live server found since the last cycle, folded into the
 * seed the repository ships. Needs BOUCHEES_ADMIN_SECRET in cle-api.txt;
 * without it, or offline, the step is skipped and says so. */
async function pullProductsSeen() {
  const secret = process.env.BOUCHEES_ADMIN_SECRET;
  if (!secret) {
    /* Names the files actually read and what was found in them, so a BOM or
     * a stray space is visible instead of guessed at. */
    const vus = ["cle-api.txt", ".env"].map(function (f) {
      const chemin = path.join(__dirname, "..", f);
      if (!fs.existsSync(chemin)) return f + ": absent";
      const noms = fs.readFileSync(chemin, "utf8").replace(/^\uFEFF/, "").split(/\r?\n/)
        .map(function (l) { return (l.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=/) || [])[1]; })
        .filter(Boolean);
      return f + ": " + (noms.length ? noms.join(", ") : "no NAME=value line");
    });
    console.log("  products seen: BOUCHEES_ADMIN_SECRET not in the environment — skipped");
    vus.forEach(function (v) { console.log("    " + v); });
    return;
  }
  const base = process.env.BOUCHEES_SERVER || "https://bouchees.onrender.com";
  const fichier = path.join(__dirname, "..", "data", "products-seen.json");
  let seed = {};
  try { seed = JSON.parse(fs.readFileSync(fichier, "utf8")); } catch (e) { seed = {}; }
  try {
    const r = await fetch(base + "/api/products-seen?key=" + encodeURIComponent(secret));
    if (!r.ok) { console.log("  products seen: server answered " + r.status + " — skipped"); return; }
    const nouveaux = await r.json();
    const avant = Object.keys(seed).length;
    Object.keys(nouveaux).forEach(function (k) { seed[k] = nouveaux[k]; });
    fs.writeFileSync(fichier, JSON.stringify(seed, null, 1) + "\n");
    console.log("  products seen: " + (Object.keys(seed).length - avant) + " new, " + Object.keys(seed).length + " in the repository");
  } catch (e) { console.log("  products seen: " + e.message + " — skipped"); }
}

/* Every rejected draft is kept with its reasons. A rejection that is only
 * printed cannot be audited, and the validator cannot be tuned without a
 * corpus of what it refused. Last two hundred, newest first. */
const REJECTED_FILE = path.join(__dirname, "..", "data", "generated", "rejected.json");
function keepRejected(rec, commande, erreurs) {
  let entries = [];
  try { entries = JSON.parse(fs.readFileSync(REJECTED_FILE, "utf8")); } catch (e) { entries = []; }
  entries.unshift({ date: new Date().toISOString().slice(0, 10), commande: commande,
                  erreurs: erreurs, recette: rec });
  fs.writeFileSync(REJECTED_FILE, JSON.stringify(entries.slice(0, 200), null, 2) + "\n");
}

function loadData() {
  return {
    catalogue: read("data/ingredients.json"),
    substitutions: read("data/substitutions.json"),
    base: read("data/base.json")
  };
}
function loadCorpus() {
  let c = read("data/recipes.json");
  try { c = c.concat(read("data/imported/imported-recipes.json")); } catch (e) {}
  try { c = c.concat(read("data/generated/generated-recipes.json")); } catch (e) {}
  return c;
}

/* ---------- 1 to 5: the recipes ---------- */
async function cycleRecettes(data, options) {
  const log = { commandees: 0, redigees: 0, acceptees: 0, rejetees: [], aRevoir: [], nouvelles: [] };
  const corpus = loadCorpus();

  title("1 · Where recipes are missing");
  const r = Gaps.report(corpus);
  fs.writeFileSync(path.join(root, "tools", "rapport-trous.md"), "");
  const commission = r.commande;
  if (!commission.length) { console.log("  no gap under the thresholds — nothing to commission this month"); return log; }
  commission.forEach(function (c) {
    console.log("  " + c.n + " x " + c.categories[0].toLowerCase() + " from " + c.ageMois + " months" +
                (c.hero ? ", around " + c.hero : "") +
      (c.passePartout ? " (works for everyone)" : " — no " + c.evite.join(", ")));
  });
  log.commandees = commission.reduce((s, c) => s + c.n, 0);

  title("2 · Writing");
  const moteur = options.moteurTexte || MoteursTexte.choisir();
  console.log("  text engine: " + moteur.name + (moteur.name === "simule" ? "  (no API key — placeholder recipes)" : ""));
  const idsExistants = corpus.map((x) => x.id);
  let drafts = [];
  let aSec = false;
  let k = 0;
  for (const ligne of commission) {
    const prompt = RecipePrompt.construire(ligne, data, {
      existants: corpus.map((x) => x.name || x.id),
      ecritsCeTour: drafts.map((d) => d.rec.name || d.rec.id)
    });
    process.stdout.write("  " + (++k) + "/" + commission.length + "  " + ligne.n + " " + ligne.categories[0].toLowerCase() +
                         " from " + ligne.ageMois + " months" + (ligne.evite.length ? ", no " + ligne.evite.join("/") : "") +
                         (ligne.hero ? ", around " + ligne.hero : "") + " … ");
    try {
      if (aSec) { console.log("skipped — no credit"); continue; }
      const output = await moteur.rediger(prompt);
      output.forEach(function (rec) {
        /* Ids are keys: ASCII, lowercase, hyphens. An accent the model
         * slipped in is normalised rather than refused. */
        if (rec && typeof rec.id === "string") {
          rec.id = rec.id.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
            .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
        }
        drafts.push({ rec: rec, commande: ligne });
      });
      console.log(output.length + " written");
    } catch (e) {
      console.log("failed: " + e.message);
      /* An empty balance refuses every call the same way: stop after the
       * first rather than hammer thirty more, and say what to do. */
      if (/credit balance|insufficient|billing/i.test(e.message)) {
        aSec = true;
        console.log("");
        console.log("  NO CREDIT ON THE ANTHROPIC ACCOUNT");
        console.log("  Every line would fail the same way. Add credits at");
        console.log("  console.anthropic.com > Plans & Billing, then run again.");
        log.sansCredit = true;
      }
    }
  }
  log.redigees = drafts.length;
  console.log("  " + drafts.length + " recipe(s) written");

  title("3 · Validation — catalogue, allergens, ages");
  const survivantes = [];
  drafts.forEach(function (b) {
    const v = Validator.validate(b.rec, b.commande, data, idsExistants.concat(survivantes.map((s) => s.rec.id)));
    if (!v.ok) {
      log.rejetees.push({ id: b.rec.id, erreurs: v.erreurs });
      keepRejected(b.rec, b.commande, v.erreurs);
      console.log("  x  " + b.rec.id + " — " + v.erreurs[0]); return;
    }
    if (v.avertissements.length) log.aRevoir.push({ id: b.rec.id, avertissements: v.avertissements });
    survivantes.push(b);
    console.log("  ok " + b.rec.id);
  });

  title("4 · Culinary coherence");
  const kept = [];
  survivantes.forEach(function (b) {
    const c = Coherence.verifier(b.rec, data);
    if (!c.ok) {
      log.rejetees.push({ id: b.rec.id, erreurs: c.erreurs });
      keepRejected(b.rec, b.commande, c.erreurs);
      console.log("  x  " + b.rec.id + " — " + c.erreurs[0]); return;
    }
    if (c.avertissements.length) log.aRevoir.push({ id: b.rec.id, avertissements: c.avertissements });
    kept.push(b.rec);
    console.log("  ok " + b.rec.id + (c.avertissements.length ? "  (" + c.avertissements.length + " reservation[s])" : ""));
  });
  log.acceptees = kept.length;
  log.nouvelles = kept.map((g) => g.id);

  title("5 · Into the pool");
  if (!kept.length) { console.log("  nothing to publish"); return log; }
  if (options.sec) { console.log("  [dry run] " + kept.length + " recipe(s) would join the pool"); return log; }

  let generees = [];
  try { generees = read("data/generated/generated-recipes.json"); } catch (e) {}
  generees = generees.concat(kept.map(function (g) {
    const copie = JSON.parse(JSON.stringify(g));
    copie.source = { source: "assisted generation", engine: moteur.name,
                     on: new Date().toISOString().slice(0, 10),
                     license: "original content, written for Bouchees",
                     cookedByAHuman: false };
    return copie;
  }));
  fs.mkdirSync(path.join(root, "data", "generated"), { recursive: true });
  write("data/generated/generated-recipes.json", generees);
  /* No batch to declare: a recipe in the corpus is in the pool. */
  console.log("  " + kept.length + " recipe(s) joined the pool");
  return log;
}

/* ---------- 6 to 8: the images ---------- */
async function cycleImages(data, options) {
  const log = { generees: 0, acceptees: 0, rejetees: [] };
  const corpus = loadCorpus();
  let manifest = {};
  try { manifest = read("generation/images/manifest.json"); } catch (e) {}

  title("6 · Images to produce");
  const steps = Images.aGenerer(corpus, data, manifest);
  if (!steps.length) { console.log("  every image is up to date"); return log; }
  console.log("  " + steps.length + " image(s) — " +
    steps.filter((p) => p.state === "missing").length + " missing, " +
    steps.filter((p) => p.state === "stale").length + " stale");

  const mImage = options.moteurImage || MoteursImage.choisir();
  const mVision = options.moteurVision || Vision.choisir();
    /* The convention, before any image is paid for: reading the prompts takes
   * milliseconds. */
  /* A prompt outside the convention sets its recipe aside, by name; the
   * rest are photographed. One drifted prompt used to stop a hundred. */
  let ecartees = [];
  try {
    require("child_process").execFileSync(process.execPath,
      [path.join(__dirname, "check-prompts.js")], { stdio: "inherit" });
  } catch (e) {
    try { ecartees = JSON.parse(fs.readFileSync(path.join(__dirname, "prompts-outside-convention.json"), "utf8")); }
    catch (e2) { ecartees = []; }
    console.log("");
    console.log("  " + ecartees.length + " recipe(s) set aside until their prompt is fixed: " + ecartees.join(", "));
    console.log("  The others are photographed.");
    console.log("");
  }

  console.log("  image engine: " + mImage.name + (mImage.name === "simule" ? "  (no engine — placeholder files)" : ""));

    /* A simulated run is not a run: the fallback exists so the cycle can be
   * tested offline, and it wrote 37 files of coloured rectangles on a real
   * run. */
  if (mImage.name === "simule" && !process.env.SIMULE_ASSUME) {
    console.log("");
    console.log("  ARRET — AUCUN MOTEUR D'IMAGE");
    console.log("");
    console.log("  Simulation mode writes coloured rectangles, not");
    console.log("  photos. Il sert aux tests hors ligne.");
    console.log("");
    console.log("  Draw Things n'a pas ete trouve. Verifie que l'app est");
    console.log("  is open and API Server is on, then run again.");
    console.log("");
    console.log("  (SIMULE_ASSUME=1 forces simulation mode on purpose)");
    console.log("");
    process.exit(1);
  }
  console.log("  vision check: " + mVision.name + (mVision.name === "absent" ? "  (no vision — everything will be rejected)" : ""));

  const limit = Number(val("--max", steps.length));
  /* Images live at the root, in images/. That is exactly what the client's
   * /images/... URL resolves to on the server — writing them anywhere else
   * donnait un 404 silencieux et un repli permanent sur l'illustration. */
  const folder = path.join(root, "images");
  if (!options.sec) fs.mkdirSync(folder, { recursive: true });

  title("7 · Generation and verification");
  const aFaire = steps.filter(function (p) { return ecartees.indexOf(p.id) < 0; });
  /* Past ten attempts, a rejection rate above two thirds stops the run:
   * a prompt or a threshold has drifted, and a night of that is waste. */
  let tentatives = 0, rejets = 0;
  for (const p of aFaire.slice(0, limit)) {
    if (tentatives >= 10 && rejets / tentatives > 0.66) {
      console.log("");
      console.log("  STOPPED — " + rejets + " of " + tentatives + " rejected. Something drifted.");
      console.log("  Read the reasons above, fix the cause, and run again.");
      break;
    }
    const recipe = corpus.find((r) => r.id === p.id);
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
      log.rejetees.push({ id: p.id, reason: "generation: " + m });
      console.log("  x  " + p.name + " — " + m);
      continue;
    }
    log.generees++;

        /* Draw Things has one renderer; firing the next call the instant the last
     * byte arrives gives it no room, and that is one of the three
     * explanations for a socket dropping mid-batch. */
    await new Promise(function (r) { setTimeout(r, 3000); });

    let verdict = await Vision.verifier(img.octets, recipe, data, { moteur: mVision, typeMime: "image/png" });

    /* Framing, before anything else: a dish starting below DEPART_MAX
     * sits inside the hero's title. */
    if (verdict.ok) {
      const tmp = path.join(require("os").tmpdir(), "bouchees-cadrage-" + process.pid + ".png");
      fs.writeFileSync(tmp, img.octets);
      try {
        const m = Cadrage.mesurer(tmp);
        if (m.sujetHaut >= Cadrage.DEPART_MAX) {
          verdict = { ok: false, moteur: verdict.moteur, le: verdict.le, detectes: [], reconnus: [], attendus: [],
                      avertissements: [],
                      erreurs: ["the dish starts " + m.sujetHaut.toFixed(2) + " of the way down, past the " +
                                Cadrage.DEPART_MAX + " mark — the hero's title would cover it"] };
        }
      } catch (e) { /* unreadable png: the vision verdict already stands */ }
      try { fs.unlinkSync(tmp); } catch (e) { /* gone */ }
    }

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
        const v2 = await Vision.verifier(img2.octets, recipe, data,
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
      const dossierRejets = path.join(root, "images", "rejected");
      fs.mkdirSync(dossierRejets, { recursive: true });
      const filePath = path.join(dossierRejets, p.id + ".png");
      fs.writeFileSync(filePath, img.octets);

      tentatives++; rejets++;
      log.rejetees.push({ id: p.id, reason: verdict.erreurs.join(" ; "),
                              detectes: verdict.detectes, fichier: "images/rejected/" + p.id + ".png" });
      console.log("  x  " + p.name + " — " + verdict.erreurs[0]);
      console.log("      the app keeps its drawing · look at images/rejected/" + p.id + ".png");
      continue;
    }
    if (options.sec) { console.log("  ok [dry run] " + p.name); log.acceptees++; continue; }

    const fichier = p.fichier.replace(/\.webp$/, ".png");
    fs.writeFileSync(path.join(root, fichier), img.octets);
    manifest[p.id] = {
      fichier: fichier, empreinte: p.empreinte, largeur: img.largeur, hauteur: img.hauteur,
      moteur: img.moteur,
      revisePar: "vérification automatique (" + verdict.moteur + ")",
      verification: { moteur: verdict.moteur, le: verdict.le, detectes: verdict.detectes,
                      reconnus: verdict.reconnus, attendus: verdict.attendus,
                      avertissements: verdict.avertissements }
    };
    log.acceptees++;
    tentatives++;
    if (verdict.avertissements.some(function (m) { return /^to review|look-alike/.test(m); })) log.photosARevoir = (log.photosARevoir || 0) + 1;
    console.log("  ok " + p.name + (verdict.avertissements.length ? "  (" + verdict.avertissements[0] + ")" : ""));

        /* The manifest is written AFTER EACH image, not at the end: they are
     * invisible to publishing, and the next run regenerates them for nothing. */
    fs.mkdirSync(path.join(root, "generation", "images"), { recursive: true });
    write("generation/images/manifest.json", manifest);
  }

  /* Files on disk the manifest does not know about: leftovers from an
   * interrupted run. We SAY so rather than leave it to guesswork. */
  if (!options.sec) {
    const declares = new Set(Object.values(manifest).map(function (e) { return e.fichier; }));
    let orphans = [];
    try {
      orphans = fs.readdirSync(folder)
        .filter(function (f) { return /\.(png|webp|jpg|jpeg)$/i.test(f); })
        .filter(function (f) { return !declares.has("images/" + f); });
    } catch (e) {}
    if (orphans.length) {
      console.log("\n  " + orphans.length + " image(s) on disk with no vision verdict:");
      orphans.slice(0, 5).forEach(function (f) { console.log("      " + f); });
      console.log("  They will NOT be published — an image with no verdict is never shown.");
      console.log("  Run the cycle again to remake them, or delete them.");
      log.orphans = orphans;
    }
  }
  return log;
}

async function principal() {
  const data = loadData();
  const options = { sec: a("--sec") };
  console.log("═".repeat(64));
  console.log("  Bouchees cycle — " + new Date().toISOString().slice(0, 10) + (options.sec ? "   [DRY RUN]" : ""));
  console.log("═".repeat(64));

  let jr = null, ji = null;
  await pullProductsSeen();
  if (!a("--images-seulement")) jr = await cycleRecettes(data, options);
  /* A run without credit is a failed run: exit non-zero so GENERER.command
   * stops after one tour instead of three. */
  if (jr && jr.sansCredit) process.exit(2);
  if (!a("--recettes-seulement")) ji = await cycleImages(data, options);

  if (!options.sec) {
    title("8 · Republishing");
    const r = Publisher.publier();
    const dist = path.join(root, "dist");
    fs.rmSync(path.join(dist, "batches"), { recursive: true, force: true });
    fs.mkdirSync(path.join(dist, "recipes"), { recursive: true });
    fs.writeFileSync(path.join(dist, "manifest.json"), JSON.stringify(r.manifest, null, 2) + "\n");
    fs.writeFileSync(path.join(dist, "safety.json"), JSON.stringify(r.securite) + "\n");
    fs.writeFileSync(path.join(dist, "catalogue.json"), JSON.stringify(r.catalogue) + "\n");
    Object.keys(r.bodies).forEach(function (id) {
      fs.writeFileSync(path.join(dist, "recipes", id + ".json"), JSON.stringify(r.bodies[id]) + "\n");
    });
    console.log("  pool  " + r.manifest.counts.Meal + " meals, " + r.manifest.counts.Snack + " snacks");
  }

  title("Summary");
  if (jr) console.log("  recipes : " + jr.acceptees + " accepted, " + jr.rejetees.length + " rejected");
  if (ji) console.log("  images  : " + ji.acceptees + " published, " + ji.rejetees.length + " rejected");
  if (ji && ji.rejetees && ji.rejetees.length) {
    const motifs = {};
    ji.rejetees.forEach(function (r) {
      const m = /of the way down/.test(r.reason || "") ? "framing"
              : /the image shows|the vision is unsure|vision named/.test(r.reason || "") ? "an ingredient the recipe lacks"
              : /dish does not match|not identified/.test(r.reason || "") ? "the dish does not match"
              : "other";
      motifs[m] = (motifs[m] || 0) + 1;
    });
    Object.keys(motifs).forEach(function (m) { console.log("     " + motifs[m] + " for " + m); });
  }
  if (ji && ji.photosARevoir) {
    console.log("  " + ji.photosARevoir + " published but flagged — five minutes of your eyes:");
    console.log("     node tools/photos-a-revoir.js");
  }
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
    /* Named, not just counted: a number that does not match tells you
     * nothing about which recipe to look at. */
    const orphans = [];      /* manifest says done, file is not there */
    const nonPubliees = [];    /* manifest says done, catalogue has no image */
    try {
      const man = JSON.parse(fsx.readFileSync(
        path.join(__dirname, "..", "generation", "images", "manifest.json"), "utf8"));
      Object.keys(man).forEach(function (k) {
        const e = man[k];
        if (!(e && e.fichier && e.revisePar)) return;
        entries++;
        if (!fsx.existsSync(path.join(folder, e.fichier))) orphans.push(k + " -> " + e.fichier);
      });
    } catch (e) { /* none yet */ }

    let publiees = 0;
    try {
      const cat = JSON.parse(fsx.readFileSync(path.join(__dirname, "..", "dist", "catalogue.json"), "utf8"));
      const avecImage = {};
      cat.forEach(function (c) { if (c.image) { publiees++; avecImage[c.id] = 1; } });
      try {
        const man = JSON.parse(fsx.readFileSync(
          path.join(__dirname, "..", "generation", "images", "manifest.json"), "utf8"));
        Object.keys(man).forEach(function (k) {
          if (man[k] && man[k].fichier && man[k].revisePar && !avecImage[k]) nonPubliees.push(k);
        });
      } catch (e) { /* none */ }
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
        console.log("  Files exist with no manifest entry: the cycle");
        console.log("  was interrupted, or the vision rejected them. PHOTOS.command takes them again.");
      }
      if (orphans.length) {
        console.log("  The manifest declares a photo whose FILE is missing:");
        orphans.forEach(function (o) { console.log("    " + o); });
        console.log("  The file was deleted or never pushed. PHOTOS.command remakes it.");
      }
      if (nonPubliees.length && !orphans.length) {
        console.log("  A photo is ready but its recipe is not in the published catalogue:");
        nonPubliees.forEach(function (o) { console.log("    " + o); });
        console.log("  The recipe left the pool, or is not in it yet. Nothing to do.");
      }
      console.log("");
      console.log("  The app shows the photos that exist; these will simply be missing.");
    }
  })();

  console.log("\n  What the cycle CANNOT check: taste, rise, real texture.");
  console.log("  A recipe that was never cooked can be bad — never unsafe: safety lives");
  console.log("  in the deterministic tables, not in the kitchen test.\n");
}

if (require.main === module) {
  principal().catch(function (e) { console.error("Cycle interrompu : " + e.message); process.exit(1); });
}

module.exports = { cycleRecettes: cycleRecettes, cycleImages: cycleImages };
