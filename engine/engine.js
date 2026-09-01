/* Substitution engine — the only place that decides anything: zero
 * dependencies, UMD, runs identically in Node, a browser and JavaScriptCore. */
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
    var seen = {};
    usages.forEach(function (u) {
      if (u.status === "omitted" || u.status === "blocked") return;
      var id = u.to || u.id;
      var def = catalogue[id];
      if (!def) return;
      def.allergens.forEach(function (a) { seen[a] = true; });
    });
    return Object.keys(seen).sort();
  }

  function analyserAllergenes(recipe, catalogue) {
    return allergenesDe(recipe.ingredients, catalogue);
  }

  /* Texture stage that applies to a given age. */
  /* Replace each swapped ingredient's name with its replacement, wherever the
   * step text mentions it. Case-insensitive, whole-word, longest name first so
   * "cow's milk" is matched before "milk". */
  function reecrireEtapes(etapes, ingredients) {
    if (!etapes || !etapes.length) return etapes;

    var swaps = ingredients
      .filter(function (i) { return i.status === "swapped" && i.toName; })
      .sort(function (a, b) { return b.name.length - a.name.length; });

    if (!swaps.length) return etapes;

    return etapes.map(function (step) {
      var texte = typeof step === "string" ? step : step.text;
      if (!texte) return step;

      swaps.forEach(function (i) {
        /* A step says "milk" where the catalogue says "Cow's milk". Try the
         * full name first, then the last significant word — that is how the
         * corpus actually writes them. */
        var motif = new RegExp("\\b" + echapper(i.name) + "s?\\b", "gi");
        if (!motif.test(texte)) {
          var court = nomCourt(i.name);
          if (!court) return;
                    /* Match the WHOLE noun phrase, not the last word alone: so any
           * leading words from the ingredient's own name are consumed too,
           * and the plural is allowed. */
          var prefixes = motsAvant(i.name, court);
          motif = new RegExp("\\b(?:" + prefixes + "\\s+)?" + echapper(court) + "s?\\b", "gi");
        } else {
          motif.lastIndex = 0;
        }
        texte = texte.replace(motif, function (trouve) {
          /* Keep the original capitalisation: a name at the start of a
           * sentence stays capitalised. */
          return trouve[0] === trouve[0].toUpperCase()
            ? i.toName.charAt(0).toUpperCase() + i.toName.slice(1)
            : i.toName.charAt(0).toLowerCase() + i.toName.slice(1);
        });
      });

      return typeof step === "string" ? texte
        : Object.assign({}, step, { text: texte });
    });
  }

  /* "Cow's milk" -> "milk". Skips words that are too generic to match safely. */
  function nomCourt(name) {
    var mots = String(name).toLowerCase().split(/[\s']+/).filter(Boolean);
    var dernier = mots[mots.length - 1];
    if (!dernier || dernier.length < 3) return null;
    if (["oil", "water", "salt", "sugar", "powder"].indexOf(dernier) !== -1) return null;
    return dernier;
  }

  /* The words that sit before the head noun, as an alternation: for
   * "Peanut butter" and head "butter", this yields "peanut". */
  function motsAvant(name, tete) {
    var mots = String(name).toLowerCase().split(/[\s']+/).filter(Boolean);
    var before = mots.slice(0, mots.lastIndexOf(tete)).filter(function (m) {
      return m.length > 2;
    });
    return before.length ? before.map(echapper).join("|") : "";
  }

  function echapper(t) {
    return String(t).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

    /* Everything a parent buys for one batch, already adapted: no milk on the
   * list, fortified soy beverage instead, with the swap noted so they know
   * why when they are standing in front of the shelf. */
  function listeEpicerie(recipes, options, data) {
    var catalogue = data.catalogue;
    var lines = {};

    recipes.forEach(function (recipe) {
      var adaptee = adapterRecette(recipe, options, data);

      adaptee.ingredients.forEach(function (ing) {
        if (ing.status === "omitted") return;

        var name = ing.toName || ing.name;
        var key = name.toLowerCase();

        if (!lines[key]) {
          lines[key] = {
            name: name,
            aisle: rayonPour(ing, catalogue),
            quantities: [],
            recipes: [],
            replaces: ing.status === "swapped" ? ing.name : null
          };
        }

        var ligne = lines[key];
        if (ligne.recipes.indexOf(recipe.name) === -1) {
          ligne.recipes.push(recipe.name);
        }

        /* qty arrives as a bare number from the published batches and as
         * { value } from the local corpus. Accept both rather than depending
         * on which path loaded the recipe. */
        var value = typeof ing.qty === "number" ? ing.qty
                   : (ing.qty && ing.qty.value) || 0;
        if (value) {
          var unite = ing.unit || "";
          var existante = null;
          for (var i = 0; i < ligne.quantities.length; i++) {
            if (ligne.quantities[i].unit === unite) { existante = ligne.quantities[i]; break; }
          }
          if (existante) existante.value += value;
          else ligne.quantities.push({ value: value, unit: unite });
        }
      });
    });

    var output = [];
    for (var k in lines) { if (lines.hasOwnProperty(k)) output.push(lines[k]); }

    return output.sort(function (a, b) {
      if (a.aisle !== b.aisle) {
        return ORDRE_RAYONS.indexOf(a.aisle) - ORDRE_RAYONS.indexOf(b.aisle);
      }
      return a.name.localeCompare(b.name);
    });
  }

  /* A parent walks a store by section, so a list ordered any other way costs
   * them laps. The aisle comes from the ingredient's own role in the
   * catalogue — no new data to maintain. */
  var ORDRE_RAYONS = ["produce", "protein", "refrigerated", "pantry", "frozen", "other"];

  var ROLE_VERS_RAYON = {
    vegetable: "produce", fruit: "produce",
    protein: "protein",
    dairy: "refrigerated", liquid: "refrigerated",
    flour: "pantry", binder: "pantry", sweetener: "pantry",
    seasoning: "pantry", fat: "pantry", leavening: "pantry", topping: "pantry"
  };

  function rayonPour(ing, catalogue) {
    var id = ing.to || ing.id;
    var def = catalogue && catalogue[id];
    var roles = (def && def.roles) || [];
    for (var i = 0; i < roles.length; i++) {
      if (ROLE_VERS_RAYON[roles[i]]) return ROLE_VERS_RAYON[roles[i]];
    }
    return "other";
  }

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
   * (1) introduces no avoided allergen, (2) meets its own minimum age, (3) is
   * not itself blocked at that age with no way out. */
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

    /* adapterRecette(recipe, { allergens: [...], ageMois: n }, data)
   * data = { catalogue, substitutions, base } Returns a complete object:
   * ingredients carrying the origin of every decision, graded alerts, */
  function adapterRecette(recipe, options, data) {
    var evites = (options.allergens || []).slice().sort();
    var ageMois = options.ageMois;
    var catalogue = data.catalogue;
    var base = data.base;

    var result = {
      id: recipe.id,
      name: recipe.name,
      status: "as_is",          /* telle_quelle | adaptee | non_adaptable */
      swapCount: 0,
      ingredients: [],
      alerts: [],
      texture: stadePour(ageMois, base),
      steps: recipe.steps
    };

    if (ageMois < recipe.minAgeMonths) {
      result.alerts.push({
        level: "caution",
        message: "This recipe is written for " + recipe.minAgeMonths + " months and up — texture and shape need rethinking below that age."
      });
    }

    recipe.ingredients.forEach(function (usage) {
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
        var regle = reglePour(usage.id, role, data.substitutions);
        var choix = choisirSubstitut(regle, evites, ageMois, catalogue, base);
        if (!choix) {
          item.status = "blocked";
          item.reason = "Contains: " + conflit.join(", ");
          result.status = "not_adaptable";
          result.alerts.push({
            level: "blocking",
            message: "No safe substitute for " + item.name + " (" + conflit.join(", ") + ") at this age."
          });
        } else if (choix.id === "_omit") {
          item.status = "omitted";
          item.reason = "Contains: " + conflit.join(", ");
          item.ratio = choix.ratio;
          result.swapCount++;
        } else {
          var defSub = catalogue[choix.id];
          item.status = "swapped";
          item.to = choix.id;
          item.toName = defSub.name;
          item.ratio = choix.ratio;
          item.reason = "Contains: " + conflit.join(", ");
          if (choix.note) item.substituteNote = choix.note;
          if (defSub.note) item.ingredientNote = defSub.note;
          result.swapCount++;
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
              result.status = "not_adaptable";
              result.alerts.push({
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
              result.swapCount++;
              result.alerts.push({ level: "info", message: item.name + " -> " + defSwap.name + ": " + interdit.reason + "." });
            }
          } else if (interdit.action.type === "prep") {
            item.prep = interdit.action.note;
            result.alerts.push({
              level: "safety",
              message: item.name + " — " + interdit.reason + ". " + interdit.action.note + "."
            });
          } else {
            item.status = "blocked";
            result.status = "not_adaptable";
            result.alerts.push({
              level: "blocking",
              message: item.name + " should be avoided before " + interdit.beforeMonths + " months: " + interdit.reason + "."
            });
          }
        }
      }

      result.ingredients.push(item);
    });

    if (result.status !== "not_adaptable" && result.swapCount > 0) {
      result.status = "adapted";
    }

    /* Checkable invariant: the allergens derived from the result never
     * intersect the avoided list, except when status is not_adaptable. */
    result.remainingAllergens = allergenesDe(result.ingredients, catalogue);
        /* The step text names the ingredient that was removed: step 2 of the
     * banana muffins reads "Mix the banana, egg, milk and oil" — but the
     * engine has just replaced the egg with applesauce and the milk with soy. */
    result.stepsOriginal = recipe.steps;
    result.steps = reecrireEtapes(recipe.steps, result.ingredients);

    return result;
  }

  return {
    analyserAllergenes: analyserAllergenes,
    adapterRecette: adapterRecette,
    listeEpicerie: listeEpicerie,
    stadePour: stadePour,
    interditPour: interditPour,
    choisirSubstitut: choisirSubstitut,
    allergenesDe: allergenesDe
  };
});
