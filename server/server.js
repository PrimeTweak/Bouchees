/* Bouchees server
 * node server/server.js        (port 8787 by default)
 *
 * Plain Node, zero dependencies: nothing to install.
 *
 * LE POINT CENTRAL : le serveur n'envoie jamais un lot auquel le account n'a
 * pas droit. Pas « envoyer puis cacher » — ne pas envoyer. Un mur payant
 * on the client is one Ctrl+U away.
 *
 * AND THE OTHER SIDE OF IT: the safety tables (engine, substitutions, age
 * rules) and the free batches go out to EVERYONE, signed in or not. What is
 * sold is the stream of new recipes, never the answer to "can my child eat
 * this".
 */
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
  catch (e) { return { accounts: {}, jetons: {} }; }
}
/* Written to a sibling file and renamed over the original. A rename is
 * atomic on the file system, so a crash or a second request mid-write leaves
 * either the old file or the new one, never a truncated one. The old code
 * wrote in place. */
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
    set: function (code, entree) {
      entree.at = Date.now();
      table[code] = entree;
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
  let marques = [];
  function nettoyer() {
    const seuil = Date.now() - 60000;
    marques = marques.filter(function (t) { return t > seuil; });
  }
  return {
    take: function () {
      nettoyer();
      if (marques.length >= PAR_MINUTE) return false;
      marques.push(Date.now());
      return true;
    },
    secondsUntilFree: function () {
      nettoyer();
      if (marques.length < PAR_MINUTE) return 0;
      return Math.max(1, Math.ceil((marques[0] + 60000 - Date.now()) / 1000));
    },
    _reset: function () { marques = []; }
  };
})();

function absent(brut, formes, via) {
  return {
    error: "product not found",
    scanned: brut,
    tried: formes,
    via: via,
    contribute: "https://world.openfoodfacts.org/cgi/product.pl?code=" + formes[0]
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
/* Deux sources d'subscription — Stripe pour le web, Apple pour iOS. Un account
 * can hold both (subscribed on the web, then installed the app): either one
 * is enough, and nobody is ever charged twice for it. */
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

/* ---------- reading the published content ---------- */
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
  const entree = db.jetons[token];
  if (!entree) return null;
  if (typeof entree === "string") {
    db.jetons[token] = { email: entree, cree: Date.now() };
    return entree;
  }
  if (Date.now() - (entree.cree || 0) > TOKEN_TTL_MS) {
    delete db.jetons[token];
    return null;
  }
  return entree.email;
}

function compteDeLaRequete(req, db) {
  const auth = req.headers.authorization || "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;
  const email = jetonValide(db, token);
  return email ? db.accounts[email] || null : null;
}

const routes = {
  /* Ce que tout le monde peut savoir : quels batches existent, lesquels sont
   * locked. The content itself does not go out. */
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
                 /* "unlocked" = the account is entitled to it AND it is in
                  * the window. A batch from two months ago stays locked even
                  * for a subscriber: it comes back through Top rated. */
                 unlocked: allowed.indexOf(l.id) !== -1 && (l.access === "free" || !!l.inWindow) };
      })
    });
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

  /* The content, filtered by entitlement AND by the rolling window.
   *
   * A subscriber gets the free batches plus the last three weeks. Anything
   * semaines plus anciennes ne descendent pas : elles reviennent par l'onglet
   * older comes back through Top rated or through saved recipes. */
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

  /* A rating, 1 to 5. One per account per recipe: the newer one
   * remplace l'ancienne, parce qu'un parent qui refait la recipe peut
   * replaces the older. An account is required — otherwise nothing stops one
   * personne de voter cent fois. */
  "POST /api/rating": async function (req, res, ctx) {
    if (!ctx.account) return json(res, 401, { error: "connexion requise pour noter" });
    /* One rating per second per account.
     *
     * Authentication stops a stranger writing, not a signed-in client looping.
     * A rating is a human gesture; anything faster than once a second is a bug
     * or a script, and neither should reach the store. */
    if (!limiteDebit(ctx.account.email)) {
      return json(res, 429, { error: "trop de requetes" });
    }
    let corps;
    try { corps = JSON.parse((await rawBody(req)).toString("utf8")); }
    catch (e) { if (e.status === 413) throw e; return json(res, 400, { error: "JSON invalide" }); }

    const r = corps.rating === null
      ? Ratings.removeRating(corps.recipe, ctx.account.email)
      : Ratings.rate(corps.recipe, ctx.account.email, corps.rating);
    if (!r.ok) return json(res, 400, { error: r.reason });
    json(res, 200, { ok: true, aggregate: r.aggregate });
  },

  /* Aggregates for a list of recipes, with the account's own rating if it
   * une. On n'expose jamais les notes des autres, seulement le total. */
  "GET /api/ratings": function (req, res, ctx) {
    const ids = (ctx.url.searchParams.get("ids") || "").split(",").filter(Boolean);
    if (!ids.length) return json(res, 200, {});
    json(res, 200, Ratings.aggregates(ids, ctx.account ? ctx.account.email : null));
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
      if (!r) return;   /* batch not allowed: nothing leaks through */
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

  /* The iOS app sends its signed StoreKit transaction. It is verified in
   * full before anything is granted — the client is never
   * cru sur parole, pas plus qu'un navigateur. */
  "POST /api/apple/transaction": async function (req, res, ctx) {
    if (!ctx.account) return json(res, 401, { error: "connexion requise" });
    let corps;
    try { corps = JSON.parse((await rawBody(req)).toString("utf8")); }
    catch (e) { if (e.status === 413) throw e; return json(res, 400, { error: "JSON invalide" }); }
    const v = Apple.verifierJWS(corps.signedTransaction);
    if (!v.ok) return json(res, 400, { error: "transaction refusée", detail: v.reason });
    const etat = Apple.etatDepuisTransaction(v.charge);
    if (!etat.ok) return json(res, 400, { error: "transaction refusée", detail: etat.reason });

    const db = ctx.db;
    /* One Apple transaction cannot serve two accounts. */
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
   * Like the Stripe webhook, this is the source of truth, not the client. */
  "POST /api/webhook/apple": async function (req, res, ctx) {
    let corps;
    try { corps = JSON.parse((await rawBody(req)).toString("utf8")); }
    catch (e) { if (e.status === 413) throw e; return json(res, 400, { error: "JSON invalide" }); }
    const n = Apple.lireNotification(corps.signedPayload);
    if (!n.ok) return json(res, 400, { error: "notification refusée", detail: n.reason });
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

  /* Consultation d'un product par code-barres. Le serveur relaie Open Food
   * Facts, derives allergens WITH OUR catalogue, and keeps nothing.
   * The ODbL requires share-alike if that data is MERGED into
   * une base : on ne fusionne pas, on consulte. */
  /* Product lookup by barcode.
   *
   * A CASCADE, not a single call. Two things were missing and each one hid
   * products that are in the database:
   *
   *   1. The camera returns whatever form is printed — UPC-E, UPC-A, EAN-13,
   *      ITF-14. Open Food Facts indexes mostly EAN-13. A North American
   *      UPC-A is the same product with a leading zero: two keys, one
   *      barcode, and only one was ever tried.
   *
   *   2. world.openfoodfacts.org covers food only. Three sibling databases
   *      share the API and the licence — beauty, pet food, everything else.
   *      A toddler puts toothpaste and kibble in their mouth too.
   *
   * We relay, derive allergens with OUR catalogue, and keep nothing. The ODbL
   * requires share-alike when data is MERGED into a base; consulting is not
   * merging.
   */
  "GET /api/product": async function (req, res, ctx) {
    const brut = (ctx.url.searchParams.get("code") || "").replace(/[^0-9]/g, "");
    if (brut.length < 6 || brut.length > 14) {
      return json(res, 400, { error: "invalid barcode" });
    }

    const formes = Barcode.formes(brut);
    if (!formes.length) return json(res, 400, { error: "invalid barcode" });

    /* THE CACHE ANSWERS FIRST, FOR EVERYONE.
     *
     * Open Food Facts allows fifteen product reads a minute PER ADDRESS, and
     * this server is one address for every parent using the app. A product
     * already looked up costs nothing here; only a barcode nobody has scanned
     * before goes out. Misses are remembered too, briefly: a product added to
     * the database tomorrow must not stay invisible for a month. */
    /* Keyed on the canonical form — the longest, which is the thirteen-digit
     * one — so a UPC-A and its EAN-13 twin share one entry. `formes[0]` is
     * whatever was scanned, and the same product would have been cached
     * twice under two names. */
    const cle = formes.reduce(function (a, b) { return b.length > a.length ? b : a; }, formes[0]);
    const connu = ProductCache.get(cle);
    if (connu) {
      if (connu.hit) return json(res, 200, connu.payload);
      return json(res, 404, absent(brut, formes, "cache"));
    }

    /* THE BUDGET STOPS US BEFORE THE BAN DOES. Twelve a minute, under their
     * fifteen: when it is spent, the answer is "try again shortly", not eight
     * requests that will all be refused. */
    if (!OffBudget.take()) {
      return json(res, 503, {
        error: "product database unavailable",
        retryAfterSeconds: OffBudget.secondsUntilFree(),
        scanned: brut
      });
    }

    const champs = "product_name,product_name_fr,brands,ingredients_text_fr," +
                   "ingredients_text,allergens_tags,traces_tags,image_small_url";
    const entetes = {
      /* The fallback names a domain that resolves. The old one, ".example",
       * gave Open Food Facts no one to contact before blocking an address. */
      "User-Agent": process.env.OFF_USER_AGENT || "Bouchees/1.0 (https://bouchees.onrender.com)"
    };

    /* FOOD WITH BOTH FORMS, THEN ONE FORM PER SIBLING.
     *
     * The old cascade tried four databases times two forms, eight requests
     * on every miss — two misses in a minute crossed the limit on their own.
     * Food is where a grocery product lives; the siblings only need a look. */
    const plan = [];
    for (const forme of formes) plan.push({ hote: "world.openfoodfacts.org", genre: "food", forme: forme });
    for (const b of [["world.openbeautyfacts.org", "beauty"],
                     ["world.openpetfoodfacts.org", "petfood"],
                     ["world.openproductsfacts.org", "product"]]) {
      plan.push({ hote: b[0], genre: b[1], forme: formes[0] });
    }

    let indisponible = false;
    for (const etape of plan) {
      if (!OffBudget.take()) { indisponible = true; break; }
      let r;
      try {
        r = await fetch("https://" + etape.hote + "/api/v2/product/" + etape.forme +
                        "?fields=" + champs, { headers: entetes });
      } catch (e) { indisponible = true; continue; }

      /* "LIMITED" IS NOT "NOT FOUND". A refused request comes back as a
       * 429, a 503, or an HTML page. Parsing that as JSON used to throw into
       * the catch below and end as "product not found" — a ban and a
       * missing product were the same message. */
      const type = (r.headers.get("content-type") || "").toLowerCase();
      if (r.status === 429 || r.status >= 500 || type.indexOf("json") < 0) {
        indisponible = true;
        continue;
      }
      let d;
      try { d = await r.json(); } catch (e) { indisponible = true; continue; }
      if (!d || d.status !== 1 || !d.product) continue;

      const p = d.product;
      const payload = {
        code: etape.forme,
        scanned: brut,
        source: etape.genre,
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
      ProductCache.set(cle, { hit: true, payload: payload });
      return json(res, 200, payload);
    }

    /* A miss is only a miss when every database actually answered. If one
     * was refusing, say so rather than remember a "not found" that is not
     * known to be true. */
    if (indisponible) {
      return json(res, 503, {
        error: "product database unavailable",
        retryAfterSeconds: OffBudget.secondsUntilFree(),
        scanned: brut
      });
    }
    ProductCache.set(cle, { hit: false });
    json(res, 404, absent(brut, formes, "live"));
  },

  /* Connexion volontairement minimale : un email, un token. Pas de mot de
   * password to manage, so no password to leak. In production this token is
   * emailed instead of being returned here. */
  "POST /api/login": async function (req, res, ctx) {
    /* CLOSED UNTIL SIGN-IN IS REAL.
     *
     * This route hands a session token to any well-formed address, with no
     * proof that the caller owns it. The note below says the token is
     * emailed in production; the deployment on Render IS production, and the
     * token came back in the response. Anyone typing a subscriber's email
     * got their subscription.
     *
     * Until a magic link exists, the route answers 503. The environment
     * variable reopens it for local testing only, knowingly. */
    if (!ctx.insecureLogin) {
      return json(res, 503, { error: "sign-in is not available yet" });
    }
    let corps;
    try { corps = JSON.parse((await rawBody(req)).toString("utf8")); }
    catch (e) { if (e.status === 413) throw e; return json(res, 400, { error: "JSON invalide" }); }
    const email = normaliserCourriel(corps.email);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json(res, 400, { error: "email invalide" });
    const db = ctx.db;
    if (!db.accounts[email]) db.accounts[email] = { email: email, cree: new Date().toISOString(), subscription: null };
    const token = jetonNeuf();
    db.jetons[token] = { email: email, cree: Date.now() };
    writeAccounts(db);
    json(res, 200, { token: token, email: email, subscribed: subscriptionActive(db.accounts[email]),
                     note: "En production, ce token s'envoie par email — il ne revient pas dans la réponse." });
  },

  "POST /api/logout": async function (req, res, ctx) {
    const auth = (req.headers.authorization || "").replace(/^Bearer\s+/i, "").trim();
    if (auth && ctx.db.jetons[auth]) { delete ctx.db.jetons[auth]; writeAccounts(ctx.db); }
    json(res, 200, { ok: true });
  },

  /* Opens a checkout session. The secret key stays on the server;
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

  /* Stripe webhook: the only source of truth on subscription state. Never the
   * client. The signature is verified before anything is touched. */
  "POST /api/webhook/stripe": async function (req, res, ctx) {
    const brut = await rawBody(req);
    const sig = req.headers["stripe-signature"] || "";
    if (!SECRET_WEBHOOK) return json(res, 500, { error: "STRIPE_WEBHOOK_SECRET non configuré" });
    if (!verifierSignature(brut, sig, SECRET_WEBHOOK)) return json(res, 400, { error: "signature invalide" });

    let evt;
    try { evt = JSON.parse(brut.toString("utf8")); }
    catch (e) { if (e.status === 413) throw e; return json(res, 400, { error: "JSON invalide" }); }

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
 * caches on the device and prunes when a batch leaves the window. */
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
                ".json": "application/json; charset=utf-8", ".css": "text/css; charset=utf-8",
                ".webp": "image/webp", ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml" };

/* A minute of recent calls per key, nothing persisted.
 *
 * Deliberately in memory: a restart forgetting who wrote a second ago is the
 * correct behaviour, and a rate limiter that needs a database is a second
 * thing that can fail. */
const _debits = new Map();
function limiteDebit(cle, parMinute) {
  const max = parMinute || 60;
  const maintenant = Date.now();
  const vus = (_debits.get(cle) || []).filter(function (t) {
    return maintenant - t < 60000;
  });
  if (vus.length >= max) { _debits.set(cle, vus); return false; }
  vus.push(maintenant);
  _debits.set(cle, vus);
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

  /* Photos des recipes. Le name de fichier contient l'empreinte des
   * ingredients: an image never changes under the same name, so the cache
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
    const cle = req.method + " " + url.pathname;
    res.setHeader("X-Content-Type-Options", "nosniff");
    if (req.method === "OPTIONS") { res.writeHead(204); return res.end(); }
    const route = routes[cle];
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

module.exports = { createServer: createServer, allowedBatches: allowedBatches,
                   subscriptionActive: subscriptionActive, routes: routes,
                   /* Exposed for the tests only. */
                   _ProductCache: ProductCache, _OffBudget: OffBudget,
                   _MAX_BODY: MAX_BODY, _TOKEN_TTL_MS: TOKEN_TTL_MS };
