/* Génération de recettes — prompt contraint (bloc C)
 * node generation/prompt-recette.js  →  écrit generation/prompt-du-mois.txt
 *
 * Le modèle ne rédige PAS librement : il reçoit la liste fermée des
 * identifiants d'ingrédients du catalogue et n'a le droit de nommer que
 * ceux-là. Tout le reste (allergènes, âges, substitutions) est déjà
 * déterministe — le modèle ne décide d'aucune question de sécurité.
 *
 * La commande vient de outils/trous.js : on ne demande pas « 8 recettes »,
 * on demande ce qui manque réellement.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const racine = path.join(__dirname, "..");
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));

function ingredientsAutorises(catalogue, evite) {
  return Object.keys(catalogue).filter(function (id) {
    return catalogue[id].allergenes.every(function (a) { return evite.indexOf(a) === -1; });
  });
}

function tableIngredients(catalogue, ids) {
  return ids.map(function (id) {
    const d = catalogue[id];
    return "  " + id + "  —  " + d.nom + "  [rôles : " + d.roles.join(", ") + "]";
  }).join("\n");
}

function construire(ligne, donnees) {
  const catalogue = donnees.catalogue;
  const base = donnees.base;
  const autorises = ingredientsAutorises(catalogue, ligne.evite);
  const interditsAge = base.interdits
    .filter(function (r) { return ligne.ageMois < r.avantMois; })
    .map(function (r) {
      const d = catalogue[r.cible];
      return "  " + r.cible + " (" + (d ? d.nom : r.cible) + ") — " + r.raison;
    });

  const nomsEvites = ligne.evite.map(function (id) {
    const a = base.allergenes.find(function (x) { return x.id === id; });
    return a ? a.nom : id;
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
"  Pourquoi : " + ligne.raison,
"",
"RÈGLE ABSOLUE",
"  Tu ne peux utiliser QUE les identifiants d'ingrédients de la liste ci-dessous.",
"  Aucun ingrédient inventé, aucun nom libre, aucune variante orthographique.",
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
'    "nom": "Nom en français, appétissant, sans superlatif",',
'    "categorie": "' + ligne.categories[0] + '",',
'    "portions": "4 portions",',
'    "ageMinBase": ' + ligne.ageMois + ",",
'    "tempsMin": 30,',
'    "ingredients": [',
'      { "id": "identifiant_du_catalogue", "qte": 250, "unite": "ml", "role": "farine" }',
"    ],",
'    "etapes": ["Phrase à l\'impératif.", "..."]',
"  }",
"",
"CONSIGNES DE RÉDACTION",
"  - Le champ role est obligatoire dès qu'un ingrédient joue un rôle structurel",
"    (liant, gras, farine, liquide, lacte, proteine). C'est lui qui pilote les",
"    substitutions : un œuf liant et un œuf protéine ne se remplacent pas pareil.",
"  - Unités métriques : ml, g, ou une unité naturelle (unité, gousse, tranche).",
"  - Étapes courtes, à l'impératif, sans jargon. 3 à 6 étapes.",
"  - Pas de sel ajouté avant 12 mois, pas de sucre ajouté avant 24 mois.",
"  - Pas de superlatif marketing dans le nom ni les étapes.",
"  - Une recette qu'un parent pressé peut faire un mardi soir.",
"",
"RAPPEL",
"  Ta sortie passe ensuite par un validateur automatique, puis par une personne",
"  qui cuisine la recette pour vrai avant publication. Écris pour être cuisiné,",
"  pas pour impressionner."
  ].join("\n");
}

function construireTout(commande, donnees) {
  return commande.map(function (l) { return construire(l, donnees); });
}

if (require.main === module) {
  const donnees = {
    catalogue: lire("donnees/ingredients.json"),
    substitutions: lire("donnees/substitutions.json"),
    base: lire("donnees/base.json")
  };
  let commande;
  try {
    commande = lire("outils/rapport-trous.json").commande;
  } catch (e) {
    console.error("Lance d'abord : node outils/trous.js");
    process.exit(1);
  }
  if (!commande.length) {
    console.log("Aucun trou sous les seuils — pas de commande à générer ce mois-ci.");
    process.exit(0);
  }
  const prompts = construireTout(commande, donnees);
  const sortie = prompts.map(function (p, i) {
    return "═".repeat(72) + "\nPROMPT " + (i + 1) + " / " + prompts.length + "\n" + "═".repeat(72) + "\n\n" + p;
  }).join("\n\n\n");
  fs.writeFileSync(path.join(racine, "generation", "prompt-du-mois.txt"), sortie + "\n");
  console.log("Écrit : generation/prompt-du-mois.txt (" + prompts.length + " prompt(s), " +
    commande.reduce((s, c) => s + c.n, 0) + " recettes commandées)");
}

module.exports = { construire: construire, construireTout: construireTout, ingredientsAutorises: ingredientsAutorises };
