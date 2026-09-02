/* The rest of the pipeline does not know which one is running: it receives
 * JSON and hands it to the validator, which rejects anything outside the
 * catalogue. Text engines — writing the recipes */
"use strict";

/* A chatty model wraps its JSON in prose. The array is pulled back out. */
function extraireJSON(texte) {
  const t = String(texte).replace(/```json|```/g, "").trim();
  const debut = t.indexOf("[");
  const finish = t.lastIndexOf("]");
  if (debut === -1 || finish === -1 || finish < debut) {
    const o1 = t.indexOf("{"), o2 = t.lastIndexOf("}");
    if (o1 !== -1 && o2 > o1) {
      const un = JSON.parse(t.slice(o1, o2 + 1));
      return Array.isArray(un) ? un : [un];
    }
    throw new Error("aucun JSON trouvé dans la réponse du modèle");
  }
  return JSON.parse(t.slice(debut, finish + 1));
}

const anthropic = {
  name: "anthropic",
  disponible: function () { return !!process.env.ANTHROPIC_API_KEY; },
  rediger: async function (prompt) {
    const rep = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": process.env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
      },
      body: JSON.stringify({
        model: process.env.MODELE_TEXTE || "claude-sonnet-4-6",
        max_tokens: 4000,
        messages: [{ role: "user", content: prompt }]
      })
    });
    const d = await rep.json();
    if (!rep.ok) throw new Error(d.error && d.error.message || "réponse " + rep.status);
    return extraireJSON(d.content.map(function (b) { return b.text || ""; }).join("\n"));
  }
};

const openai = {
  name: "openai",
  disponible: function () { return !!process.env.OPENAI_API_KEY; },
  rediger: async function (prompt) {
    const rep = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: "Bearer " + process.env.OPENAI_API_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: process.env.MODELE_TEXTE || "gpt-4o",
        messages: [{ role: "user", content: prompt }]
      })
    });
    const d = await rep.json();
    if (!rep.ok) throw new Error(d.error && d.error.message || "réponse " + rep.status);
    return extraireJSON(d.choices[0].message.content);
  }
};

/* Simulated: composes a valid recipe from the allowed catalogue read out of
 * the prompt. Lets the whole cycle run with no network. */
const simule = {
  name: "simule",
  disponible: function () { return true; },
  rediger: async function (prompt) {
    const ids = [];
    const re = /^\s{2}([a-z0-9_]+)\s+—\s+/gm;
    let m;
    while ((m = re.exec(prompt))) ids.push(m[1]);
    const mCat = prompt.match(/of category "([^"]+)"/);
    const mAge = prompt.match(/Minimum age: (\d+)/);
    const mN = prompt.match(/^\s+(\d+) recipe\(s\)/m);
    const category = mCat ? mCat[1].trim() : "Snack";
    const minAgeMonths = mAge ? parseInt(mAge[1], 10) : 12;
    const n = mN ? parseInt(mN[1], 10) : 1;

    const par = function (role) { return ids.filter(function (id) { return SIMULE_ROLES[id] === role; }); };
    const out = [];
    for (let i = 0; i < n; i++) {
      const base = par("fruit")[i % Math.max(par("fruit").length, 1)] || ids[0];
      const liant = par("binder")[i % Math.max(par("binder").length, 1)] || ids[1];
      const assais = par("seasoning")[i % Math.max(par("seasoning").length, 1)] || ids[2];
      out.push({
        id: "simule-" + category.toLowerCase() + "-" + (i + 1),
        name: "Recette simulée " + (i + 1),
        category: category,
        servings: "4 portions",
        minAgeMonths: minAgeMonths,
        timeMinutes: 15,
        ingredients: [
          { id: base, qty: 250, unit: "ml" },
          { id: liant, qty: 125, unit: "ml", role: "binder" },
          { id: assais, qty: 2, unit: "ml" }
        ],
        steps: [
          "Écraser le premier ingrédient à la fourchette.",
          "Incorporer les autres ingrédients et mélanger.",
          "Servir tiède, à la texture qui convient à l'âge."
        ]
      });
    }
    return out;
  }
};

/* Minimal role table for the simulated mode — the real catalogue stays the
 * source of truth everywhere else. */
const SIMULE_ROLES = {
  compote_pommes: "binder", puree_banane: "binder", lin_moulu: "binder", graines_chia: "binder",
  banane: "fruit", pomme: "fruit", mangue: "fruit", bleuets: "fruit",
  cannelle: "seasoning", vanille: "seasoning", jus_citron: "seasoning"
};

const MOTEURS = { anthropic: anthropic, openai: openai, simule: simule };

function choisir(name) {
  const target = name || process.env.MOTEUR_TEXTE || "";
  if (target && MOTEURS[target]) return MOTEURS[target];
  if (anthropic.disponible()) return anthropic;
  if (openai.disponible()) return openai;
  return simule;
}

module.exports = { choisir: choisir, MOTEURS: MOTEURS, extraireJSON: extraireJSON };
