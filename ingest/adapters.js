/* Adaptateurs de sources — lot 3, v0.2
 * Chaque adaptateur transforme le schéma d'une source to le format brut
 * commun : { source, externalId, originalName, portions?, tempsMin?,
 *            lines: [texte], steps: [texte], url?, license }
 * Le pipeline est agnostique de la source : brancher une vraie API = écrire
 * (ou réutiliser) un adaptateur et respecter sa licence. Voir LICENCES.md.
 */
"use strict";

/* Schéma « générique » — notre propre format d'échange (partenaires, exports).
 *
 * Accepte DEUX formes, parce que le prompt du mois demande au modèle un
 * tableau nu et qu'il serait absurde d'exiger un emballage manuel ensuite :
 *   [ {...}, {...} ]                      (tableau direct)
 *   { source, license, recettes: [...] }  (avec métadonnées)
 */
function generic(doc) {
  var wrapper = Array.isArray(doc)
    ? { source: "in-house", license: "original content, written for Bouchées", recipes: doc }
    : doc;
  /* Partner feeds arrive in whatever language the partner works in. A Quebec
   * feed uses French keys; ours uses English. Accept both rather than forcing
   * every partner to rewrite their export. */
  var list = wrapper.recipes || wrapper.recettes || [];
  return list.map(function (r) {
    return {
      source: wrapper.source || "generic",
      externalId: r.id,
      originalName: r.name || r.nom,
      servings: r.servings || r.portions || null,
      timeMinutes: r.timeMinutes || r.tempsMin || null,
      lines: (r.ingredients || []).slice(),
      steps: (r.steps || r.etapes || []).slice(),
      url: r.url || null,
      license: wrapper.license || wrapper.licence || "to be confirmed"
    };
  });
}

/* Schéma « spoonacular » — forme des réponses /recipes/{id}/information
 * (extendedIngredients[].original, analyzedInstructions[].steps[].step). */
function spoonacular(doc) {
  return (doc.recipes || []).map(function (r) {
    const steps = [];
    (r.analyzedInstructions || []).forEach(function (bloc) {
      (bloc.steps || []).forEach(function (s) { steps.push(s.step); });
    });
    return {
      source: doc.source || "spoonacular",
      externalId: String(r.id),
      originalName: r.title,
      servings: r.servings ? String(r.servings) + " portions" : null,
      timeMinutes: r.readyInMinutes || null,
      lines: (r.extendedIngredients || []).map(function (i) { return i.original; }),
      steps: steps,
      url: r.sourceUrl || null,
      license: doc.license || "voir conditions spoonacular"
    };
  });
}

/* Schéma « TheMealDB » — strIngredient1..20 / strMeasure1..20, strInstructions. */
function mealdb(doc) {
  return (doc.meals || []).map(function (m) {
    const lines = [];
    for (let i = 1; i <= 20; i++) {
      const ing = m["strIngredient" + i];
      if (ing && ing.trim()) {
        const mes = (m["strMeasure" + i] || "").trim();
        lines.push((mes + " " + ing).trim());
      }
    }
    return {
      source: doc.source || "themealdb",
      externalId: String(m.idMeal),
      originalName: m.strMeal,
      servings: null,
      timeMinutes: null,
      lines: lines,
      steps: String(m.strInstructions || "").split(/\r?\n/).map(function (l) { return l.trim(); }).filter(Boolean),
      url: m.strSource || null,
      license: doc.license || "voir conditions themealdb"
    };
  });
}

function detect(doc) {
  if (Array.isArray(doc)) return generic;
  if (doc.meals) return mealdb;
  if (doc.recipes && doc.recipes[0] && doc.recipes[0].extendedIngredients) return spoonacular;
  return generic;
}

module.exports = { generic: generic, spoonacular: spoonacular, mealdb: mealdb, detect: detect };
