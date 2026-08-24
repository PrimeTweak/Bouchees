/* Substitution engine — the only place that decides anything.
 *
 * Zero dependencies, UMD, runs identically in Node, a browser and
 * JavaScriptCore. That is deliberate: one engine means one truth, and on food
 * allergies a second implementation would be a second truth.
 *
 * INVARIANTS, PROVEN BY THE TEST SUITE
 *   - An adapted recipe never contains an avoided allergen.
 *   - No substitute is ever offered below its minimum age.
 *   - Allergens are DERIVED from the ingredient catalogue, never read off an
 *     external label. A partner feed can be wrong; our catalogue is the
 *     reference.
 *   - When no safe substitute exists, the recipe is marked not_adaptable with
 *     a blocking alert. Never a silent removal — a parent must see the reason.
 *   - Age rules apply to the FINAL ingredient, after substitution. Swapping in
 *     honey for a nine-month-old would otherwise slip through.
 */
(function (racine, fabrique) {
  if (typeof module !== "undefined" && module.exports) module.exports = fabrique();
  else racine.Engine = fabrique();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  /* ---------- utilitaires ---------- */

  function roleDe(usage, def) {
    return usage.role || (def && def.roles && def.roles[0]) || "autre";
  }

  function intersection(a, b) {
    return a.filter(function (x) { return b.indexOf(x) !== -1; });
  }

  /* Allergen families present in a list of ingredient usages, derived from the
   * catalogue — never read off an external label. */
  function allergenesDe(usages, catalogue) {
    var vus = {};
    usages.forEach(function (u) {
      if (u.status === "omitted" || u.status === "blocked") return;
      var id = u.to || u.id;
      var def = catalogue[id];
      if (!def) return;
      def.allergens.forEach(function (a) { vus[a] = true; });
    });
    return Object.keys(vus).sort();
  }

  function analyserAllergenes(recette, catalogue) {
    return allergenesDe(recette.ingredients, catalogue);
  }

  /* Texture stage that applies to a given age. */
  function stadePour(ageMois, base) {
    for (var i = 0; i < base.stages.length; i++) {
      var s = base.stages[i];
      if (ageMois >= s.min && ageMois <= s.max) return s;
    }
    return base.stages[base.stages.length - 1];
  }

  /* First age rule that applies to an ingredient at a given age. Rules are
   * ordered youngest bracket first in base.ageRules; the first match wins. */
  function interditPour(id, ageMois, base) {
    for (var i = 0; i < base.ageRules.length; i++) {
      var r = base.ageRules[i];
      if (r.target === id && ageMois < r.beforeMonths) return r;
    }
    return null;
  }

  /* Substitution rule for (ingredient, role). */
  function reglePour(id, role, tableSubst) {
    for (var i = 0; i < tableSubst.length; i++) {
      var r = tableSubst[i];
      if (r.target === id && r.role === role) return r;
    }
    return null;
  }

  /* Deterministic pick of a substitute: the first option in the table that
   * (1) introduces no avoided allergen,
   * (2) meets its own minimum age,
   * (3) is not itself blocked at that age with no way out.
   * Retourne null si aucune option ne passe. */
  function choisirSubstitut(regle, allergenesEvites, ageMois, catalogue, base) {
    if (!regle) return null;
    for (var i = 0; i < regle.options.length; i++) {
      var o = regle.options[i];
      if (o.minAgeMonths > ageMois) continue;
      if (o.id === "_omit") return o;
      var def = catalogue[o.id];
      if (!def) continue;
      if (intersection(def.allergens, allergenesEvites).length > 0) continue;
      var interdit = interditPour(o.id, ageMois, base);
      if (interdit && interdit.action.type === "block") continue;
      return o;
    }
    return null;
  }

  /* ---------- fonction principale ---------- */

  /* adapterRecette(recette, { allergens: [...], ageMois: n }, donnees)
   * donnees = { catalogue, substitutions, base }
   * Returns a complete object: ingredients carrying the origin of every
   * decision, graded alerts, texture guidance, overall status. */
  function adapterRecette(recette, options, donnees) {
    var evites = (options.allergens || []).slice().sort();
    var ageMois = options.ageMois;
    var catalogue = donnees.catalogue;
    var base = donnees.base;

    var resultat = {
      id: recette.id,
      name: recette.name,
      status: "as_is",          /* telle_quelle | adaptee | non_adaptable */
      swapCount: 0,
      ingredients: [],
      alerts: [],
      texture: stadePour(ageMois, base),
      steps: recette.steps
    };

    if (ageMois < recette.minAgeMonths) {
      resultat.alerts.push({
        level: "caution",
        message: "This recipe is written for " + recette.minAgeMonths + " months and up — texture and shape need rethinking below that age."
      });
    }

    recette.ingredients.forEach(function (usage) {
      var def = catalogue[usage.id];
      var role = roleDe(usage, def);
      var item = {
        id: usage.id,
        name: def ? def.name : usage.id,
        qty: usage.qty,
        unit: usage.unit,
        role: role,
        status: "kept"
      };
      if (def && def.note) item.ingredientNote = def.note;

      /* 1 — allergen conflict on the original ingredient */
      var conflit = def ? intersection(def.allergens, evites) : [];
      if (conflit.length > 0) {
        var regle = reglePour(usage.id, role, donnees.substitutions);
        var choix = choisirSubstitut(regle, evites, ageMois, catalogue, base);
        if (!choix) {
          item.status = "blocked";
          item.reason = "Contains: " + conflit.join(", ");
          resultat.status = "not_adaptable";
          resultat.alerts.push({
            level: "blocking",
            message: "No safe substitute for " + item.name + " (" + conflit.join(", ") + ") at this age."
          });
        } else if (choix.id === "_omit") {
          item.status = "omitted";
          item.reason = "Contains: " + conflit.join(", ");
          item.ratio = choix.ratio;
          resultat.swapCount++;
        } else {
          var defSub = catalogue[choix.id];
          item.status = "swapped";
          item.to = choix.id;
          item.toName = defSub.name;
          item.ratio = choix.ratio;
          item.reason = "Contains: " + conflit.join(", ");
          if (choix.note) item.substituteNote = choix.note;
          if (defSub.note) item.ingredientNote = defSub.note;
          resultat.swapCount++;
        }
      }

      /* 2 — age rules on the FINAL ingredient (original or substitute) */
      if (item.status !== "blocked") {
        var idFinal = item.to || item.id;
        var interdit = (item.status === "omitted") ? null : interditPour(idFinal, ageMois, base);
        if (interdit) {
          if (interdit.action.type === "swap") {
            var defSwap = catalogue[interdit.action.to];
            var conflitSwap = intersection(defSwap.allergens, evites);
            if (conflitSwap.length > 0) {
              item.status = "blocked";
              resultat.status = "not_adaptable";
              resultat.alerts.push({
                level: "blocking",
                message: item.name + " should be avoided before " + interdit.beforeMonths +
                  " months, and its replacement (" + defSwap.name + ") contains: " + conflitSwap.join(", ") + "."
              });
            } else {
              item.status = "swapped";
              item.to = interdit.action.to;
              item.toName = defSwap.name;
              item.ratio = interdit.action.ratio;
              item.reason = interdit.reason;
              resultat.swapCount++;
              resultat.alerts.push({ level: "info", message: item.name + " -> " + defSwap.name + ": " + interdit.reason + "." });
            }
          } else if (interdit.action.type === "prep") {
            item.prep = interdit.action.note;
            resultat.alerts.push({
              level: "safety",
              message: item.name + " — " + interdit.reason + ". " + interdit.action.note + "."
            });
          } else {
            item.status = "blocked";
            resultat.status = "not_adaptable";
            resultat.alerts.push({
              level: "blocking",
              message: item.name + " should be avoided before " + interdit.beforeMonths + " months: " + interdit.reason + "."
            });
          }
        }
      }

      resultat.ingredients.push(item);
    });

    if (resultat.status !== "not_adaptable" && resultat.swapCount > 0) {
      resultat.status = "adapted";
    }

    /* Checkable invariant: the allergens derived from the result never
     * intersect the avoided list, except when status is not_adaptable. */
    resultat.remainingAllergens = allergenesDe(resultat.ingredients, catalogue);
    return resultat;
  }

  return {
    analyserAllergenes: analyserAllergenes,
    adapterRecette: adapterRecette,
    stadePour: stadePour,
    interditPour: interditPour,
    choisirSubstitut: choisirSubstitut,
    allergenesDe: allergenesDe
  };
});
