/* Importeur — lot 3, v0.2
 * node ingest/importer.js
 * Sources → adaptateur → normalisation → PORTES DE SÉCURITÉ → recettes canoniques.
 *
 * Deux portes, non négociables :
 *   1. Reconnaissance totale : une seule ligne d'ingrédient inconnue et la
 *      recette entière part en quarantine. On ne devine jamais un ingrédient
 *      dans une app d'allergies.
 *   2. Curation humaine : sans entrée dans curation.json (âge minimal validé,
 *      rôles confirmés, étapes en français), pas d'import — même si tout est
 *      recognized. Le pipeline propose, l'humain dispose.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const adaptateurs = require("./adapters.js");
const { normalizeLine, construireIndex } = require("./normalizer.js");

const racine = path.join(__dirname, "..");
const UNITES_FR = { clove: "gousse", cloves: "gousses", fillet: "filet", fillets: "filets", can: "boîte", cans: "boîtes", slice: "tranche", slices: "tranches" };
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));

function importAll(options) {
  options = options || {};
  const catalogue = options.catalogue || lire("data/ingredients.json");
  const lexique = options.lexique || lire("ingest/lexicon.json");
  const curation = options.curation || lire("ingest/curation.json");
  const dossierSources = options.dossierSources || path.join(racine, "ingest", "sources");
  const idsReserves = new Set((options.idsReserves || lire("data/recipes.json").map((r) => r.id)));
  const index = construireIndex(lexique);

  const imported = [];
  const quarantine = [];

  fs.readdirSync(dossierSources).filter((f) => f.endsWith(".json")).sort().forEach(function (fichier) {
    const doc = JSON.parse(fs.readFileSync(path.join(dossierSources, fichier), "utf8"));
    const adaptateur = adaptateurs.detect(doc);
    adaptateur(doc).forEach(function (brute) {
      const cle = brute.source + ":" + brute.externalId;
      const lines = brute.lines.map(function (l) { return normalizeLine(l, lexique, catalogue, index); });
      const inconnues = lines.filter(function (l) { return l.status === "unknown"; });

      if (inconnues.length > 0) {
        quarantine.push({
          cle: cle, name: brute.originalName, reason: "lines non reconnues",
          detail: inconnues.map(function (l) { return l.originalText; })
        });
        return;
      }
      const cur = curation[cle];
      if (!cur) {
        quarantine.push({
          cle: cle, name: brute.originalName, reason: "curation manquante",
          detail: ["Tous les ingrédients sont reconnus, mais aucune entrée de curation (âge minimal, rôles, étapes FR)."]
        });
        return;
      }
      if (idsReserves.has(cur.id)) {
        quarantine.push({ cle: cle, name: brute.originalName, reason: "conflit d'identifiant", detail: [cur.id] });
        return;
      }
      idsReserves.add(cur.id);

      imported.push({
        id: cur.id,
        name: cur.name || brute.originalName,
        category: cur.category,
        servings: brute.servings || cur.servings || "",
        minAgeMonths: cur.minAgeMonths,
        timeMinutes: brute.timeMinutes || cur.timeMinutes || null,
        ingredients: lines.map(function (l) {
          const unit = UNITES_FR[l.unit] || l.unit;
          const usage = { id: l.id, qty: l.qty === null ? "" : l.qty, unit: l.qty === null ? "au goût" : unit };
          const role = (cur.roles && cur.roles[l.id]) || null;
          if (role) usage.role = role;
          return usage;
        }),
        steps: (cur.steps && cur.steps.length ? cur.steps : brute.steps),
        source: {
          source: brute.source, externalId: brute.externalId,
          url: brute.url || null, license: brute.license,
          confidence: lines.some(function (l) { return l.confidence === "partielle"; }) ? "à revoir (correspondances partielles)" : "exacte"
        }
      });
    });
  });

  return { imported: imported, quarantine: quarantine };
}

function rapportMarkdown(resultat) {
  const l = [];
  l.push("# Rapport d'import — " + new Date().toISOString().slice(0, 10));
  l.push("");
  l.push("Importées : **" + resultat.imported.length + "** · En quarantine : **" + resultat.quarantine.length + "**");
  l.push("");
  l.push("## Importées");
  l.push("");
  l.push("| Recette | Source | Âge min. | Confiance |");
  l.push("|---|---|---|---|");
  resultat.imported.forEach(function (r) {
    l.push("| " + r.name + " | " + r.source.source + " | " + r.minAgeMonths + " mois | " + r.source.confidence + " |");
  });
  l.push("");
  l.push("## Quarantaine — à traiter par un humain");
  l.push("");
  resultat.quarantine.forEach(function (q) {
    l.push("- **" + q.name + "** (`" + q.cle + "`) — " + q.reason);
    q.detail.forEach(function (d) { l.push("    - " + d); });
  });
  l.push("");
  l.push("Règle : une ligne inconnue = recette entière en quarantine. L'IA peut proposer");
  l.push("de nouveaux alias de lexique ou une entrée de curation; un humain les valide.");
  return l.join("\n");
}

if (require.main === module) {
  const resultat = importAll();
  const dossier = path.join(racine, "data", "imported");
  fs.mkdirSync(dossier, { recursive: true });
  fs.writeFileSync(path.join(dossier, "imported-recipes.json"), JSON.stringify(resultat.imported, null, 2) + "\n");
  fs.writeFileSync(path.join(dossier, "import-report.json"), JSON.stringify(resultat.quarantine, null, 2) + "\n");
  fs.writeFileSync(path.join(racine, "ingest", "import-report.md"), rapportMarkdown(resultat) + "\n");
  console.log("Importées : " + resultat.imported.length + " · Quarantaine : " + resultat.quarantine.length);
  resultat.quarantine.forEach(function (q) { console.log("  quarantine — " + q.name + " (" + q.reason + ")"); });
}

module.exports = { importAll: importAll, rapportMarkdown: rapportMarkdown };
