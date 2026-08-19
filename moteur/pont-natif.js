/* Pont natif — la surface que JavaScriptCore appelle depuis Swift.
 *
 * Pourquoi le moteur reste en JavaScript : il est déterministe et couvert par
 * 90 tests, dont un invariant vérifié sur des milliers de combinaisons. Le
 * réécrire en Swift créerait un DEUXIÈME moteur, donc une deuxième vérité.
 * Sur des allergies alimentaires, un écart entre les deux, c'est un enfant qui
 * mange ce qu'il ne devrait pas.
 *
 * Ce fichier ne contient aucune décision de sécurité : il ne fait que passer
 * des JSON entre Swift et le moteur. Tout ce qui décide vit dans moteur.js et
 * dans les tables.
 *
 * Convention : entrée JSON (chaîne), sortie JSON (chaîne). Aucun objet JS ne
 * traverse la frontière — la conversion JSValue est fragile, le JSON ne l'est
 * pas.
 */
"use strict";

var PONT = (function () {

  var donnees = null;   /* { catalogue, substitutions, base } */

  function requis() {
    if (!donnees) throw new Error("pont : données non chargées");
    return donnees;
  }

  function sansAccents(t) {
    return String(t || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  }
  function aplatir(t) {
    return sansAccents(t).replace(/['\u2019\u2013-]/g, " ").replace(/\s+/g, " ").trim();
  }
  function nomAllergene(id) {
    var a = requis().base.allergenes.find(function (x) { return x.id === id; });
    return a ? a.nom.toLowerCase() : id;
  }
  function listeFr(t) {
    if (t.length < 2) return t.join("");
    return t.slice(0, -1).join(", ") + " et " + t[t.length - 1];
  }

  return {
    /* Appelé une fois au démarrage. */
    charger: function (jsonDonnees) {
      var d = JSON.parse(jsonDonnees);
      donnees = { catalogue: d.ingredients, substitutions: d.substitutions, base: d.base };
      return JSON.stringify({ ok: true,
        ingredients: Object.keys(d.ingredients).length,
        substitutions: d.substitutions.length,
        allergenes: d.base.allergenes.length });
    },

    /* Adapte une recette à un profil. Entrée et sortie en JSON. */
    adapter: function (jsonRecette, jsonProfil) {
      var d = requis();
      var recette = JSON.parse(jsonRecette);
      var profil = JSON.parse(jsonProfil);
      var res = Moteur.adapterRecette(recette,
        { allergenes: profil.allergenes || [], ageMois: profil.ageMois },
        { catalogue: d.catalogue, substitutions: d.substitutions, base: d.base });
      return JSON.stringify(res);
    },

    /* Adapte tout un corpus d'un coup : un seul aller-retour au lieu de 30. */
    adapterLot: function (jsonRecettes, jsonProfil) {
      var d = requis();
      var recettes = JSON.parse(jsonRecettes);
      var profil = JSON.parse(jsonProfil);
      var opts = { allergenes: profil.allergenes || [], ageMois: profil.ageMois };
      var tables = { catalogue: d.catalogue, substitutions: d.substitutions, base: d.base };
      var out = recettes.map(function (r) { return Moteur.adapterRecette(r, opts, tables); });
      return JSON.stringify(out);
    },

    /* Stade de texture pour un âge donné. */
    stade: function (ageMois) {
      return JSON.stringify(Moteur.stadePour(ageMois, requis().base));
    },

    /* Analyse d'une liste d'ingrédients lue sur une étiquette de produit.
     *
     * Règle de prudence : ce qui n'est pas reconnu est SIGNALÉ, jamais ignoré.
     * Sur une étiquette, le mot inconnu peut être précisément l'allergène. Un
     * produit ne ressort donc « sûr » que si TOUT a été identifié. */
    evaluerEtiquette: function (texte, jsonEvites) {
      var d = requis();
      var evites = JSON.parse(jsonEvites) || [];
      var morceaux = String(texte || "")
        .split(/[,;()\[\]\u2022\u00b7\n]+/)
        .map(function (t) {
          return t.replace(/\d+([.,]\d+)?\s*%/g, " ")
                  .replace(/^\s*(et|ou|dont|contient|traces de)\s+/i, "").trim();
        })
        .filter(function (t) { return t.length > 1; });

      var index = {};
      Object.keys(d.catalogue).forEach(function (id) {
        index[aplatir(d.catalogue[id].nom)] = id;
      });
      var cles = Object.keys(index);

      var trouves = {}, inconnus = [];
      morceaux.forEach(function (m) {
        var n = aplatir(m);
        var id = index[n];
        if (!id) {
          var cle = cles.find(function (c) {
            return c.length > 3 && (n.indexOf(c) !== -1 || (n.length > 3 && c.indexOf(n) !== -1));
          });
          id = cle ? index[cle] : null;
        }
        if (!id) { if (n.length > 2) inconnus.push(m); return; }
        d.catalogue[id].allergenes.forEach(function (a) {
          if (evites.indexOf(a) !== -1) trouves[a] = true;
        });
      });

      var liste = Object.keys(trouves).map(nomAllergene);
      var statut, message;
      if (liste.length) {
        statut = "a_eviter";
        message = "\u00c0 \u00e9viter \u2014 l\u2019\u00e9tiquette contient : " + listeFr(liste) + ".";
      } else if (inconnus.length) {
        statut = "incertain";
        message = "Rien d\u2019interdit reconnu, mais des ingr\u00e9dients n\u2019ont pas \u00e9t\u00e9 identifi\u00e9s. Lisez l\u2019\u00e9tiquette.";
      } else {
        statut = "sur";
        message = "Aucun allerg\u00e8ne \u00e9vit\u00e9 d\u00e9tect\u00e9 dans la liste d\u2019ingr\u00e9dients.";
      }
      return JSON.stringify({
        statut: statut,
        allergenesTrouves: liste,
        ingredientsInconnus: inconnus.slice(0, 6),
        message: message
      });
    }
  };
})();
