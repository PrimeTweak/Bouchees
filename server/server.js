/* Serveur Bouchées — bloc F
 * node server/server.js        (port 8787 par défaut)
 *
 * Node pur, zéro dépendance : rien à installer.
 *
 * LE POINT CENTRAL : le serveur n'envoie jamais un lot auquel le account n'a
 * pas droit. Pas « envoyer puis cacher » — ne pas envoyer. Un mur payant
 * côté client s'ouvre avec Ctrl+U.
 *
 * ET LA CONTREPARTIE : les tables de sécurité (moteur, substitutions, règles
 * d'âge) et les batches free partent pour TOUT LE MONDE, connecté ou non.
 * On vend le flux de nouvelles recipes, pas la réponse à « est-ce que mon
 * fils peut manger ça ».
 */
"use strict";
const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { verifierSignature, evenementPertinent, creerSession } = require("./stripe.js");
const Apple = require("./apple.js");
const { CONDITIONS, CONFIDENTIALITE } = require("./legal-pages.js");
const Ratings = require("./ratings.js");

const root = path.join(__dirname, "..");
const dist = path.join(root, "dist");
const PORT = process.env.PORT || 8787;
const FICHIER_COMPTES = process.env.BOUCHEES_COMPTES || path.join(__dirname, "accounts.json");
const SECRET_WEBHOOK = process.env.STRIPE_WEBHOOK_SECRET || "";
const GRACE_DAYS = 3;   /* on ne coupe pas l'accès à la seconde où un paiement échoue */

/* ---------- petite base sur fichier ---------- */
function readAccounts() {
  try { return JSON.parse(fs.readFileSync(FICHIER_COMPTES, "utf8")); }
  catch (e) { return { accounts: {}, jetons: {} }; }
}
function writeAccounts(db) {
  fs.writeFileSync(FICHIER_COMPTES, JSON.stringify(db, null, 2));
}
function normaliserCourriel(c) { return String(c || "").trim().toLowerCase(); }
function jetonNeuf() { return crypto.randomBytes(24).toString("hex"); }

/* ---------- droits ---------- */
function activeFrom(a) {
  if (!a) return false;
  if (a.status === "actif") return true;
  if (a.status === "en_retard" && a.periodEnd)
    return Date.now() < new Date(a.periodEnd).getTime() + GRACE_DAYS * 864e5;
  return false;
}
/* Deux sources d'subscription — Stripe pour le web, Apple pour iOS. Un account
 * peut avoir les deux (il s'est abonné sur le web puis a installé l'app) :
 * l'une OU l'autre suffit, et on ne facture jamais deux fois pour ça. */
function subscriptionActive(account) {
  if (!account) return false;
  return activeFrom(account.subscription) || activeFrom(account.abonnementApple);
}
function allowedBatches(manifeste, account) {
  const actif = subscriptionActive(account);
  return manifeste.batches
    .filter(function (l) { return l.access === "free" || actif; })
    .map(function (l) { return l.id; });
}

/* ---------- lecture du content publié ---------- */
function loadManifest() {
  return JSON.parse(fs.readFileSync(path.join(dist, "manifest.json"), "utf8"));
}
function loadBatch(id) {
  return JSON.parse(fs.readFileSync(path.join(dist, "batches", id + ".json"), "utf8"));
}

/* ---------- HTTP ---------- */
function json(res, code, corps) {
  const s = JSON.stringify(corps);
  res.writeHead(code, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(s),
    "Cache-Control": "no-store"
  });
  res.end(s);
}
function rawBody(req) {
  return new Promise(function (res, rej) {
    const m = [];
    req.on("data", function (c) { m.push(c); });
    req.on("end", function () { res(Buffer.concat(m)); });
    req.on("error", rej);
  });
}
function compteDeLaRequete(req, db) {
  const auth = req.headers.authorization || "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;
  const email = db.jetons[token];
  return email ? db.accounts[email] || null : null;
}

const routes = {
  /* Ce que tout le monde peut savoir : quels batches existent, lesquels sont
   * verrouillés. Le content, lui, ne part pas. */
  "GET /api/manifest": function (req, res, ctx) {
    const m = loadManifest();
    const allowed = allowedBatches(m, ctx.account);
    json(res, 200, {
      version: m.version,
      subscribed: subscriptionActive(ctx.account),
      currentWeek: m.currentWeek || null,
      windowSize: m.windowSize || null,
      batches: m.batches.map(function (l) {
        return { id: l.id, title: l.title, date: l.date, access: l.access, note: l.note,
                 count: l.count, weekly: !!l.weekly,
                 inWindow: !!l.inWindow,
                 /* « déverrouillé » = le account y a droit ET c'est dans la
                  * fenêtre. Un lot d'il y a deux mois reste verrouillé même
                  * pour un abonné : il revient par les Meilleures. */
                 unlocked: allowed.indexOf(l.id) !== -1 && (l.access === "free" || !!l.inWindow) };
      })
    });
  },

  /* Pages légales. Apple exige des URL publiques et fonctionnelles :
   * un lien mort fait rejeter la soumission. */
  "GET /terms": function (req, res) {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8",
                         "Cache-Control": "public, max-age=3600" });
    res.end(CONDITIONS);
  },

  "GET /privacy": function (req, res) {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8",
                         "Cache-Control": "public, max-age=3600" });
    res.end(CONFIDENTIALITE);
  },

  /* Les tables de sécurité : gratuites, toujours, sans account. */
  "GET /api/safety": function (req, res) {
    const s = fs.readFileSync(path.join(dist, "safety.json"));
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "public, max-age=3600" });
    res.end(s);
  },

  /* Le content, filtré par droits ET par la fenêtre glissante.
   *
   * Un abonné reçoit les batches free plus les trois dernières semaines. Les
   * semaines plus anciennes ne descendent pas : elles reviennent par l'onglet
   * Meilleures ou par les favoris que l'appareil a gardés. */
  "GET /api/recipes": function (req, res, ctx) {
    const m = loadManifest();
    const allowed = allowedBatches(m, ctx.account);
    const requested = ctx.url.searchParams.get("batch");
    const inWindow = new Set(m.batches.filter(function (l) { return l.inWindow; })
                                      .map(function (l) { return l.id; }));
    const targets = requested ? [requested] : allowed.filter(function (id) { return inWindow.has(id); });
    const refuses = targets.filter(function (id) { return allowed.indexOf(id) === -1; });
    if (refuses.length) return json(res, 402, { error: "subscription requis", batches: refuses });
    let out = [];
    targets.forEach(function (id) {
      try { out = out.concat(loadBatch(id)); } catch (e) {}
    });
    json(res, 200, { subscribed: subscriptionActive(ctx.account), batches: targets, recipes: out });
  },

  /* Une note, de 1 à 5. Une seule par account et par recipe : la nouvelle
   * remplace l'ancienne, parce qu'un parent qui refait la recipe peut
   * changer d'notice. Un account est requis — sinon rien n'empêche une même
   * personne de voter cent fois. */
  "POST /api/rating": async function (req, res, ctx) {
    if (!ctx.account) return json(res, 401, { error: "connexion requise pour noter" });
    let corps;
    try { corps = JSON.parse((await rawBody(req)).toString("utf8")); }
    catch (e) { return json(res, 400, { error: "JSON invalide" }); }

    const r = corps.rating === null
      ? Ratings.removeRating(corps.recipe, ctx.account.email)
      : Ratings.rate(corps.recipe, ctx.account.email, corps.rating);
    if (!r.ok) return json(res, 400, { error: r.reason });
    json(res, 200, { ok: true, aggregate: r.aggregate });
  },

  /* Les agrégats d'une liste de recipes, avec la note du account s'il en a
   * une. On n'expose jamais les notes des autres, seulement le total. */
  "GET /api/ratings": function (req, res, ctx) {
    const ids = (ctx.url.searchParams.get("ids") || "").split(",").filter(Boolean);
    if (!ids.length) return json(res, 200, {});
    json(res, 200, Ratings.aggregates(ids, ctx.account ? ctx.account.email : null));
  },

  /* L'onglet Meilleures. C'est la façon dont une recipe out de la fenêtre
   * revient : par mérite, et pour de bon. Le content complet est renvoyé, même
   * hors fenêtre — sinon le ranking montrerait des titres inaccessibles. */
  "GET /api/top-rated": function (req, res, ctx) {
    const limit = Math.min(Number(ctx.url.searchParams.get("limit")) || 10, 50);
    const ranked = Ratings.ranking(limit);
    if (!ranked.length) {
      return json(res, 200, { threshold: Ratings.MIN_VOTES, recipes: [],
        progress: Ratings.progress() });
    }
    const m = loadManifest();
    const allowed = new Set(allowedBatches(m, ctx.account));
    const parId = {};
    m.batches.forEach(function (l) {
      if (!allowed.has(l.id)) return;
      try {
        loadBatch(l.id).forEach(function (r) { parId[r.id] = r; });
      } catch (e) {}
    });

    const out = [];
    ranked.forEach(function (c) {
      const r = parId[c.recipeId];
      if (!r) return;   /* lot non autorisé : on ne laisse rien filtrer */
      const copie = JSON.parse(JSON.stringify(r));
      copie.votes = c.votes;
      copie.average = c.average;
      if (ctx.account) copie.myRating = Ratings.ratingBy(c.recipeId, ctx.account.email);
      out.push(copie);
    });
    json(res, 200, { threshold: Ratings.MIN_VOTES, recipes: out, progress: Ratings.progress() });
  },

  "GET /api/me": function (req, res, ctx) {
    if (!ctx.account) return json(res, 200, { connecte: false, subscribed: false });
    json(res, 200, {
      connecte: true, email: ctx.account.email, subscribed: subscriptionActive(ctx.account),
      subscription: ctx.account.subscription || null,
      abonnementApple: ctx.account.abonnementApple || null,
      source: activeFrom(ctx.account.abonnementApple) ? "apple"
            : activeFrom(ctx.account.subscription) ? "stripe" : null
    });
  },

  /* L'app iOS envoie sa transaction StoreKit signée. On la vérifie
   * intégralement avant d'accorder quoi que ce soit — le client n'est jamais
   * cru sur parole, pas plus qu'un navigateur. */
  "POST /api/apple/transaction": async function (req, res, ctx) {
    if (!ctx.account) return json(res, 401, { error: "connexion requise" });
    let corps;
    try { corps = JSON.parse((await rawBody(req)).toString("utf8")); }
    catch (e) { return json(res, 400, { error: "JSON invalide" }); }
    const v = Apple.verifierJWS(corps.signedTransaction);
    if (!v.ok) return json(res, 400, { error: "transaction refusée", detail: v.reason });
    const etat = Apple.etatDepuisTransaction(v.charge);
    if (!etat.ok) return json(res, 400, { error: "transaction refusée", detail: etat.reason });

    const db = ctx.db;
    /* Une même transaction Apple ne peut pas servir deux accounts. */
    const proprietaire = Object.keys(db.accounts).find(function (c) {
      const a = db.accounts[c].abonnementApple;
      return a && a.transaction === etat.transaction && c !== ctx.account.email;
    });
    if (proprietaire) return json(res, 409, { error: "cette transaction est déjà liée à un autre account" });

    db.accounts[ctx.account.email].abonnementApple = {
      status: etat.status, periodEnd: etat.periodEnd, product: etat.product,
      transaction: etat.transaction, environnement: etat.environnement,
      updatedAt: new Date().toISOString()
    };
    writeAccounts(db);
    json(res, 200, { ok: true, subscribed: subscriptionActive(db.accounts[ctx.account.email]), status: etat.status });
  },

  /* Notifications V2 d'Apple : renouvellements, remboursements, expirations.
   * Comme le webhook Stripe, c'est la source de vérité, pas le client. */
  "POST /api/webhook/apple": async function (req, res, ctx) {
    let corps;
    try { corps = JSON.parse((await rawBody(req)).toString("utf8")); }
    catch (e) { return json(res, 400, { error: "JSON invalide" }); }
    const n = Apple.lireNotification(corps.signedPayload);
    if (!n.ok) return json(res, 400, { error: "notification refusée", detail: n.reason });
    if (n.ignored) return json(res, 200, { ignored: n.ignored });

    const db = ctx.db;
    const email = Object.keys(db.accounts).find(function (c) {
      const a = db.accounts[c].abonnementApple;
      return a && a.transaction === n.transaction;
    });
    /* Transaction inconnue : on l'archive sans planter. Le account sera lié au
     * prochain lancement de l'app, et l'état sera repris à ce moment-là. */
    if (!email) {
      db.orphelinsApple = db.orphelinsApple || {};
      db.orphelinsApple[n.transaction] = { status: n.status, periodEnd: n.periodEnd, le: new Date().toISOString() };
      writeAccounts(db);
      return json(res, 200, { ok: true, enAttenteDeLiaison: n.transaction });
    }
    db.accounts[email].abonnementApple = {
      status: n.status, periodEnd: n.periodEnd, product: n.product,
      transaction: n.transaction, environnement: n.environnement,
      updatedAt: new Date().toISOString(), derniereNotification: n.type
    };
    writeAccounts(db);
    json(res, 200, { ok: true, email: email, status: n.status });
  },

  /* Consultation d'un product par code-barres. Le serveur relaie Open Food
   * Facts, dérive les allergènes AVEC NOTRE catalogue, et ne conserve rien.
   * L'ODbL impose le partage à l'identique si on FUSIONNE ces données dans
   * une base : on ne fusionne pas, on consulte. */
  "GET /api/product": async function (req, res, ctx) {
    const code = (ctx.url.searchParams.get("code") || "").replace(/[^0-9]/g, "");
    if (code.length < 8 || code.length > 14) return json(res, 400, { error: "code-barres invalide" });
    try {
      const r = await fetch("https://world.openfoodfacts.org/api/v2/product/" + code +
        "?fields=product_name,brands,ingredients_text_fr,ingredients_text,allergens_tags,traces_tags,image_small_url", {
        headers: { "User-Agent": process.env.OFF_USER_AGENT || "Bouchees/0.6 (contact@bouchees.example)" }
      });
      const d = await r.json();
      if (!d || d.status !== 1 || !d.product) return json(res, 404, { error: "product inconnu", code: code });
      const p = d.product;
      json(res, 200, {
        code: code,
        name: p.product_name || null,
        brand: p.brands || null,
        ingredientsText: p.ingredients_text_fr || p.ingredients_text || null,
        allergenTags: p.allergens_tags || [],
        traceTags: p.traces_tags || [],
        image: p.image_small_url || null,
        assignment: "Données de Open Food Facts, sous licence ODbL (opendatacommons.org/licenses/odbl/1-0)",
        notice: "Les étiquettes d'allergènes de la base sont indicatives — Bouchées re-dérive tout depuis la liste d'ingrédients."
      });
    } catch (e) { json(res, 502, { error: "consultation impossible", detail: e.message }); }
  },

  /* Connexion volontairement minimale : un email, un token. Pas de mot de
   * passe à gérer, donc pas de mot de passe à faire fuir. En production, ce
   * token s'envoie par email au lieu d'être retourné ici. */
  "POST /api/login": async function (req, res, ctx) {
    let corps;
    try { corps = JSON.parse((await rawBody(req)).toString("utf8")); }
    catch (e) { return json(res, 400, { error: "JSON invalide" }); }
    const email = normaliserCourriel(corps.email);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json(res, 400, { error: "email invalide" });
    const db = ctx.db;
    if (!db.accounts[email]) db.accounts[email] = { email: email, cree: new Date().toISOString(), subscription: null };
    const token = jetonNeuf();
    db.jetons[token] = email;
    writeAccounts(db);
    json(res, 200, { token: token, email: email, subscribed: subscriptionActive(db.accounts[email]),
                     note: "En production, ce token s'envoie par email — il ne revient pas dans la réponse." });
  },

  "POST /api/logout": async function (req, res, ctx) {
    const auth = (req.headers.authorization || "").replace(/^Bearer\s+/i, "").trim();
    if (auth && ctx.db.jetons[auth]) { delete ctx.db.jetons[auth]; writeAccounts(ctx.db); }
    json(res, 200, { ok: true });
  },

  /* Ouvre une session de paiement. La clé secrète reste sur le serveur;
   * le navigateur ne voit qu'une URL Stripe. */
  "POST /api/checkout": async function (req, res, ctx) {
    if (!ctx.account) return json(res, 401, { error: "connexion requise" });
    if (!process.env.STRIPE_CLE_SECRETE || !process.env.STRIPE_PRIX)
      return json(res, 501, { error: "paiement non configuré", manque: ["STRIPE_CLE_SECRETE", "STRIPE_PRIX"] });
    const origine = process.env.BOUCHEES_ORIGINE || ("http://localhost:" + PORT);
    try {
      const session = await creerSession({
        prix: process.env.STRIPE_PRIX,
        email: ctx.account.email,
        retourOk: origine + "/?subscription=ok",
        retourAnnule: origine + "/?subscription=annule"
      });
      json(res, 200, { url: session.url });
    } catch (err) { json(res, 502, { error: err.message }); }
  },

  /* Webhook Stripe : la seule source de vérité sur l'état de l'subscription.
   * Jamais le client. Signature vérifiée avant de toucher à quoi que ce soit. */
  "POST /api/webhook/stripe": async function (req, res, ctx) {
    const brut = await rawBody(req);
    const sig = req.headers["stripe-signature"] || "";
    if (!SECRET_WEBHOOK) return json(res, 500, { error: "STRIPE_WEBHOOK_SECRET non configuré" });
    if (!verifierSignature(brut, sig, SECRET_WEBHOOK)) return json(res, 400, { error: "signature invalide" });

    let evt;
    try { evt = JSON.parse(brut.toString("utf8")); }
    catch (e) { return json(res, 400, { error: "JSON invalide" }); }

    const maj = evenementPertinent(evt);
    if (!maj) return json(res, 200, { ignored: evt.type });

    const email = normaliserCourriel(maj.email);
    const db = ctx.db;
    if (!db.accounts[email]) db.accounts[email] = { email: email, cree: new Date().toISOString(), subscription: null };
    db.accounts[email].subscription = {
      status: maj.status, periodEnd: maj.periodEnd,
      client: maj.client, updatedAt: new Date().toISOString()
    };
    writeAccounts(db);
    json(res, 200, { ok: true, email: email, status: maj.status });
  }
};

/* Les photos vivent sur le serveur, pas dans l'app : les semaines tournent,
 * et embarquer les images ferait grossir l'IPA sans fin. Le client les met en
 * cache sur l'appareil et fait le ménage quand un lot sort de la fenêtre. */
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
                ".json": "application/json; charset=utf-8", ".css": "text/css; charset=utf-8",
                ".webp": "image/webp", ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml" };

const ALLOWED_IMAGE_EXT = [".png", ".webp", ".jpg", ".jpeg"];

function serveStatic(req, res, url) {
  let rel = decodeURIComponent(url.pathname);
  if (rel === "/" || rel === "") rel = "/index.html";

  /* Photos des recipes. Le name de fichier contient l'empreinte des
   * ingrédients : une image ne change jamais sous le même name, donc cache
   * immuable. Extensions en liste blanche — rien d'autre qu'une image ne
   * sort de ce dossier. */
  if (rel.indexOf("/images/") === 0) {
    const ext = path.extname(rel).toLowerCase();
    if (ALLOWED_IMAGE_EXT.indexOf(ext) === -1) { res.writeHead(404); return res.end(); }
    const target = path.normalize(path.join(root, rel));
    if (target.indexOf(path.join(root, "images")) !== 0) { res.writeHead(403); return res.end(); }
    return fs.readFile(target, function (err, data) {
      if (err) { res.writeHead(404); return res.end(); }
      res.writeHead(200, { "Content-Type": TYPES[ext] || "application/octet-stream",
                           "Cache-Control": "public, max-age=31536000, immutable" });
      res.end(data);
    });
  }

  const base = rel === "/index.html" ? path.join(root, "web") : root;
  const target = path.normalize(path.join(base, rel));
  if (!target.startsWith(root)) { res.writeHead(403); return res.end("interdit"); }
  fs.readFile(target, function (err, data) {
    if (err) { res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" }); return res.end("introuvable"); }
    res.writeHead(200, { "Content-Type": TYPES[path.extname(target)] || "application/octet-stream" });
    res.end(data);
  });
}

function createServer() {
  return http.createServer(async function (req, res) {
    const url = new URL(req.url, "http://x");
    const cle = req.method + " " + url.pathname;
    res.setHeader("X-Content-Type-Options", "nosniff");
    if (req.method === "OPTIONS") { res.writeHead(204); return res.end(); }
    const route = routes[cle];
    if (!route) return serveStatic(req, res, url);
    const db = readAccounts();
    const ctx = { db: db, url: url, account: compteDeLaRequete(req, db) };
    try { await route(req, res, ctx); }
    catch (err) { json(res, 500, { error: err.message }); }
  });
}

if (require.main === module) {
  createServer().listen(PORT, function () {
    console.log("Bouchées — serveur sur http://localhost:" + PORT);
    console.log("  batches free servis à tous, batches abonnés filtrés côté serveur");
    if (!SECRET_WEBHOOK) console.log("  (STRIPE_WEBHOOK_SECRET absent : le webhook répondra 500)");
  });
}

module.exports = { createServer: createServer, allowedBatches: allowedBatches,
                   subscriptionActive: subscriptionActive, routes: routes };
