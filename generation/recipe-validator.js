/* This validator is the gate that stops it. Validator for generated recipes
 * valider(recette, brief, data) → { ok, erreurs[], avertissements[] } */
"use strict";
const path = require("path");
const Engine = require(path.join(__dirname, "..", "engine", "engine.js"));

const ROLES = ["flour", "binder", "fat", "liquid", "dairy", "protein", "sweetener",
               "fruit", "vegetable", "seasoning", "leavening", "topping", "autre"];
const UNITES = ["ml", "g", "unit", "unit", "clove", "clove", "tranche", "tranches",
                "boîte", "boîtes", "filet", "filets", "au goût"];

function valider(r, brief, data, idsExistants) {
  const e = [], a = [];
  const catalogue = data.catalogue;
  idsExistants = idsExistants || [];

  /* --- structure --- */
  if (!r || typeof r !== "object") return { ok: false, erreurs: ["objet invalide"], avertissements: [] };
  ["id", "name", "category", "minAgeMonths", "ingredients", "steps"].forEach(function (k) {
    if (r[k] === undefined || r[k] === null) e.push("champ manquant : " + k);
  });
  if (e.length) return { ok: false, erreurs: e, avertissements: a };

  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(r.id)) e.push("malformed id: " + r.id);
  if (idsExistants.indexOf(r.id) !== -1) e.push("id déjà utilisé : " + r.id);
  if (!Array.isArray(r.ingredients) || r.ingredients.length < 2) e.push("moins de 2 ingrédients");
  if (!Array.isArray(r.steps) || r.steps.length < 2) e.push("moins de 2 étapes");
  if (!Number.isInteger(r.minAgeMonths) || r.minAgeMonths < 6) e.push("ageMinBase invalide : " + r.minAgeMonths);

  /* --- ingredients: the main gate --- */
  (r.ingredients || []).forEach(function (u, i) {
    if (!u || !u.id) { e.push("ingrédient " + i + " sans id"); return; }
    if (!catalogue[u.id]) { e.push("ingrédient hors catalogue : « " + u.id + " » — inventé par le modèle"); return; }
    if (u.role && ROLES.indexOf(u.role) === -1) e.push("rôle inconnu sur " + u.id + " : " + u.role);
    if (u.qty !== undefined && u.qty !== "" && !(typeof u.qty === "number" && u.qty > 0))
      e.push("quantité invalide sur " + u.id + " : " + u.qty);
    if (u.unit && UNITES.indexOf(u.unit) === -1) a.push("unité inhabituelle sur " + u.id + " : " + u.unit);
    const roleStructurel = ["binder", "fat", "flour", "liquid", "dairy", "protein"];
    const rolesCat = catalogue[u.id].roles;
    if (!u.role && rolesCat.length > 1 && rolesCat.some(function (x) { return roleStructurel.indexOf(x) !== -1; }))
      a.push("rôle non précisé sur « " + u.id + " » alors qu'il en a plusieurs (" + rolesCat.join("/") + ") — à trancher");
  });
  if (e.length) return { ok: false, erreurs: e, avertissements: a };

  /* --- honouring the commission: the excluded allergen must be absent --- */
  const evite = (brief && brief.evite) || [];
  const presents = Engine.analyserAllergenes(r, catalogue);
  const fuite = presents.filter(function (x) { return evite.indexOf(x) !== -1; });
  if (fuite.length) e.push("contient un allergène que la commande exclut : " + fuite.join(", "));

  if (r.category !== "Meal" && r.category !== "Snack")
    e.push("category must be Meal or Snack, not \"" + r.category + "\"");
  if (brief && brief.categories && brief.categories.indexOf(r.category) === -1)
    a.push("catégorie « " + r.category + " » différente de la commande (" + brief.categories.join("/") + ")");
  if (brief && r.minAgeMonths > brief.ageMois)
    a.push("âge minimal " + r.minAgeMonths + " mois alors que la commande visait " + brief.ageMois + " mois");

  /* --- the recipe standard (docs/RECIPE-STANDARD.md), the checkable part --- */
  standard(r, catalogue).forEach(function (x) { e.push(x); });

  /* --- age guidance: it has to be workable at the target age --- */
  r.ingredients.forEach(function (u) {
    const interdit = Engine.interditPour(u.id, r.minAgeMonths, data.base);
    if (interdit && interdit.action.type === "bloquer")
      e.push("« " + u.id + " » est interdit avant " + interdit.beforeMonths + " mois : " + interdit.reason);
    else if (interdit)
      a.push("« " + u.id + " » demande une préparation particulière à " + r.minAgeMonths + " mois : " + interdit.reason);
  });

  /* The engine must process the recipe without crashing. */
  try {
    const res = Engine.adapterRecette(r, { allergens: evite, ageMois: r.minAgeMonths }, data);
    if (res.status === "not_adaptable")
      e.push("le moteur la déclare non adaptable pour la commande elle-même");
    const restant = res.remainingAllergens.filter(function (x) { return evite.indexOf(x) !== -1; });
    if (restant.length) e.push("invariant violé après adaptation : " + restant.join(", "));
  } catch (err) {
    e.push("le moteur plante dessus : " + err.message);
  }

  /* --- writing --- */
  (r.steps || []).forEach(function (s, i) {
    if (typeof s !== "string" || s.trim().length < 8) e.push("étape " + (i + 1) + " trop courte ou vide");
    else if (s.length > 320) a.push("étape " + (i + 1) + " très longue");
  });
  if (/délicieux|incroyable|best|parfait|savoureux|irrésistible/i.test(r.name || ""))
    a.push("name avec superlatif marketing — à réécrire");

  return { ok: e.length === 0, erreurs: e, avertissements: a };
}

function validerLot(recettes, brief, data, idsExistants) {
  const seen = (idsExistants || []).slice();
  const acceptees = [], rejetees = [], aRevoir = [];
  (recettes || []).forEach(function (r) {
    const v = valider(r, brief, data, seen);
    if (!v.ok) { rejetees.push({ recette: r, erreurs: v.erreurs }); return; }
    seen.push(r.id);
    if (v.avertissements.length) aRevoir.push({ recette: r, avertissements: v.avertissements });
    else acceptees.push(r);
  });
  return { acceptees: acceptees, aRevoir: aRevoir, rejetees: rejetees };
}

/* The seven rules a program can check. A recipe that fails one is a draft,
 * not a recipe, whoever wrote it. */
const CUE = /\buntil\b|\bgolden\b|\btender\b|\bsoft\b|\bset\b|\bthick|\bbubbl|\bcooked through\b|\bfirm\b|\bsmooth\b|\bbrowned\b|\bcrisp|\bno pink\b|\bfork\b|\btoothpick\b|\bpulls away\b|\bfragrant\b|\bwilt|\btranslucent\b|\bopaque\b|\bflakes\b/i;
/* Verbs that cook. "heat", "melt" and "reduce" are out: "remove from the
 * heat", "melt the butter" and "reduce the heat" are preparation, and each
 * false positive here threw away a whole recipe. */
const COOKS = /\b(bake|roast|fry|saut[eé]|simmer|boil|cook|grill|steam|poach|broil|sear)\b/i;
const DURATION = /\d+\s*(?:to\s*\d+\s*)?(?:min|minute|hour|second|sec)s?\b/i;
const TEMP_BOTH = /\d{2,3}\s*°\s*C\s*\(\s*\d{3}\s*°\s*F\s*\)/;
const STOP = ["fresh", "ground", "large", "small", "dried", "whole", "plain", "unsweetened", "extract",
              "powder", "cooked", "natural", "mashed", "pitted", "rolled", "white", "cow", "heavy",
              "unsalted", "raw", "seeds", "juice", "paste", "flour", "milk", "oil", "sauce", "extra", "virgin"];

function standard(r, catalogue) {
  const out = [];
  const steps = Array.isArray(r.steps) ? r.steps : [];
  const text = steps.join(" ").toLowerCase();

  if (steps.length < 6 || steps.length > 10)
    out.push("standard 6: " + steps.length + " steps; a recipe has six to ten, one action each");
  steps.forEach(function (st, i) {
    /* Twenty is the target the prompt gives; twenty-six is the ceiling, the
     * room a temperature in both units or a doneness cue needs. */
    if (st.split(/\s+/).length > 26) out.push("standard 6: step " + (i + 1) + " runs past the ceiling of twenty-six words");
  });
  if (/all (?:the|of the) ingredients/.test(text))
    out.push("standard 1: \"all the ingredients\" names nothing; each ingredient is named with its preparation");

  /* Every ingredient named: at least one significant word of its catalogue
   * name appears in the steps. */
  (r.ingredients || []).forEach(function (u) {
    const def = catalogue[u.id];
    const name = ((def && def.name) || u.id).toLowerCase().replace(/\(.*?\)/g, "");
    const words = name.split(/[^a-z']+/).filter(function (w) { return w.length > 2 && STOP.indexOf(w) === -1; });
    const key = words.length ? words : name.split(/[^a-z']+/).filter(Boolean);
    const hit = key.some(function (w) { return text.indexOf(w.slice(0, Math.max(4, w.length - 1))) !== -1; });
    if (!hit) out.push("standard 1: " + name.trim() + " is never named in a step");
  });

  /* Every cooking step: a duration and a cue. */
  steps.forEach(function (st, i) {
    if (!COOKS.test(st)) return;
    /* A duration OR a cue. Demanding both threw out "bake for 18 to 20
     * minutes", which a parent with a baby on one arm can follow. */
    if (!DURATION.test(st) && !CUE.test(st))
      out.push("standard 5: step " + (i + 1) + " cooks without a duration or a doneness cue");
  });

  /* An oven recipe: both units, and the oven on before it is used. */
  if (/\b(oven|bake|roast)\b/i.test(text)) {
    if (!TEMP_BOTH.test(steps.join(" "))) out.push("standard 4: an oven temperature is written as 200 \u00b0C (400 \u00b0F)");
    const preheat = steps.findIndex(function (s) { return /preheat/i.test(s); });
    const bake = steps.findIndex(function (s) { return /\b(bake|roast)\b/i.test(s) && !/preheat/i.test(s); });
    if (preheat === -1 || (bake !== -1 && preheat > bake)) out.push("standard 2: the oven is preheated before anything bakes");
  }

  /* Yield in what a family eats. */
  if (r.servings && /\b(loaf|glass|verre|ml)\b/i.test(r.servings) && !/portion|serving/i.test(r.servings))
    out.push("standard 7: yield \"" + r.servings + "\" says nothing about portions");

  return out;
}

module.exports = { valider: valider, standard: standard, validerLot: validerLot };
