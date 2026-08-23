/* Moteurs de texte — rédaction des recettes
 *
 * Trois adaptateurs derrière une seule interface. Le reste du pipeline ne sait
 * pas lequel tourne : il reçoit du JSON et le passe au validateur, qui rejette
 * tout ce qui sort du catalogue. Le modèle ne décide d'aucune question de
 * sécurité — il rédige, les tables décident.
 *
 *   anthropic  — ANTHROPIC_API_KEY
 *   openai     — OPENAI_API_KEY
 *   simule     — hors ligne, pour les tests
 */
"use strict";

/* Un modèle bavard entoure son JSON de texte. On récupère le tableau. */
function extraireJSON(texte) {
  const t = String(texte).replace(/```json|```/g, "").trim();
  const debut = t.indexOf("[");
  const fin = t.lastIndexOf("]");
  if (debut === -1 || fin === -1 || fin < debut) {
    const o1 = t.indexOf("{"), o2 = t.lastIndexOf("}");
    if (o1 !== -1 && o2 > o1) {
      const un = JSON.parse(t.slice(o1, o2 + 1));
      return Array.isArray(un) ? un : [un];
    }
    throw new Error("aucun JSON trouvé dans la réponse du modèle");
  }
  return JSON.parse(t.slice(debut, fin + 1));
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

/* Simulé : compose une recette valide à partir du catalogue autorisé lu dans
 * le prompt. Ça permet de faire tourner le cycle complet sans réseau. */
const simule = {
  name: "simule",
  disponible: function () { return true; },
  rediger: async function (prompt) {
    const ids = [];
    const re = /^\s{2}([a-z0-9_]+)\s+—\s+/gm;
    let m;
    while ((m = re.exec(prompt))) ids.push(m[1]);
    const mCat = prompt.match(/de catégorie « ([^»]+) »/);
    const mAge = prompt.match(/Âge minimal visé : (\d+)/);
    const mN = prompt.match(/^\s+(\d+) recette\(s\)/m);
    const categorie = mCat ? mCat[1].trim() : "Collation";
    const ageMinBase = mAge ? parseInt(mAge[1], 10) : 12;
    const n = mN ? parseInt(mN[1], 10) : 1;

    const par = function (role) { return ids.filter(function (id) { return SIMULE_ROLES[id] === role; }); };
    const out = [];
    for (let i = 0; i < n; i++) {
      const base = par("fruit")[i % Math.max(par("fruit").length, 1)] || ids[0];
      const liant = par("binder")[i % Math.max(par("binder").length, 1)] || ids[1];
      const assais = par("seasoning")[i % Math.max(par("seasoning").length, 1)] || ids[2];
      out.push({
        id: "simule-" + categorie.toLowerCase() + "-" + (i + 1),
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

/* Table minimale de rôles pour le mode simulé — le vrai catalogue reste la
 * source de vérité partout ailleurs. */
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
