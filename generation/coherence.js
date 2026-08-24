/* Culinary coherence check.
 *
 * Replaces PART of what a test bake would catch. Let us be exact about which
 * part: this finds recipes that cannot work as written — impossible liquid to
 * flour ratios, an ingredient listed but never used, oven baking with no
 * temperature, a cooking time that does not match the method, a raw protein
 * that is never cooked.
 *
 * What it cannot find: taste, rise, and real texture. "Dry", "bland",
 * "rubbery" — only cooking the dish tells you that.
 *
 * A recipe that has not been cooked can be BAD. It must never be UNSAFE:
 * safety lives in the deterministic tables, not in the kitchen test.
 */
"use strict";

/* Reference volumes in ml, so everything lands on a comparable scale. */
function enMl(u, catalogue) {
  const q = Number(u.qty);
  if (!Number.isFinite(q) || q <= 0) return 0;
  if (u.unit === "ml") return q;
  if (u.unit === "g") return q;                       /* deliberate approximation */
  const un = String(u.unit || "").toLowerCase();
  if (/gousse/.test(un)) return q * 5;
  if (/tranche/.test(un)) return q * 30;
  if (/bo[îi]te|conserve/.test(un)) return q * 400;
  if (/gros|grosse/.test(un)) return q * 400;
  if (/filet/.test(un)) return q * 150;
  /* Unknown unit with a small quantity ("1 large", "2 grated units"):
   * c'est un aliment qui se compte, pas un volume. Retourner le nombre brut
   * would read as 1 ml and trigger false rejections. */
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

/* Word boundaries are mandatory : “fourchette” contains “four”.
 * A checker that cries wolf gets ignored, so it has to be exact.
 * Entries ending in "~" accept an inflection (simmer~ ->
 * mijoter, mijotez, mijote). */
/* Recipe steps are English now, but partner feeds and older content may still
 * be French. Both vocabularies are kept: a checker that only understands one
 * language would silently stop catching anything in the other. */
const OVEN_WORDS = ["oven", "bake~", "baking sheet", "roast~", "broil~",
                    "four", "fours", "enfourn~", "gratin~", "plaque", "plaques", "moule", "moules"];
const SIMMER_WORDS = ["simmer~", "boil~", "reduce~", "poach~",
                      "mijot~", "frémi~", "fremi~", "bouill~", "réduir~", "reduir~", "ébullition"];
const REST_WORDS = ["refrigerat~", "chill~", "rest~", "set~", "overnight", "in the fridge",
                    "réfrigér~", "refriger~", "repos~", "fig~", "au froid", "toute la nuit", "au frais"];
const COOK_WORDS = ["cook~", "sear~", "brown~", "sauté~", "saute~", "fry~", "steam~", "grill~", "stir-fry",
                    "cuire", "cuis~", "saisir", "dorer", "rissol~", "sauter", "poêl~", "poel~", "vapeur"];

function contient(txt, mots) {
  return mots.some(function (m) {
    const brut = m.replace(/~$/, "");
    const reason = m.endsWith("~")
      ? "(^|[^a-zà-ÿ])" + brut
      : "(^|[^a-zà-ÿ])" + brut + "([^a-zà-ÿ]|$)";
    return new RegExp(reason, "i").test(txt);
  });
}

function texteEtapes(r) {
  return (r.steps || []).join(" ").toLowerCase();
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

  /* 1. Every ingredient has to appear somewhere in the steps. An ingredient
   *    listed but never used is the number one flaw in generated recipes —
   *    and it only shows up while cooking, never before. */
  /* "the dry ingredients", "the rest": a legitimate catch-all. When it is
   * present, each ingredient no longer has to be named individually. */
  const collectif = /(les |tous les |le reste des )?(ingr[ée]dients|secs|humides)\b|le reste\b|tout le reste/.test(txt);
  const jamaisNommes = [];
  if (!collectif) {
    recette.ingredients.forEach(function (u) {
      const d = catalogue[u.id];
      if (!d) return;
      const name = normalise(d.name.replace(/\(.*?\)/g, " "));
      const mots = name.split(/[\s,]+/).filter(function (w) { return w.length > 3; });
      /* Short names (egg, garlic, salt, rice) have no long word: match the
       * whole name with boundaries, plural tolerated. */
      /* A cook writes "add the vegetables", not "add the zucchini, the
       * spinach and the cheddar". A family term covers its role. */
      /* Roles now carry English identifiers, and the family terms cover both
       * de famille couvrent les deux langues : un flux partenaire francophone
       * languages: a French partner feed must still be understood. */
      const familles = {
        vegetable: ["vegetable", "veggie", "legume"],
        fruit: ["fruit"],
        dairy: ["cheese", "dairy", "fromage", "laitier"],
        protein: ["meat", "protein", "viande"],
        flour: ["dry", "flour", "sec", "farine"],
        fat: ["oil", "fat", "huile", "gras"],
        seasoning: ["season", "spice", "assaisonn", "epice"],
        liquid: ["liquid", "liquide"],
        binder: ["binder", "liant"],
        sweetener: ["sweeten", "sucr"],
        topping: ["topping", "garnitur"],
        leavening: ["leaven", "levant"]
      };
      const roles = rolesDe(u, catalogue);
      const couvertParFamille = roles.some(function (r) {
        return (familles[r] || []).some(function (f) {
          return new RegExp("(^|[^a-z])" + f + "[a-z]{0,3}([^a-z]|$)").test(txtNorm);
        });
      });
      if (couvertParFamille) return;
      const cibles = mots.length ? mots : [name];
      const nomme = cibles.some(function (w) {
        /* Stem plus tolerated suffix. The suffix was calibrated on French
         * (chapelure = chapel + ure); English compounds are longer
         * (breadcrumbs = breadc + rumbs) and were slipping past. */
        const racineMot = w.length > 6 ? w.slice(0, 6) : w;
        return new RegExp("(^|[^a-z])" + racineMot.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "[a-z]{0,8}([^a-z]|$)")
          .test(txtNorm);
      });
      if (!nomme) jamaisNommes.push(d.name);
    });
  }
  if (jamaisNommes.length > 2)
    erreurs.push("ingrédients listés mais jamais utilisés dans les étapes : " + jamaisNommes.join(", "));
  else if (jamaisNommes.length)
    avertissements.push("ingrédient peu clair dans les étapes : " + jamaisNommes.join(", "));

  /* 2. Liquid to absorbent ratio. A batter with three times more liquid than
   *    flour does not hold — you can see that without turning on the oven. */
  const liquide = totalPourRole(recette, catalogue, ["liquid", "dairy"]);
  const absorbant = totalPourRole(recette, catalogue, ["flour", "binder"]);
  const cuisson = contient(txt, OVEN_WORDS);
  if (liquide > 0 && absorbant > 0 && cuisson) {
    const ratio = liquide / absorbant;
    if (ratio > 2.5) erreurs.push("beaucoup trop de liquide pour la farine (" + ratio.toFixed(1) +
      "×) — la pâte ne tiendra pas");
    else if (ratio > 1.8) avertissements.push("pâte très liquide (" + ratio.toFixed(1) + "×) — à revoir");
  }
  if (cuisson && absorbant === 0 && liquide > 200)
    avertissements.push("cuisson au four avec beaucoup de liquide et aucun absorbant");

  /* 3. An oven with no temperature makes a recipe unusable. */
  if (cuisson && !/\d{2,3}\s*°|\d{3}\s*(f|degr)/i.test(txt))
    erreurs.push("cuisson au four sans température indiquée");

  /* 4. The stated time has to hold up against what the steps describe. */
  const minutes = [];
  const re = /(\d{1,3})\s*(?:à|-)?\s*(\d{1,3})?\s*minutes?/g;
  let m;
  while ((m = re.exec(txt))) minutes.push(Number(m[2] || m[1]));
  const heures = /(\d{1,2})\s*heures?/.exec(txt);
  const sommeEtapes = minutes.reduce(function (a, b) { return a + b; }, 0) + (heures ? Number(heures[1]) * 60 : 0);
  const repos = contient(txt, REST_WORDS);
  if (recette.timeMinutes && sommeEtapes > recette.timeMinutes + 10 && !repos)
    erreurs.push("les étapes totalisent au moins " + sommeEtapes + " minutes mais tempsMin annonce " +
      recette.timeMinutes);
  if (recette.timeMinutes && recette.timeMinutes > 20 && sommeEtapes === 0 &&
      (cuisson || contient(txt, SIMMER_WORDS)))
    avertissements.push("cuisson décrite sans aucune durée dans les étapes");

  /* 5. Total volume has to be plausible for the number of servings. */
  const total = recette.ingredients.reduce(function (s, u) { return s + enMl(u, catalogue); }, 0);
  /* « 500 ml » n'est pas 500 portions. On n'accepte un nombre que s'il est
   * followed by a serving word, not by a volume unit. */
  const mp = /(\d+)\s*(portions?|muffins?|galettes?|croquettes?|boulettes?|barres?|biscuits?|cr[eê]pes?|verres?|pains?|parts?|boules?|mini)/i
    .exec(recette.servings || "");
  const nPortions = mp ? Number(mp[1]) : null;
  /* A meatball is not a serving: piece yields have their own scale, or the
   * check cries wolf on every recipe. */
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

  /* 6. A raw protein has to be cooked somewhere. */
  const crus = recette.ingredients.filter(function (u) {
    return rolesDe(u, catalogue).indexOf("protein") !== -1 &&
      ["chicken", "ground_turkey", "white_fish", "salmon", "shrimp"].indexOf(u.id) !== -1;
  });
  /* Bilingual on purpose: partner feeds still arrive in French. */
  const COOKING = /cook|bak|roast|broil|sear|brown|saut|fry|steam|grill|simmer|boil|poach|stir-fry|heat|warm|oven|cui[ts]?|cuire|cuisson|dor[ei]|saisi|mijot|enfourn|au four|po[êe]l|r[ôo]tir|vapeur|revenir|revenu|rissol|chauff|bouill|fr[ée]mi|[ée]bullition|braiser|sauter/;
  if (crus.length && !COOKING.test(txtNorm))
    erreurs.push("raw protein with no cooking step");

  /* 7. A few steps, and not sentence fragments. */
  if ((recette.steps || []).length < 3)
    avertissements.push("moins de 3 étapes — souvent trop peu pour être suivi");
  (recette.steps || []).forEach(function (e, i) {
    if (!/[.!?]$/.test(String(e).trim())) avertissements.push("étape " + (i + 1) + " sans ponctuation finale");
  });

  return { ok: erreurs.length === 0, erreurs: erreurs, avertissements: avertissements,
           mesures: { liquide: liquide, absorbant: absorbant, totalMl: total, minutesEtapes: sommeEtapes } };
}

module.exports = { verifier: verifier, enMl: enMl, contient: contient,
                   OVEN_WORDS: OVEN_WORDS, REST_WORDS: REST_WORDS };
