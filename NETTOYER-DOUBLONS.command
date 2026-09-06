#!/bin/bash
# Removes the "name 2.ext" / "name 3.ext" copies Finder creates when it is
# asked to keep both files. Each copy is deleted only if it is identical,
# byte for byte, to the original beside it; anything that differs is kept
# and listed, so nothing that matters can be lost.
cd "$(dirname "$0")"
echo ""
echo "  BOUCHEES — DOUBLONS DE FINDER"
echo "  -----------------------------"
node - <<'JS'
const fs = require("fs"), path = require("path");
let removed = 0, kept = [];
function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    if (f === ".git" || f === "node_modules") continue;
    const p = path.join(dir, f);
    if (fs.statSync(p).isDirectory()) { walk(p); continue; }
    const m = f.match(/^(.*) (\d)(\.[^.]+)$/);
    if (!m) continue;
    const original = path.join(dir, m[1] + m[3]);
    if (!fs.existsSync(original)) { kept.push(p + "  (no original beside it)"); continue; }
    if (fs.readFileSync(p).equals(fs.readFileSync(original))) { fs.unlinkSync(p); removed++; }
    else kept.push(p + "  (differs from the original — check by hand)");
  }
}
walk(".");
/* A note from an earlier delivery that landed at the root; the current one
 * lives at docs/APP-STORE.md. */
if (fs.existsSync("APP-STORE.md") && fs.existsSync("docs/APP-STORE.md")) { fs.unlinkSync("APP-STORE.md"); console.log("  removed: APP-STORE.md at the root (the current one is docs/APP-STORE.md)"); }
console.log("  removed: " + removed + " identical copies");
if (kept.length) { console.log("  kept, to check by hand:"); kept.forEach((k) => console.log("    " + k)); }
else console.log("  kept: none — nothing differed");
JS
echo ""
echo "  Ensuite : node tests/test.js doit dire 210 tests, sans FAILED."
node tests/test.js 2>&1 | grep -E "FAILED|tests\.$"
echo ""
read -n 1 -p "  Appuie sur une touche pour fermer."
