#!/bin/bash
# Double-clique ceci. Il fabrique une version 480 px de chaque photo pour
# les vignettes. sips est integre a macOS : rien a installer.
cd "$(dirname "$0")"
mkdir -p images/thumbs
n=0; d=0
for f in images/*.png; do
  [ -f "$f" ] || continue
  cible="images/thumbs/$(basename "$f")"
  if [ -f "$cible" ] && [ "$cible" -nt "$f" ]; then d=$((d+1)); continue; fi
  sips -Z 480 "$f" --out "$cible" >/dev/null 2>&1 && n=$((n+1))
done
echo ""
echo "  VIGNETTES"
echo "    fabriquees   $n"
echo "    deja a jour  $d"
echo ""
echo "  Ensuite : node tools/publish.js  (ou PHOTOS.command), puis pousse"
echo "  images/thumbs/ AVEC dist/."
echo ""
read -n 1 -p "  Appuie sur une touche pour fermer."
