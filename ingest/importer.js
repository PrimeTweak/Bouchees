"use strict";
const fs = require("fs");
const path = require("path");
const adaptateurs = require("./adapters.js");
const { normalizeLine, construireIndex } = require("./normalizer.js");

const root = path.join(__dirname, "..");
const UNITES_FR = { clove: "gousse", cloves: "gousses", fillet: "filet", fillets: "filets", can: "boîte", cans: "boîtes", slice: "tranche", slices: "tranches" };
const read = (p) => JSON.parse(fs.readFileSync(path.join(root, p), "utf8"));

function importAll(options) {
  options = options || {};
  const catalogue = options.catalogue || read("data/ingredients.json");
  const lexique = options.lexique || read("ingest/lexicon.json");
  const curation = options.curation || read("ingest/curation.json");
  const dossierSources = options.dossierSources || path.join(root, "ingest", "sources");
  const idsReserves = new Set((options.idsReserves || read("data/recipes.json").map((r) => r.id)));
  const index = construireIndex(lexique);

  const imported = [];
  const quarantine = [];

  fs.readdirSync(dossierSources).filter((f) => f.endsWith(".json")).sort().forEach(function (fichier) {
    const doc = JSON.parse(fs.readFileSync(path.join(dossierSources, fichier), "utf8"));
    const adaptateur = adaptateurs.detect(doc);
    adaptateur(doc).forEach(function (brute) {
      const key = brute.source + ":" + brute.externalId;
      const lines = brute.lines.map(function (l) { return normalizeLine(l, lexique, catalogue, index); });
      const inconnues = lines.filter(function (l) { return l.status === "unknown"; });

      if (inconnues.length > 0) {
        quarantine.push({
          key: key, name: brute.originalName, reason: "lines not recognised",
          detail: inconnues.map(function (l) { return l.originalText; })
        });
        return;
      }
      /* No licence, no import: a recipe whose right to be stored is not
       * stated is quarantined, exactly like one without curation. */
      if (!brute.license) {
        quarantine.push({ key: key, name: brute.originalName, reason: "licence missing",
                          detail: ["The source document states no licence for storing this recipe."] });
        return;
      }
      const cur = curation[key];
      if (!cur) {
        quarantine.push({
          key: key, name: brute.originalName, reason: "curation missing",
          detail: ["Every ingredient is recognised, but there is no curation entry (minimum age, roles, steps)."]
        });
        return;
      }
      if (idsReserves.has(cur.id)) {
        quarantine.push({ key: key, name: brute.originalName, reason: "id conflict", detail: [cur.id] });
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

function rapportMarkdown(result) {
  const l = [];
  l.push("# Rapport d'import — " + new Date().toISOString().slice(0, 10));
  l.push("");
  l.push("Importées : **" + result.imported.length + "** · En quarantine : **" + result.quarantine.length + "**");
  l.push("");
  l.push("## Imported");
  l.push("");
  l.push("| Recette | Source | Âge min. | Confiance |");
  l.push("|---|---|---|---|");
  result.imported.forEach(function (r) {
    l.push("| " + r.name + " | " + r.source.source + " | " + r.minAgeMonths + " mois | " + r.source.confidence + " |");
  });
  l.push("");
  l.push("## Quarantine — for a human to handle");
  l.push("");
  result.quarantine.forEach(function (q) {
    l.push("- **" + q.name + "** (`" + q.key + "`) — " + q.reason);
    q.detail.forEach(function (d) { l.push("    - " + d); });
  });
  l.push("");
  l.push("Rule: one unknown line puts the whole recipe in quarantine. The AI may suggest");
  l.push("new lexicon aliases or a curation entry; a human validates them.");
  return l.join("\n");
}

if (require.main === module) {
  const result = importAll();
  const folder = path.join(root, "data", "imported");
  fs.mkdirSync(folder, { recursive: true });
  fs.writeFileSync(path.join(folder, "imported-recipes.json"), JSON.stringify(result.imported, null, 2) + "\n");
  fs.writeFileSync(path.join(folder, "import-report.json"), JSON.stringify(result.quarantine, null, 2) + "\n");
  fs.writeFileSync(path.join(root, "ingest", "import-report.md"), rapportMarkdown(result) + "\n");
  console.log("Imported: " + result.imported.length + " · Quarantined: " + result.quarantine.length);
  result.quarantine.forEach(function (q) { console.log("  quarantine — " + q.name + " (" + q.reason + ")"); });
}

module.exports = { importAll: importAll, rapportMarkdown: rapportMarkdown };
