/* Moteur de recettes — lot 2, v0.1
 * Fonctions pures, déterministes, sans dépendance.
 * Règle d'or : l'IA rédige, les règles décident. Aucune décision de
 * sécurité (allergène, âge) ne sort d'un modèle — tout vient des tables.
 */
(function (racine, fabrique) {
  if (typeof module !== "undefined" && module.exports) module.exports = fabrique();
  else racine.Moteur = fabrique();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  /* ---------- utilitaires ---------- */

  function roleDe(usage, def) {
    return usage.role || (def && def.roles && def.roles[0]) || "autre";
  }

  function intersection(a, b) {
    return a.filter(function (x) { return b.indexOf(x) !== -1; });
  }

  /* Familles d'allergènes présentes dans une liste d'usages d'ingrédients,
   * dérivées du catalogue — jamais lues depuis des étiquettes externes. */
  function allergenesDe(usages, catalogue) {
    var vus = {};
    usages.forEach(function (u) {
      if (u.statut === "omis" || u.statut === "impossible") return;
      var id = u.vers || u.id;
      var def = catalogue[id];
      if (!def) return;
      def.allergenes.forEach(function (a) { vus[a] = true; });
    });
    return Object.keys(vus).sort();
  }

  function analyserAllergenes(recette, catalogue) {
    return allergenesDe(recette.ingredients, catalogue);
  }

  /* Stade de texture applicable à un âge donné. */
  function stadePour(ageMois, base) {
    for (var i = 0; i < base.stades.length; i++) {
      var s = base.stades[i];
      if (ageMois >= s.min && ageMois <= s.max) return s;
    }
    return base.stades[base.stades.length - 1];
  }

  /* Première règle d'interdit applicable à un ingrédient pour un âge.
   * Les règles sont ordonnées de la tranche la plus jeune à la plus vieille
   * dans base.interdits; on retourne la première qui s'applique. */
  function interditPour(id, ageMois, base) {
    for (var i = 0; i < base.interdits.length; i++) {
      var r = base.interdits[i];
      if (r.cible === id && ageMois < r.avantMois) return r;
    }
    return null;
  }

  /* Règle de substitution pour (ingrédient, rôle). */
  function reglePour(id, role, tableSubst) {
    for (var i = 0; i < tableSubst.length; i++) {
      var r = tableSubst[i];
      if (r.cible === id && r.role === role) return r;
    }
    return null;
  }

  /* Choix déterministe d'un substitut : première option de la table qui
   * (1) n'introduit aucun allergène évité,
   * (2) respecte son âge minimum,
   * (3) n'est pas elle-même interdite à cet âge sans porte de sortie.
   * Retourne null si aucune option ne passe. */
  function choisirSubstitut(regle, allergenesEvites, ageMois, catalogue, base) {
    if (!regle) return null;
    for (var i = 0; i < regle.options.length; i++) {
      var o = regle.options[i];
      if (o.ageMin > ageMois) continue;
      if (o.id === "_omettre") return o;
      var def = catalogue[o.id];
      if (!def) continue;
      if (intersection(def.allergenes, allergenesEvites).length > 0) continue;
      var interdit = interditPour(o.id, ageMois, base);
      if (interdit && interdit.action.type === "bloquer") continue;
      return o;
    }
    return null;
  }

  /* ---------- fonction principale ---------- */

  /* adapterRecette(recette, { allergenes: [...], ageMois: n }, donnees)
   * donnees = { catalogue, substitutions, base }
   * Retourne un objet complet : ingrédients avec provenance de chaque
   * décision, alertes graduées, consigne de texture, statut global. */
  function adapterRecette(recette, options, donnees) {
    var evites = (options.allergenes || []).slice().sort();
    var ageMois = options.ageMois;
    var catalogue = donnees.catalogue;
    var base = donnees.base;

    var resultat = {
      id: recette.id,
      nom: recette.nom,
      statut: "telle_quelle",          /* telle_quelle | adaptee | non_adaptable */
      nbSubstitutions: 0,
      ingredients: [],
      alertes: [],
      texture: stadePour(ageMois, base),
      etapes: recette.etapes
    };

    if (ageMois < recette.ageMinBase) {
      resultat.alertes.push({
        niveau: "attention",
        message: "Recette pensée pour " + recette.ageMinBase + " mois et plus — texture et format à revoir avant cet âge."
      });
    }

    recette.ingredients.forEach(function (usage) {
      var def = catalogue[usage.id];
      var role = roleDe(usage, def);
      var item = {
        id: usage.id,
        nom: def ? def.nom : usage.id,
        qte: usage.qte,
        unite: usage.unite,
        role: role,
        statut: "conserve"
      };
      if (def && def.note) item.noteIngredient = def.note;

      /* 1 — conflit d'allergène sur l'ingrédient d'origine */
      var conflit = def ? intersection(def.allergenes, evites) : [];
      if (conflit.length > 0) {
        var regle = reglePour(usage.id, role, donnees.substitutions);
        var choix = choisirSubstitut(regle, evites, ageMois, catalogue, base);
        if (!choix) {
          item.statut = "impossible";
          item.motif = "Contient : " + conflit.join(", ");
          resultat.statut = "non_adaptable";
          resultat.alertes.push({
            niveau: "bloquant",
            message: "Aucun substitut sûr pour « " + item.nom + " » (" + conflit.join(", ") + ") à cet âge."
          });
        } else if (choix.id === "_omettre") {
          item.statut = "omis";
          item.motif = "Contient : " + conflit.join(", ");
          item.ratio = choix.ratio;
          resultat.nbSubstitutions++;
        } else {
          var defSub = catalogue[choix.id];
          item.statut = "substitue";
          item.vers = choix.id;
          item.nomVers = defSub.nom;
          item.ratio = choix.ratio;
          item.motif = "Contient : " + conflit.join(", ");
          if (choix.note) item.noteSubstitut = choix.note;
          if (defSub.note) item.noteIngredient = defSub.note;
          resultat.nbSubstitutions++;
        }
      }

      /* 2 — règles d'âge sur l'ingrédient FINAL (origine ou substitut) */
      if (item.statut !== "impossible") {
        var idFinal = item.vers || item.id;
        var interdit = (item.statut === "omis") ? null : interditPour(idFinal, ageMois, base);
        if (interdit) {
          if (interdit.action.type === "swap") {
            var defSwap = catalogue[interdit.action.vers];
            var conflitSwap = intersection(defSwap.allergenes, evites);
            if (conflitSwap.length > 0) {
              item.statut = "impossible";
              resultat.statut = "non_adaptable";
              resultat.alertes.push({
                niveau: "bloquant",
                message: "« " + item.nom + " » est à éviter avant " + interdit.avantMois +
                  " mois et son remplacement (" + defSwap.nom + ") contient : " + conflitSwap.join(", ") + "."
              });
            } else {
              item.statut = "substitue";
              item.vers = interdit.action.vers;
              item.nomVers = defSwap.nom;
              item.ratio = interdit.action.ratio;
              item.motif = interdit.raison;
              resultat.nbSubstitutions++;
              resultat.alertes.push({ niveau: "info", message: item.nom + " → " + defSwap.nom + " : " + interdit.raison + "." });
            }
          } else if (interdit.action.type === "preparation") {
            item.preparation = interdit.action.note;
            resultat.alertes.push({
              niveau: "securite",
              message: item.nom + " — " + interdit.raison + ". " + interdit.action.note + "."
            });
          } else {
            item.statut = "impossible";
            resultat.statut = "non_adaptable";
            resultat.alertes.push({
              niveau: "bloquant",
              message: "« " + item.nom + " » est à éviter avant " + interdit.avantMois + " mois : " + interdit.raison + "."
            });
          }
        }
      }

      resultat.ingredients.push(item);
    });

    if (resultat.statut !== "non_adaptable" && resultat.nbSubstitutions > 0) {
      resultat.statut = "adaptee";
    }

    /* Invariant vérifiable : les allergènes dérivés du résultat ne
     * croisent jamais la liste évitée, sauf statut non_adaptable. */
    resultat.allergenesRestants = allergenesDe(resultat.ingredients, catalogue);
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
