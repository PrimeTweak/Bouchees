/* Vision check on generated images.
 *
 * THE MODEL DESCRIBES; THE CODE DECIDES. A vision model is asked what it sees,
 * in plain words. It is never asked whether the image is acceptable — that
 * judgement stays here, in code we can read and test.
 *
 * An image is REJECTED when:
 *   - a food appears that the recipe does not contain;
 *   - a choking hazard is visible for the target age;
 *   - the picture is clearly a different dish;
 *   - the model fails, answers unreadably, or is missing entirely.
 *
 * That last case matters most. A failure never means acceptance: no verdict,
 * no photo, and the app falls back to its illustration.
 */
"use strict";
const path = require("path");

/* Visual vocabulary: what a vision model is likely to name, mapped to the
 * allergen families. The table decides, not the model. */
const VOCABULAIRE = {
  milk: ["fromage", "cheddar", "mozzarella", "parmesan", "crème", "creme", "beurre", "yogourt", "yaourt",
         "lait", "cheese", "butter", "cream", "yogurt", "milk", "gratin", "béchamel"],
  egg: ["œuf", "oeuf", "jaune d'œuf", "blanc d'œuf", "omelette", "egg", "frittata", "meringue"],
  peanut: ["arachide", "cacahuète", "cacahuete", "peanut", "beurre d'arachide"],
  tree_nut: ["noix", "amande", "pacane", "noisette", "pistache", "cajou", "walnut", "almond", "pecan",
         "hazelnut", "cashew", "pistachio"],
  /* "batter" on its own is too broad: baking powder is not wheat. The real
   * forms are named instead. */
  wheat: ["pain", "croûton", "crouton", "chapelure", "biscuit", "bread", "breadcrumb",
        "pasta", "cracker", "tortilla de blé", "pâtes", "pâte à pizza", "pâte brisée", "pâte feuilletée",
        "pâte à tarte", "farine de blé", "couscous", "spaghetti", "macaroni", "penne", "baguette"],
  soy: ["sauce soya", "sauce soja", "tofu", "edamame", "soy sauce", "soybean"],
  sesame: ["sésame", "sesame", "tahini", "graines de sésame"],
  fish: ["poisson", "saumon", "thon", "morue", "fish", "salmon", "tuna", "cod", "anchois"],
  shellfish: ["crevette", "crabe", "homard", "moule", "palourde", "shrimp", "crab",
                         "lobster", "mussel", "clam", "calmar"],
  mustard: ["moutarde", "mustard", "dijon"],
  sulphites: ["abricot séché", "raisin doré", "fruits séchés orange", "dried apricot"]
};

/* Choking hazards an image must not show to a toddler audience, whatever the
 * allergens are. */
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

/* The plant-based trap: "lait de coco" contains the word lait without being
 * produit laitier, « beurre de tournesol » n'est pas du beurre. Ces formes
 * sont reconnues AVANT le vocabulaire, et elles neutralisent la famille. */
const INNOCENTS = [
  /* Formes anglaises — les descriptions de vision sont maintenant en anglais,
   * dairy, and "coconut milk" does the same in English. */
  { reason: /\b(coconut|rice|oat|almond|soy|hazelnut) milk\b/, except: null },
  { reason: /\b(coconut|rice|oat|soy) (beverage|drink|cream)\b/, except: null },
  { reason: /\b(coconut|soy|oat) yogh?urt\b/, except: null },
  { reason: /\b(sunflower seed|coconut|cocoa) butter\b/, except: null },
  { reason: /\bpeanut butter\b/, except: "peanut" },
  { reason: /\b(almond|hazelnut|cashew) butter\b/, except: "tree_nut" },
  { reason: /\b(vegan|plant-based|dairy-free) cheese\b/, except: null },
  { reason: /\bmargarine\b/, except: null },
  { reason: /\b(rice|chickpea|oat|corn|buckwheat) flour\b/, except: null },
  { reason: /\bbaking (powder|soda)\b/, except: null },
  { reason: /\bnutritional yeast\b/, except: null },
  { reason: /\blait (de|d ) ?(coco|riz|avoine|amande|soya|soja|noisette)\b/, except: null },
  { reason: /\bboisson (de|d ) ?(coco|riz|avoine|amande|soya|soja)\b/, except: null },
  { reason: /\bcreme (de|d ) ?(coco|riz|avoine|soya|soja)\b/, except: null },
  { reason: /\byogourt (de|d ) ?(coco|soya|soja|avoine)\b/, except: null },
  { reason: /\bbeurre (de|d ) ?(tournesol|coco|cacao)\b/, except: null },
  { reason: /\bbeurre (de|d ) ?(arachide|cacahuete)\b/, except: "peanut" },
  { reason: /\bbeurre (de|d ) ?(amande|noisette|cajou)\b/, except: "tree_nut" },
  { reason: /\bfromage (vegetal|vegetalien|vegan)\b/, except: null },
  { reason: /\bmargarine\b/, except: null },
  { reason: /\bfarine (de|d ) ?(riz|pois chiches|avoine|mais|sarrasin)\b/, except: null },
  { reason: /\bpates (de|d ) ?riz\b/, except: null },
  { reason: /\btortillas? (de|d ) ?mais\b/, except: null },
  { reason: /\bsauce tamari\b/, except: "soy" },
  { reason: /\bnoix (de|d ) ?coco\b/, except: null },
  { reason: /\blait maternel\b/, except: null },
  { reason: /\bpoudre a pate\b/, except: null },
  { reason: /\bbicarbonate\b/, except: null },
  { reason: /\blevure\b/, except: null }
];

/* Families implied by a named food — the code decides, not the model. */
function famillesDe(alimentNormalise) {
  for (let i = 0; i < INNOCENTS.length; i++) {
    if (INNOCENTS[i].reason.test(alimentNormalise)) {
      return INNOCENTS[i].except ? [INNOCENTS[i].except] : [];
    }
  }
  const out = [];
  Object.keys(VOCABULAIRE).forEach(function (famille) {
    const touche = VOCABULAIRE[famille].some(function (mot) {
      const m = normaliser(mot);
      /* word boundaries on both sides, plural tolerated */
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
  name: "anthropic",
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
  name: "openai",
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

/* With no vision configured we do not guess: the image is declared unreadable,
 * ce qui la fait rejeter. L'app garde son illustration. */
const absent = {
  name: "absent",
  disponible: function () { return true; },
  decrire: async function () {
    return JSON.stringify({ aliments: [], lisible: false,
      incertitudes: ["aucun modèle de vision configuré"] });
  }
};

const MOTEURS = { anthropic: anthropic, openai: openai, absent: absent };

function choisir(name) {
  const target = name || process.env.MOTEUR_VISION || "";
  if (target && MOTEURS[target]) return MOTEURS[target];
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

/* The core: compare what the vision named against what the recipe contains.
 * The verdict comes from the code, not from the model. */
function comparer(description, recette, donnees) {
  const catalogue = donnees.catalogue;
  const Engine = require(path.join(__dirname, "..", "engine", "engine.js"));
  const erreurs = [], avertissements = [];

  if (!description.lisible) {
    return { ok: false, erreurs: ["image jugée illisible par la vision : " +
      (description.incertitudes.join(", ") || "sans détail")], avertissements: [], detectes: [] };
  }
  if (!description.aliments.length) {
    return { ok: false, erreurs: ["aucun aliment identifié dans l'image"], avertissements: [], detectes: [] };
  }

  const vus = description.aliments.map(normaliser);
  const presentes = Engine.analyserAllergenes(recette, catalogue);

  /* 1. An allergen ABSENT from the recipe must not appear in the image.
   *    This is the check that really matters. */
  vus.forEach(function (aliment, i) {
    famillesDe(aliment).forEach(function (famille) {
      if (presentes.indexOf(famille) !== -1) return;
      const name = donnees.base.allergens.find(function (a) { return a.id === famille; });
      const msg = "l'image montre « " + description.aliments[i] + " » alors que la recette ne contient pas de " +
        (name ? name.name.toLowerCase() : famille);
      if (erreurs.indexOf(msg) === -1) erreurs.push(msg);
    });
  });

  /* 2. Choking hazards, whatever the allergens are. */
  Object.keys(RISQUES_VISUELS).forEach(function (risque) {
    const touches = RISQUES_VISUELS[risque].filter(function (mot) {
      const m = normaliser(mot);
      return vus.some(function (v) { return v.indexOf(m) !== -1; });
    });
    if (touches.length) erreurs.push("l'image montre un risque d'étouffement : " + risque);
  });

  /* 3. The image has to look like the recipe: at least one main ingredient
   *    recognised, otherwise it may well be a picture of another dish. */
  const principaux = recette.ingredients.map(function (u) {
    const d = catalogue[u.id];
    return d ? normaliser(d.name.split("(")[0].trim()) : null;
  }).filter(Boolean);
  const reconnus = principaux.filter(function (p) {
    const mots = p.split(/\s+/).filter(function (w) { return w.length > 3; });
    return vus.some(function (v) { return mots.some(function (w) { return v.indexOf(w) !== -1 || w.indexOf(v) !== -1; }); });
  });
  if (!reconnus.length) {
    erreurs.push("aucun ingrédient de la recette n'est reconnaissable dans l'image");
  } else if (reconnus.length < 2 && principaux.length >= 4) {
    /* One ingredient recognised is sometimes legitimate: in a photo of
     * muffins on voit « muffin », pas la banane ni l'avoine. Mais si la
     * vision ALSO hedges, that is the profile of a failed image — the one that
     * "could be couscous, polenta or turmeric". Measured: an orange mush got
     * through with recognised=1 and hedging.
     *
     * One ingredient recognised AND no hedging: accept.
     * One ingredient recognised AND hedging: reject. */
    if (description.incertitudes.length) {
      erreurs.push("un seul ingrédient reconnu sur " + principaux.length +
        ", et la vision hésite — l'image ne ressemble pas assez à la recette");
    } else {
      avertissements.push("un seul ingrédient reconnu sur " + principaux.length + " — ressemblance faible");
    }
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
    return { ok: false, moteur: moteur.name, erreurs: ["la vision a échoué : " + e.message],
             avertissements: [], detectes: [] };
  }
  const description = lireDescription(brut);
  const verdict = comparer(description, recette, donnees);
  verdict.moteur = moteur.name;
  verdict.le = new Date().toISOString();
  return verdict;
}

module.exports = { verifier: verifier, comparer: comparer, lireDescription: lireDescription,
                   famillesDe: famillesDe, normaliser: normaliser, INNOCENTS: INNOCENTS,
                   choisir: choisir, MOTEURS: MOTEURS, VOCABULAIRE: VOCABULAIRE,
                   RISQUES_VISUELS: RISQUES_VISUELS, CONSIGNE: CONSIGNE };
