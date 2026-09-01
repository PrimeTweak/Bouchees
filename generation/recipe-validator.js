/* This validator is the gate that stops it. Validator for generated recipes
 * valider(recette, commande, data) → { ok, erreurs[], avertissements[] } */
"use strict";
const path = require("path");
const Engine = require(path.join(__dirname, "..", "engine", "engine.js"));

const ROLES = ["flour", "binder", "fat", "liquid", "dairy", "protein", "sweetener",
               "fruit", "vegetable", "seasoning", "leavening", "topping", "autre"];
const UNITES = ["ml", "g", "unit", "unit", "clove", "clove", "tranche", "tranches",
                "boîte", "boîtes", "filet", "filets", "au goût"];

function valider(r, commande, data, idsExistants) {
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
  const evite = (commande && commande.evite) || [];
  const presents = Engine.analyserAllergenes(r, catalogue);
  const fuite = presents.filter(function (x) { return evite.indexOf(x) !== -1; });
  if (fuite.length) e.push("contient un allergène que la commande exclut : " + fuite.join(", "));

  if (commande && commande.categories && commande.categories.indexOf(r.category) === -1)
    a.push("catégorie « " + r.category + " » différente de la commande (" + commande.categories.join("/") + ")");
  if (commande && r.minAgeMonths > commande.ageMois)
    a.push("âge minimal " + r.minAgeMonths + " mois alors que la commande visait " + commande.ageMois + " mois");

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

function validerLot(recettes, commande, data, idsExistants) {
  const seen = (idsExistants || []).slice();
  const acceptees = [], rejetees = [], aRevoir = [];
  (recettes || []).forEach(function (r) {
    const v = valider(r, commande, data, seen);
    if (!v.ok) { rejetees.push({ recette: r, erreurs: v.erreurs }); return; }
    seen.push(r.id);
    if (v.avertissements.length) aRevoir.push({ recette: r, avertissements: v.avertissements });
    else acceptees.push(r);
  });
  return { acceptees: acceptees, aRevoir: aRevoir, rejetees: rejetees };
}

module.exports = { valider: valider, validerLot: validerLot };
