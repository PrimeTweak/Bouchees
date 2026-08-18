/* Adaptateurs de sources — lot 3, v0.2
 * Chaque adaptateur transforme le schéma d'une source vers le format brut
 * commun : { source, idExterne, nomOriginal, portions?, tempsMin?,
 *            lignes: [texte], etapes: [texte], url?, licence }
 * Le pipeline est agnostique de la source : brancher une vraie API = écrire
 * (ou réutiliser) un adaptateur et respecter sa licence. Voir LICENCES.md.
 */
"use strict";

/* Schéma « générique » — notre propre format d'échange (partenaires, exports). */
function generique(doc) {
  return (doc.recettes || []).map(function (r) {
    return {
      source: doc.source || "generique",
      idExterne: r.id,
      nomOriginal: r.nom,
      portions: r.portions || null,
      tempsMin: r.tempsMin || null,
      lignes: r.ingredients.slice(),
      etapes: (r.etapes || []).slice(),
      url: r.url || null,
      licence: doc.licence || "à préciser"
    };
  });
}

/* Schéma « spoonacular » — forme des réponses /recipes/{id}/information
 * (extendedIngredients[].original, analyzedInstructions[].steps[].step). */
function spoonacular(doc) {
  return (doc.recipes || []).map(function (r) {
    const etapes = [];
    (r.analyzedInstructions || []).forEach(function (bloc) {
      (bloc.steps || []).forEach(function (s) { etapes.push(s.step); });
    });
    return {
      source: doc.source || "spoonacular",
      idExterne: String(r.id),
      nomOriginal: r.title,
      portions: r.servings ? String(r.servings) + " portions" : null,
      tempsMin: r.readyInMinutes || null,
      lignes: (r.extendedIngredients || []).map(function (i) { return i.original; }),
      etapes: etapes,
      url: r.sourceUrl || null,
      licence: doc.licence || "voir conditions spoonacular"
    };
  });
}

/* Schéma « TheMealDB » — strIngredient1..20 / strMeasure1..20, strInstructions. */
function mealdb(doc) {
  return (doc.meals || []).map(function (m) {
    const lignes = [];
    for (let i = 1; i <= 20; i++) {
      const ing = m["strIngredient" + i];
      if (ing && ing.trim()) {
        const mes = (m["strMeasure" + i] || "").trim();
        lignes.push((mes + " " + ing).trim());
      }
    }
    return {
      source: doc.source || "themealdb",
      idExterne: String(m.idMeal),
      nomOriginal: m.strMeal,
      portions: null,
      tempsMin: null,
      lignes: lignes,
      etapes: String(m.strInstructions || "").split(/\r?\n/).map(function (l) { return l.trim(); }).filter(Boolean),
      url: m.strSource || null,
      licence: doc.licence || "voir conditions themealdb"
    };
  });
}

function detecter(doc) {
  if (doc.meals) return mealdb;
  if (doc.recipes && doc.recipes[0] && doc.recipes[0].extendedIngredients) return spoonacular;
  return generique;
}

module.exports = { generique: generique, spoonacular: spoonacular, mealdb: mealdb, detecter: detecter };
