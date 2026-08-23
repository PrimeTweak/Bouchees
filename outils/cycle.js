/* Le cycle du mois — une seule commande
 *   node outils/cycle.js
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

const Trous = require("./trous.js");
const Publier = require("./publier.js");
const PromptRecette = require("../generation/prompt-recette.js");
const Valideur = require("../generation/valideur-recette.js");
const Coherence = require("../generation/coherence.js");
const Images = require("../generation/images.js");
const Vision = require("../generation/vision.js");
const MoteursTexte = require("../generation/moteurs-texte.js");
const MoteursImage = require("../generation/moteurs-image.js");

const args = process.argv.slice(2);
const a = (n) => args.indexOf(n) !== -1;
const val = (n, d) => { const x = args.find((v) => v.startsWith(n + "=")); return x ? x.split("=")[1] : d; };

const Semaines = require("./semaines.js");

/* Les lots sont hebdomadaires depuis la fenêtre glissante : le cycle publie
 * dans la semaine courante, pas dans un mois. */
function semaineCourante() {
  return Semaines.identifiantSemaine(new Date());
}

function titre(t) { console.log("\n" + t + "\n" + "─".repeat(t.length)); }

function chargerDonnees() {
  return {
    catalogue: lire("donnees/ingredients.json"),
    substitutions: lire("donnees/substitutions.json"),
    base: lire("donnees/base.json")
  };
}
function chargerCorpus() {
  let c = lire("donnees/recettes.json");
  try { c = c.concat(lire("donnees/importees/recettes-importees.json")); } catch (e) {}
  try { c = c.concat(lire("donnees/generees/recettes-generees.json")); } catch (e) {}
  return c;
}

/* ---------- 1 à 5 : les recettes ---------- */
async function cycleRecettes(donnees, options) {
  const journal = { commandees: 0, redigees: 0, acceptees: 0, rejetees: [], aRevoir: [], nouvelles: [] };
  const corpus = chargerCorpus();

  titre("1 · Où manquent les recettes");
  const r = Trous.rapport(corpus);
  fs.writeFileSync(path.join(racine, "outils", "rapport-trous.md"), "");
  const commande = r.commande;
  if (!commande.length) { console.log("  aucun trou sous les seuils — rien à commander ce mois-ci"); return journal; }
  commande.forEach(function (c) {
    console.log("  " + c.n + " × " + c.categories[0].toLowerCase() + " dès " + c.ageMois + " mois" +
      (c.passePartout ? " (passe-partout)" : " — sans " + c.evite.join(", ")));
  });
  journal.commandees = commande.reduce((s, c) => s + c.n, 0);

  titre("2 · Rédaction");
  const moteur = options.moteurTexte || MoteursTexte.choisir();
  console.log("  moteur : " + moteur.nom + (moteur.nom === "simule" ? "  (aucune clé d'API — recettes factices)" : ""));
  const idsExistants = corpus.map((x) => x.id);
  let brutes = [];
  for (const ligne of commande) {
    const prompt = PromptRecette.construire(ligne, donnees);
    try {
      const sortie = await moteur.rediger(prompt);
      sortie.forEach(function (rec) { brutes.push({ rec: rec, commande: ligne }); });
    } catch (e) { console.log("  échec de rédaction : " + e.message); }
  }
  journal.redigees = brutes.length;
  console.log("  " + brutes.length + " recette(s) rédigée(s)");

  titre("3 · Validation — catalogue, allergènes, âges");
  const survivantes = [];
  brutes.forEach(function (b) {
    const v = Valideur.valider(b.rec, b.commande, donnees, idsExistants.concat(survivantes.map((s) => s.rec.id)));
    if (!v.ok) { journal.rejetees.push({ id: b.rec.id, erreurs: v.erreurs }); console.log("  ✕ " + b.rec.id + " — " + v.erreurs[0]); return; }
    if (v.avertissements.length) journal.aRevoir.push({ id: b.rec.id, avertissements: v.avertissements });
    survivantes.push(b);
    console.log("  ✓ " + b.rec.id);
  });

  titre("4 · Cohérence culinaire");
  const gardees = [];
  survivantes.forEach(function (b) {
    const c = Coherence.verifier(b.rec, donnees);
    if (!c.ok) { journal.rejetees.push({ id: b.rec.id, erreurs: c.erreurs }); console.log("  ✕ " + b.rec.id + " — " + c.erreurs[0]); return; }
    if (c.avertissements.length) journal.aRevoir.push({ id: b.rec.id, avertissements: c.avertissements });
    gardees.push(b.rec);
    console.log("  ✓ " + b.rec.id + (c.avertissements.length ? "  (" + c.avertissements.length + " réserve[s])" : ""));
  });
  journal.acceptees = gardees.length;
  journal.nouvelles = gardees.map((g) => g.id);

  titre("5 · Publication dans un lot");
  if (!gardees.length) { console.log("  rien à publier"); return journal; }
  const lot = options.lot || semaineCourante();
  if (options.sec) { console.log("  [à sec] " + gardees.length + " recette(s) iraient dans " + lot); return journal; }

  let generees = [];
  try { generees = lire("donnees/generees/recettes-generees.json"); } catch (e) {}
  generees = generees.concat(gardees.map(function (g) {
    const copie = JSON.parse(JSON.stringify(g));
    copie.provenance = { source: "génération assistée", moteur: moteur.nom,
                         le: new Date().toISOString().slice(0, 10),
                         licence: "contenu original — rédigé pour Bouchées",
                         cuisineParUnHumain: false };
    return copie;
  }));
  fs.mkdirSync(path.join(racine, "donnees", "generees"), { recursive: true });
  ecrire("donnees/generees/recettes-generees.json", generees);

  const pub = lire("donnees/publication.json");
  if (!pub.lots.some((l) => l.id === lot)) {
    pub.lots.push({ id: lot, titre: "Semaine du " + lot, acces: "abonne",
                    hebdomadaire: true,
                    note: "Sept recettes visant les profils les moins servis." });
  }
  gardees.forEach(function (g) { pub.attribution[g.id] = lot; });
  ecrire("donnees/publication.json", pub);
  console.log("  " + gardees.length + " recette(s) publiée(s) dans " + lot);
  return journal;
}

/* ---------- 6 à 8 : les images ---------- */
async function cycleImages(donnees, options) {
  const journal = { generees: 0, acceptees: 0, rejetees: [] };
  const corpus = chargerCorpus();
  let manifeste = {};
  try { manifeste = lire("generation/images/manifeste.json"); } catch (e) {}

  titre("6 · Images à produire");
  const plan = Images.aGenerer(corpus, donnees, manifeste);
  if (!plan.length) { console.log("  toutes les images sont à jour"); return journal; }
  console.log("  " + plan.length + " image(s) — " +
    plan.filter((p) => p.etat === "manquante").length + " manquante(s), " +
    plan.filter((p) => p.etat === "périmée").length + " périmée(s)");

  const mImage = options.moteurImage || MoteursImage.choisir();
  const mVision = options.moteurVision || Vision.choisir();
  console.log("  génération : " + mImage.nom + (mImage.nom === "simule" ? "  (aucun moteur — fichiers factices)" : ""));
  console.log("  vérification : " + mVision.nom + (mVision.nom === "absent" ? "  (aucune vision — tout sera rejeté)" : ""));

  const limite = Number(val("--max", plan.length));
  /* Les images vivent à la racine, dans images/. C'est exactement ce que
   * l'URL /images/… du client résout côté serveur — les écrire ailleurs
   * donnait un 404 silencieux et un repli permanent sur l'illustration. */
  const dossier = path.join(racine, "images");
  if (!options.sec) fs.mkdirSync(dossier, { recursive: true });

  titre("7 · Génération et vérification");
  for (const p of plan.slice(0, limite)) {
    const recette = corpus.find((r) => r.id === p.id);
    let img;
    try { img = await mImage.generer({ prompt: p.prompt, negatif: p.negatif, largeur: 1024, hauteur: 768 }); }
    catch (e) { journal.rejetees.push({ id: p.id, raison: "génération : " + e.message }); console.log("  ✕ " + p.nom + " — " + e.message); continue; }
    journal.generees++;

    const verdict = await Vision.verifier(img.octets, recette, donnees, { moteur: mVision, typeMime: "image/png" });
    if (!verdict.ok) {
      journal.rejetees.push({ id: p.id, raison: verdict.erreurs.join(" ; "), detectes: verdict.detectes });
      console.log("  ✕ " + p.nom + " — " + verdict.erreurs[0]);
      console.log("      → l'app garde son illustration pour cette recette");
      continue;
    }
    if (options.sec) { console.log("  ✓ [à sec] " + p.nom); journal.acceptees++; continue; }

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
    console.log("  ✓ " + p.nom + (verdict.avertissements.length ? "  (" + verdict.avertissements[0] + ")" : ""));
  }

  if (!options.sec) {
    fs.mkdirSync(path.join(racine, "generation", "images"), { recursive: true });
    ecrire("generation/images/manifeste.json", manifeste);
  }
  return journal;
}

async function principal() {
  const donnees = chargerDonnees();
  const options = { sec: a("--sec"), lot: val("--lot", null) };
  console.log("═".repeat(64));
  console.log("  Cycle Bouchées — " + new Date().toISOString().slice(0, 10) + (options.sec ? "   [À SEC]" : ""));
  console.log("═".repeat(64));

  let jr = null, ji = null;
  if (!a("--images-seulement")) jr = await cycleRecettes(donnees, options);
  if (!a("--recettes-seulement")) ji = await cycleImages(donnees, options);

  if (!options.sec) {
    titre("8 · Republication");
    const r = Publier.publier();
    fs.mkdirSync(path.join(racine, "dist", "lots"), { recursive: true });
    fs.writeFileSync(path.join(racine, "dist", "manifeste.json"), JSON.stringify(r.manifeste, null, 2) + "\n");
    fs.writeFileSync(path.join(racine, "dist", "securite.json"), JSON.stringify(r.securite) + "\n");
    Object.keys(r.contenu).forEach(function (lot) {
      fs.writeFileSync(path.join(racine, "dist", "lots", lot + ".json"), JSON.stringify(r.contenu[lot]) + "\n");
    });
    r.manifeste.lots.forEach(function (l) {
      console.log("  " + l.id + "  " + (l.acces === "libre" ? "libre " : "abonné") + "  " +
        String(l.nombre).padStart(2) + " recettes");
    });
  }

  titre("Bilan");
  if (jr) console.log("  recettes  : " + jr.acceptees + " acceptée(s), " + jr.rejetees.length + " rejetée(s)");
  if (ji) console.log("  images    : " + ji.acceptees + " publiée(s), " + ji.rejetees.length + " rejetée(s)");
  const revoir = (jr && jr.aRevoir.length) || 0;
  if (revoir) console.log("  réserves  : " + revoir + " recette(s) avec avertissement");

  if (!options.sec) {
    ecrire("outils/journal-cycle.json", { le: new Date().toISOString(), recettes: jr, images: ji });
    console.log("  journal   : outils/journal-cycle.json");
  }

  console.log("\n  Ce que le cycle NE peut pas vérifier : le goût, la levée, la texture réelle.");
  console.log("  Une recette non cuisinée peut être ratée — jamais dangereuse : la sécurité");
  console.log("  vit dans les tables déterministes, pas dans le test en cuisine.\n");
}

if (require.main === module) {
  principal().catch(function (e) { console.error("Cycle interrompu : " + e.message); process.exit(1); });
}

module.exports = { cycleRecettes: cycleRecettes, cycleImages: cycleImages, semaineCourante: semaineCourante };
