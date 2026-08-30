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
  /* Replace each swapped ingredient's name with its replacement, wherever the
   * step text mentions it. Case-insensitive, whole-word, longest name first so
   * "cow's milk" is matched before "milk". */
  function reecrireEtapes(etapes, ingredients) {
    if (!etapes || !etapes.length) return etapes;

    var swaps = ingredients
      .filter(function (i) { return i.status === "swapped" && i.toName; })
      .sort(function (a, b) { return b.name.length - a.name.length; });

    if (!swaps.length) return etapes;

    return etapes.map(function (etape) {
      var texte = typeof etape === "string" ? etape : etape.text;
      if (!texte) return etape;

      swaps.forEach(function (i) {
        /* A step says "milk" where the catalogue says "Cow's milk". Try the
         * full name first, then the last significant word — that is how the
         * corpus actually writes them. */
        var motif = new RegExp("\\b" + echapper(i.name) + "s?\\b", "gi");
        if (!motif.test(texte)) {
          var court = nomCourt(i.name);
          if (!court) return;
          /* Match the WHOLE noun phrase, not the last word alone.
           *
           * Replacing just "butter" in "peanut butter" leaves "peanut
           * sunflower seed butter" — with the allergen still in the sentence.
           * So any leading words from the ingredient's own name are consumed
           * too, and the plural is allowed. */
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

      return typeof etape === "string" ? texte
        : Object.assign({}, etape, { text: texte });
    });
  }

  /* "Cow's milk" -> "milk". Skips words that are too generic to match safely. */
  function nomCourt(nom) {
    var mots = String(nom).toLowerCase().split(/[\s']+/).filter(Boolean);
    var dernier = mots[mots.length - 1];
    if (!dernier || dernier.length < 3) return null;
    if (["oil", "water", "salt", "sugar", "powder"].indexOf(dernier) !== -1) return null;
    return dernier;
  }

  /* The words that sit before the head noun, as an alternation: for
   * "Peanut butter" and head "butter", this yields "peanut". */
  function motsAvant(nom, tete) {
    var mots = String(nom).toLowerCase().split(/[\s']+/).filter(Boolean);
    var avant = mots.slice(0, mots.lastIndexOf(tete)).filter(function (m) {
      return m.length > 2;
    });
    return avant.length ? avant.map(echapper).join("|") : "";
  }

  function echapper(t) {
    return String(t).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  /* THE WEEK'S SHOPPING LIST.
   *
   * Everything a parent buys for one batch, already adapted: no milk on the
   * list, fortified soy beverage instead, with the swap noted so they know why
   * when they are standing in front of the shelf.
   *
   * Quantities are added only when the units MATCH. The corpus mixes "125 ml"
   * with "1 unit", and inventing a total across those would be a lie on a
   * shopping list — mismatched entries are listed side by side instead.
   */
  function listeEpicerie(recettes, options, donnees) {
    var catalogue = donnees.catalogue;
    var lignes = {};

    recettes.forEach(function (recette) {
      var adaptee = adapterRecette(recette, options, donnees);

      adaptee.ingredients.forEach(function (ing) {
        if (ing.status === "omitted") return;

        var nom = ing.toName || ing.name;
        var cle = nom.toLowerCase();

        if (!lignes[cle]) {
          lignes[cle] = {
            name: nom,
            aisle: rayonPour(ing, catalogue),
            quantities: [],
            recipes: [],
            replaces: ing.status === "swapped" ? ing.name : null
          };
        }

        var ligne = lignes[cle];
        if (ligne.recipes.indexOf(recette.name) === -1) {
          ligne.recipes.push(recette.name);
        }

        /* qty arrives as a bare number from the published batches and as
         * { value } from the local corpus. Accept both rather than depending
         * on which path loaded the recipe. */
        var valeur = typeof ing.qty === "number" ? ing.qty
                   : (ing.qty && ing.qty.value) || 0;
        if (valeur) {
          var unite = ing.unit || "";
          var existante = null;
          for (var i = 0; i < ligne.quantities.length; i++) {
            if (ligne.quantities[i].unit === unite) { existante = ligne.quantities[i]; break; }
          }
          if (existante) existante.value += valeur;
          else ligne.quantities.push({ value: valeur, unit: unite });
        }
      });
    });

    var sortie = [];
    for (var k in lignes) { if (lignes.hasOwnProperty(k)) sortie.push(lignes[k]); }

    return sortie.sort(function (a, b) {
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
    /* THE STEP TEXT NAMES THE INGREDIENT THAT WAS REMOVED.
     *
     * Step 2 of the banana muffins reads "Mix the banana, egg, milk and oil"
     * — but the engine has just replaced the egg with applesauce and the milk
     * with soy. A parent mid-recipe reads the name of the food their child
     * cannot eat, at the step where they are told to add it, and has to scroll
     * back to the swap list to translate. With their hands in the batter.
     *
     * Measured on the corpus: eight of the seventeen adapted recipes carry
     * this conflict for a milk/egg/peanut profile.
     *
     * So the steps are rewritten with the names the parent actually has. The
     * original stays available in `stepsOriginal` for anyone who wants it. */
    resultat.stepsOriginal = recette.steps;
    resultat.steps = reecrireEtapes(recette.steps, resultat.ingredients);

    return resultat;
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
