/* Vérification des images par vision
 *
 * Remplace la paire d'yeux humaine. Un modèle de vision décrit ce qu'il voit,
 * et le CODE compare cette description à la liste d'ingrédients réelle. Le
 * modèle n'a pas le droit de conclure : il décrit, on décide.
 *
 * Règle de prudence, non négociable : au moindre doute — vision indisponible,
 * réponse illisible, aliment non identifié — l'image est REJETÉE et l'app
 * retombe sur son illustration générée. Le repli est toujours sûr, donc le
 * coût d'un faux rejet est nul et celui d'un faux accord est un incident.
 */
"use strict";
const path = require("path");

/* Vocabulaire visuel : ce qu'un modèle de vision est susceptible de nommer,
 * relié aux familles d'allergènes. C'est la table qui décide, pas le modèle. */
const VOCABULAIRE = {
  lait: ["fromage", "cheddar", "mozzarella", "parmesan", "crème", "creme", "beurre", "yogourt", "yaourt",
         "lait", "cheese", "butter", "cream", "yogurt", "milk", "gratin", "béchamel"],
  oeuf: ["œuf", "oeuf", "jaune d'œuf", "blanc d'œuf", "omelette", "egg", "frittata", "meringue"],
  arachide: ["arachide", "cacahuète", "cacahuete", "peanut", "beurre d'arachide"],
  noix: ["noix", "amande", "pacane", "noisette", "pistache", "cajou", "walnut", "almond", "pecan",
         "hazelnut", "cashew", "pistachio"],
  /* « pâte » tout court est trop large : la poudre à pâte n'est pas du blé.
   * On nomme les formes réelles. */
  ble: ["pain", "croûton", "crouton", "chapelure", "biscuit", "bread", "breadcrumb",
        "pasta", "cracker", "tortilla de blé", "pâtes", "pâte à pizza", "pâte brisée", "pâte feuilletée",
        "pâte à tarte", "farine de blé", "couscous", "spaghetti", "macaroni", "penne", "baguette"],
  soya: ["sauce soya", "sauce soja", "tofu", "edamame", "soy sauce", "soybean"],
  sesame: ["sésame", "sesame", "tahini", "graines de sésame"],
  poisson: ["poisson", "saumon", "thon", "morue", "fish", "salmon", "tuna", "cod", "anchois"],
  crustaces_mollusques: ["crevette", "crabe", "homard", "moule", "palourde", "shrimp", "crab",
                         "lobster", "mussel", "clam", "calmar"],
  moutarde: ["moutarde", "mustard", "dijon"],
  sulfites: ["abricot séché", "raisin doré", "fruits séchés orange", "dried apricot"]
};

/* Aliments à risque d'étouffement qu'une image ne doit pas montrer pour un
 * public de tout-petits, quels que soient les allergènes. */
const RISQUES_VISUELS = {
  "noix entières": ["noix entière", "noix entières", "whole nut", "whole nuts", "amandes entières"],
  "raisins entiers": ["raisin entier", "raisins entiers", "whole grape", "whole grapes"],
  "tomates cerises entières": ["tomate cerise", "cherry tomato"],
  "bonbons durs": ["bonbon", "candy", "hard candy"],
  "saucisse en rondelles": ["rondelle de saucisse", "hot dog slice", "saucisse ronde"]
};

function normaliser(t) {
  return String(t || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/['\u2019]/g, " ").replace(/\s+/g, " ").trim();
}

/* Le piège des végétaux : « lait de coco » contient le mot lait sans être un
 * produit laitier, « beurre de tournesol » n'est pas du beurre. Ces formes
 * sont reconnues AVANT le vocabulaire, et elles neutralisent la famille. */
const INNOCENTS = [
  { motif: /\blait (de|d ) ?(coco|riz|avoine|amande|soya|soja|noisette)\b/, sauf: null },
  { motif: /\bboisson (de|d ) ?(coco|riz|avoine|amande|soya|soja)\b/, sauf: null },
  { motif: /\bcreme (de|d ) ?(coco|riz|avoine|soya|soja)\b/, sauf: null },
  { motif: /\byogourt (de|d ) ?(coco|soya|soja|avoine)\b/, sauf: null },
  { motif: /\bbeurre (de|d ) ?(tournesol|coco|cacao)\b/, sauf: null },
  { motif: /\bbeurre (de|d ) ?(arachide|cacahuete)\b/, sauf: "arachide" },
  { motif: /\bbeurre (de|d ) ?(amande|noisette|cajou)\b/, sauf: "noix" },
  { motif: /\bfromage (vegetal|vegetalien|vegan)\b/, sauf: null },
  { motif: /\bmargarine\b/, sauf: null },
  { motif: /\bfarine (de|d ) ?(riz|pois chiches|avoine|mais|sarrasin)\b/, sauf: null },
  { motif: /\bpates (de|d ) ?riz\b/, sauf: null },
  { motif: /\btortillas? (de|d ) ?mais\b/, sauf: null },
  { motif: /\bsauce tamari\b/, sauf: "soya" },
  { motif: /\bnoix (de|d ) ?coco\b/, sauf: null },
  { motif: /\blait maternel\b/, sauf: null },
  { motif: /\bpoudre a pate\b/, sauf: null },
  { motif: /\bbicarbonate\b/, sauf: null },
  { motif: /\blevure\b/, sauf: null }
];

/* Familles impliquées par un aliment nommé — le code décide, pas le modèle. */
function famillesDe(alimentNormalise) {
  for (let i = 0; i < INNOCENTS.length; i++) {
    if (INNOCENTS[i].motif.test(alimentNormalise)) {
      return INNOCENTS[i].sauf ? [INNOCENTS[i].sauf] : [];
    }
  }
  const out = [];
  Object.keys(VOCABULAIRE).forEach(function (famille) {
    const touche = VOCABULAIRE[famille].some(function (mot) {
      const m = normaliser(mot);
      /* frontières de mots des deux côtés, pluriel toléré */
      return new RegExp("(^|[^a-z])" + m.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "s?([^a-z]|$)")
        .test(alimentNormalise);
    });
    if (touche) out.push(famille);
  });
  return out;
}

const CONSIGNE = [
  "Tu décris une photo de plat. Tu ne juges rien, tu ne conclus rien : tu listes.",
  "",
  "Réponds UNIQUEMENT avec cet objet JSON, sans texte autour :",
  "{",
  '  "aliments": ["chaque aliment que tu vois distinctement, en français, au singulier"],',
  '  "lisible": true,',
  '  "incertitudes": ["ce que tu n\'arrives pas à identifier avec certitude"]',
  "}",
  "",
  "Règles :",
  "- Nomme chaque aliment visible, même en petite quantité, même en garniture.",
  "- Si tu hésites entre deux aliments, mets les DEUX dans aliments.",
  "- Si l'image est floue, vide, ou n'est pas un plat, mets lisible à false.",
  "- N'invente rien : ne nomme que ce qui est visible."
].join("\n");

const anthropic = {
  nom: "anthropic",
  disponible: function () { return !!process.env.ANTHROPIC_API_KEY; },
  decrire: async function (octets, typeMime) {
    const rep = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": process.env.ANTHROPIC_API_KEY, "anthropic-version": "2023-06-01",
                 "content-type": "application/json" },
      body: JSON.stringify({
        model: process.env.MODELE_VISION || "claude-sonnet-4-6",
        max_tokens: 800,
        messages: [{ role: "user", content: [
          { type: "image", source: { type: "base64", media_type: typeMime || "image/png",
                                     data: Buffer.from(octets).toString("base64") } },
          { type: "text", text: CONSIGNE }
        ] }]
      })
    });
    const d = await rep.json();
    if (!rep.ok) throw new Error(d.error && d.error.message || "réponse " + rep.status);
    return d.content.map(function (b) { return b.text || ""; }).join("\n");
  }
};

const openai = {
  nom: "openai",
  disponible: function () { return !!process.env.OPENAI_API_KEY; },
  decrire: async function (octets, typeMime) {
    const rep = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: "Bearer " + process.env.OPENAI_API_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: process.env.MODELE_VISION || "gpt-4o",
        messages: [{ role: "user", content: [
          { type: "text", text: CONSIGNE },
          { type: "image_url", image_url: { url: "data:" + (typeMime || "image/png") + ";base64," +
                                                 Buffer.from(octets).toString("base64") } }
        ] }]
      })
    });
    const d = await rep.json();
    if (!rep.ok) throw new Error(d.error && d.error.message || "réponse " + rep.status);
    return d.choices[0].message.content;
  }
};

/* Sans vision configurée, on ne devine pas : on déclare l'image illisible,
 * ce qui la fait rejeter. L'app garde son illustration. */
const absent = {
  nom: "absent",
  disponible: function () { return true; },
  decrire: async function () {
    return JSON.stringify({ aliments: [], lisible: false,
      incertitudes: ["aucun modèle de vision configuré"] });
  }
};

const MOTEURS = { anthropic: anthropic, openai: openai, absent: absent };

function choisir(nom) {
  const cible = nom || process.env.MOTEUR_VISION || "";
  if (cible && MOTEURS[cible]) return MOTEURS[cible];
  if (anthropic.disponible()) return anthropic;
  if (openai.disponible()) return openai;
  return absent;
}

function lireDescription(texte) {
  const t = String(texte).replace(/```json|```/g, "").trim();
  const a = t.indexOf("{"), b = t.lastIndexOf("}");
  if (a === -1 || b < a) return { aliments: [], lisible: false, incertitudes: ["réponse illisible"] };
  try {
    const o = JSON.parse(t.slice(a, b + 1));
    return { aliments: Array.isArray(o.aliments) ? o.aliments : [],
             lisible: o.lisible !== false,
             incertitudes: Array.isArray(o.incertitudes) ? o.incertitudes : [] };
  } catch (e) {
    return { aliments: [], lisible: false, incertitudes: ["JSON invalide"] };
  }
}

/* Le cœur : comparer ce que la vision a nommé à ce que la recette contient.
 * Le verdict sort du code, pas du modèle. */
function comparer(description, recette, donnees) {
  const catalogue = donnees.catalogue;
  const Moteur = require(path.join(__dirname, "..", "moteur", "moteur.js"));
  const erreurs = [], avertissements = [];

  if (!description.lisible) {
    return { ok: false, erreurs: ["image jugée illisible par la vision : " +
      (description.incertitudes.join(", ") || "sans détail")], avertissements: [], detectes: [] };
  }
  if (!description.aliments.length) {
    return { ok: false, erreurs: ["aucun aliment identifié dans l'image"], avertissements: [], detectes: [] };
  }

  const vus = description.aliments.map(normaliser);
  const presentes = Moteur.analyserAllergenes(recette, catalogue);

  /* 1. Un allergène ABSENT de la recette ne doit pas apparaître dans l'image.
   *    C'est le contrôle qui compte vraiment. */
  vus.forEach(function (aliment, i) {
    famillesDe(aliment).forEach(function (famille) {
      if (presentes.indexOf(famille) !== -1) return;
      const nom = donnees.base.allergenes.find(function (a) { return a.id === famille; });
      const msg = "l'image montre « " + description.aliments[i] + " » alors que la recette ne contient pas de " +
        (nom ? nom.nom.toLowerCase() : famille);
      if (erreurs.indexOf(msg) === -1) erreurs.push(msg);
    });
  });

  /* 2. Aliments à risque d'étouffement, quels que soient les allergènes. */
  Object.keys(RISQUES_VISUELS).forEach(function (risque) {
    const touches = RISQUES_VISUELS[risque].filter(function (mot) {
      const m = normaliser(mot);
      return vus.some(function (v) { return v.indexOf(m) !== -1; });
    });
    if (touches.length) erreurs.push("l'image montre un risque d'étouffement : " + risque);
  });

  /* 3. L'image doit ressembler à la recette : au moins un ingrédient principal
   *    reconnu, sinon c'est peut-être une image d'un autre plat. */
  const principaux = recette.ingredients.map(function (u) {
    const d = catalogue[u.id];
    return d ? normaliser(d.nom.split("(")[0].trim()) : null;
  }).filter(Boolean);
  const reconnus = principaux.filter(function (p) {
    const mots = p.split(/\s+/).filter(function (w) { return w.length > 3; });
    return vus.some(function (v) { return mots.some(function (w) { return v.indexOf(w) !== -1 || w.indexOf(v) !== -1; }); });
  });
  if (!reconnus.length) {
    erreurs.push("aucun ingrédient de la recette n'est reconnaissable dans l'image");
  } else if (reconnus.length < 2 && principaux.length >= 4) {
    avertissements.push("un seul ingrédient reconnu sur " + principaux.length + " — ressemblance faible");
  }

  if (description.incertitudes.length)
    avertissements.push("la vision hésite sur : " + description.incertitudes.join(", "));

  return { ok: erreurs.length === 0, erreurs: erreurs, avertissements: avertissements,
           detectes: description.aliments, reconnus: reconnus.length, attendus: principaux.length };
}

async function verifier(octets, recette, donnees, options) {
  options = options || {};
  const moteur = options.moteur || choisir();
  let brut;
  try { brut = await moteur.decrire(octets, options.typeMime || "image/png"); }
  catch (e) {
    return { ok: false, moteur: moteur.nom, erreurs: ["la vision a échoué : " + e.message],
             avertissements: [], detectes: [] };
  }
  const description = lireDescription(brut);
  const verdict = comparer(description, recette, donnees);
  verdict.moteur = moteur.nom;
  verdict.le = new Date().toISOString();
  return verdict;
}

module.exports = { verifier: verifier, comparer: comparer, lireDescription: lireDescription,
                   famillesDe: famillesDe, normaliser: normaliser, INNOCENTS: INNOCENTS,
                   choisir: choisir, MOTEURS: MOTEURS, VOCABULAIRE: VOCABULAIRE,
                   RISQUES_VISUELS: RISQUES_VISUELS, CONSIGNE: CONSIGNE };
