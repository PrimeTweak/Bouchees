#!/bin/bash
# Rebuilds every thumbnail and republishes, so the catalogue names them.
# publish.js makes thumbnails on its own from now on; this is for a first
# run, or for starting over after emptying images/thumbs/.
cd "$(dirname "$0")"
echo ""
echo "  BOUCHEES — VIGNETTES"
echo "  --------------------"
node tools/thumbs.js
node tools/publish.js | head -3
echo ""
echo "  Termine. Dans GitHub Desktop : images/thumbs/ (nouveau) et dist/ modifie."
echo "  Pousse les deux ensemble."
echo ""
read -n 1 -p "  Appuie sur une touche pour fermer."
