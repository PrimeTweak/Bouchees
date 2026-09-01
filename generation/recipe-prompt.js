/* Everything else (allergens, ages, substitutions) is already deterministic —
 * the model decides no safety question. */
"use strict";
const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const read = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));

function ingredientsAutorises(catalogue, evite) {
  return Object.keys(catalogue).filter(function (id) {
    return catalogue[id].allergens.every(function (a) { return evite.indexOf(a) === -1; });
  });
}

function tableIngredients(catalogue, ids) {
  return ids.map(function (id) {
    const d = catalogue[id];
    return "  " + id + "  —  " + d.name + "  [rôles : " + d.roles.join(", ") + "]";
  }).join("\n");
}

function construire(ligne, data) {
  const catalogue = data.catalogue;
  const base = data.base;
  const autorises = ingredientsAutorises(catalogue, ligne.evite);
  const interditsAge = base.ageRules
    .filter(function (r) { return ligne.ageMois < r.beforeMonths; })
    .map(function (r) {
      const d = catalogue[r.target];
      return "  " + r.target + " (" + (d ? d.name : r.target) + ") — " + r.reason;
    });

  const nomsEvites = ligne.evite.map(function (id) {
    const a = base.allergens.find(function (x) { return x.id === id; });
    return a ? a.name : id;
  });

  return [
"Tu rédiges des recettes pour Bouchées, une application destinée aux parents",
"d'enfants avec des allergies alimentaires. La sécurité est gérée ailleurs, par",
"des tables déterministes : ton rôle est la rédaction culinaire, pas la décision.",
"",
"COMMANDE",
"  " + ligne.n + " recette(s) de catégorie « " + ligne.categories[0] + " »",
"  Âge minimal visé : " + ligne.ageMois + " mois",
"  Doit être exempte de : " + (nomsEvites.length ? nomsEvites.join(", ") : "aucune contrainte d'allergène"),
"  Pourquoi : " + ligne.reason,
"",
"RÈGLE ABSOLUE",
"  Tu ne peux utiliser QUE les identifiants d'ingrédients de la liste ci-dessous.",
"  Aucun ingrédient inventé, aucun name libre, aucune variante orthographique.",
"  Une recette contenant un identifiant hors liste est rejetée automatiquement.",
"",
"INGRÉDIENTS AUTORISÉS (" + autorises.length + ")",
tableIngredients(catalogue, autorises),
"",
"À ÉVITER À CET ÂGE (utilisables plus tard, pas ici)",
interditsAge.length ? interditsAge.join("\n") : "  aucun",
"",
"FORMAT DE SORTIE",
"  Un tableau JSON, rien d'autre — pas de texte avant ni après, pas de balises.",
"  Chaque objet :",
"  {",
'    "id": "identifiant-en-minuscules-avec-tirets",',
'    "name": "Nom en français, appétissant, sans superlatif",',
'    "category": "' + ligne.categories[0] + '",',
'    "servings": "4 portions",',
'    "minAgeMonths": ' + ligne.ageMois + ",",
'    "timeMinutes": 30,',
'    "ingredients": [',
'      { "id": "identifiant_du_catalogue", "qty": 250, "unit": "ml", "role": "flour" }',
"    ],",
'    "steps": ["Phrase à l\'impératif.", "..."]',
"  }",
"",
"CONSIGNES DE RÉDACTION",
"  - Le champ role est obligatoire dès qu'un ingrédient joue un rôle structurel",
"    (liant, gras, farine, liquide, lacte, proteine). C'est lui qui pilote les",
"    substitutions : un œuf liant et un œuf protéine ne se remplacent pas pareil.",
"  - Unités métriques : ml, g, ou une unité naturelle (unité, gousse, tranche).",
"  - Étapes courtes, à l'impératif, sans jargon. 3 à 6 étapes.",
"  - Pas de sel ajouté avant 12 mois, pas de sucre ajouté avant 24 mois.",
"  - Pas de superlatif marketing dans le name ni les étapes.",
"  - Une recette qu'un parent pressé peut faire un mardi soir.",
"",
"RAPPEL",
"  Ta sortie passe ensuite par un validateur automatique, puis par une personne",
"  qui cuisine la recette pour vrai avant publication. Écris pour être cuisiné,",
"  pas pour impressionner."
  ].join("\n");
}

function construireTout(commande, data) {
  return commande.map(function (l) { return construire(l, data); });
}

if (require.main === module) {
  const data = {
    catalogue: read("data/ingredients.json"),
    substitutions: read("data/substitutions.json"),
    base: read("data/base.json")
  };
  let commande;
  try {
    commande = read("tools/gap-report.json").commande;
  } catch (e) {
    console.error("Lance d'abord : node tools/gaps.js");
    process.exit(1);
  }
  if (!commande.length) {
    console.log("Aucun trou sous les seuils — pas de commande à générer ce mois-ci.");
    process.exit(0);
  }
  const prompts = construireTout(commande, data);
  const output = prompts.map(function (p, i) {
    return "═".repeat(72) + "\nPROMPT " + (i + 1) + " / " + prompts.length + "\n" + "═".repeat(72) + "\n\n" + p;
  }).join("\n\n\n");
  fs.writeFileSync(path.join(racine, "generation", "prompt-du-mois.txt"), output + "\n");
  console.log("Écrit : generation/monthly-prompt.txt (" + prompts.length + " prompt(s), " +
    commande.reduce((s, c) => s + c.n, 0) + " recettes commandées)");
}

module.exports = { construire: construire, construireTout: construireTout, ingredientsAutorises: ingredientsAutorises };
