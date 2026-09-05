/* It is NOT trusted: the signature is verified, the certificate chain is
 * walked up to the pinned Apple root, and only then is the entitlement
 * granted. Same rule as Stripe — the server decides, never the client. */
"use strict";
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

/* SHA-256 fingerprint of the expected Apple root. A mismatch refuses
 * everything, which blocks a substituted root. Empty disables pinning;
 * the chain is still checked. */
const EMPREINTE_RACINE = process.env.APPLE_ROOT_SHA256 || "";

function base64urlVersBuffer(s) {
  return Buffer.from(String(s).replace(/-/g, "+").replace(/_/g, "/"), "base64");
}
function lireJSONb64(s) {
  return JSON.parse(base64urlVersBuffer(s).toString("utf8"));
}

/* La signature ES256 d'un JWS est en format raw (r||s, 64 octets).
 * Node attend du DER : on convertit. */
function bruteVersDER(sig) {
  if (sig.length !== 64) return null;
  const entier = function (b) {
    let i = 0;
    while (i < b.length - 1 && b[i] === 0) i++;
    let v = b.slice(i);
    if (v[0] & 0x80) v = Buffer.concat([Buffer.from([0]), v]);
    return Buffer.concat([Buffer.from([0x02, v.length]), v]);
  };
  const r = entier(sig.slice(0, 32));
  const s = entier(sig.slice(32));
  const body = Buffer.concat([r, s]);
  return Buffer.concat([Buffer.from([0x30, body.length]), body]);
}

function certDepuisB64(b64) {
  const pem = "-----BEGIN CERTIFICATE-----\n" +
    String(b64).replace(/(.{64})/g, "$1\n").replace(/\n$/, "") +
    "\n-----END CERTIFICATE-----\n";
  return new crypto.X509Certificate(pem);
}

function empreinteCert(cert) {
  return crypto.createHash("sha256").update(cert.raw).digest("hex");
}

function chargerRacine(cheminRacine) {
  const p = cheminRacine || process.env.APPLE_ROOT_CER || path.join(__dirname, "AppleRootCA-G3.cer");
  if (!fs.existsSync(p)) return null;
  const raw = fs.readFileSync(p);
  const txt = raw.toString("utf8");
  return new crypto.X509Certificate(txt.indexOf("-----BEGIN") !== -1 ? txt : raw);
}

/* Verifies the x5c chain: leaf -> intermediate(s) -> expected root. Each
 * certificate must be signed by the next, and all must be valid today. */
function verifierChaine(x5c, racine, maintenant) {
  if (!Array.isArray(x5c) || x5c.length < 2) return { ok: false, reason: "chaîne x5c absente ou trop courte" };
  let certs;
  try { certs = x5c.map(certDepuisB64); }
  catch (e) { return { ok: false, reason: "certificat illisible : " + e.message }; }

  const now = maintenant || new Date();
  for (const c of certs) {
    if (new Date(c.validFrom) > now || new Date(c.validTo) < now)
      return { ok: false, reason: "certificat hors de sa période de validité" };
  }
  for (let i = 0; i < certs.length - 1; i++) {
    if (!certs[i].verify(certs[i + 1].publicKey))
      return { ok: false, reason: "maillon " + i + " non signé par le suivant" };
  }
  const sommet = certs[certs.length - 1];
  if (!racine) return { ok: false, reason: "racine Apple absente — impossible de vérifier (refuse out of caution)" };
  if (empreinteCert(sommet) !== empreinteCert(racine)) {
    if (!sommet.verify(racine.publicKey))
      return { ok: false, reason: "la chaîne ne remonte pas à la racine fournie" };
  }
  if (EMPREINTE_RACINE && empreinteCert(racine) !== EMPREINTE_RACINE.toLowerCase())
    return { ok: false, reason: "la racine fournie ne correspond pas à l'empreinte épinglée" };
  return { ok: true, feuille: certs[0] };
}

/* Verifies a JWS signed by Apple and returns its payload. */
function verifierJWS(jws, options) {
  options = options || {};
  const parties = String(jws || "").split(".");
  if (parties.length !== 3) return { ok: false, reason: "JWS mal formé" };

  let entete;
  try { entete = lireJSONb64(parties[0]); }
  catch (e) { return { ok: false, reason: "entête illisible" }; }
  if (entete.alg !== "ES256") return { ok: false, reason: "algorithme refusé : " + entete.alg };

  const racine = options.racine !== undefined ? options.racine : chargerRacine(options.cheminRacine);
  const chain = verifierChaine(entete.x5c, racine, options.maintenant);
  if (!chain.ok) return { ok: false, reason: chain.reason };

  const der = bruteVersDER(base64urlVersBuffer(parties[2]));
  if (!der) return { ok: false, reason: "signature de taille inattendue" };
  const valide = crypto.createVerify("SHA256")
    .update(parties[0] + "." + parties[1])
    .verify(chain.feuille.publicKey, der);
  if (!valide) return { ok: false, reason: "signature invalide" };

  let charge;
  try { charge = lireJSONb64(parties[1]); }
  catch (e) { return { ok: false, reason: "charge utile illisible" }; }
  return { ok: true, charge: charge };
}

/* Translates a verified StoreKit transaction into subscription state. Same
 * statuses as Stripe: the rest of the server sees no difference. */
function etatDepuisTransaction(charge, options) {
  options = options || {};
  const expected = options.bundleId || process.env.APPLE_BUNDLE_ID;
  if (expected && charge.bundleId && charge.bundleId !== expected)
    return { ok: false, reason: "bundleId inattendu : " + charge.bundleId };
  const produits = options.produits || (process.env.APPLE_PRODUITS || "").split(",").filter(Boolean);
  if (produits.length && charge.productId && produits.indexOf(charge.productId) === -1)
    return { ok: false, reason: "produit inconnu : " + charge.productId };

  const now = options.maintenant ? options.maintenant.getTime() : Date.now();
  const finish = charge.expiresDate || null;
  const revoque = !!charge.revocationDate;
  let status;
  if (revoque) status = "annule";
  else if (!finish) status = "actif";                       /* achat non renouvelable */
  else if (finish > now) status = "actif";
  else status = "annule";

  return {
    ok: true,
    status: status,
    periodEnd: finish ? new Date(finish).toISOString() : null,
    produit: charge.productId || null,
    transaction: charge.originalTransactionId || charge.transactionId || null,
    environnement: charge.environment || null
  };
}

/* Notifications V2 : Apple pousse les changements d'subscription.
 * signedPayload -> signedTransactionInfo/signedRenewalInfo, each signed. */
function lireNotification(signedPayload, options) {
  const ext = verifierJWS(signedPayload, options);
  if (!ext.ok) return { ok: false, reason: ext.reason };
  const d = ext.charge.data || {};
  const tx = d.signedTransactionInfo ? verifierJWS(d.signedTransactionInfo, options) : null;
  if (d.signedTransactionInfo && (!tx || !tx.ok))
    return { ok: false, reason: "transaction imbriquée invalide : " + (tx && tx.reason) };

  const type = ext.charge.notificationType;
  const sousType = ext.charge.subtype;
  const base = tx ? etatDepuisTransaction(tx.charge, options) : { ok: true, status: null };
  if (!base.ok) return { ok: false, reason: base.reason };

  /* Le type de notification prime sur la date d'expiration : un remboursement
   * cuts access immediately; a failed payment lets the grace period run. */
  const carte = {
    SUBSCRIBED: "actif", DID_RENEW: "actif", OFFER_REDEEMED: "actif",
    DID_CHANGE_RENEWAL_STATUS: base.status || "actif",
    DID_FAIL_TO_RENEW: "en_retard", GRACE_PERIOD_EXPIRED: "annule",
    EXPIRED: "annule", REFUND: "annule", REVOKE: "annule",
    DID_CHANGE_RENEWAL_PREF: base.status || "actif"
  };
  if (!(type in carte)) return { ok: true, ignore: type };
  return {
    ok: true, type: type, sousType: sousType || null,
    status: carte[type], periodEnd: base.periodEnd,
    produit: base.produit, transaction: base.transaction,
    environnement: ext.charge.data && ext.charge.data.environment || base.environnement
  };
}

module.exports = {
  verifierJWS: verifierJWS, verifierChaine: verifierChaine, chargerRacine: chargerRacine,
  etatDepuisTransaction: etatDepuisTransaction, lireNotification: lireNotification,
  empreinteCert: empreinteCert, bruteVersDER: bruteVersDER
};
