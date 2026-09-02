/* Un mur payant on the client is one Ctrl+U away. What is sold is the stream
 * of new recipes, never the answer to "can my child eat this". */
"use strict";

const Barcode = require("../engine/barcode.js");
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
const GRACE_DAYS = 3;   /* access is not cut the second a payment fails */

/* ---------- petite base sur fichier ---------- */
function readAccounts() {
  try { return JSON.parse(fs.readFileSync(FICHIER_COMPTES, "utf8")); }
  catch (e) { return { accounts: {}, tokens: {} }; }
}
/* Written to a sibling file and renamed over the original. */
function writeAccounts(db) {
  const tmp = FICHIER_COMPTES + "." + process.pid + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(db, null, 2));
  fs.renameSync(tmp, FICHIER_COMPTES);
}

/* Thirty days. A token used to live forever: a phone lost in 2026 could still
 * rate recipes in 2030. */
const TOKEN_TTL_MS = 30 * 24 * 3600 * 1000;
function normaliserCourriel(c) { return String(c || "").trim().toLowerCase(); }
function jetonNeuf() { return crypto.randomBytes(24).toString("hex"); }

/* ---------- product lookups: cache and budget ---------- */

/* Shared across every caller. Hits keep for thirty days, misses for a day.
 * Persisted beside accounts.json so a redeploy does not start cold. */
const FICHIER_CACHE = process.env.BOUCHEES_PRODUCT_CACHE ||
                      path.join(__dirname, "product-cache.json");
const ProductCache = (function () {
  const HIT_TTL = 30 * 24 * 3600 * 1000, MISS_TTL = 24 * 3600 * 1000, MAX = 50000;
  let table = {};
  try { table = JSON.parse(fs.readFileSync(FICHIER_CACHE, "utf8")); } catch (e) { table = {}; }
  let sales = 0;
  function persist() {
    try {
      const tmp = FICHIER_CACHE + "." + process.pid + ".tmp";
      fs.writeFileSync(tmp, JSON.stringify(table));
      fs.renameSync(tmp, FICHIER_CACHE);
    } catch (e) { /* the cache is a convenience; losing it costs a lookup */ }
  }
  return {
    get: function (code) {
      const e = table[code];
      if (!e) return null;
      if (Date.now() - e.at > (e.hit ? HIT_TTL : MISS_TTL)) { delete table[code]; return null; }
      return e;
    },
    set: function (code, entry) {
      entry.at = Date.now();
      table[code] = entry;
      if (Object.keys(table).length > MAX) table = {};
      if (++sales % 20 === 0) persist();
    },
    /* For the tests, and for a rebuild after a change to the shape. */
    _reset: function () { table = {}; },
    _size: function () { return Object.keys(table).length; },
    _flush: persist
  };
})();

/* A sliding minute, kept below Open Food Facts' fifteen per address. */
const OffBudget = (function () {
  const PAR_MINUTE = Number(process.env.OFF_BUDGET_PER_MINUTE) || 12;
  let marks = [];
  function prune() {
    const seuil = Date.now() - 60000;
    marks = marks.filter(function (t) { return t > seuil; });
  }
  return {
    available: function () {
      prune();
      return marks.length < PAR_MINUTE;
    },
    take: function () {
      prune();
      if (marks.length >= PAR_MINUTE) return false;
      marks.push(Date.now());
      return true;
    },
    secondsUntilFree: function () {
      prune();
      if (marks.length < PAR_MINUTE) return 0;
      return Math.max(1, Math.ceil((marks[0] + 60000 - Date.now()) / 1000));
    },
    _reset: function () { marks = []; }
  };
})();

function absent(raw, forms, via) {
  return {
    error: "product not found",
    scanned: raw,
    tried: forms,
    via: via,
    contribute: "https://world.openfoodfacts.org/cgi/product.pl?code=" + forms[0]
  };
}

/* ---------- droits ---------- */
function activeFrom(a) {
  if (!a) return false;
  if (a.status === "actif") return true;
  if (a.status === "en_retard" && a.periodEnd)
    return Date.now() < new Date(a.periodEnd).getTime() + GRACE_DAYS * 864e5;
  return false;
}
/* Two subscription sources, Stripe on the web and Apple on iOS. An
 * account may hold both; either one is enough, and nobody is charged twice. */
function subscriptionActive(account) {
  if (!account) return false;
  return activeFrom(account.subscription) || activeFrom(account.abonnementApple);
}
/* Entitlement in the pool model: a free recipe goes to everyone, any other
 * body goes to a subscriber only. The catalogue itself is public. */
function canReadBody(card, account) {
  return !!(card && (card.free || subscriptionActive(account)));
}

/* ---------- reading the published content ---------- */
function loadManifest() {
  return JSON.parse(fs.readFileSync(path.join(dist, "manifest.json"), "utf8"));
}
let catalogueCache = null;
function loadCatalogue() {
  const p = path.join(dist, "catalogue.json");
  const stat = fs.statSync(p);
  if (!catalogueCache || catalogueCache.mtime !== stat.mtimeMs) {
    const list = JSON.parse(fs.readFileSync(p, "utf8"));
    const byId = {};
    list.forEach(function (c) { byId[c.id] = c; });
    catalogueCache = { mtime: stat.mtimeMs, list: list, byId: byId };
  }
  return catalogueCache;
}
function loadBody(id) {
  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(id)) return null;
  try { return JSON.parse(fs.readFileSync(path.join(dist, "recipes", id + ".json"), "utf8")); }
  catch (e) { return null; }
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
/* Sixty-four kilobytes is forty times the largest body any route here
 * expects. Without a ceiling, one request of a few gigabytes exhausts the
 * server's memory: the chunks are kept until the end of the stream. */
const MAX_BODY = 64 * 1024;

function rawBody(req) {
  return new Promise(function (res, rej) {
    const m = [];
    let total = 0;
    req.on("data", function (c) {
      total += c.length;
      if (total > MAX_BODY) {
        /* Stop reading, answer, then let the handler close the socket: a
         * destroy here would reset the connection before the 413 goes out. */
        req.pause();
        const e = new Error("body too large");
        e.status = 413;
        return rej(e);
      }
      m.push(c);
    });
    req.on("end", function () { res(Buffer.concat(m)); });
    req.on("error", rej);
  });
}
/* A token entry is either the bare email (the old shape, treated as issued
 * now on first sight so nothing already installed is logged out) or an object
 * with the email and the issue time. */
function jetonValide(db, token) {
  const entry = db.tokens[token];
  if (!entry) return null;
  if (typeof entry === "string") {
    db.tokens[token] = { email: entry, cree: Date.now() };
    return entry;
  }
  if (Date.now() - (entry.cree || 0) > TOKEN_TTL_MS) {
    delete db.tokens[token];
    return null;
  }
  return entry.email;
}

/* The receipt is the key. A bearer with two dots is a signed Apple
 * transaction: verified up to Apple's root and still in force, it entitles
 * this request on its own — no account, no email, nothing stored. A
 * session token from a real sign-in still works when one exists. */
function compteDeLaRequete(req, db) {
  const auth = req.headers.authorization || "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;
  if ((token.match(/\./g) || []).length === 2) return compteDepuisRecu(token);
  const email = jetonValide(db, token);
  return email ? db.accounts[email] || null : null;
}

function compteDepuisRecu(jws) {
  const v = Apple.verifierJWS(jws);
  if (!v.ok) return null;
  const etat = Apple.etatDepuisTransaction(v.charge);
  if (!etat.ok) return null;
  return { email: null, fromReceipt: true,
           abonnementApple: { status: etat.status, periodEnd: etat.periodEnd || null } };
}

const routes = {
  /* Public: the pool's catalogue — every card, no body. */
  "GET /api/manifest": function (req, res, ctx) {
    const m = loadManifest();
    json(res, 200, {
      version: m.version,
      subscribed: subscriptionActive(ctx.account),
      rotationWeeks: m.rotationWeeks || 16,
      counts: m.counts || null,
      catalogueChecksum: m.catalogueChecksum || null
    });
  },

  "GET /api/catalogue": function (req, res) {
    const c = loadCatalogue();
    json(res, 200, { catalogue: c.list });
  },

  /* Legal pages. Apple requires public, working URLs:
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

  /* The safety tables: free, always, no account required. */
  "GET /api/safety": function (req, res) {
    const s = fs.readFileSync(path.join(dist, "safety.json"));
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "public, max-age=3600" });
    res.end(s);
  },

  /* Bodies, by id. A free recipe goes to anyone; the rest to subscribers.
   * An id the caller is not entitled to answers 402 with the list, and no
   * other body leaves with it. */
  "GET /api/recipes": function (req, res, ctx) {
    const c = loadCatalogue();
    const ids = String(ctx.url.searchParams.get("ids") || "").split(",")
      .map(function (x) { return x.trim(); }).filter(Boolean).slice(0, 200);
    if (!ids.length) return json(res, 400, { error: "ids required" });
    const known = ids.filter(function (id) { return !!c.byId[id]; });
    const unknown = ids.filter(function (id) { return !c.byId[id]; });
    if (!known.length) return json(res, 404, { error: "no such recipe", recipes: unknown });
    const refused = known.filter(function (id) { return !canReadBody(c.byId[id], ctx.account); });
    if (refused.length) return json(res, 402, { error: "subscription required", recipes: refused });
    /* Only a catalogue id ever reaches the file system. */
    const out = [];
    known.forEach(function (id) {
      const body = loadBody(id);
      if (body) out.push(Object.assign({}, c.byId[id], body));
    });
    json(res, 200, { subscribed: subscriptionActive(ctx.account), recipes: out, unknown: unknown });
  },

    /* A rating, 1 to 5: an account is required — otherwise nothing stops one
   * personne de voter cent fois. */
  "POST /api/rating": async function (req, res, ctx) {
    if (!ctx.account || !ctx.account.email) return json(res, 401, { error: "sign-in required to rate" });
        /* One rating per second per account: authentication stops a stranger
     * writing, not a signed-in client looping. */
    if (!limiteDebit(ctx.account.email)) {
      return json(res, 429, { error: "too many requests" });
    }
    let corps;
    try { corps = JSON.parse((await rawBody(req)).toString("utf8")); }
    catch (e) { if (e.status === 413) throw e; return json(res, 400, { error: "invalid JSON" }); }

    const r = corps.rating === null
      ? Ratings.removeRating(corps.recipe, ctx.account.email)
      : Ratings.rate(corps.recipe, ctx.account.email, corps.rating);
    if (!r.ok) return json(res, 400, { error: r.reason });
    json(res, 200, { ok: true, aggregate: r.aggregate });
  },

  /* Aggregates for a list of recipes, plus the account's own rating.
   * Other people's ratings are never exposed, only the totals. */
  "GET /api/ratings": function (req, res, ctx) {
    const ids = (ctx.url.searchParams.get("ids") || "").split(",").filter(Boolean);
    if (!ids.length) return json(res, 200, {});
    json(res, 200, Ratings.aggregates(ids, ctx.account && ctx.account.email ? ctx.account.email : null));
  },

  /* The Top rated tab. This is how a recipe that left the window comes back:
   * on merit, and for good. Full content is returned even outside the window —
   * otherwise the ranking would show titles nobody can open. */
  "GET /api/top-rated": function (req, res, ctx) {
    const limit = Math.min(Number(ctx.url.searchParams.get("limit")) || 10, 50);
    const ranked = Ratings.ranking(limit);
    if (!ranked.length) {
      return json(res, 200, { threshold: Ratings.MIN_VOTES, recipes: [],
        progress: Ratings.progress() });
    }
    const c = loadCatalogue();
    const out = [];
    ranked.forEach(function (r) {
      const card = c.byId[r.recipeId];
      if (!card) return;
      /* The card always; the body only where entitled. A ranked recipe a
       * free account cannot open still shows, locked, with its name. */
      const copie = JSON.parse(JSON.stringify(card));
      if (canReadBody(card, ctx.account)) {
        const body = loadBody(r.recipeId);
        if (body) Object.assign(copie, body);
      }
      copie.votes = r.votes;
      copie.average = r.average;
      if (ctx.account && ctx.account.email) copie.myRating = Ratings.ratingBy(r.recipeId, ctx.account.email);
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

  /* The iOS app sends its signed StoreKit transaction. It is verified in
   * full before anything is granted — the client is never
   * cru sur parole, pas plus qu'un navigateur. */
  "POST /api/apple/transaction": async function (req, res, ctx) {
    if (!ctx.account) return json(res, 401, { error: "sign-in required" });
    let corps;
    try { corps = JSON.parse((await rawBody(req)).toString("utf8")); }
    catch (e) { if (e.status === 413) throw e; return json(res, 400, { error: "invalid JSON" }); }
    const v = Apple.verifierJWS(corps.signedTransaction);
    if (!v.ok) return json(res, 400, { error: "transaction refused", detail: v.reason });
    const etat = Apple.etatDepuisTransaction(v.charge);
    if (!etat.ok) return json(res, 400, { error: "transaction refused", detail: etat.reason });

    const db = ctx.db;
    /* One Apple transaction cannot serve two accounts. */
    const proprietaire = Object.keys(db.accounts).find(function (c) {
      const a = db.accounts[c].abonnementApple;
      return a && a.transaction === etat.transaction && c !== ctx.account.email;
    });
    if (proprietaire) return json(res, 409, { error: "this transaction is already linked to another account" });

    db.accounts[ctx.account.email].abonnementApple = {
      status: etat.status, periodEnd: etat.periodEnd, product: etat.product,
      transaction: etat.transaction, environnement: etat.environnement,
      updatedAt: new Date().toISOString()
    };
    writeAccounts(db);
    json(res, 200, { ok: true, subscribed: subscriptionActive(db.accounts[ctx.account.email]), status: etat.status });
  },

  /* Notifications V2 d'Apple : renouvellements, remboursements, expirations.
   * Like the Stripe webhook, this is the source of truth, not the client. */
  "POST /api/webhook/apple": async function (req, res, ctx) {
    let corps;
    try { corps = JSON.parse((await rawBody(req)).toString("utf8")); }
    catch (e) { if (e.status === 413) throw e; return json(res, 400, { error: "invalid JSON" }); }
    const n = Apple.lireNotification(corps.signedPayload);
    if (!n.ok) return json(res, 400, { error: "notification refused", detail: n.reason });
    if (n.ignored) return json(res, 200, { ignored: n.ignored });

    const db = ctx.db;
    const email = Object.keys(db.accounts).find(function (c) {
      const a = db.accounts[c].abonnementApple;
      return a && a.transaction === n.transaction;
    });
    /* Unknown transaction: filed without crashing. The account gets linked on
     * the app's next launch, and the state is picked up then. */
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

    /* Consultation d'un product par code-barres: le serveur relaie Open Food
   * Facts, derives allergens WITH OUR catalogue, and keeps nothing. */
    /* Product lookup by barcode: two things were missing and each one hid
   * products that are in the database: */
  "GET /api/product": async function (req, res, ctx) {
        /* GS1-aware: a QR or a Data Matrix hands over a URL or an element string,
     * and keeping only their digits gave a seventeen-digit key that nothing
     * indexes. `digits` finds the GTIN inside, or says there is none. */
    const raw = Barcode.digits(ctx.url.searchParams.get("code"));
    if (!raw) {
      return json(res, 400, { error: "no barcode in this code",
                              scanned: String(ctx.url.searchParams.get("code") || "").slice(0, 80) });
    }

    const forms = Barcode.forms(raw);
    if (!forms.length) return json(res, 400, { error: "invalid barcode" });

        /* The cache answers first, for everyone: open Food Facts allows fifteen
     * product reads a minute PER ADDRESS, and this server is one address for
     * every parent using the app. */
        /* Keyed on the canonical form — the longest, which is the thirteen-digit
     * one — so a UPC-A and its EAN-13 twin share one entry. */
    const key = forms.reduce(function (a, b) { return b.length > a.length ? b : a; }, forms[0]);
    const connu = ProductCache.get(key);
    if (connu) {
      if (connu.hit) return json(res, 200, connu.payload);
      return json(res, 404, absent(raw, forms, "cache"));
    }

        /* The budget stops us before the ban does: twelve a minute, under their
     * fifteen: when it is spent, the answer is "try again shortly", not eight
     * requests that will all be refused. */
    if (!OffBudget.available()) {
      return json(res, 503, {
        error: "product database unavailable",
        retryAfterSeconds: OffBudget.secondsUntilFree(),
        scanned: raw
      });
    }

    const champs = "product_name,product_name_fr,brands,ingredients_text_fr," +
                   "ingredients_text,allergens_tags,traces_tags,image_small_url";
    const entetes = {
      /* The fallback names a domain that resolves. The old one, ".example",
       * gave Open Food Facts no one to contact before blocking an address. */
      "User-Agent": process.env.OFF_USER_AGENT || "Bouchees/1.0 (https://bouchees.onrender.com)"
    };

        /* Food with both forms, then one form per sibling: food is where a
     * grocery product lives; the siblings only need a look. */
    const plan = [];
    for (const forme of forms) plan.push({ hote: "world.openfoodfacts.org", genre: "food", forme: forme });
    for (const b of [["world.openbeautyfacts.org", "beauty"],
                     ["world.openpetfoodfacts.org", "petfood"],
                     ["world.openproductsfacts.org", "product"]]) {
      plan.push({ hote: b[0], genre: b[1], forme: forms[0] });
    }

    let unavailable = false;
    for (const step of plan) {
      if (!OffBudget.take()) { unavailable = true; break; }
      let r;
      try {
        r = await fetch("https://" + step.hote + "/api/v2/product/" + step.forme +
                        "?fields=" + champs, { headers: entetes });
      } catch (e) { unavailable = true; continue; }

            /* "limited" is not "not found": a refused request comes back as a 429,
       * a 503, or an HTML page. */
      const type = (r.headers.get("content-type") || "").toLowerCase();
      if (r.status === 429 || r.status >= 500 || type.indexOf("json") < 0) {
        unavailable = true;
        continue;
      }
      let d;
      try { d = await r.json(); } catch (e) { unavailable = true; continue; }
      if (!d || d.status !== 1 || !d.product) continue;

      const p = d.product;
      const payload = {
        code: step.forme,
        scanned: raw,
        source: step.genre,
        name: p.product_name_fr || p.product_name || null,
        brand: p.brands || null,
        ingredientsText: p.ingredients_text_fr || p.ingredients_text || null,
        allergenTags: p.allergens_tags || [],
        traceTags: p.traces_tags || [],
        image: p.image_small_url || null,
        assignment: "Data from Open Food Facts and its sibling databases, " +
                    "ODbL licence (opendatacommons.org/licenses/odbl/1-0)",
        notice: "The database's own allergen tags are indicative — Bouchees " +
                "re-derives everything from the ingredient list."
      };
      ProductCache.set(key, { hit: true, payload: payload });
      return json(res, 200, payload);
    }

    /* A miss is only a miss when every database actually answered. If one
     * was refusing, say so rather than remember a "not found" that is not
     * known to be true. */
    if (unavailable) {
      return json(res, 503, {
        error: "product database unavailable",
        retryAfterSeconds: OffBudget.secondsUntilFree(),
        scanned: raw
      });
    }
    ProductCache.set(key, { hit: false });
    json(res, 404, absent(raw, forms, "live"));
  },

  /* Connexion volontairement minimale : un email, un token. Pas de mot de
   * password to manage, so no password to leak. In production this token is
   * emailed instead of being returned here. */
  "POST /api/login": async function (req, res, ctx) {
        /* Closed until sign-in is real: the note below says the token is emailed
     * in production; the deployment on Render IS production, and the token
     * came back in the response. */
    if (!ctx.insecureLogin) {
      return json(res, 503, { error: "sign-in is not available yet" });
    }
    let corps;
    try { corps = JSON.parse((await rawBody(req)).toString("utf8")); }
    catch (e) { if (e.status === 413) throw e; return json(res, 400, { error: "invalid JSON" }); }
    const email = normaliserCourriel(corps.email);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json(res, 400, { error: "email invalide" });
    const db = ctx.db;
    if (!db.accounts[email]) db.accounts[email] = { email: email, cree: new Date().toISOString(), subscription: null };
    const token = jetonNeuf();
    db.tokens[token] = { email: email, cree: Date.now() };
    writeAccounts(db);
    json(res, 200, { token: token, email: email, subscribed: subscriptionActive(db.accounts[email]),
                     note: "En production, ce token s'envoie par email — il ne revient pas dans la réponse." });
  },

  "POST /api/logout": async function (req, res, ctx) {
    const auth = (req.headers.authorization || "").replace(/^Bearer\s+/i, "").trim();
    if (auth && ctx.db.tokens[auth]) { delete ctx.db.tokens[auth]; writeAccounts(ctx.db); }
    json(res, 200, { ok: true });
  },

  /* Opens a checkout session. The secret key stays on the server; the
   * browser only sees a Stripe URL. */
  "POST /api/checkout": async function (req, res, ctx) {
    if (!ctx.account) return json(res, 401, { error: "sign-in required" });
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

  /* Stripe webhook: the only source of truth on subscription state. Never the
   * client. The signature is verified before anything is touched. */
  "POST /api/webhook/stripe": async function (req, res, ctx) {
    const raw = await rawBody(req);
    const sig = req.headers["stripe-signature"] || "";
    if (!SECRET_WEBHOOK) return json(res, 500, { error: "STRIPE_WEBHOOK_SECRET non configuré" });
    if (!verifierSignature(raw, sig, SECRET_WEBHOOK)) return json(res, 400, { error: "signature invalide" });

    let evt;
    try { evt = JSON.parse(raw.toString("utf8")); }
    catch (e) { if (e.status === 413) throw e; return json(res, 400, { error: "invalid JSON" }); }

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

/* Photos live on the server, not in the app: batches rotate, and the
 * client caches them on the device, pruning when a batch leaves the window. */
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
                ".json": "application/json; charset=utf-8", ".css": "text/css; charset=utf-8",
                ".webp": "image/webp", ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml" };

/* A minute of recent calls per key, nothing persisted. */
const _debits = new Map();
function limiteDebit(key, parMinute) {
  const max = parMinute || 60;
  const now = Date.now();
  const seen = (_debits.get(key) || []).filter(function (t) {
    return now - t < 60000;
  });
  if (seen.length >= max) { _debits.set(key, seen); return false; }
  seen.push(now);
  _debits.set(key, seen);
  /* Bounded: without this the map grows one entry per account, forever. */
  if (_debits.size > 5000) {
    for (const k of _debits.keys()) { _debits.delete(k); if (_debits.size <= 4000) break; }
  }
  return true;
}

const ALLOWED_IMAGE_EXT = [".png", ".webp", ".jpg", ".jpeg"];

function serveStatic(req, res, url) {
  let rel = decodeURIComponent(url.pathname);
  if (rel === "/" || rel === "") rel = "/index.html";

    /* Recipe photos: the file name carries the ingredient fingerprint, so an
   * image never changes under the same name and the cache is immutable. */
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

  /* Nothing else is served. The repository is not a document root: dist/,
   * data/ and server/ hold the recipe bodies and the accounts, the web demo
   * inlines the whole corpus, and a wall the API enforces is worth nothing
   * if a plain URL walks around it. The demo runs locally, from web/. */
  if (rel === "/" || rel === "/index.html") {
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    return res.end("Bouchees");
  }
  res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("introuvable");
}

function createServer(options) {
  /* Read once, here, rather than from the environment on every request, so
   * a test can open the door on one instance without opening it on another
   * running beside it. */
  const insecureLogin = options && "allowInsecureLogin" in options
    ? !!options.allowInsecureLogin
    : process.env.ALLOW_INSECURE_LOGIN === "1";
  return http.createServer(async function (req, res) {
    req.on("error", function () { /* aborted by rawBody; the 413 below answers */ });
    const url = new URL(req.url, "http://x");
    const key = req.method + " " + url.pathname;
    res.setHeader("X-Content-Type-Options", "nosniff");
    if (req.method === "OPTIONS") { res.writeHead(204); return res.end(); }
    const route = routes[key];
    if (!route) return serveStatic(req, res, url);
    const db = readAccounts();
    const ctx = { db: db, url: url, account: compteDeLaRequete(req, db),
                  insecureLogin: insecureLogin };
    try { await route(req, res, ctx); }
    catch (err) {
      if (res.headersSent) return;
      /* A body that blew past the ceiling is the caller's fault, not ours. */
      json(res, err.status === 413 ? 413 : 500,
           { error: err.status === 413 ? "body too large" : err.message });
      if (err.status === 413) res.on("finish", function () { req.destroy(); });
    }
  });
}

if (require.main === module) {
  createServer().listen(PORT, function () {
    console.log("Bouchées — serveur sur http://localhost:" + PORT);
    console.log("  batches free servis à tous, batches abonnés filtrés côté serveur");
    if (!SECRET_WEBHOOK) console.log("  (STRIPE_WEBHOOK_SECRET absent : le webhook répondra 500)");
  });
}

module.exports = { createServer: createServer, canReadBody: canReadBody,
                   subscriptionActive: subscriptionActive, routes: routes,
                   /* Exposed for the tests only. */
                   _ProductCache: ProductCache, _OffBudget: OffBudget,
                   _MAX_BODY: MAX_BODY, _TOKEN_TTL_MS: TOKEN_TTL_MS };
