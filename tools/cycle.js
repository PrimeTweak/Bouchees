/* Le cycle du mois — une seule commande
 *   node tools/cycle.js
 *
 * Options :
 *   --recettes-seulement   stop before the images
 *   --images-seulement     skip the writing
 *   --sec                  write nothing, show what would happen
 *   --lot=2026-10          the batch the new recipes go into
 *
 * Chains: gaps -> constrained prompt -> writing -> validation -> coherence ->
 * automatic curation -> publishing -> image generation -> verification by
 * vision → manifeste → republication.
 *
 * Ce qui est automatique et ce qui ne l'est pas :
 *   AUTOMATIC — allergens, ages, ingredients outside the catalogue, intruders
 *     in the images, impossible proportions, incomplete steps.
 *   NOT AUTOMATIC — taste, rise, real texture. No line of code replaces an
 *     actual bake for that. The cycle log says so on every run.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));
const ecrire = (p, o) => fs.writeFileSync(path.join(racine, p), JSON.stringify(o, null, 2) + "\n");

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

/* Batches are weekly since the rolling window: the cycle publishes
 * dans la semaine courante, pas dans un mois. */
function currentWeek() {
  return Semaines.identifiantSemaine(new Date());
}

function title(t) { console.log("\n" + t + "\n" + "─".repeat(t.length)); }

function chargerDonnees() {
  return {
    catalogue: lire("data/ingredients.json"),
    substitutions: lire("data/substitutions.json"),
    base: lire("data/base.json")
  };
}
function chargerCorpus() {
  let c = lire("data/recipes.json");
  try { c = c.concat(lire("data/imported/imported-recipes.json")); } catch (e) {}
  try { c = c.concat(lire("data/generated/generated-recipes.json")); } catch (e) {}
  return c;
}

/* ---------- 1 to 5: the recipes ---------- */
async function cycleRecettes(donnees, options) {
  const journal = { commandees: 0, redigees: 0, acceptees: 0, rejetees: [], aRevoir: [], nouvelles: [] };
  const corpus = chargerCorpus();

  title("1 · Where recipes are missing");
  const r = Trous.rapport(corpus);
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
    const prompt = PromptRecette.construire(ligne, donnees);
    try {
      const sortie = await moteur.rediger(prompt);
      sortie.forEach(function (rec) { brutes.push({ rec: rec, commande: ligne }); });
    } catch (e) { console.log("  writing failed: " + e.message); }
  }
  journal.redigees = brutes.length;
  console.log("  " + brutes.length + " recette(s) rédigée(s)");

  title("3 · Validation — catalogue, allergens, ages");
  const survivantes = [];
  brutes.forEach(function (b) {
    const v = Valideur.valider(b.rec, b.commande, donnees, idsExistants.concat(survivantes.map((s) => s.rec.id)));
    if (!v.ok) { journal.rejetees.push({ id: b.rec.id, erreurs: v.erreurs }); console.log("  x  " + b.rec.id + " — " + v.erreurs[0]); return; }
    if (v.avertissements.length) journal.aRevoir.push({ id: b.rec.id, avertissements: v.avertissements });
    survivantes.push(b);
    console.log("  ok " + b.rec.id);
  });

  title("4 · Culinary coherence");
  const gardees = [];
  survivantes.forEach(function (b) {
    const c = Coherence.verifier(b.rec, donnees);
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
  try { generees = lire("data/generated/generated-recipes.json"); } catch (e) {}
  generees = generees.concat(gardees.map(function (g) {
    const copie = JSON.parse(JSON.stringify(g));
    copie.source = { source: "génération assistée", moteur: moteur.name,
                         le: new Date().toISOString().slice(0, 10),
                         license: "content original — rédigé pour Bouchées",
                         cuisineParUnHumain: false };
    return copie;
  }));
  fs.mkdirSync(path.join(racine, "data", "generated"), { recursive: true });
  ecrire("data/generated/generated-recipes.json", generees);

  const pub = lire("data/publishing.json");
  if (!pub.batches.some((l) => l.id === lot)) {
    pub.batches.push({ id: lot, title: "Semaine du " + lot, access: "subscriber",
                    weekly: true,
                    note: "Seven recipes aimed at the least-served profiles." });
  }
  gardees.forEach(function (g) { pub.assignment[g.id] = lot; });
  ecrire("data/publishing.json", pub);
  console.log("  " + gardees.length + " recette(s) publiée(s) dans " + lot);
  return journal;
}

/* ---------- 6 to 8: the images ---------- */
async function cycleImages(donnees, options) {
  const journal = { generees: 0, acceptees: 0, rejetees: [] };
  const corpus = chargerCorpus();
  let manifeste = {};
  try { manifeste = lire("generation/images/manifest.json"); } catch (e) {}

  title("6 · Images to produce");
  const plan = Images.aGenerer(corpus, donnees, manifeste);
  if (!plan.length) { console.log("  every image is up to date"); return journal; }
  console.log("  " + plan.length + " image(s) — " +
    plan.filter((p) => p.etat === "missing").length + " missing, " +
    plan.filter((p) => p.etat === "stale").length + " stale");

  const mImage = options.moteurImage || MoteursImage.choisir();
  const mVision = options.moteurVision || Vision.choisir();
  /* THE CONVENTION, BEFORE ANY IMAGE IS PAID FOR.
   *
   * A malformed prompt costs a full generation to discover — several minutes
   * each, nineteen of them. Reading the prompts takes milliseconds. */
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

  /* A SIMULATED RUN IS NOT A RUN. STOP.
   *
   * The fallback exists so the cycle can be tested offline, and it wrote 37
   * files of coloured rectangles on a real run. The vision rejected every
   * one, correctly — but the only warning was the word "simule" on one line
   * above forty lines of red.
   *
   * A fallback that quietly does the wrong thing for half an hour is worse
   * than no fallback. It has to be asked for now. */
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
  const dossier = path.join(racine, "images");
  if (!options.sec) fs.mkdirSync(dossier, { recursive: true });

  title("7 · Generation and verification");
  for (const p of plan.slice(0, limite)) {
    const recette = corpus.find((r) => r.id === p.id);
    let img;
    /* SQUARE, and that is the whole point.
     *
     * Measured: the identical request at 1664x1104 comes back as an embossed
     * relief; at 1:1 it comes back as a clean photo. FLUX schnell is trained
     * square, and forcing a 3:2 frame through the API degrades the render.
     *
     * Every other suspect was isolated and ruled out first — prompt, negative
     * prompt, steps, sampler, seed, transport. It was the aspect ratio.
     *
     * 1408 rather than 1024: still square, still native to the model, and wide
     * enough that a card crop is not upscaled on an iPhone Pro Max (1320 px).
     * Adjustable through DRAWTHINGS_LARGEUR and DRAWTHINGS_HAUTEUR, but keep
     * them equal. */
    try {
      img = await mImage.generer({
        prompt: p.prompt, negatif: p.negatif,
        largeur: Number(process.env.DRAWTHINGS_LARGEUR || 1408),
        hauteur: Number(process.env.DRAWTHINGS_HAUTEUR || 1408)
      });
    }
    catch (e) { journal.rejetees.push({ id: p.id, reason: "génération : " + e.message }); console.log("  x  " + p.name + " — " + e.message); continue; }
    journal.generees++;

    let verdict = await Vision.verifier(img.octets, recette, donnees, { moteur: mVision, typeMime: "image/png" });

    /* One retry when the render itself failed, not when the content is wrong.
     *
     * The embossed relief comes back intermittently from Draw Things — the
     * same request that fails once succeeds on the next call. Rejecting it
     * outright throws away a recipe over a transient fault, and the image
     * costs three minutes, not three hours.
     *
     * A wrong dish or an intruding allergen is NOT retried: that is the model
     * doing what it was asked, and asking again would only reroll the dice on
     * a decision the guard is supposed to make. */
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
        const v2 = await Vision.verifier(img2.octets, recette, donnees,
          { moteur: mVision, typeMime: "image/png" });
        if (v2.ok) { img = img2; verdict = v2; }
      } catch (e) {
        console.log("      retry failed: " + e.message);
      }
    }

    if (!verdict.ok) {
      /* Write the rejected image to disk. Otherwise a rejection is a sentence
       * with nothing behind it: "no ingredient recognisable" reads the same
       * whether the model drew the wrong dish or the API returned a broken
       * render. Seeing the file tells the two apart in one look. */
      const dossierRejets = path.join(racine, "images", "rejected");
      fs.mkdirSync(dossierRejets, { recursive: true });
      const chemin = path.join(dossierRejets, p.id + ".png");
      fs.writeFileSync(chemin, img.octets);

      journal.rejetees.push({ id: p.id, reason: verdict.erreurs.join(" ; "),
                              detectes: verdict.detectes, fichier: "images/rejected/" + p.id + ".png" });
      console.log("  x  " + p.name + " — " + verdict.erreurs[0]);
      console.log("      the app keeps its drawing · look at images/rejected/" + p.id + ".png");
      continue;
    }
    if (options.sec) { console.log("  ok [dry run] " + p.name); journal.acceptees++; continue; }

    const fichier = p.fichier.replace(/\.webp$/, ".png");
    fs.writeFileSync(path.join(racine, fichier), img.octets);
    manifeste[p.id] = {
      fichier: fichier, empreinte: p.empreinte, largeur: img.largeur, hauteur: img.hauteur,
      moteur: img.moteur,
      revisePar: "vérification automatique (" + verdict.moteur + ")",
      verification: { moteur: verdict.moteur, le: verdict.le, detectes: verdict.detectes,
                      reconnus: verdict.reconnus, attendus: verdict.attendus,
                      avertissements: verdict.avertissements }
    };
    journal.acceptees++;
    console.log("  ok " + p.name + (verdict.avertissements.length ? "  (" + verdict.avertissements[0] + ")" : ""));

    /* The manifest is written AFTER EACH image, not at the end.
     *
     * Otherwise an interruption — Ctrl-C, a closed terminal, an error — leaves
     * images on disk that nothing declares. They are invisible to publishing,
     * and the next run regenerates them for nothing. That is exactly what
     * happened: five orphaned images. */
    fs.mkdirSync(path.join(racine, "generation", "images"), { recursive: true });
    ecrire("generation/images/manifest.json", manifeste);
  }

  /* Files on disk the manifest does not know about: leftovers from an
   * interrupted run. We SAY so rather than leave it to guesswork. */
  if (!options.sec) {
    const declares = new Set(Object.values(manifeste).map(function (e) { return e.fichier; }));
    let orphelins = [];
    try {
      orphelins = fs.readdirSync(dossier)
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
  const donnees = chargerDonnees();
  const options = { sec: a("--sec"), lot: val("--lot", null) };
  console.log("═".repeat(64));
  console.log("  Bouchees cycle — " + new Date().toISOString().slice(0, 10) + (options.sec ? "   [DRY RUN]" : ""));
  console.log("═".repeat(64));

  let jr = null, ji = null;
  if (!a("--images-seulement")) jr = await cycleRecettes(donnees, options);
  if (!a("--recettes-seulement")) ji = await cycleImages(donnees, options);

  if (!options.sec) {
    title("8 · Republishing");
    const r = Publier.publier();
    fs.mkdirSync(path.join(racine, "dist", "batches"), { recursive: true });
    fs.writeFileSync(path.join(racine, "dist", "manifest.json"), JSON.stringify(r.manifeste, null, 2) + "\n");
    fs.writeFileSync(path.join(racine, "dist", "safety.json"), JSON.stringify(r.securite) + "\n");
    Object.keys(r.content).forEach(function (lot) {
      fs.writeFileSync(path.join(racine, "dist", "batches", lot + ".json"), JSON.stringify(r.content[lot]) + "\n");
    });
    r.manifeste.batches.forEach(function (l) {
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
    ecrire("tools/cycle-log.json", { le: new Date().toISOString(), recettes: jr, images: ji });
    console.log("  journal   : tools/cycle-log.json");
  }

  console.log("\n  What the cycle CANNOT check: taste, rise, real texture.");
  console.log("  A recipe that was never cooked can be bad — never unsafe: safety lives");
  console.log("  in the deterministic tables, not in the kitchen test.\n");
}

if (require.main === module) {
  principal().catch(function (e) { console.error("Cycle interrompu : " + e.message); process.exit(1); });
}

module.exports = { cycleRecettes: cycleRecettes, cycleImages: cycleImages, currentWeek: currentWeek };
