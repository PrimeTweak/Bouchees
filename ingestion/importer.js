/* Importeur — lot 3, v0.2
 * node ingestion/importer.js
 * Sources → adaptateur → normalisation → PORTES DE SÉCURITÉ → recettes canoniques.
 *
 * Deux portes, non négociables :
 *   1. Reconnaissance totale : une seule ligne d'ingrédient inconnue et la
 *      recette entière part en quarantaine. On ne devine jamais un ingrédient
 *      dans une app d'allergies.
 *   2. Curation humaine : sans entrée dans curation.json (âge minimal validé,
 *      rôles confirmés, étapes en français), pas d'import — même si tout est
 *      reconnu. Le pipeline propose, l'humain dispose.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const adaptateurs = require("./adaptateurs.js");
const { normaliserLigne, construireIndex } = require("./normaliseur.js");

const racine = path.join(__dirname, "..");
const UNITES_FR = { clove: "gousse", cloves: "gousses", fillet: "filet", fillets: "filets", can: "boîte", cans: "boîtes", slice: "tranche", slices: "tranches" };
const lire = (p) => JSON.parse(fs.readFileSync(path.join(racine, p), "utf8"));

function importerTout(options) {
  options = options || {};
  const catalogue = options.catalogue || lire("donnees/ingredients.json");
  const lexique = options.lexique || lire("ingestion/lexique.json");
  const curation = options.curation || lire("ingestion/curation.json");
  const dossierSources = options.dossierSources || path.join(racine, "ingestion", "sources");
  const idsReserves = new Set((options.idsReserves || lire("donnees/recettes.json").map((r) => r.id)));
  const index = construireIndex(lexique);

  const importees = [];
  const quarantaine = [];

  fs.readdirSync(dossierSources).filter((f) => f.endsWith(".json")).sort().forEach(function (fichier) {
    const doc = JSON.parse(fs.readFileSync(path.join(dossierSources, fichier), "utf8"));
    const adaptateur = adaptateurs.detecter(doc);
    adaptateur(doc).forEach(function (brute) {
      const cle = brute.source + ":" + brute.idExterne;
      const lignes = brute.lignes.map(function (l) { return normaliserLigne(l, lexique, catalogue, index); });
      const inconnues = lignes.filter(function (l) { return l.statut === "inconnu"; });

      if (inconnues.length > 0) {
        quarantaine.push({
          cle: cle, nom: brute.nomOriginal, raison: "lignes non reconnues",
          detail: inconnues.map(function (l) { return l.texteOriginal; })
        });
        return;
      }
      const cur = curation[cle];
      if (!cur) {
        quarantaine.push({
          cle: cle, nom: brute.nomOriginal, raison: "curation manquante",
          detail: ["Tous les ingrédients sont reconnus, mais aucune entrée de curation (âge minimal, rôles, étapes FR)."]
        });
        return;
      }
      if (idsReserves.has(cur.id)) {
        quarantaine.push({ cle: cle, nom: brute.nomOriginal, raison: "conflit d'identifiant", detail: [cur.id] });
        return;
      }
      idsReserves.add(cur.id);

      importees.push({
        id: cur.id,
        nom: cur.nom || brute.nomOriginal,
        categorie: cur.categorie,
        portions: brute.portions || cur.portions || "",
        ageMinBase: cur.ageMinBase,
        tempsMin: brute.tempsMin || cur.tempsMin || null,
        ingredients: lignes.map(function (l) {
          const unite = UNITES_FR[l.unite] || l.unite;
          const usage = { id: l.id, qte: l.qte === null ? "" : l.qte, unite: l.qte === null ? "au goût" : unite };
          const role = (cur.roles && cur.roles[l.id]) || null;
          if (role) usage.role = role;
          return usage;
        }),
        etapes: (cur.etapes && cur.etapes.length ? cur.etapes : brute.etapes),
        provenance: {
          source: brute.source, idExterne: brute.idExterne,
          url: brute.url || null, licence: brute.licence,
          confiance: lignes.some(function (l) { return l.confiance === "partielle"; }) ? "à revoir (correspondances partielles)" : "exacte"
        }
      });
    });
  });

  return { importees: importees, quarantaine: quarantaine };
}

function rapportMarkdown(resultat) {
  const l = [];
  l.push("# Rapport d'import — " + new Date().toISOString().slice(0, 10));
  l.push("");
  l.push("Importées : **" + resultat.importees.length + "** · En quarantaine : **" + resultat.quarantaine.length + "**");
  l.push("");
  l.push("## Importées");
  l.push("");
  l.push("| Recette | Source | Âge min. | Confiance |");
  l.push("|---|---|---|---|");
  resultat.importees.forEach(function (r) {
    l.push("| " + r.nom + " | " + r.provenance.source + " | " + r.ageMinBase + " mois | " + r.provenance.confiance + " |");
  });
  l.push("");
  l.push("## Quarantaine — à traiter par un humain");
  l.push("");
  resultat.quarantaine.forEach(function (q) {
    l.push("- **" + q.nom + "** (`" + q.cle + "`) — " + q.raison);
    q.detail.forEach(function (d) { l.push("    - " + d); });
  });
  l.push("");
  l.push("Règle : une ligne inconnue = recette entière en quarantaine. L'IA peut proposer");
  l.push("de nouveaux alias de lexique ou une entrée de curation; un humain les valide.");
  return l.join("\n");
}

if (require.main === module) {
  const resultat = importerTout();
  const dossier = path.join(racine, "donnees", "importees");
  fs.mkdirSync(dossier, { recursive: true });
  fs.writeFileSync(path.join(dossier, "recettes-importees.json"), JSON.stringify(resultat.importees, null, 2) + "\n");
  fs.writeFileSync(path.join(dossier, "rapport-import.json"), JSON.stringify(resultat.quarantaine, null, 2) + "\n");
  fs.writeFileSync(path.join(racine, "ingestion", "rapport-import.md"), rapportMarkdown(resultat) + "\n");
  console.log("Importées : " + resultat.importees.length + " · Quarantaine : " + resultat.quarantaine.length);
  resultat.quarantaine.forEach(function (q) { console.log("  quarantaine — " + q.nom + " (" + q.raison + ")"); });
}

module.exports = { importerTout: importerTout, rapportMarkdown: rapportMarkdown };
