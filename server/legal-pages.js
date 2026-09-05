/* If the behaviour changes, these pages change the same day — a policy that
 * lies is pire que pas de politique. Legal pages — served by the server */
"use strict";

/* The contact address is configuration, not text: the placeholder shipped
 * for weeks. BOUCHEES_CONTACT on Render, or the fallback below. */
const CONTACT = process.env.BOUCHEES_CONTACT || "bonjour@bouchees.ca";
const RESPONSABLE = process.env.BOUCHEES_PRIVACY_OFFICER || "le fondateur de Bouchées";

const GABARIT = (titre, body, lang) => `<!DOCTYPE html>
<html lang="${lang || "en"}">
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
${body}
<footer>
  Bouchées · <a href="/terms">Terms of Use</a> ·
  <a href="/privacy">Privacy Policy</a>
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
<p>Refunds for purchases made through the App Store are handled by Apple under
Apple's own refund terms; request one from your Apple account or at
reportaproblem.apple.com.</p>

<h2>Governing law</h2>
<p>These terms are governed by the laws of the province of Québec and the
federal laws of Canada applicable therein. The French version of these terms
is available at <a href="/fr/terms">/fr/terms</a>.</p>

<h2>Availability</h2>
<p>We may change, suspend or discontinue any part of the service. Content already
downloaded to your device remains usable offline.</p>

<h2>Liability</h2>
<p>Bouchées is provided as is. To the extent permitted by law, we are not liable
for indirect or consequential damages arising from use of the app. Nothing here
limits liability that cannot be limited by law.</p>

<h2>Contact</h2>
<p>Questions about these terms: <a href="mailto:${CONTACT}">${CONTACT}</a></p>
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
<p>Most scans are answered on your device, from a product pack downloaded once
after installation. Nothing leaves the phone for those, and the scanner works
without a signal. When a barcode is not in the pack, it is sent to our server,
which forwards it to Open Food Facts and returns the result. That lookup is not
stored and is not linked to your account.</p>

<h2>Where product data comes from</h2>
<p>American products come from
<a href="https://fdc.nal.usda.gov">USDA FoodData Central</a>, Branded Foods.
That data is in the public domain under CC0 1.0. Suggested citation: U.S.
Department of Agriculture, Agricultural Research Service, FoodData Central.</p>
<p>Canadian products contain information from
<a href="https://world.openfoodfacts.org">Open Food Facts</a>, which is made
available here under the
<a href="https://opendatacommons.org/licenses/odbl/1-0/">Open Database License
(ODbL)</a>. That Canadian set is kept as a separate file and is available on
request under the same licence.</p>
<p>The two sets are never joined to each other, and neither is merged into our
own ingredient and substitution tables. Allergens are worked out from the
printed ingredient list by our own catalogue, at the moment you scan. A
database's own allergen tags are treated as indicative only, never as the
answer.</p>

<h2>Children</h2>
<p>Bouchées is intended for parents and caregivers, not for children. We do not
knowingly collect personal information from anyone under 13. Information about a
child that a parent enters into the app stays on that parent's device.</p>

<h2>Where data is held</h2>
<p>Account records are stored on our server. We keep them as long as your account
exists, and delete them on request.</p>
<p>Product information comes from Open Food Facts under the Open Database
Licence (ODbL). The subset we keep to answer scans faster is available under the
same licence on request.</p>

<h2>Person in charge of personal information</h2>
<p>Under Québec's Act respecting the protection of personal information in the
private sector (Law 25), the person in charge of personal information is
${RESPONSABLE}, reachable at <a href="mailto:${CONTACT}">${CONTACT}</a>. The
French version of this policy is available at <a href="/fr/privacy">/fr/privacy</a>.</p>

<h2>Your rights</h2>
<p>You may ask for a copy of your account data or ask us to delete it entirely.
Deleting the app removes every profile from your device permanently — we have no
copy to restore. Write to
<a href="mailto:confidentialite@bouchees.example">confidentialite@bouchees.example</a>.</p>

<h2>Changes</h2>
<p>If this policy changes, the date at the top changes with it. Material changes
will be announced in the app.</p>
`);


const CONDITIONS_FR = GABARIT("Conditions d'utilisation", `
<h1>Conditions d'utilisation</h1>
<p class="maj">Dernière mise à jour : ${MAJ}</p>

<div class="avis">
  <strong>Bouchées n'est pas un avis médical.</strong> Les substitutions d'ingrédients et
  les repères par âge proviennent de tables déterministes conçues comme point de
  départ. Ce n'est ni un diagnostic, ni un traitement, ni un substitut à un
  professionnel. Si votre enfant a une allergie alimentaire diagnostiquée, le plan
  de votre allergologue a toujours préséance sur ce que l'application vous montre.
</div>

<h2>Ce que fait l'application</h2>
<p>Bouchées adapte des recettes aux allergies alimentaires et à l'âge d'un enfant.
Elle retire les allergènes évités, propose des remplacements et signale les
repères de préparation liés à l'âge. Chaque décision vient de tables versionnées,
pas d'un modèle de langage.</p>

<h2>Ce que vous devez toujours faire</h2>
<ul>
  <li><strong>Lire les étiquettes.</strong> Les formulations des produits changent sans
      préavis. Quand l'application ne peut pas identifier un ingrédient, elle le dit
      au lieu de deviner — prenez-le comme un signal de vérifier vous-même.</li>
  <li><strong>Introduire les nouveaux aliments</strong> comme votre professionnel l'a
      conseillé. L'application ne connaît pas l'historique de votre enfant.</li>
  <li><strong>Surveiller les repas.</strong> Les repères sur l'étouffement sont
      généraux ; chaque enfant est différent.</li>
</ul>

<h2>Limites du contenu des recettes</h2>
<p>Les recettes peuvent être rédigées avec l'aide d'outils automatisés et relues
avant publication. Certaines n'ont pas été cuisinées en cuisine d'essai. Une
recette peut donc décevoir — les règles de sécurité (allergènes, limites d'âge)
sont déterministes et testées, mais le goût, la levée et la texture ne sont pas
garantis.</p>

<h2>Lecture de produits</h2>
<p>Le lecteur de codes-barres consulte les données de
<a href="https://world.openfoodfacts.org">Open Food Facts</a>, une base ouverte
maintenue par des contributeurs. Ces données peuvent être incomplètes ou
périmées. Bouchées recalcule les allergènes à partir de la liste d'ingrédients
plutôt que de se fier aux étiquettes d'allergènes de la base, mais ne peut pas
garantir l'exactitude de la liste elle-même. L'étiquette sur l'emballage fait
toujours autorité.</p>

<h2>Abonnement</h2>
<p>Le moteur, les tables de substitution, les repères par âge, le lecteur et les
recettes de départ sont gratuits et le restent. Un abonnement payant ajoute un
lot mensuel de nouvelles recettes. Sur iOS, les abonnements sont gérés par
Apple ; ils se renouvellent automatiquement sauf annulation au moins 24 heures
avant la fin de la période, et se gèrent dans les réglages de votre compte
Apple.</p>
<p>Les remboursements d'achats faits sur l'App Store sont traités par Apple selon
ses propres conditions ; demandez-les depuis votre compte Apple ou sur
reportaproblem.apple.com.</p>

<h2>Droit applicable</h2>
<p>Les présentes conditions sont régies par les lois de la province de Québec et
les lois fédérales du Canada qui s'y appliquent. En cas de divergence entre les
versions, la version française prévaut pour les consommateurs du Québec.</p>

<h2>Disponibilité</h2>
<p>Nous pouvons modifier, suspendre ou cesser toute partie du service. Le contenu
déjà téléchargé sur votre appareil reste utilisable hors ligne.</p>

<h2>Responsabilité</h2>
<p>Bouchées est fournie telle quelle. Dans la mesure permise par la loi, nous ne
sommes pas responsables des dommages indirects ou consécutifs découlant de
l'utilisation de l'application. Rien ici ne limite une responsabilité qui ne peut
l'être en vertu de la loi.</p>

<h2>Contact</h2>
<p>Questions sur ces conditions : <a href="mailto:${CONTACT}">${CONTACT}</a></p>
`, "fr");

const CONFIDENTIALITE_FR = GABARIT("Politique de confidentialité", `
<h1>Politique de confidentialité</h1>
<p class="maj">Dernière mise à jour : ${MAJ}</p>

<div class="avis">
  <strong>Les profils de vos enfants ne quittent jamais votre appareil.</strong> Le
  prénom, l'âge et les allergènes évités sont conservés dans le conteneur de
  l'application, sur votre téléphone. Aucune route du serveur ne les reçoit. Ce
  n'est pas une promesse d'intention — c'est ainsi que le code est écrit, et c'est
  ce que nous déclarons dans les étiquettes de confidentialité de l'App Store.
</div>

<h2>Ce que nous recueillons</h2>
<ul>
  <li><strong>Adresse courriel</strong> — seulement si vous créez un compte, et
      seulement pour retrouver votre abonnement sur vos appareils.</li>
  <li><strong>Identifiant d'achat</strong> — fourni par Apple, utilisé pour vérifier
      qu'un abonnement est actif.</li>
</ul>

<h2>Ce que nous ne recueillons pas</h2>
<ul>
  <li>Le prénom, l'âge ou les allergènes de vos enfants</li>
  <li>Votre position, vos contacts, vos photos ou vos dossiers de santé</li>
  <li>Des données d'analyse, des identifiants publicitaires ou un suivi comportemental</li>
  <li>Les produits que vous lisez — les recherches par code-barres ne sont pas
      journalisées avec votre compte</li>
</ul>

<h2>Lecture de codes-barres</h2>
<p>La plupart des lectures sont résolues sur votre appareil, à partir d'un
ensemble de produits téléchargé une fois après l'installation. Rien ne quitte le
téléphone pour celles-là, et le lecteur fonctionne sans réseau. Quand un
code-barres n'est pas dans l'ensemble, il est envoyé à notre serveur, qui le
transmet à Open Food Facts et renvoie le résultat. Cette recherche n'est pas
conservée et n'est pas liée à votre compte.</p>

<h2>Provenance des données de produits</h2>
<p>Les produits américains proviennent de
<a href="https://fdc.nal.usda.gov/">USDA FoodData Central, Branded Foods</a>.
Ces données sont dans le domaine public (CC0 1.0). Citation suggérée : U.S.
Department of Agriculture, Agricultural Research Service, FoodData Central.</p>
<p>Les produits canadiens contiennent des informations d'
<a href="https://world.openfoodfacts.org">Open Food Facts</a>, mises à disposition
ici sous la <a href="https://opendatacommons.org/licenses/odbl/1-0/">licence Open
Database (ODbL)</a>. Cet ensemble canadien est conservé dans un fichier distinct et
est disponible sur demande sous la même licence.</p>
<p>Les deux ensembles ne sont jamais joints, et aucun n'est fusionné à nos propres
tables d'ingrédients et de substitutions. Les allergènes sont déduits de la liste
d'ingrédients imprimée par notre propre catalogue, au moment de la lecture. Les
étiquettes d'allergènes d'une base sont traitées comme indicatives, jamais comme
la réponse.</p>

<h2>Enfants</h2>
<p>Bouchées s'adresse aux parents et aux personnes qui prennent soin d'enfants,
pas aux enfants. Nous ne recueillons sciemment aucun renseignement personnel de
personnes de moins de 13 ans. Les informations qu'un parent entre au sujet d'un
enfant restent sur l'appareil de ce parent.</p>

<h2>Où sont conservées les données</h2>
<p>Les dossiers de compte sont conservés sur notre serveur. Nous les gardons tant
que votre compte existe, et les supprimons sur demande.</p>
<p>Les informations de produits proviennent d'Open Food Facts sous licence ODbL.
Le sous-ensemble que nous conservons pour répondre plus vite aux lectures est
disponible sous la même licence sur demande.</p>

<h2>Responsable de la protection des renseignements personnels</h2>
<p>En vertu de la Loi sur la protection des renseignements personnels dans le
secteur privé (Loi 25), la personne responsable de la protection des
renseignements personnels est ${RESPONSABLE}, joignable à
<a href="mailto:${CONTACT}">${CONTACT}</a>.</p>

<h2>Vos droits</h2>
<p>Vous pouvez demander une copie des données de votre compte ou demander leur
suppression complète. Vous pouvez retirer votre consentement en tout temps en
supprimant votre compte. Écrivez à <a href="mailto:${CONTACT}">${CONTACT}</a> ;
nous répondons dans les 30 jours prévus par la loi.</p>

<h2>Modifications</h2>
<p>Si cette politique change, la date en haut de page est mise à jour et
l'application vous en informe au prochain lancement.</p>
`, "fr");

module.exports = { CONDITIONS, CONFIDENTIALITE, CONDITIONS_FR, CONFIDENTIALITE_FR };
