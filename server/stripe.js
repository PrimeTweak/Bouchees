/* Stripe — bloc F Signature verification and event reading: no key is written
 * here. */
"use strict";
const crypto = require("crypto");

const TOLERANCE = 300; /* seconds: a signature older than 5 minutes is refused */

/* Header format: t=1719000000,v1=abcdef...
 * On recalcule le HMAC de « t.body » et on compare en temps constant. */
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

  const expected = crypto.createHmac("sha256", secret)
    .update(parties.t + "." + Buffer.from(corpsBrut).toString("utf8"))
    .digest("hex");
  const ab = Buffer.from(expected, "utf8");
  return parties.v1.some(function (v) {
    const vb = Buffer.from(v, "utf8");
    return vb.length === ab.length && crypto.timingSafeEqual(vb, ab);
  });
}

/* Translates a Stripe event into an account update, or null when the event is
 * none of our business. Only the subscription lifecycle matters here. */
function evenementPertinent(evt) {
  if (!evt || !evt.type || !evt.data || !evt.data.object) return null;
  const o = evt.data.object;

  const email = o.customer_email || o.customer_details && o.customer_details.email ||
                   o.metadata && o.metadata.email || null;
  const finish = o.current_period_end ? new Date(o.current_period_end * 1000).toISOString() : null;

  switch (evt.type) {
    case "checkout.session.completed":
      if (!email) return null;
      return { email: email, status: "actif", periodEnd: finish, client: o.customer || null };

    case "customer.subscription.created":
    case "customer.subscription.updated": {
      if (!email) return null;
      const carte = { active: "actif", trialing: "actif", past_due: "en_retard",
                      unpaid: "en_retard", canceled: "annule", incomplete_expired: "annule" };
      return { email: email, status: carte[o.status] || "annule",
               periodEnd: finish, client: o.customer || null };
    }

    case "customer.subscription.deleted":
      if (!email) return null;
      return { email: email, status: "annule", periodEnd: finish, client: o.customer || null };

    case "invoice.payment_failed":
      if (!email) return null;
      return { email: email, status: "en_retard", periodEnd: finish, client: o.customer || null };

    default:
      return null;
  }
}

/* Creates a checkout session. Needs the network and a secret key — runs on
 * your machine or your host, never in the browser. */
async function creerSession(options) {
  const key = process.env.STRIPE_CLE_SECRETE;
  if (!key) throw new Error("STRIPE_CLE_SECRETE absente");
  const body = new URLSearchParams({
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
    headers: { Authorization: "Bearer " + key, "Content-Type": "application/x-www-form-urlencoded" },
    body: body
  });
  const data = await rep.json();
  if (!rep.ok) throw new Error(data.error && data.error.message || "Stripe a refusé la requête");
  return data;
}

module.exports = { verifierSignature: verifierSignature, evenementPertinent: evenementPertinent,
                   creerSession: creerSession, TOLERANCE: TOLERANCE };
