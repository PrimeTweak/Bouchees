#!/usr/bin/env node
/* Is Draw Things ready to run a batch?
 *
 * WHY THIS EXISTS. The cycle sends a prompt and lets Draw Things apply its own
 * settings, which is correct — a distilled model driven by an SDXL solver
 * never finishes denoising. But it means the app's CURRENT selection decides
 * everything, and nothing checked it.
 *
 * On Krea 2 Raw at 52 steps a single image took two hours. Ten of them is
 * twenty hours, discovered after the first one. This asks the questions before
 * anything runs.
 */
"use strict";

const BASE = process.env.DRAWTHINGS_URL || "http://127.0.0.1:7860";

async function demander(chemin) {
  const controleur = new AbortController();
  const minuterie = setTimeout(() => controleur.abort(), 4000);
  try {
    const r = await fetch(BASE + chemin, { signal: controleur.signal });
    clearTimeout(minuterie);
    if (!r.ok) return null;
    return await r.json();
  } catch (e) {
    clearTimeout(minuterie);
    return null;
  }
}

(async function () {
  /* The console output is FRENCH on purpose: it is read by the person running
   * the batch, not by a developer. Everything else in this file - names,
   * comments, logic - is English like the rest of the code. */
  const problemes = [];
  const notes = [];

  /* 1. Is anything listening?
   *
   * GET / , not /sdapi/v1/options. Draw Things implements the endpoints that
   * do work — txt2img, img2img — and returns 404 for the introspection ones
   * that AUTOMATIC1111 exposes. Asking for options made this check report
   * "not responding" even with the server running. */
  const etat = await demander("/");
  if (!etat) {
    console.error("");
    console.error("  DRAW THINGS NE REPOND PAS");
    console.error("");
    console.error("  " + BASE + " est silencieux.");
    console.error("");
    console.error("  Dans Draw Things :");
    console.error("    1. icone ENGRENAGE, dans la barre de GAUCHE");
    console.error("    2. onglet  Advanced");
    console.error("    3. descends jusqu'a  API Server");
    console.error("");
    console.error("  Quatre reglages, et le deuxieme est celui qu'on rate :");
    console.error("    Server Online   On  (le point doit etre vert)");
    console.error("    Protocol        HTTP     <-- PAS gRPC");
    console.error("    Port            celui que l'app propose");
    console.error("                    (souvent 7860, parfois 7859)");
    console.error("    TLS             Off");
    console.error("");
    console.error("  Laisse Draw Things ouvert, puis relance.");
    console.error("");
    process.exit(1);
  }

  /* 2. Which model is selected?
   *
   * The root response carries the app's current configuration. Field names
   * vary between versions, so several are tried and a miss is a note rather
   * than a failure — refusing to run because a field was renamed would be
   * worse than running. */
  const modele = String(etat.model || etat.sd_model_checkpoint ||
                        etat.sd_model || etat.checkpoint || "");
  if (!modele) {
    notes.push("le modèle n'est pas exposé par cette version de Draw Things");
  } else {
    const bas = modele.toLowerCase();
    if (bas.includes("raw")) {
      problemes.push(
        "le modèle sélectionné est « " + modele + " ».\n" +
        "      Raw est le checkpoint d'ENTRAÎNEMENT : 52 étapes par image.\n" +
        "      Krea recommande Turbo pour générer — 8 étapes, treize fois\n" +
        "      plus rapide. Dix images passeraient de vingt heures à deux.");
    } else {
      notes.push("modèle : " + modele);
    }
  }

  /* 3. How many images would run, and what does that cost? */
  const path = require("path");
  const fs = require("fs");
  const racine = path.join(__dirname, "..");
  const recettes = JSON.parse(fs.readFileSync(
    path.join(racine, "data/recipes.json"), "utf8"));
  let manifeste = {};
  try {
    manifeste = JSON.parse(fs.readFileSync(
      path.join(racine, "generation/images/manifest.json"), "utf8"));
  } catch (e) { /* first run */ }

  const aFaire = recettes.filter(function (r) { return !manifeste[r.id]; });
  notes.push(aFaire.length + " image(s) à générer sur " + recettes.length + " recettes");

  console.log("");
  console.log("  AVANT DE PARTIR");
  console.log("  " + "-".repeat(46));
  notes.forEach(function (n) { console.log("  ok   " + n); });

  if (problemes.length) {
    console.log("");
    problemes.forEach(function (p) { console.log("  ⚠    " + p); });
    console.log("");
    console.log("  Corrige dans Draw Things, puis relance.");
    console.log("");
    process.exit(1);
  }

  console.log("");
  console.log("  Tout est prêt.");
  console.log("");
})();
