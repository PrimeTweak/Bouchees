/* Pages légales — servies par le serveur
 *
 * Apple exige des URL publiques et fonctionnelles pour les conditions et la
 * confidentialité. Un lien mort fait rejeter la soumission.
 *
 * Ces textes décrivent ce que le code fait RÉELLEMENT. Si le comportement
 * change, ces pages doivent changer le même jour — une politique qui ment est
 * pire que pas de politique.
 *
 * ⚠️ Je ne suis pas avocat. Ces textes sont un point de départ honnête et
 * complet, à faire relire avant une vraie mise en marché — surtout pour la
 * partie qui touche aux données d'enfants (Loi 25 au Québec, RGPD si tu
 * dépasses la frontière).
 */
"use strict";

const GABARIT = (titre, corps) => `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${titre} — Bouchées</title>
<style>
  :root { color-scheme: light dark; }
  body {
    font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    max-width: 44rem; margin: 0 auto; padding: 2.5rem 1.25rem 5rem;
    color: #1B211B; background: #F1F3EC;
  }
  @media (prefers-color-scheme: dark) { body { color: #EDEFE8; background: #14180F; } }
  h1 { font-size: 1.9rem; letter-spacing: -0.02em; margin-bottom: .25rem; }
  h2 { font-size: 1.15rem; margin-top: 2.2rem; }
  .maj { color: #7A3557; font-weight: 600; font-size: .9rem; }
  .encadre {
    background: rgba(122,53,87,.09); border-radius: 14px;
    padding: 1rem 1.15rem; margin: 1.5rem 0;
  }
  ul { padding-left: 1.15rem; }
  li { margin: .4rem 0; }
  a { color: #7A3557; }
  footer { margin-top: 3rem; font-size: .85rem; opacity: .7; }
</style>
</head>
<body>
${corps}
<footer>
  Bouchées · <a href="/conditions">Terms of Use</a> ·
  <a href="/confidentialite">Privacy Policy</a>
</footer>
</body>
</html>`;

const MAJ = "August 2026";

const CONDITIONS = GABARIT("Terms of Use", `
<h1>Terms of Use</h1>
<p class="maj">Last updated: ${MAJ}</p>

<div class="encadre">
  <strong>Bouchées is not medical advice.</strong> Ingredient swaps and age
  guidance come from deterministic tables built as a starting point. They are
  not a diagnosis, a treatment, or a substitute for a professional. If your
  child has a diagnosed food allergy, your allergist's plan always takes
  precedence over anything this app shows you.
</div>

<h2>What the app does</h2>
<p>Bouchées adapts recipes to a child's food allergies and age. It removes
avoided allergens, proposes replacements, and flags age-related preparation
guidance. Every decision comes from versioned tables, not from a language
model.</p>

<h2>What you must still do</h2>
<ul>
  <li><strong>Read labels.</strong> Product formulations change without notice.
      When the app cannot identify an ingredient, it says so rather than
      guessing — treat that as a signal to check yourself.</li>
  <li><strong>Introduce new foods as your professional advised.</strong> The app
      does not know your child's history.</li>
  <li><strong>Supervise eating.</strong> Choking guidance in the app is general;
      children differ.</li>
</ul>

<h2>Limits of the recipe content</h2>
<p>Recipes may be drafted with the help of automated tools and reviewed before
publication. Some have not been cooked in a test kitchen. A recipe may
therefore turn out poorly — the safety rules (allergens, age limits) are
deterministic and tested, but taste, rise and texture are not guaranteed.</p>

<h2>Product scanning</h2>
<p>The barcode scanner looks up product data from
<a href="https://world.openfoodfacts.org">Open Food Facts</a>, an open database
maintained by contributors. That data may be incomplete or out of date. Bouchées
re-derives allergens from the ingredient list rather than trusting the database's
own allergen tags, but it cannot guarantee the list itself is accurate. The
label on the package is always the authority.</p>

<h2>Subscription</h2>
<p>The engine, the swap tables, the age guidance, the scanner and the starter
recipes are free and stay free. A paid subscription adds a monthly batch of new
recipes. On iOS, subscriptions are handled by Apple; they renew automatically
unless cancelled at least 24 hours before the end of the period, and are managed
in your Apple account settings.</p>

<h2>Availability</h2>
<p>We may change, suspend or discontinue any part of the service. Content already
downloaded to your device remains usable offline.</p>

<h2>Liability</h2>
<p>Bouchées is provided as is. To the extent permitted by law, we are not liable
for indirect or consequential damages arising from use of the app. Nothing here
limits liability that cannot be limited by law.</p>

<h2>Contact</h2>
<p>Questions about these terms: <a href="mailto:contact@bouchees.example">contact@bouchees.example</a></p>
`);

const CONFIDENTIALITE = GABARIT("Privacy Policy", `
<h1>Privacy Policy</h1>
<p class="maj">Last updated: ${MAJ}</p>

<div class="encadre">
  <strong>Your children's profiles never leave your device.</strong> First name,
  age and avoided allergens are stored in the app's own container on your phone.
  No server route receives them. This is not a promise about intent — it is how
  the code is written, and it is what we declare in the App Store privacy labels.
</div>

<h2>What we collect</h2>
<ul>
  <li><strong>Email address</strong> — only if you create an account, and only to
      find your subscription across your devices.</li>
  <li><strong>Purchase identifier</strong> — provided by Apple, used to verify
      that a subscription is active.</li>
</ul>

<h2>What we do not collect</h2>
<ul>
  <li>Your children's names, ages, or allergens</li>
  <li>Location, contacts, photos, or health records</li>
  <li>Analytics, advertising identifiers, or behavioural tracking</li>
  <li>The products you scan — barcode lookups are not logged against your account</li>
</ul>

<h2>Barcode scanning</h2>
<p>When you scan a product, the barcode is sent to our server, which forwards it
to Open Food Facts and returns the result. The lookup is not stored and is not
linked to your account. Product data is used under the
<a href="https://opendatacommons.org/licenses/odbl/1-0/">ODbL licence</a> and is
never merged into our own database.</p>

<h2>Children</h2>
<p>Bouchées is intended for parents and caregivers, not for children. We do not
knowingly collect personal information from anyone under 13. Information about a
child that a parent enters into the app stays on that parent's device.</p>

<h2>Where data is held</h2>
<p>Account records are stored on our server. We keep them as long as your account
exists, and delete them on request.</p>

<h2>Your rights</h2>
<p>You may ask for a copy of your account data or ask us to delete it entirely.
Deleting the app removes every profile from your device permanently — we have no
copy to restore. Write to
<a href="mailto:confidentialite@bouchees.example">confidentialite@bouchees.example</a>.</p>

<h2>Changes</h2>
<p>If this policy changes, the date at the top changes with it. Material changes
will be announced in the app.</p>
`);

module.exports = { CONDITIONS, CONFIDENTIALITE };
