/* Native bridge — the surface JavaScriptCore calls from Swift.
 *
 * Why the engine stays in JavaScript: it is deterministic and covered by the
 * test suite, including an invariant checked across thousands of profile x
 * age combinations. Porting it to Swift would create a SECOND engine, and a
 * divergence between the two would mean a child eating something they should
 * not.
 *
 * This file makes no safety decision. It passes JSON between Swift and the
 * engine; everything that decides lives in engine.js and in the tables.
 *
 * Convention: JSON string in, JSON string out. No JS object crosses the
 * boundary — JSValue conversion is brittle, JSON is not.
 */
"use strict";

var PONT = (function () {

  var data = null;   /* { catalogue, substitutions, base } */

  function required() {
    if (!data) throw new Error("pont : données non chargées");
    return data;
  }

  function sansAccents(t) {
    return String(t || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  }
  function flatten(t) {
    return sansAccents(t).replace(/['\u2019\u2013-]/g, " ").replace(/\s+/g, " ").trim();
  }
  function nomAllergene(id) {
    var a = required().base.allergens.find(function (x) { return x.id === id; });
    return a ? a.name.toLowerCase() : id;
  }
  function listeFr(t) {
    if (t.length < 2) return t.join("");
    return t.slice(0, -1).join(", ") + " et " + t[t.length - 1];
  }

  return {
    /* Called once at startup. */
    load: function (jsonData) {
      var d = JSON.parse(jsonData);
      data = { catalogue: d.ingredients, substitutions: d.substitutions, base: d.base };
      return JSON.stringify({ ok: true,
        ingredients: Object.keys(d.ingredients).length,
        substitutions: d.substitutions.length,
        allergens: d.base.allergens.length });
    },

    /* Adapts a recipe to a profile. JSON in, JSON out. */
    adapt: function (jsonRecipe, jsonProfile) {
      var d = required();
      var recipe = JSON.parse(jsonRecipe);
      var profile = JSON.parse(jsonProfile);
      var res = Engine.adapterRecette(recipe,
        { allergens: profile.allergens || [], ageMois: profile.ageMois },
        { catalogue: d.catalogue, substitutions: d.substitutions, base: d.base });
      return JSON.stringify(res);
    },

    /* Adapte tout un corpus d'un coup : un seul aller-retour au lieu de 30. */
    adaptBatch: function (jsonRecipes, jsonProfile) {
      var d = required();
      var recipes = JSON.parse(jsonRecipes);
      var profile = JSON.parse(jsonProfile);
      var opts = { allergens: profile.allergens || [], ageMois: profile.ageMois };
      var tables = { catalogue: d.catalogue, substitutions: d.substitutions, base: d.base };
      var out = recipes.map(function (r) { return Engine.adapterRecette(r, opts, tables); });
      return JSON.stringify(out);
    },

    /* Texture stage for a given age. */
    /* The week's shopping list, aggregated on this side so Swift only has to
     * display it. */
    shoppingList: function (jsonRecipes, jsonProfile) {
      var recettes = JSON.parse(jsonRecipes);
      var profil = JSON.parse(jsonProfile);
      return JSON.stringify(Moteur.listeEpicerie(recettes, {
        allergens: profil.allergens || [],
        ageMois: profil.ageMonths
      }, donnees));
    },

    stage: function (ageMois) {
      return JSON.stringify(Engine.stadePour(ageMois, required().base));
    },

    /* Reads an ingredient list off a product label.
     *
     * Rule of caution: anything unrecognised is FLAGGED, never ignored. On a
     * label, the unknown word may be precisely the allergen. A product comes
     * back "safe" only when EVERYTHING has been identified. */
    evaluateLabel: function (text, jsonAvoided) {
      var d = required();
      var avoided = JSON.parse(jsonAvoided) || [];
      var parts = String(text || "")
        .split(/[,;()\[\]\u2022\u00b7\n]+/)
        .map(function (t) {
          return t.replace(/\d+([.,]\d+)?\s*%/g, " ")
                  .replace(/^\s*(et|ou|dont|contient|traces de)\s+/i, "").trim();
        })
        .filter(function (t) { return t.length > 1; });

      /* Both names are indexed. A Quebec label reads "farine de ble", not
       * "wheat flour": without the French name the scanner would stop
       * recognising products sold here. */
      var index = {};
      Object.keys(d.catalogue).forEach(function (id) {
        var def = d.catalogue[id];
        if (def.name) index[flatten(def.name)] = id;
        if (def.nameFr) index[flatten(def.nameFr)] = id;
      });
      var keys = Object.keys(index);

      var found = {}, unknown = [];
      parts.forEach(function (m) {
        var n = flatten(m);
        var id = index[n];
        if (!id) {
          var key = keys.find(function (c) {
            return c.length > 3 && (n.indexOf(c) !== -1 || (n.length > 3 && c.indexOf(n) !== -1));
          });
          id = key ? index[key] : null;
        }
        if (!id) { if (n.length > 2) unknown.push(m); return; }
        d.catalogue[id].allergens.forEach(function (a) {
          if (avoided.indexOf(a) !== -1) found[a] = true;
        });
      });

      var liste = Object.keys(found).map(nomAllergene);
      var status, message;
      if (liste.length) {
        status = "avoid";
        message = "\u00c0 \u00e9viter \u2014 l\u2019\u00e9tiquette contient : " + listeFr(liste) + ".";
      } else if (unknown.length) {
        status = "uncertain";
        message = "Rien d\u2019interdit reconnu, mais des ingr\u00e9dients n\u2019ont pas \u00e9t\u00e9 identifi\u00e9s. Lisez l\u2019\u00e9tiquette.";
      } else {
        status = "safe";
        message = "No avoided allergen found in the ingredient list.";
      }
      return JSON.stringify({
        status: status,
        allergensFound: liste,
        unknownIngredients: unknown.slice(0, 6),
        message: message
      });
    }
  };
})();
