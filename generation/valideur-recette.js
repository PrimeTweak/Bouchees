/* Validateur de recettes générées — bloc C
 * valider(recette, commande, donnees) → { ok, erreurs[], avertissements[] }
 *
 * Un modèle qui invente « graines de tournesol grillées » au lieu de
 * beurre_tournesol produit une recette invisible pour le moteur : elle
 * passerait le filtre allergène sans jamais avoir été analysée. Ce validateur
 * est la porte qui empêche ça.
 *
 * Erreur = rejet. Avertissement = quarantaine pour révision humaine.
 */
"use strict";
const path = require("path");
const Moteur = require(path.join(__dirname, "..", "moteur", "moteur.js"));

const ROLES = ["farine", "liant", "gras", "liquide", "lacte", "proteine", "sucrant",
               "fruit", "legume", "assaisonnement", "levant", "garniture", "autre"];
const UNITES = ["ml", "g", "unité", "unités", "gousse", "gousses", "tranche", "tranches",
                "boîte", "boîtes", "filet", "filets", "au goût"];

function valider(r, commande, donnees, idsExistants) {
  const e = [], a = [];
  const catalogue = donnees.catalogue;
  idsExistants = idsExistants || [];

  /* --- structure --- */
  if (!r || typeof r !== "object") return { ok: false, erreurs: ["objet invalide"], avertissements: [] };
  ["id", "nom", "categorie", "ageMinBase", "ingredients", "etapes"].forEach(function (k) {
    if (r[k] === undefined || r[k] === null) e.push("champ manquant : " + k);
  });
  if (e.length) return { ok: false, erreurs: e, avertissements: a };

  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(r.id)) e.push("id mal formé : " + r.id);
  if (idsExistants.indexOf(r.id) !== -1) e.push("id déjà utilisé : " + r.id);
  if (!Array.isArray(r.ingredients) || r.ingredients.length < 2) e.push("moins de 2 ingrédients");
  if (!Array.isArray(r.etapes) || r.etapes.length < 2) e.push("moins de 2 étapes");
  if (!Number.isInteger(r.ageMinBase) || r.ageMinBase < 6) e.push("ageMinBase invalide : " + r.ageMinBase);

  /* --- ingrédients : la porte principale --- */
  (r.ingredients || []).forEach(function (u, i) {
    if (!u || !u.id) { e.push("ingrédient " + i + " sans id"); return; }
    if (!catalogue[u.id]) { e.push("ingrédient hors catalogue : « " + u.id + " » — inventé par le modèle"); return; }
    if (u.role && ROLES.indexOf(u.role) === -1) e.push("rôle inconnu sur " + u.id + " : " + u.role);
    if (u.qte !== undefined && u.qte !== "" && !(typeof u.qte === "number" && u.qte > 0))
      e.push("quantité invalide sur " + u.id + " : " + u.qte);
    if (u.unite && UNITES.indexOf(u.unite) === -1) a.push("unité inhabituelle sur " + u.id + " : " + u.unite);
    const roleStructurel = ["liant", "gras", "farine", "liquide", "lacte", "proteine"];
    const rolesCat = catalogue[u.id].roles;
    if (!u.role && rolesCat.length > 1 && rolesCat.some(function (x) { return roleStructurel.indexOf(x) !== -1; }))
      a.push("rôle non précisé sur « " + u.id + " » alors qu'il en a plusieurs (" + rolesCat.join("/") + ") — à trancher");
  });
  if (e.length) return { ok: false, erreurs: e, avertissements: a };

  /* --- respect de la commande : l'allergène demandé absent doit l'être --- */
  const evite = (commande && commande.evite) || [];
  const presents = Moteur.analyserAllergenes(r, catalogue);
  const fuite = presents.filter(function (x) { return evite.indexOf(x) !== -1; });
  if (fuite.length) e.push("contient un allergène que la commande exclut : " + fuite.join(", "));

  if (commande && commande.categories && commande.categories.indexOf(r.categorie) === -1)
    a.push("catégorie « " + r.categorie + " » différente de la commande (" + commande.categories.join("/") + ")");
  if (commande && r.ageMinBase > commande.ageMois)
    a.push("âge minimal " + r.ageMinBase + " mois alors que la commande visait " + commande.ageMois + " mois");

  /* --- consignes d'âge : elles doivent être tenables à l'âge visé --- */
  r.ingredients.forEach(function (u) {
    const interdit = Moteur.interditPour(u.id, r.ageMinBase, donnees.base);
    if (interdit && interdit.action.type === "bloquer")
      e.push("« " + u.id + " » est interdit avant " + interdit.avantMois + " mois : " + interdit.raison);
    else if (interdit)
      a.push("« " + u.id + " » demande une préparation particulière à " + r.ageMinBase + " mois : " + interdit.raison);
  });

  /* --- le moteur doit savoir la traiter sans planter --- */
  try {
    const res = Moteur.adapterRecette(r, { allergenes: evite, ageMois: r.ageMinBase }, donnees);
    if (res.statut === "non_adaptable")
      e.push("le moteur la déclare non adaptable pour la commande elle-même");
    const restant = res.allergenesRestants.filter(function (x) { return evite.indexOf(x) !== -1; });
    if (restant.length) e.push("invariant violé après adaptation : " + restant.join(", "));
  } catch (err) {
    e.push("le moteur plante dessus : " + err.message);
  }

  /* --- rédaction --- */
  (r.etapes || []).forEach(function (s, i) {
    if (typeof s !== "string" || s.trim().length < 8) e.push("étape " + (i + 1) + " trop courte ou vide");
    else if (s.length > 320) a.push("étape " + (i + 1) + " très longue");
  });
  if (/délicieux|incroyable|meilleur|parfait|savoureux|irrésistible/i.test(r.nom || ""))
    a.push("nom avec superlatif marketing — à réécrire");

  return { ok: e.length === 0, erreurs: e, avertissements: a };
}

function validerLot(recettes, commande, donnees, idsExistants) {
  const vus = (idsExistants || []).slice();
  const acceptees = [], rejetees = [], aRevoir = [];
  (recettes || []).forEach(function (r) {
    const v = valider(r, commande, donnees, vus);
    if (!v.ok) { rejetees.push({ recette: r, erreurs: v.erreurs }); return; }
    vus.push(r.id);
    if (v.avertissements.length) aRevoir.push({ recette: r, avertissements: v.avertissements });
    else acceptees.push(r);
  });
  return { acceptees: acceptees, aRevoir: aRevoir, rejetees: rejetees };
}

module.exports = { valider: valider, validerLot: validerLot };
