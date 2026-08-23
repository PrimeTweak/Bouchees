/* Système visuel — v0.3
 * Illustration.plat(resultatAdapte, catalogue) → SVG (chaîne)
 *
 * Point clé : l'illustration est dérivée des ingrédients APRÈS adaptation.
 * Quand le beurre d'arachide devient du beurre de tournesol, la tuile change
 * de couleur. Une image ne peut donc jamais contredire la fiche — c'est le
 * défaut fatal d'une photo de stock dans une app d'allergies.
 *
 * Déterministe : même recette + même profil → même image, au pixel près.
 */
(function (racine, fabrique) {
  if (typeof module !== "undefined" && module.exports) module.exports = fabrique();
  else racine.Illustration = fabrique();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  /* ---------- palette alimentaire ----------
   * [couleur, forme, masse]  masse : 3 = base du plat, 2 = garniture, 1 = touche */
  var ING = {
    farine_ble: ["#E6CB93", "poudre", 3], farine_avoine: ["#DEC49B", "poudre", 3],
    farine_riz: ["#EDE3CE", "poudre", 3], farine_pois_chiches: ["#E0C583", "poudre", 3],
    melange_sans_gluten: ["#E9DCBE", "poudre", 3], chapelure: ["#DBB782", "grain", 2],
    chapelure_sans_gluten: ["#E4CDA6", "grain", 2], flocons_avoine: ["#D9C49A", "grain", 3],
    pates_ble: ["#E9C97F", "brin", 3], pates_riz: ["#EFE2CB", "brin", 3],
    riz: ["#F1EADB", "grain", 3], couscous: ["#E6CE9B", "grain", 3], quinoa: ["#D8C6A4", "grain", 3],
    tortillas_ble: ["#E7CE9C", "poudre", 3], tortillas_mais: ["#EFCF80", "poudre", 3],
    fecule_mais: ["#F2ECDE", "poudre", 1],

    oeuf: ["#F2C64E", "rond", 2], compote_pommes: ["#E3CE93", "arc", 2],
    puree_banane: ["#EBD588", "arc", 2], lin_moulu: ["#9E7A50", "poudre", 1],
    graines_chia: ["#4C4237", "poudre", 1], aquafaba: ["#EDE6D3", "arc", 1],

    lait_vache: ["#F6F1E4", "arc", 2], boisson_soya: ["#EFE7D2", "arc", 2],
    boisson_avoine: ["#EDE2CC", "arc", 2], lait_coco: ["#F8F5EC", "arc", 2],
    beurre: ["#F0D479", "goutte", 1], margarine_sans_lait: ["#F2DA92", "goutte", 1],
    creme_35: ["#F7F2E5", "arc", 2], yogourt_nature: ["#F6F2E8", "arc", 2],
    yogourt_grec: ["#F4F0E6", "arc", 2], yogourt_soya: ["#EFE8D6", "arc", 2],
    yogourt_coco: ["#F8F5EC", "arc", 2],
    fromage_cheddar: ["#E79B33", "chunk", 2], fromage_mozzarella: ["#F4EEDD", "chunk", 2],
    fromage_parmesan: ["#EBD9A8", "poudre", 1], levure_alimentaire: ["#E0B84E", "poudre", 1],

    huile_olive: ["#B7A03C", "goutte", 1], huile_canola: ["#E2C558", "goutte", 1],
    puree_avocat: ["#7E9B4E", "arc", 2],
    beurre_arachide: ["#BE8347", "goutte", 2], beurre_tournesol: ["#A98A55", "goutte", 2],
    beurre_soya: ["#B79A62", "goutte", 2], tahini: ["#D3BC86", "goutte", 2],
    beurre_amande: ["#B98D5E", "goutte", 2], noix_grenoble: ["#9C7248", "rond", 1],

    poulet: ["#D8A778", "chunk", 3], dinde_hachee: ["#C99672", "chunk", 3],
    poisson_blanc: ["#EBDCC6", "chunk", 3], saumon: ["#E8926B", "chunk", 3],
    crevette: ["#EE9F80", "chunk", 2], tofu_ferme: ["#F1EBDA", "chunk", 3],
    lentilles: ["#9A7A4E", "rond", 3], pois_chiches: ["#D8BC7E", "rond", 3],

    miel: ["#E0A32C", "goutte", 1], sirop_erable: ["#B5722C", "goutte", 1],
    sucre: ["#F4EFE3", "poudre", 1], dattes: ["#7A5136", "rond", 2],

    banane: ["#EDD264", "rond", 2], pomme: ["#C5533A", "rond", 2],
    mangue: ["#EFA22F", "rond", 2], bleuets: ["#5A5A93", "rond", 1],
    raisins_secs: ["#7B5340", "rond", 1], abricots_seches: ["#DE9440", "rond", 1],
    jus_citron: ["#EFDD73", "goutte", 1],

    patate_douce: ["#DE8B41", "chunk", 3], courge_butternut: ["#E5A03F", "chunk", 3],
    carotte: ["#DE7F32", "chunk", 2], carotte_crue: ["#E88A38", "chunk", 2],
    concombre: ["#8FAE5E", "rond", 2], courgette: ["#7C9E4F", "rond", 2],
    epinards: ["#4F7A3E", "feuille", 2], petits_pois: ["#6E9B45", "rond", 2],
    poivron: ["#CE4C39", "chunk", 2], brocoli: ["#557F42", "feuille", 2],
    oignon: ["#E8DFC9", "arc", 1], ail: ["#EFE8D6", "rond", 1],
    tomates_broyees: ["#C24A2E", "arc", 3],

    moutarde_dijon: ["#D8B23F", "goutte", 1], sel: ["#F5F2EA", "poudre", 1],
    cannelle: ["#9A6238", "poudre", 1], vanille: ["#C4A578", "goutte", 1],
    basilic: ["#4E7B3C", "feuille", 1], gingembre: ["#D7B36A", "poudre", 1],
    sauce_soya: ["#4A3226", "arc", 1], sauce_tamari: ["#4A3226", "arc", 1],
    coco_aminos: ["#6B4A33", "arc", 1], sauce_poisson: ["#8A6437", "goutte", 1],
    levure_chimique: ["#F5F2EA", "poudre", 1], bicarbonate: ["#F5F2EA", "poudre", 1],
    bouillon_sans_sel: ["#E4D7B4", "arc", 2], eau: ["#EDF1EE", "arc", 1]
  };

  var PAR_ROLE = {
    farine: ["#E6CB93", "poudre", 3], proteine: ["#D8A778", "chunk", 3],
    legume: ["#7C9E4F", "rond", 2], fruit: ["#D98A50", "rond", 2],
    lacte: ["#F5F0E3", "arc", 2], liquide: ["#EAE3D0", "arc", 2],
    gras: ["#E2C558", "goutte", 1], liant: ["#E3CE93", "arc", 1],
    sucrant: ["#C98A34", "goutte", 1], garniture: ["#9C7248", "rond", 1],
    assaisonnement: ["#C8B994", "poudre", 1], levant: ["#F5F2EA", "poudre", 1]
  };

  var TEINTES_FOND = {
    "Déjeuner":  ["#F7F1E4", "#EFE4CE"],
    "Repas":     ["#EDF2EA", "#DFEAD9"],
    "Collation": ["#F8EFF3", "#F0E1E9"],
    "Dessert":   ["#F4EFF6", "#E8E0EF"]
  };

  /* ---------- aléa déterministe ---------- */
  function graine(texte) {
    var h = 2166136261;
    for (var i = 0; i < texte.length; i++) { h ^= texte.charCodeAt(i); h = Math.imul(h, 16777619); }
    return h >>> 0;
  }
  function alea(etat) {
    return function () {
      etat |= 0; etat = (etat + 0x6D2B79F5) | 0;
      var t = Math.imul(etat ^ (etat >>> 15), 1 | etat);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  var arr = function (n) { return Math.round(n * 100) / 100; };
  function foncer(hex, k) {
    var n = parseInt(hex.slice(1), 16);
    var r = Math.round(((n >> 16) & 255) * k), v = Math.round(((n >> 8) & 255) * k), b = Math.round((n & 255) * k);
    return "#" + (1 << 24 | r << 16 | v << 8 | b).toString(16).slice(1);
  }

  /* ---------- formes ---------- */
  function blob(cx, cy, r, rnd, points) {
    points = points || 9;
    var d = "", i, a, rr, x, y;
    for (i = 0; i < points; i++) {
      a = (i / points) * Math.PI * 2;
      rr = r * (0.9 + rnd() * 0.2);
      x = cx + Math.cos(a) * rr; y = cy + Math.sin(a) * rr * 0.94;
      d += (i === 0 ? "M" : "L") + arr(x) + " " + arr(y);
    }
    return d + "Z";
  }
  function goutte(cx, cy, t) {
    return "M" + arr(cx) + " " + arr(cy - t) +
      "C" + arr(cx + t * 0.85) + " " + arr(cy - t * 0.15) +
      " " + arr(cx + t * 0.6) + " " + arr(cy + t) +
      " " + arr(cx) + " " + arr(cy + t) +
      "C" + arr(cx - t * 0.6) + " " + arr(cy + t) +
      " " + arr(cx - t * 0.85) + " " + arr(cy - t * 0.15) +
      " " + arr(cx) + " " + arr(cy - t) + "Z";
  }
  function feuille(cx, cy, t, rot) {
    return '<path d="M' + arr(cx - t) + " " + arr(cy) +
      "Q" + arr(cx) + " " + arr(cy - t * 0.95) + " " + arr(cx + t) + " " + arr(cy) +
      "Q" + arr(cx) + " " + arr(cy + t * 0.95) + " " + arr(cx - t) + " " + arr(cy) +
      'Z" transform="rotate(' + arr(rot) + " " + arr(cx) + " " + arr(cy) + ')"';
  }

  function dessiner(forme, cx, cy, t, couleur, rnd) {
    var rot = rnd() * 360, o = "", i;
    if (forme === "chunk") {
      return '<rect x="' + arr(cx - t) + '" y="' + arr(cy - t * 0.78) + '" width="' + arr(t * 2) +
        '" height="' + arr(t * 1.56) + '" rx="' + arr(t * 0.42) + '" fill="' + couleur +
        '" transform="rotate(' + arr(rot * 0.16 - 8) + " " + arr(cx) + " " + arr(cy) + ')"/>';
    }
    if (forme === "rond") {
      for (i = 0; i < 3; i++) {
        var a = rot + i * 118, d = t * 0.72;
        o += '<circle cx="' + arr(cx + Math.cos(a * Math.PI / 180) * d) + '" cy="' +
          arr(cy + Math.sin(a * Math.PI / 180) * d * 0.9) + '" r="' + arr(t * 0.6) + '" fill="' + couleur + '"/>';
      }
      return o;
    }
    if (forme === "grain") {
      for (i = 0; i < 5; i++) {
        var ag = rot + i * 72;
        o += '<ellipse cx="' + arr(cx + Math.cos(ag * Math.PI / 180) * t * 0.8) + '" cy="' +
          arr(cy + Math.sin(ag * Math.PI / 180) * t * 0.7) + '" rx="' + arr(t * 0.46) + '" ry="' + arr(t * 0.26) +
          '" fill="' + couleur + '" transform="rotate(' + arr(ag * 0.7) + " " + arr(cx) + " " + arr(cy) + ')"/>';
      }
      return o;
    }
    if (forme === "brin") {
      for (i = 0; i < 3; i++) {
        var dy = (i - 1) * t * 0.62;
        o += '<path d="M' + arr(cx - t * 1.5) + " " + arr(cy + dy) + "q" + arr(t * 0.75) + " " + arr(-t * 0.5) +
          " " + arr(t * 1.5) + " 0 q" + arr(t * 0.75) + " " + arr(t * 0.5) + " " + arr(t * 1.5) + ' 0" fill="none" stroke="' +
          couleur + '" stroke-width="' + arr(t * 0.42) + '" stroke-linecap="round"/>';
      }
      return o;
    }
    if (forme === "arc") {
      return '<path d="M' + arr(cx - t * 1.35) + " " + arr(cy) + "a" + arr(t * 1.35) + " " + arr(t * 0.95) +
        " 0 0 1 " + arr(t * 2.7) + ' 0" fill="none" stroke="' + couleur + '" stroke-width="' + arr(t * 0.6) +
        '" stroke-linecap="round" transform="rotate(' + arr(rot * 0.3 - 15) + " " + arr(cx) + " " + arr(cy) + ')"/>';
    }
    if (forme === "goutte") return '<path d="' + goutte(cx, cy, t * 0.95) + '" fill="' + couleur + '"/>';
    if (forme === "feuille") return "<" + "path " + feuille(cx, cy, t * 1.15, rot * 0.4 - 20).slice(6) + ' fill="' + couleur + '"/>';
    /* poudre */
    for (i = 0; i < 7; i++) {
      o += '<circle cx="' + arr(cx + (rnd() - 0.5) * t * 2.6) + '" cy="' + arr(cy + (rnd() - 0.5) * t * 2.2) +
        '" r="' + arr(t * 0.19 + rnd() * t * 0.1) + '" fill="' + couleur + '"/>';
    }
    return o;
  }

  /* ---------- composition ---------- */
  function visuelDe(id, role, catalogue) {
    if (ING[id]) return ING[id];
    var def = catalogue[id];
    var r = role || (def && def.roles && def.roles[0]) || "seasoning";
    return PAR_ROLE[r] || PAR_ROLE.assaisonnement;
  }

  function plat(resultat, catalogue, category) {
    var visibles = resultat.ingredients.filter(function (i) {
      return i.status !== "omitted" && i.status !== "blocked";
    }).map(function (i) {
      var id = i.to || i.id;
      var v = visuelDe(id, i.role, catalogue);
      return { id: id, couleur: v[0], forme: v[1], masse: v[2] };
    });

    var cle = resultat.id + "|" + visibles.map(function (v) { return v.id; }).join(",");
    var rnd = alea(graine(cle));
    var fond = TEINTES_FOND[category] || TEINTES_FOND["Repas"];

    var tries = visibles.slice().sort(function (a, b) { return b.masse - a.masse; });
    var base = tries[0] || { couleur: "#E9E3D2", forme: "poudre" };
    var accents = [];
    var vus = {};
    tries.slice(1).forEach(function (v) {
      if (vus[v.couleur + v.forme] || accents.length >= 6) return;
      vus[v.couleur + v.forme] = 1;
      accents.push(v);
    });

    var cx = 160, cy = 126, uid = "b" + (graine(cle) % 100000);
    var s = '<svg viewBox="0 0 320 240" xmlns="http://www.w3.org/2000/svg" role="img" aria-hidden="true" preserveAspectRatio="xMidYMid slice">';
    s += '<defs><clipPath id="' + uid + '"><circle cx="' + cx + '" cy="' + cy + '" r="74"/></clipPath>' +
      '<linearGradient id="g' + uid + '" x1="0" y1="0" x2="0.6" y2="1">' +
      '<stop offset="0" stop-color="' + fond[0] + '"/><stop offset="1" stop-color="' + fond[1] + '"/></linearGradient>' +
      '<radialGradient id="o' + uid + '" cx="0.5" cy="0.5" r="0.5">' +
      '<stop offset="0.62" stop-color="#1B211B" stop-opacity="0"/>' +
      '<stop offset="1" stop-color="#1B211B" stop-opacity="0.17"/></radialGradient></defs>';
    s += '<rect width="320" height="240" fill="url(#g' + uid + ')"/>';

    /* miettes sur la table : positions semées, jamais les mêmes deux fois */
    accents.slice(0, 3).forEach(function (a, i) {
      var ang = (graine(a.id + cle) % 360) * Math.PI / 180;
      var d0 = 112 + rnd() * 26;
      var px = cx + Math.cos(ang) * d0, py = cy + Math.sin(ang) * d0 * 0.78;
      var dist = Math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
      if (dist < 104) { px = cx + (px - cx) / dist * 106; py = cy + (py - cy) / dist * 106; }
      px = Math.max(24, Math.min(296, px)); py = Math.max(24, Math.min(216, py));
      s += '<g opacity=".6">' + dessiner(a.forme, px, py, 7 + rnd() * 3, a.couleur, rnd) + "</g>";
    });

    s += '<ellipse cx="' + cx + '" cy="' + (cy + 84) + '" rx="86" ry="12" fill="#1B211B" opacity=".08"/>';
    s += '<circle cx="' + cx + '" cy="' + cy + '" r="90" fill="#FCFBF6"/>';
    s += '<circle cx="' + cx + '" cy="' + cy + '" r="90" fill="none" stroke="#1B211B" opacity=".12" stroke-width="1.5"/>';
    s += '<circle cx="' + cx + '" cy="' + cy + '" r="76" fill="#F8F5EC"/>';

    s += '<g clip-path="url(#' + uid + ')">';

    /* La base se dessine selon sa NATURE : un potage remplit le bol,
     * un plat en morceaux se pose en pièces, une pâtisserie fait un dôme. */
    var mode = (base.forme === "arc") ? "liquid" : (base.forme === "chunk" ? "morceaux" : "dome");
    if (mode === "liquid") {
      s += '<circle cx="' + cx + '" cy="' + cy + '" r="74" fill="' + base.couleur + '"/>';
      s += '<circle cx="' + cx + '" cy="' + (cy + 10) + '" r="70" fill="' + foncer(base.couleur, 0.92) + '"/>';
      s += '<path d="M' + (cx - 46) + " " + (cy + 6) + "q23 -20 46 0 q23 20 46 0" +
        '" fill="none" stroke="#FFFFFF" opacity=".3" stroke-width="5" stroke-linecap="round"/>';
    } else if (mode === "morceaux") {
      s += '<circle cx="' + cx + '" cy="' + cy + '" r="72" fill="' + base.couleur + '" opacity=".3"/>';
      for (var c = 0; c < 5; c++) {
        var ac = c * 72 + rnd() * 26;
        s += dessiner("chunk", cx + Math.cos(ac * Math.PI / 180) * (16 + rnd() * 24),
          cy + Math.sin(ac * Math.PI / 180) * (15 + rnd() * 22), 15 + rnd() * 6, base.couleur, rnd);
      }
    } else {
      s += '<path d="' + blob(cx, cy + 9, 64, rnd, 11) + '" fill="' + foncer(base.couleur, 0.86) + '"/>';
      s += '<path d="' + blob(cx, cy + 1, 65, rnd, 11) + '" fill="' + base.couleur + '"/>';
      if (base.forme === "brin" || base.forme === "grain") {
        for (var k = 0; k < 8; k++) {
          var ab = k * 45 + rnd() * 22;
          s += dessiner(base.forme, cx + Math.cos(ab * Math.PI / 180) * (18 + rnd() * 24),
            cy + Math.sin(ab * Math.PI / 180) * (16 + rnd() * 22), 11, foncer(base.couleur, 0.84), rnd);
        }
      }
    }

    /* garnitures : assez nombreuses pour que le bol ait l'air plein */
    var n = accents.length;
    accents.forEach(function (a, i) {
      var reps = n <= 2 ? 3 : (n <= 4 ? 2 : 1);
      for (var j = 0; j < reps; j++) {
        var idx = i + j * n;
        var ang = idx * 137.508 + (graine(a.id) % 70);
        var ray = 13 + 42 * Math.sqrt((idx + 0.55) / Math.max(n * reps, 1));
        s += dessiner(a.forme, cx + Math.cos(ang * Math.PI / 180) * ray,
          cy + Math.sin(ang * Math.PI / 180) * ray * 0.93, 12 + rnd() * 5, a.couleur, rnd);
      }
    });
    s += "</g>";

    s += '<circle cx="' + cx + '" cy="' + cy + '" r="74" fill="url(#o' + uid + ')"/>';
    s += '<circle cx="' + cx + '" cy="' + cy + '" r="76" fill="none" stroke="#1B211B" opacity=".1" stroke-width="1"/>';
    s += '<path d="M' + (cx - 58) + " " + (cy - 52) + "a76 76 0 0 1 44 -21" +
      '" fill="none" stroke="#FFFFFF" opacity=".8" stroke-width="3.5" stroke-linecap="round"/>';
    return s + "</svg>";
  }

  /* ---------- glyphes d'allergènes (monoline, currentColor) ---------- */
  var G = {
    lait: '<path d="M7 3h6v3l2 3v9H5v-9l2-3z"/><path d="M7 6h6"/>',
    oeuf: '<path d="M10 3c3 0 5 4.2 5 7.6C15 14.3 12.8 17 10 17s-5-2.7-5-6.4C5 7.2 7 3 10 3z"/>',
    arachide: '<path d="M7.4 4.2c2 0 2.6 1.6 3.4 2.8.9 1.3 2.4 1.6 2.4 3.6 0 2.2-1.6 3.9-3.6 3.9-2 0-2.7-1.5-3.5-2.7C5.2 10.5 3.7 10 3.7 8.1c0-2.1 1.7-3.9 3.7-3.9z" transform="translate(3 1)"/><path d="M8.6 8.6l2.8 2.8"/>',
    noix: '<circle cx="10" cy="10" r="6.5"/><path d="M10 3.5v13M7 5.2c1.6 2.4 1.6 7.2 0 9.6M13 5.2c-1.6 2.4-1.6 7.2 0 9.6"/>',
    ble: '<path d="M10 17V7"/><path d="M10 7.5c0-2 1.2-3.4 3-3.9.3 2.1-.8 3.6-3 3.9zM10 7.5c0-2-1.2-3.4-3-3.9-.3 2.1.8 3.6 3 3.9zM10 12c0-2 1.2-3.4 3-3.9.3 2.1-.8 3.6-3 3.9zM10 12c0-2-1.2-3.4-3-3.9-.3 2.1.8 3.6 3 3.9z"/>',
    soya: '<path d="M4.5 12.5c0-4 3.5-7.5 7.5-7.5 2 0 3.5 1.5 3.5 3.5 0 4-3.5 7.5-7.5 7.5-2 0-3.5-1.5-3.5-3.5z"/><circle cx="8" cy="12.5" r="1.4"/><circle cx="11.8" cy="9" r="1.4"/>',
    sesame: '<ellipse cx="7" cy="8" rx="1.8" ry="2.8" transform="rotate(-25 7 8)"/><ellipse cx="12.5" cy="7" rx="1.8" ry="2.8" transform="rotate(20 12.5 7)"/><ellipse cx="10" cy="13" rx="1.8" ry="2.8" transform="rotate(-8 10 13)"/>',
    poisson: '<path d="M3 10c2.6-3 5.6-4.5 8.6-4.5 2.4 0 4.2 1.8 5.4 4.5-1.2 2.7-3 4.5-5.4 4.5C8.6 14.5 5.6 13 3 10z"/><path d="M3 10L1.2 7v6L3 10z"/><circle cx="12.6" cy="9" r=".9"/>',
    crustaces_mollusques: '<path d="M15 5.5c-4 0-7.5 2.4-7.5 5.4 0 2.2 1.8 3.8 4 3.8 2 0 3.5-1.3 3.5-3"/><path d="M7.5 11c-1.6 0-3-.9-3.6-2.3M15 5.5c1.2-.6 2-1.5 2.3-2.5"/><circle cx="14.4" cy="7.6" r=".8"/>',
    moutarde: '<path d="M8 3h4v2.2l1.6 2.3V17H6.4V7.5L8 5.2z"/><path d="M6.4 10h7.2"/>',
    sulfites: '<path d="M8 3h4v4.4l3.3 7.1c.5 1.1-.2 2.5-1.5 2.5H6.2c-1.3 0-2-1.4-1.5-2.5L8 7.4V3z"/><circle cx="9" cy="13.4" r="1"/><circle cx="11.8" cy="15" r=".8"/>'
  };
  function glyphe(id) {
    return '<svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" ' +
      'stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      (G[id] || '<circle cx="10" cy="10" r="6"/>') + "</svg>";
  }

  return { plat: plat, glyphe: glyphe, visuelDe: visuelDe };
});
