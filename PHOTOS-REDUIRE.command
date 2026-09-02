#!/bin/bash
# Les vignettes. PHOTOS.command les fait deja tout seul : ce script sert a
# les refaire toutes, par exemple apres avoir vide images/thumbs/.
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
echo "  Ensuite : node tools/publish.js, puis pousse images/thumbs/ AVEC dist/."
echo ""
read -n 1 -p "  Appuie sur une touche pour fermer."
