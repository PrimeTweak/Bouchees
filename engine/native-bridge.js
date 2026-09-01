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
    if (!data) throw new Error("bridge: data not loaded");
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
  /* Joins names the way an English sentence does. The messages built in this
   * file were still French, left over from before English became the base
   * language of the app. */
  function listeEn(t) {
    if (t.length < 2) return t.join("");
    return t.slice(0, -1).join(", ") + " and " + t[t.length - 1];
  }

  function listeFr(t) {
    if (t.length < 2) return t.join("");
    return t.slice(0, -1).join(", ") + " et " + t[t.length - 1];
  }

  /* SEGMENTS A LABEL INTO WHAT IS IN IT AND WHAT MAY BE IN IT.
   *
   * "May contain traces of peanuts" used to be stripped of its "traces de"
   * prefix and read as an ingredient, so a factory warning and an actual
   * peanut produced the same verdict. Conservative, but it meant a parent
   * could never tell a product that HAS the allergen from one made near it,
   * and every trace statement on the shelf read "avoid".
   *
   * THE TRAP THAT DECIDES THE DIRECTION OF A MISTAKE. American labels carry
   * "MAY CONTAIN LESS THAN 2% OF: SALT, WHEY". That phrase opens with the
   * same two words as a cross-contamination warning and means the opposite:
   * those ARE ingredients, sometimes present. Reading it as a trace would
   * turn real whey into "caution" for a milk-allergic child — a false safe,
   * the one failure this file must never produce. It is matched first and
   * kept with the ingredients.
   *
   * Anything not clearly a warning stays with the ingredients. The weaker
   * bucket is never the default. */
  function segmenter(texte) {
    var t = String(texte || "");

    /* Percentage sub-lists, before anything else looks at "may contain". */
    var pourcentage = /\b(may|can)\s+contain\s+(less\s+than\s+)?\d+([.,]\d+)?\s*%|\bpeut\s+contenir\s+(moins\s+de\s+)?\d+([.,]\d+)?\s*%|\b(may|can)\s+contain\s+\d+\s*%\s*or\s+less/gi;
    var gardes = [];
    t = t.replace(pourcentage, function (m) {
      gardes.push(m);
      return "\u0000" + (gardes.length - 1) + "\u0000";
    });

    var marqueurs = new RegExp(
      "(" +
      /* English */
      "may\\s+contain|may\\s+also\\s+contain|can\\s+contain|" +
      "may\\s+contain\\s+traces|traces?\\s+of|" +
      "manufactured\\s+(in|on)|produced\\s+(in|on)|processed\\s+(in|on)|" +
      "packed\\s+(in|on)|made\\s+(in|on)\\s+(shared|the\\s+same)|" +
      "shared\\s+equipment|same\\s+equipment|shared\\s+facility|same\\s+facility|" +
      /* French */
      "peut\\s+contenir|peut\\s+renfermer|pourrait\\s+contenir|" +
      "traces?\\s+(possibles?|[e\u00e9]ventuelles?)|traces?\\s+d[eu']|" +
      "fabriqu[e\u00e9]\\s+dans|pr\u00e9par[e\u00e9]\\s+dans|emball[e\u00e9]\\s+dans|" +
      "[e\u00e9]quipement\\s+partag[e\u00e9]|m[e\u00ea]me\\s+[e\u00e9]quipement" +
      ")", "i");

    var ingredients = [], traces = [];
    /* A warning runs to the end of its sentence, not to the end of the
     * label: "May contain peanuts. Contains milk." must not swallow the
     * milk into the warning. */
    String(t).split(/(?<=[.;\u2022])\s+|\n+/).forEach(function (phrase) {
      var m = phrase.match(marqueurs);
      if (!m) { ingredients.push(phrase); return; }
      ingredients.push(phrase.slice(0, m.index));
      traces.push(phrase.slice(m.index + m[0].length));
    });

    function rendre(morceaux) {
      return morceaux.join(" ").replace(/\u0000(\d+)\u0000/g, function (x, i) {
        return gardes[Number(i)];
      });
    }
    return { ingredients: rendre(ingredients), traces: rendre(traces) };
  }

  /* Cuts one segment into the fragments the matcher reads. */
  function fragments(texte) {
    return String(texte || "")
      .split(/[,;()\[\]\u2022\u00b7\n]+/)
      .map(function (t) {
        return t.replace(/\d+([.,]\d+)?\s*%/g, " ")
                .replace(/^\s*(and|or|et|ou|dont|contains?|contient|including)\s*:?\s+/i, "")
                .replace(/^\s*:\s*/, "").trim();
      })
      .filter(function (t) { return t.length > 1; });
  }

  /* Reads an ingredient list off a product label.
   *
   * Rule of caution: anything unrecognised is FLAGGED, never ignored. On a
   * label, the unknown word may be precisely the allergen. A product comes
   * back "safe" only when EVERYTHING has been identified. */
  function evaluateLabel(text, jsonAvoided) {
    var d = required();
    var avoided = JSON.parse(jsonAvoided) || [];
    var segments = segmenter(text);

    /* THE LABEL LEXICON, NOT THE RECIPE CATALOGUE.
     *
     * The catalogue holds 92 cooking ingredients with roles and
     * substitutes — it was built to ADAPT RECIPES. A product label says
     * "durum wheat semolina", "thiamine mononitrate", "sodium caseinate":
     * industrial names with no role in a kitchen, so none of them are in
     * it. Every processed product therefore came back "not sure", which is
     * a catalogue mismatch rather than a bug.
     *
     * The lexicon covers 600 label terms: every alias of the eleven
     * allergen families, in English and French, plus the additives,
     * vitamins and thickeners that are simply SAFE and were making perfectly
     * readable labels look unreadable.
     *
     * The catalogue is still consulted after it, so a recipe ingredient
     * spotted on a label still resolves. */
    var lex = d.lexicon || { allergens: {}, safe: [] };
    var surs = {};
    (lex.safe || []).forEach(function (t) { surs[flatten(t)] = true; });

    var index = {};
    Object.keys(d.catalogue).forEach(function (id) {
      var def = d.catalogue[id];
      if (def.name) index[flatten(def.name)] = id;
      if (def.nameFr) index[flatten(def.nameFr)] = id;
    });
    var keys = Object.keys(index);

    var termes = Object.keys(lex.allergens || {}).map(flatten);
    /* Longest first: "peanut butter" must win over "butter". */
    termes.sort(function (a, b) { return b.length - a.length; });

    /* The same matcher, run once per segment. One pass over the list, one
     * over the warning, and the results kept apart. */
    function balayer(texte, collecte) {
    var unknown = [];
    fragments(texte).forEach(function (m) {
      var n = flatten(m);

      /* 1. An allergen term, whole word or contained in the phrase. */
      var frappe = null;
      for (var i = 0; i < termes.length; i++) {
        var t = termes[i];
        if (n === t || n.indexOf(t) !== -1) { frappe = t; break; }
      }
      if (frappe) {
        var famille = lex.allergens[Object.keys(lex.allergens).find(function (k) {
          return flatten(k) === frappe;
        })];
        if (famille && avoided.indexOf(famille) !== -1) collecte[famille] = true;
        return;
      }

      /* 2. A term known to be safe — an additive, a vitamin, a spice. */
      if (surs[n]) return;
      var sur = Object.keys(surs).find(function (t) {
        return t.length > 3 && n.indexOf(t) !== -1;
      });
      if (sur) return;

      /* 3. The recipe catalogue, for anything the lexicon missed. */
      var id = index[n];
      if (!id) {
        var key = keys.find(function (c) {
          return c.length > 3 && (n.indexOf(c) !== -1 || (n.length > 3 && c.indexOf(n) !== -1));
        });
        id = key ? index[key] : null;
      }
      if (!id) { if (n.length > 2) unknown.push(m); return; }
      d.catalogue[id].allergens.forEach(function (a) {
        if (avoided.indexOf(a) !== -1) collecte[a] = true;
      });
    });
    return unknown;
    }

    var found = {}, mayContain = {};
    var unknown = balayer(segments.ingredients, found);
    /* Unread words inside a factory warning are not counted as unreadable:
     * the warning is prose, not a list, and flagging its verbs would make
     * every label uncertain. */
    balayer(segments.traces, mayContain);

    var liste = Object.keys(found).map(nomAllergene);
    /* A warning about something already IN the product adds nothing: it is
     * avoided either way, and naming it twice reads as two problems. */
    var listeTraces = Object.keys(mayContain)
      .filter(function (a) { return !found[a]; })
      .map(nomAllergene);

    /* THE ORDER OF THE FOUR STATES, AND WHY.
     *
     * avoid      the allergen is declared present. Nothing outranks it.
     * uncertain  a word could not be read. Weaker than avoid, STRONGER than
     *            caution on purpose: "may contain peanut" is a known risk a
     *            parent can weigh, an unread word is a risk nobody has
     *            measured. The unmeasured one is never softened.
     * caution    a factory warning, and the list itself was fully read.
     * safe       everything read, nothing found.
     *
     * The traces list travels in every case, so a screen can show the warning
     * even when the status is driven by something else. */
    var status, message;
    if (liste.length) {
      status = "avoid";
      message = "Avoid \u2014 the label declares: " + listeEn(liste) + ".";
    } else if (unknown.length) {
      status = "uncertain";
      message = "Nothing avoided was recognised, but some ingredients were " +
                "not identified. Read the label.";
    } else if (listeTraces.length) {
      status = "caution";
      message = "May contain " + listeEn(listeTraces) +
                ". The ingredient list itself is clear.";
    } else {
      status = "safe";
      message = "No avoided allergen found in the ingredient list.";
    }
    if (listeTraces.length && status !== "caution") {
      message += " The label also warns it may contain " +
                 listeEn(listeTraces) + ".";
    }
    return JSON.stringify({
      status: status,
      allergensFound: liste,
      mayContain: listeTraces,
      unknownIngredients: unknown.slice(0, 6),
      message: message
    });
  }

  return {
    /* Called once at startup. */
    load: function (jsonData) {
      var d = JSON.parse(jsonData);
      data = { catalogue: d.ingredients, substitutions: d.substitutions,
               base: d.base, lexicon: d.lexicon || null };
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

    /* The week's shopping list, aggregated here so Swift only displays it.
     *
     * This threw on every call: I wrote `Moteur` and `donnees`, which are the
     * names used in the test harness. In this file the engine is `Engine` and
     * the tables come from `required()`. The exception surfaced as an empty
     * list, because the Swift side falls back to [] on any bridge error. */
    shoppingList: function (jsonRecipes, jsonProfile) {
      var recettes = JSON.parse(jsonRecipes);
      var profil = JSON.parse(jsonProfile);
      return JSON.stringify(Engine.listeEpicerie(recettes, {
        allergens: profil.allergens || [],
        ageMois: profil.ageMonths
      }, required()));
    },

    /* Texture stage for a given age. */

    stage: function (ageMois) {
      return JSON.stringify(Engine.stadePour(ageMois, required().base));
    },

    /* Reads a product label.
     *
     * Declared as a function here rather than pointed at the one above,
     * because check-decoding.js reads this file as text to compare the names
     * against the Swift calls. An alias compiles and runs, and would have
     * gone in as "the bridge does not expose evaluateLabel". */
    evaluateLabel: function (text, jsonAvoided) {
      return evaluateLabel(text, jsonAvoided);
    }
  };
})();
