/* Cohérence culinaire
 *
 * Remplace une PARTIE de ce que la cuisson d'essai attrapait. Soyons exacts sur
 * ce que ça couvre et ce que ça ne couvre pas :
 *
 *   ATTRAPÉ  — proportions aberrantes, ingrédient jamais mentionné dans les
 *              étapes, cuisson au four sans température, temps incohérent avec
 *              la méthode, portions invraisemblables, liquide sans absorbant.
 *   PAS ATTRAPÉ — « ça ne lève pas », « c'est fade », « la texture est
 *              caoutchouteuse ». Seule une vraie cuisson le dit.
 *
 * Rien ici ne touche à la sécurité : les allergènes et les règles d'âge sont
 * déjà déterministes ailleurs. C'est un contrôle de QUALITÉ.
 */
"use strict";

/* Volumes de référence, en ml, pour ramener tout à une échelle comparable. */
function enMl(u, catalogue) {
  const q = Number(u.qte);
  if (!Number.isFinite(q) || q <= 0) return 0;
  if (u.unite === "ml") return q;
  if (u.unite === "g") return q;                       /* approximation assumée */
  const un = String(u.unite || "").toLowerCase();
  if (/gousse/.test(un)) return q * 5;
  if (/tranche/.test(un)) return q * 30;
  if (/bo[îi]te|conserve/.test(un)) return q * 400;
  if (/gros|grosse/.test(un)) return q * 400;
  if (/filet/.test(un)) return q * 150;
  /* Unité inconnue avec une petite quantité (« 1 grosse », « 2 unités râpées ») :
   * c'est un aliment qui se compte, pas un volume. Retourner le nombre brut
   * ferait croire à 1 ml et déclencherait de faux rejets. */
  if (q <= 10) return q * 100;
  return q;
}

function rolesDe(u, catalogue) {
  const d = catalogue[u.id];
  return u.role ? [u.role] : (d ? d.roles : []);
}
function totalPourRole(recette, catalogue, roles) {
  return recette.ingredients.reduce(function (s, u) {
    const r = rolesDe(u, catalogue);
    return r.some(function (x) { return roles.indexOf(x) !== -1; }) ? s + enMl(u, catalogue) : s;
  }, 0);
}

/* Frontières de mots obligatoires : « fourchette » contient « four ».
 * Un vérificateur qui crie au loup se fait ignorer, donc il doit être exact.
 * Les entrées se terminant par « ~ » acceptent une conjugaison (mijot~ →
 * mijoter, mijotez, mijote). */
const MOTS_FOUR = ["four", "fours", "enfourn~", "gratin~", "plaque", "plaques", "moule", "moules"];
const MOTS_MIJOTAGE = ["mijot~", "frémi~", "fremi~", "bouill~", "réduir~", "reduir~", "ébullition"];
const MOTS_REPOS = ["réfrigér~", "refriger~", "repos~", "fig~", "au froid", "toute la nuit", "au frais"];

function contient(txt, mots) {
  return mots.some(function (m) {
    const brut = m.replace(/~$/, "");
    const motif = m.endsWith("~")
      ? "(^|[^a-zà-ÿ])" + brut
      : "(^|[^a-zà-ÿ])" + brut + "([^a-zà-ÿ]|$)";
    return new RegExp(motif, "i").test(txt);
  });
}

function texteEtapes(r) {
  return (r.etapes || []).join(" ").toLowerCase();
}
function normalise(t) {
  return String(t || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/['\u2019]/g, " ").replace(/\s+/g, " ").trim();
}

function verifier(recette, donnees) {
  const catalogue = donnees.catalogue;
  const erreurs = [], avertissements = [];
  const txt = texteEtapes(recette);
  const txtNorm = normalise(txt);

  /* 1. Chaque ingrédient doit apparaître quelque part dans les étapes.
   *    Un ingrédient listé mais jamais utilisé est le raté nº 1 des recettes
   *    générées — et il se voit à la cuisson, jamais avant. */
  /* « les ingrédients secs », « le reste » : formule légitime qui couvre tout.
   * Si elle est présente, on n'exige plus que chaque ingrédient soit nommé. */
  const collectif = /(les |tous les |le reste des )?(ingr[ée]dients|secs|humides)\b|le reste\b|tout le reste/.test(txt);
  const jamaisNommes = [];
  if (!collectif) {
    recette.ingredients.forEach(function (u) {
      const d = catalogue[u.id];
      if (!d) return;
      const nom = normalise(d.nom.replace(/\(.*?\)/g, " "));
      const mots = nom.split(/[\s,]+/).filter(function (w) { return w.length > 3; });
      /* Les noms courts (œuf, ail, sel, riz) n'ont aucun mot long : on cherche
       * le nom entier avec frontières, pluriel toléré. */
      /* Un cuisinier écrit « ajouter les légumes », pas « ajouter la courgette,
       * les épinards et le cheddar ». Un terme de famille couvre son rôle. */
      const familles = { legume: ["legume"], fruit: ["fruit"], lacte: ["fromage", "laitier"],
                         proteine: ["viande", "proteine"], farine: ["sec", "farine"],
                         assaisonnement: ["assaisonn", "epice"] };
      const roles = rolesDe(u, catalogue);
      const couvertParFamille = roles.some(function (r) {
        return (familles[r] || []).some(function (f) {
          return new RegExp("(^|[^a-z])" + f + "[a-z]{0,3}([^a-z]|$)").test(txtNorm);
        });
      });
      if (couvertParFamille) return;
      const cibles = mots.length ? mots : [nom];
      const nomme = cibles.some(function (w) {
        const racineMot = w.length > 6 ? w.slice(0, 6) : w;
        return new RegExp("(^|[^a-z])" + racineMot.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "[a-z]{0,4}([^a-z]|$)")
          .test(txtNorm);
      });
      if (!nomme) jamaisNommes.push(d.nom);
    });
  }
  if (jamaisNommes.length > 2)
    erreurs.push("ingrédients listés mais jamais utilisés dans les étapes : " + jamaisNommes.join(", "));
  else if (jamaisNommes.length)
    avertissements.push("ingrédient peu clair dans les étapes : " + jamaisNommes.join(", "));

  /* 2. Proportions liquide / absorbant. Une pâte à 3 fois plus de liquide que
   *    de farine ne tient pas — ça se voit sans allumer le four. */
  const liquide = totalPourRole(recette, catalogue, ["liquide", "lacte"]);
  const absorbant = totalPourRole(recette, catalogue, ["farine", "liant"]);
  const cuisson = contient(txt, MOTS_FOUR);
  if (liquide > 0 && absorbant > 0 && cuisson) {
    const ratio = liquide / absorbant;
    if (ratio > 2.5) erreurs.push("beaucoup trop de liquide pour la farine (" + ratio.toFixed(1) +
      "×) — la pâte ne tiendra pas");
    else if (ratio > 1.8) avertissements.push("pâte très liquide (" + ratio.toFixed(1) + "×) — à revoir");
  }
  if (cuisson && absorbant === 0 && liquide > 200)
    avertissements.push("cuisson au four avec beaucoup de liquide et aucun absorbant");

  /* 3. Un four sans température, c'est une recette inutilisable. */
  if (cuisson && !/\d{2,3}\s*°|\d{3}\s*(f|degr)/i.test(txt))
    erreurs.push("cuisson au four sans température indiquée");

  /* 4. Le temps annoncé doit tenir avec ce que les étapes décrivent. */
  const minutes = [];
  const re = /(\d{1,3})\s*(?:à|-)?\s*(\d{1,3})?\s*minutes?/g;
  let m;
  while ((m = re.exec(txt))) minutes.push(Number(m[2] || m[1]));
  const heures = /(\d{1,2})\s*heures?/.exec(txt);
  const sommeEtapes = minutes.reduce(function (a, b) { return a + b; }, 0) + (heures ? Number(heures[1]) * 60 : 0);
  const repos = contient(txt, MOTS_REPOS);
  if (recette.tempsMin && sommeEtapes > recette.tempsMin + 10 && !repos)
    erreurs.push("les étapes totalisent au moins " + sommeEtapes + " minutes mais tempsMin annonce " +
      recette.tempsMin);
  if (recette.tempsMin && recette.tempsMin > 20 && sommeEtapes === 0 &&
      (cuisson || contient(txt, MOTS_MIJOTAGE)))
    avertissements.push("cuisson décrite sans aucune durée dans les étapes");

  /* 5. Le volume total doit être plausible pour le nombre de portions. */
  const total = recette.ingredients.reduce(function (s, u) { return s + enMl(u, catalogue); }, 0);
  /* « 500 ml » n'est pas 500 portions. On n'accepte un nombre que s'il est
   * suivi d'un mot de portion, pas d'une unité de volume. */
  const mp = /(\d+)\s*(portions?|muffins?|galettes?|croquettes?|boulettes?|barres?|biscuits?|cr[eê]pes?|verres?|pains?|parts?|boules?|mini)/i
    .exec(recette.portions || "");
  const nPortions = mp ? Number(mp[1]) : null;
  /* Une boulette n'est pas une portion : les rendements en pièces ont leur
   * propre échelle, sinon le contrôle crie au loup sur toutes les recettes. */
  const enPieces = mp ? !/portions?|parts?/i.test(mp[2]) : false;
  if (nPortions && total > 0) {
    const parUnite = total / nPortions;
    const min = enPieces ? 15 : 90;
    const max = enPieces ? 300 : 800;
    const mot = enPieces ? "pièce" : "portion";
    if (parUnite < min) erreurs.push("volume total très faible pour " + nPortions + " " + mot + "s (" +
      Math.round(parUnite) + " ml/" + mot + ")");
    else if (parUnite > max) avertissements.push("volume élevé : " + Math.round(parUnite) + " ml/" + mot);
  }

  /* 6. Une protéine crue doit être cuite quelque part. */
  const crus = recette.ingredients.filter(function (u) {
    return rolesDe(u, catalogue).indexOf("proteine") !== -1 &&
      ["poulet", "dinde_hachee", "poisson_blanc", "saumon", "crevette"].indexOf(u.id) !== -1;
  });
  const CUISSON = /cui[ts]?|cuire|cuisson|dor[ei]|saisi|mijot|enfourn|au four|po[êe]l|grill|r[ôo]tir|vapeur|revenir|revenu|rissol|chauff|bouill|fr[ée]mi|[ée]bullition|braiser|sauter/;
  if (crus.length && !CUISSON.test(txtNorm))
    erreurs.push("protéine crue sans aucune étape de cuisson");

  /* 7. Quelques étapes, et pas des bouts de phrase. */
  if ((recette.etapes || []).length < 3)
    avertissements.push("moins de 3 étapes — souvent trop peu pour être suivi");
  (recette.etapes || []).forEach(function (e, i) {
    if (!/[.!?]$/.test(String(e).trim())) avertissements.push("étape " + (i + 1) + " sans ponctuation finale");
  });

  return { ok: erreurs.length === 0, erreurs: erreurs, avertissements: avertissements,
           mesures: { liquide: liquide, absorbant: absorbant, totalMl: total, minutesEtapes: sommeEtapes } };
}

module.exports = { verifier: verifier, enMl: enMl, contient: contient,
                   MOTS_FOUR: MOTS_FOUR, MOTS_REPOS: MOTS_REPOS };
