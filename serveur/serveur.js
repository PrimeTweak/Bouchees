/* Serveur Bouchées — bloc F
 * node serveur/serveur.js        (port 8787 par défaut)
 *
 * Node pur, zéro dépendance : rien à installer.
 *
 * LE POINT CENTRAL : le serveur n'envoie jamais un lot auquel le compte n'a
 * pas droit. Pas « envoyer puis cacher » — ne pas envoyer. Un mur payant
 * côté client s'ouvre avec Ctrl+U.
 *
 * ET LA CONTREPARTIE : les tables de sécurité (moteur, substitutions, règles
 * d'âge) et les lots libres partent pour TOUT LE MONDE, connecté ou non.
 * On vend le flux de nouvelles recettes, pas la réponse à « est-ce que mon
 * fils peut manger ça ».
 */
"use strict";
const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { verifierSignature, evenementPertinent, creerSession } = require("./stripe.js");
const Apple = require("./apple.js");

const racine = path.join(__dirname, "..");
const dist = path.join(racine, "dist");
const PORT = process.env.PORT || 8787;
const FICHIER_COMPTES = process.env.BOUCHEES_COMPTES || path.join(__dirname, "comptes.json");
const SECRET_WEBHOOK = process.env.STRIPE_WEBHOOK_SECRET || "";
const JOURS_GRACE = 3;   /* on ne coupe pas l'accès à la seconde où un paiement échoue */

/* ---------- petite base sur fichier ---------- */
function lireComptes() {
  try { return JSON.parse(fs.readFileSync(FICHIER_COMPTES, "utf8")); }
  catch (e) { return { comptes: {}, jetons: {} }; }
}
function ecrireComptes(db) {
  fs.writeFileSync(FICHIER_COMPTES, JSON.stringify(db, null, 2));
}
function normaliserCourriel(c) { return String(c || "").trim().toLowerCase(); }
function jetonNeuf() { return crypto.randomBytes(24).toString("hex"); }

/* ---------- droits ---------- */
function actifSelon(a) {
  if (!a) return false;
  if (a.statut === "actif") return true;
  if (a.statut === "en_retard" && a.finPeriode)
    return Date.now() < new Date(a.finPeriode).getTime() + JOURS_GRACE * 864e5;
  return false;
}
/* Deux sources d'abonnement — Stripe pour le web, Apple pour iOS. Un compte
 * peut avoir les deux (il s'est abonné sur le web puis a installé l'app) :
 * l'une OU l'autre suffit, et on ne facture jamais deux fois pour ça. */
function abonnementActif(compte) {
  if (!compte) return false;
  return actifSelon(compte.abonnement) || actifSelon(compte.abonnementApple);
}
function lotsAutorises(manifeste, compte) {
  const actif = abonnementActif(compte);
  return manifeste.lots
    .filter(function (l) { return l.acces === "libre" || actif; })
    .map(function (l) { return l.id; });
}

/* ---------- lecture du contenu publié ---------- */
function chargerManifeste() {
  return JSON.parse(fs.readFileSync(path.join(dist, "manifeste.json"), "utf8"));
}
function chargerLot(id) {
  return JSON.parse(fs.readFileSync(path.join(dist, "lots", id + ".json"), "utf8"));
}

/* ---------- HTTP ---------- */
function json(rep, code, corps) {
  const s = JSON.stringify(corps);
  rep.writeHead(code, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(s),
    "Cache-Control": "no-store"
  });
  rep.end(s);
}
function corpsBrut(req) {
  return new Promise(function (res, rej) {
    const m = [];
    req.on("data", function (c) { m.push(c); });
    req.on("end", function () { res(Buffer.concat(m)); });
    req.on("error", rej);
  });
}
function compteDeLaRequete(req, db) {
  const auth = req.headers.authorization || "";
  const jeton = auth.replace(/^Bearer\s+/i, "").trim();
  if (!jeton) return null;
  const courriel = db.jetons[jeton];
  return courriel ? db.comptes[courriel] || null : null;
}

const routes = {
  /* Ce que tout le monde peut savoir : quels lots existent, lesquels sont
   * verrouillés. Le contenu, lui, ne part pas. */
  "GET /api/manifeste": function (req, rep, ctx) {
    const m = chargerManifeste();
    const permis = lotsAutorises(m, ctx.compte);
    json(rep, 200, {
      version: m.version,
      abonne: abonnementActif(ctx.compte),
      lots: m.lots.map(function (l) {
        return { id: l.id, titre: l.titre, date: l.date, acces: l.acces, note: l.note,
                 nombre: l.nombre, deverrouille: permis.indexOf(l.id) !== -1 };
      })
    });
  },

  /* Les tables de sécurité : gratuites, toujours, sans compte. */
  "GET /api/securite": function (req, rep) {
    const s = fs.readFileSync(path.join(dist, "securite.json"));
    rep.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "public, max-age=3600" });
    rep.end(s);
  },

  /* Le contenu, filtré par droits. Un lot non autorisé ne traverse pas. */
  "GET /api/recettes": function (req, rep, ctx) {
    const m = chargerManifeste();
    const permis = lotsAutorises(m, ctx.compte);
    const demande = ctx.url.searchParams.get("lot");
    const cibles = demande ? [demande] : permis;
    const refuses = cibles.filter(function (id) { return permis.indexOf(id) === -1; });
    if (refuses.length) return json(rep, 402, { erreur: "abonnement requis", lots: refuses });
    let out = [];
    cibles.forEach(function (id) {
      try { out = out.concat(chargerLot(id)); } catch (e) {}
    });
    json(rep, 200, { abonne: abonnementActif(ctx.compte), lots: cibles, recettes: out });
  },

  "GET /api/moi": function (req, rep, ctx) {
    if (!ctx.compte) return json(rep, 200, { connecte: false, abonne: false });
    json(rep, 200, {
      connecte: true, courriel: ctx.compte.courriel, abonne: abonnementActif(ctx.compte),
      abonnement: ctx.compte.abonnement || null,
      abonnementApple: ctx.compte.abonnementApple || null,
      source: actifSelon(ctx.compte.abonnementApple) ? "apple"
            : actifSelon(ctx.compte.abonnement) ? "stripe" : null
    });
  },

  /* L'app iOS envoie sa transaction StoreKit signée. On la vérifie
   * intégralement avant d'accorder quoi que ce soit — le client n'est jamais
   * cru sur parole, pas plus qu'un navigateur. */
  "POST /api/apple/transaction": async function (req, rep, ctx) {
    if (!ctx.compte) return json(rep, 401, { erreur: "connexion requise" });
    let corps;
    try { corps = JSON.parse((await corpsBrut(req)).toString("utf8")); }
    catch (e) { return json(rep, 400, { erreur: "JSON invalide" }); }
    const v = Apple.verifierJWS(corps.signedTransaction);
    if (!v.ok) return json(rep, 400, { erreur: "transaction refusée", detail: v.raison });
    const etat = Apple.etatDepuisTransaction(v.charge);
    if (!etat.ok) return json(rep, 400, { erreur: "transaction refusée", detail: etat.raison });

    const db = ctx.db;
    /* Une même transaction Apple ne peut pas servir deux comptes. */
    const proprietaire = Object.keys(db.comptes).find(function (c) {
      const a = db.comptes[c].abonnementApple;
      return a && a.transaction === etat.transaction && c !== ctx.compte.courriel;
    });
    if (proprietaire) return json(rep, 409, { erreur: "cette transaction est déjà liée à un autre compte" });

    db.comptes[ctx.compte.courriel].abonnementApple = {
      statut: etat.statut, finPeriode: etat.finPeriode, produit: etat.produit,
      transaction: etat.transaction, environnement: etat.environnement,
      majLe: new Date().toISOString()
    };
    ecrireComptes(db);
    json(rep, 200, { ok: true, abonne: abonnementActif(db.comptes[ctx.compte.courriel]), statut: etat.statut });
  },

  /* Notifications V2 d'Apple : renouvellements, remboursements, expirations.
   * Comme le webhook Stripe, c'est la source de vérité, pas le client. */
  "POST /api/webhook/apple": async function (req, rep, ctx) {
    let corps;
    try { corps = JSON.parse((await corpsBrut(req)).toString("utf8")); }
    catch (e) { return json(rep, 400, { erreur: "JSON invalide" }); }
    const n = Apple.lireNotification(corps.signedPayload);
    if (!n.ok) return json(rep, 400, { erreur: "notification refusée", detail: n.raison });
    if (n.ignore) return json(rep, 200, { ignore: n.ignore });

    const db = ctx.db;
    const courriel = Object.keys(db.comptes).find(function (c) {
      const a = db.comptes[c].abonnementApple;
      return a && a.transaction === n.transaction;
    });
    /* Transaction inconnue : on l'archive sans planter. Le compte sera lié au
     * prochain lancement de l'app, et l'état sera repris à ce moment-là. */
    if (!courriel) {
      db.orphelinsApple = db.orphelinsApple || {};
      db.orphelinsApple[n.transaction] = { statut: n.statut, finPeriode: n.finPeriode, le: new Date().toISOString() };
      ecrireComptes(db);
      return json(rep, 200, { ok: true, enAttenteDeLiaison: n.transaction });
    }
    db.comptes[courriel].abonnementApple = {
      statut: n.statut, finPeriode: n.finPeriode, produit: n.produit,
      transaction: n.transaction, environnement: n.environnement,
      majLe: new Date().toISOString(), derniereNotification: n.type
    };
    ecrireComptes(db);
    json(rep, 200, { ok: true, courriel: courriel, statut: n.statut });
  },

  /* Consultation d'un produit par code-barres. Le serveur relaie Open Food
   * Facts, dérive les allergènes AVEC NOTRE catalogue, et ne conserve rien.
   * L'ODbL impose le partage à l'identique si on FUSIONNE ces données dans
   * une base : on ne fusionne pas, on consulte. */
  "GET /api/produit": async function (req, rep, ctx) {
    const code = (ctx.url.searchParams.get("code") || "").replace(/[^0-9]/g, "");
    if (code.length < 8 || code.length > 14) return json(rep, 400, { erreur: "code-barres invalide" });
    try {
      const r = await fetch("https://world.openfoodfacts.org/api/v2/product/" + code +
        "?fields=product_name,brands,ingredients_text_fr,ingredients_text,allergens_tags,traces_tags,image_small_url", {
        headers: { "User-Agent": process.env.OFF_USER_AGENT || "Bouchees/0.6 (contact@bouchees.example)" }
      });
      const d = await r.json();
      if (!d || d.status !== 1 || !d.product) return json(rep, 404, { erreur: "produit inconnu", code: code });
      const p = d.product;
      json(rep, 200, {
        code: code,
        nom: p.product_name || null,
        marque: p.brands || null,
        ingredientsTexte: p.ingredients_text_fr || p.ingredients_text || null,
        etiquettesAllergenes: p.allergens_tags || [],
        etiquettesTraces: p.traces_tags || [],
        image: p.image_small_url || null,
        attribution: "Données de Open Food Facts, sous licence ODbL (opendatacommons.org/licenses/odbl/1-0)",
        avis: "Les étiquettes d'allergènes de la base sont indicatives — Bouchées re-dérive tout depuis la liste d'ingrédients."
      });
    } catch (e) { json(rep, 502, { erreur: "consultation impossible", detail: e.message }); }
  },

  /* Connexion volontairement minimale : un courriel, un jeton. Pas de mot de
   * passe à gérer, donc pas de mot de passe à faire fuir. En production, ce
   * jeton s'envoie par courriel au lieu d'être retourné ici. */
  "POST /api/connexion": async function (req, rep, ctx) {
    let corps;
    try { corps = JSON.parse((await corpsBrut(req)).toString("utf8")); }
    catch (e) { return json(rep, 400, { erreur: "JSON invalide" }); }
    const courriel = normaliserCourriel(corps.courriel);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(courriel)) return json(rep, 400, { erreur: "courriel invalide" });
    const db = ctx.db;
    if (!db.comptes[courriel]) db.comptes[courriel] = { courriel: courriel, cree: new Date().toISOString(), abonnement: null };
    const jeton = jetonNeuf();
    db.jetons[jeton] = courriel;
    ecrireComptes(db);
    json(rep, 200, { jeton: jeton, courriel: courriel, abonne: abonnementActif(db.comptes[courriel]),
                     note: "En production, ce jeton s'envoie par courriel — il ne revient pas dans la réponse." });
  },

  "POST /api/deconnexion": async function (req, rep, ctx) {
    const auth = (req.headers.authorization || "").replace(/^Bearer\s+/i, "").trim();
    if (auth && ctx.db.jetons[auth]) { delete ctx.db.jetons[auth]; ecrireComptes(ctx.db); }
    json(rep, 200, { ok: true });
  },

  /* Ouvre une session de paiement. La clé secrète reste sur le serveur;
   * le navigateur ne voit qu'une URL Stripe. */
  "POST /api/paiement": async function (req, rep, ctx) {
    if (!ctx.compte) return json(rep, 401, { erreur: "connexion requise" });
    if (!process.env.STRIPE_CLE_SECRETE || !process.env.STRIPE_PRIX)
      return json(rep, 501, { erreur: "paiement non configuré", manque: ["STRIPE_CLE_SECRETE", "STRIPE_PRIX"] });
    const origine = process.env.BOUCHEES_ORIGINE || ("http://localhost:" + PORT);
    try {
      const session = await creerSession({
        prix: process.env.STRIPE_PRIX,
        courriel: ctx.compte.courriel,
        retourOk: origine + "/?abonnement=ok",
        retourAnnule: origine + "/?abonnement=annule"
      });
      json(rep, 200, { url: session.url });
    } catch (err) { json(rep, 502, { erreur: err.message }); }
  },

  /* Webhook Stripe : la seule source de vérité sur l'état de l'abonnement.
   * Jamais le client. Signature vérifiée avant de toucher à quoi que ce soit. */
  "POST /api/webhook/stripe": async function (req, rep, ctx) {
    const brut = await corpsBrut(req);
    const sig = req.headers["stripe-signature"] || "";
    if (!SECRET_WEBHOOK) return json(rep, 500, { erreur: "STRIPE_WEBHOOK_SECRET non configuré" });
    if (!verifierSignature(brut, sig, SECRET_WEBHOOK)) return json(rep, 400, { erreur: "signature invalide" });

    let evt;
    try { evt = JSON.parse(brut.toString("utf8")); }
    catch (e) { return json(rep, 400, { erreur: "JSON invalide" }); }

    const maj = evenementPertinent(evt);
    if (!maj) return json(rep, 200, { ignore: evt.type });

    const courriel = normaliserCourriel(maj.courriel);
    const db = ctx.db;
    if (!db.comptes[courriel]) db.comptes[courriel] = { courriel: courriel, cree: new Date().toISOString(), abonnement: null };
    db.comptes[courriel].abonnement = {
      statut: maj.statut, finPeriode: maj.finPeriode,
      client: maj.client, majLe: new Date().toISOString()
    };
    ecrireComptes(db);
    json(rep, 200, { ok: true, courriel: courriel, statut: maj.statut });
  }
};

const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
                ".json": "application/json; charset=utf-8", ".css": "text/css; charset=utf-8",
                ".webp": "image/webp", ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml" };

function servirStatique(req, rep, url) {
  let rel = decodeURIComponent(url.pathname);
  if (rel === "/" || rel === "") rel = "/index.html";
  const base = rel === "/index.html" ? path.join(racine, "app") : racine;
  const cible = path.normalize(path.join(base, rel));
  if (!cible.startsWith(racine)) { rep.writeHead(403); return rep.end("interdit"); }
  fs.readFile(cible, function (err, data) {
    if (err) { rep.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" }); return rep.end("introuvable"); }
    rep.writeHead(200, { "Content-Type": TYPES[path.extname(cible)] || "application/octet-stream" });
    rep.end(data);
  });
}

function creerServeur() {
  return http.createServer(async function (req, rep) {
    const url = new URL(req.url, "http://x");
    const cle = req.method + " " + url.pathname;
    rep.setHeader("X-Content-Type-Options", "nosniff");
    if (req.method === "OPTIONS") { rep.writeHead(204); return rep.end(); }
    const route = routes[cle];
    if (!route) return servirStatique(req, rep, url);
    const db = lireComptes();
    const ctx = { db: db, url: url, compte: compteDeLaRequete(req, db) };
    try { await route(req, rep, ctx); }
    catch (err) { json(rep, 500, { erreur: err.message }); }
  });
}

if (require.main === module) {
  creerServeur().listen(PORT, function () {
    console.log("Bouchées — serveur sur http://localhost:" + PORT);
    console.log("  lots libres servis à tous, lots abonnés filtrés côté serveur");
    if (!SECRET_WEBHOOK) console.log("  (STRIPE_WEBHOOK_SECRET absent : le webhook répondra 500)");
  });
}

module.exports = { creerServeur: creerServeur, lotsAutorises: lotsAutorises,
                   abonnementActif: abonnementActif, routes: routes };
