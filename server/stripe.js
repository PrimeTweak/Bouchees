/* Stripe — bloc F
 * Vérification de signature et lecture des événements. Node pur.
 *
 * Aucune clé n'est écrite ici. Elles se passent par variables
 * d'environnement, jamais dans le dépôt :
 *   STRIPE_WEBHOOK_SECRET   (whsec_…)  — pour vérifier les webhooks
 *   STRIPE_CLE_SECRETE      (sk_…)     — pour créer une session de paiement
 */
"use strict";
const crypto = require("crypto");

const TOLERANCE = 300; /* secondes : une signature vieille de 5 min est refusée */

/* Format de l'entête : t=1719000000,v1=abcdef…
 * On recalcule le HMAC de « t.corps » et on compare en temps constant. */
function verifierSignature(corpsBrut, entete, secret, maintenant) {
  if (!entete || !secret) return false;
  const parties = {};
  String(entete).split(",").forEach(function (p) {
    const i = p.indexOf("=");
    if (i === -1) return;
    const k = p.slice(0, i).trim(), v = p.slice(i + 1).trim();
    if (k === "v1") (parties.v1 = parties.v1 || []).push(v);
    else parties[k] = v;
  });
  if (!parties.t || !parties.v1) return false;

  const t = parseInt(parties.t, 10);
  if (!Number.isFinite(t)) return false;
  const now = maintenant || Math.floor(Date.now() / 1000);
  if (Math.abs(now - t) > TOLERANCE) return false;

  const attendu = crypto.createHmac("sha256", secret)
    .update(parties.t + "." + Buffer.from(corpsBrut).toString("utf8"))
    .digest("hex");
  const ab = Buffer.from(attendu, "utf8");
  return parties.v1.some(function (v) {
    const vb = Buffer.from(v, "utf8");
    return vb.length === ab.length && crypto.timingSafeEqual(vb, ab);
  });
}

/* Traduit un événement Stripe en mise à jour de account, ou null si l'événement
 * ne nous concerne pas. On ne s'intéresse qu'au cycle de vie de l'subscription. */
function evenementPertinent(evt) {
  if (!evt || !evt.type || !evt.data || !evt.data.object) return null;
  const o = evt.data.object;

  const email = o.customer_email || o.customer_details && o.customer_details.email ||
                   o.metadata && o.metadata.email || null;
  const fin = o.current_period_end ? new Date(o.current_period_end * 1000).toISOString() : null;

  switch (evt.type) {
    case "checkout.session.completed":
      if (!email) return null;
      return { email: email, status: "actif", periodEnd: fin, client: o.customer || null };

    case "customer.subscription.created":
    case "customer.subscription.updated": {
      if (!email) return null;
      const carte = { active: "actif", trialing: "actif", past_due: "en_retard",
                      unpaid: "en_retard", canceled: "annule", incomplete_expired: "annule" };
      return { email: email, status: carte[o.status] || "annule",
               periodEnd: fin, client: o.customer || null };
    }

    case "customer.subscription.deleted":
      if (!email) return null;
      return { email: email, status: "annule", periodEnd: fin, client: o.customer || null };

    case "invoice.payment_failed":
      if (!email) return null;
      return { email: email, status: "en_retard", periodEnd: fin, client: o.customer || null };

    default:
      return null;
  }
}

/* Création d'une session de paiement. Nécessite le réseau et une clé secrète —
 * s'exécute sur ta machine ou ton hébergeur, jamais dans le navigateur. */
async function creerSession(options) {
  const cle = process.env.STRIPE_CLE_SECRETE;
  if (!cle) throw new Error("STRIPE_CLE_SECRETE absente");
  const corps = new URLSearchParams({
    mode: "subscription",
    "line_items[0][price]": options.prix,
    "line_items[0][quantity]": "1",
    customer_email: options.email,
    "metadata[email]": options.email,
    "subscription_data[metadata][email]": options.email,
    success_url: options.retourOk,
    cancel_url: options.retourAnnule
  });
  const rep = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: { Authorization: "Bearer " + cle, "Content-Type": "application/x-www-form-urlencoded" },
    body: corps
  });
  const data = await rep.json();
  if (!rep.ok) throw new Error(data.error && data.error.message || "Stripe a refusé la requête");
  return data;
}

module.exports = { verifierSignature: verifierSignature, evenementPertinent: evenementPertinent,
                   creerSession: creerSession, TOLERANCE: TOLERANCE };
