/* Le cycle du mois — une seule commande
 *   node tools/cycle.js
 *
 * Options :
 *   --recettes-seulement   s'arrête avant les images
 *   --images-seulement     saute la rédaction
 *   --sec                  n'écrit rien, montre ce qui se passerait
 *   --lot=2026-10          le lot où publier les nouvelles recettes
 *
 * Enchaîne : trous → prompt contraint → rédaction → validation → cohérence →
 * curation automatique → publication → génération d'images → vérification par
 * vision → manifeste → republication.
 *
 * Ce qui est automatique et ce qui ne l'est pas :
 *   AUTOMATIQUE — allergènes, âges, ingrédients hors catalogue, intrus dans
 *     les images, proportions aberrantes, étapes incomplètes.
 *   PAS AUTOMATIQUE — le goût, la levée, la texture réelle. Aucune ligne de
 *     code ne remplace une vraie cuisson pour ça. Le journal du cycle le
 *     rappelle à chaque passage.
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

/* Les batches sont hebdomadaires depuis la fenêtre glissante : le cycle publie
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

/* ---------- 1 à 5 : les recettes ---------- */
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

/* ---------- 6 à 8 : les images ---------- */
async function cycleImages(donnees, options) {
  const journal = { generees: 0, acceptees: 0, rejetees: [] };
  const corpus = chargerCorpus();
  let manifeste = {};
  try { manifeste = lire("generation/images/manifest.json"); } catch (e) {}

  title("6 · Images to produce");
  const plan = Images.aGenerer(corpus, donnees, manifeste);
  if (!plan.length) { console.log("  every image is up to date"); return journal; }
  console.log("  " + plan.length + " image(s) — " +
    plan.filter((p) => p.etat === "manquante").length + " manquante(s), " +
    plan.filter((p) => p.etat === "périmée").length + " périmée(s)");

  const mImage = options.moteurImage || MoteursImage.choisir();
  const mVision = options.moteurVision || Vision.choisir();
  console.log("  image engine: " + mImage.name + (mImage.name === "simule" ? "  (no engine — placeholder files)" : ""));
  console.log("  vision check: " + mVision.name + (mVision.name === "absent" ? "  (no vision — everything will be rejected)" : ""));

  const limite = Number(val("--max", plan.length));
  /* Les images vivent à la racine, dans images/. C'est exactement ce que
   * l'URL /images/… du client résout côté serveur — les écrire ailleurs
   * donnait un 404 silencieux et un repli permanent sur l'illustration. */
  const dossier = path.join(racine, "images");
  if (!options.sec) fs.mkdirSync(dossier, { recursive: true });

  title("7 · Generation and verification");
  for (const p of plan.slice(0, limite)) {
    const recette = corpus.find((r) => r.id === p.id);
    let img;
    /* 1216×832 : assez de définition pour les cartes et la fiche, et un
     * rapport 3:2 qui se recadre bien en 4:3 comme en 16:10. Réglable par
     * DRAWTHINGS_LARGEUR et DRAWTHINGS_HAUTEUR. */
    try {
      img = await mImage.generer({
        prompt: p.prompt, negatif: p.negatif,
        largeur: Number(process.env.DRAWTHINGS_LARGEUR || 1216),
        hauteur: Number(process.env.DRAWTHINGS_HAUTEUR || 832)
      });
    }
    catch (e) { journal.rejetees.push({ id: p.id, reason: "génération : " + e.message }); console.log("  x  " + p.name + " — " + e.message); continue; }
    journal.generees++;

    const verdict = await Vision.verifier(img.octets, recette, donnees, { moteur: mVision, typeMime: "image/png" });
    if (!verdict.ok) {
      journal.rejetees.push({ id: p.id, reason: verdict.erreurs.join(" ; "), detectes: verdict.detectes });
      console.log("  x  " + p.name + " — " + verdict.erreurs[0]);
      console.log("      → l'app garde son illustration pour cette recette");
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

    /* Le manifeste s'écrit APRÈS CHAQUE image, pas à la fin.
     *
     * Autrement, une interruption — Ctrl-C, terminal fermé, erreur — laisse
     * sur le disque des images que rien ne déclare. Elles sont invisibles à
     * la publishing, et le prochain passage les regénère pour rien. C'est
     * exactement ce qui est arrivé : cinq images orphans. */
    fs.mkdirSync(path.join(racine, "generation", "images"), { recursive: true });
    ecrire("generation/images/manifest.json", manifeste);
  }

  /* Fichiers sur le disque que le manifeste ne connaît pas : restes d'un
   * passage interrompu. On le DIT plutôt que de laisser deviner. */
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
