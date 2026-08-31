#!/bin/bash
# Double-click this. It generates every missing recipe photo.
#
# Everything the run needs is checked or asked for here, in order, with a
# message that says what to do. Nothing is assumed.
cd "$(dirname "$0")"

echo ""
echo "  BOUCHEES — GENERATION DES PHOTOS"
echo "  ================================"
echo ""

# ---------------------------------------------------------------- 1. Node
if ! command -v node > /dev/null 2>&1; then
  echo "  NODE N'EST PAS INSTALLE"
  echo ""
  echo "  Va sur  nodejs.org , prends le bouton vert LTS."
  echo "  Puis ferme cette fenetre et double-clique a nouveau."
  echo ""
  read -n 1 -p "  Appuie sur une touche pour fermer."
  exit 1
fi

# ------------------------------------------------------- 2. The vision key
#
# Asked once and kept in .env, which git ignores. Without it the vision check
# has no verdict, and a missing verdict REJECTS the image — so a run without a
# key generates ten photos and files none of them.
if [ -f .env ]; then
  set -a; . ./.env; set +a
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "  IL MANQUE TA CLE ANTHROPIC"
  echo ""
  echo "  Elle sert a VERIFIER les images : un modele decrit ce qu'il"
  echo "  voit, et le code rejette une photo qui montre un aliment"
  echo "  absent de la recette, ou un risque d'etouffement."
  echo ""
  echo "  Sans elle, les dix images se generent et AUCUNE n'est gardee."
  echo ""
  echo "  Colle-la ici (elle commence par sk-ant-) :"
  read -r cle
  if [ -z "$cle" ]; then
    echo ""
    echo "  Rien de colle. J'arrete."
    read -n 1 -p "  Appuie sur une touche pour fermer."
    exit 1
  fi
  echo "ANTHROPIC_API_KEY=$cle" >> .env
  export ANTHROPIC_API_KEY="$cle"
  echo ""
  echo "  Gardee dans .env — tu ne la retaperas plus."
  echo "  (git ignore ce fichier, elle ne partira jamais sur GitHub)"
  echo ""
fi

# --------------------------------------------------------- 3. Draw Things
#
# Steps and sampler still come from the app: an SDXL solver on a distilled
# model produces an embossed anaglyph. Only the model is pinned.
export DRAWTHINGS_MODELE="Krea 2 Turbo"

node tools/preflight.js || {
  echo ""
  read -n 1 -p "  Appuie sur une touche pour fermer."
  exit 1
}

# ------------------------------------------------------------- 4. Generate
echo "  Generation en cours. Quelques minutes par image."
echo "  Tu peux laisser tourner et revenir."
echo ""

node tools/cycle.js --images-seulement

echo ""
echo "  Termine. Les photos sont dans images/, le manifeste est a jour."
echo "  Il reste a pousser dans GitHub Desktop."
echo ""
read -n 1 -p "  Appuie sur une touche pour fermer."
