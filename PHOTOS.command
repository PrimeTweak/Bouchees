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
# NOTHING IS SENT BUT THE PROMPT AND THE SIZE.
#
# I tried pinning the model with override_settings. Draw Things refused every
# single request — "Unrecognized keys" — and 38 recipes failed at once. The
# code even carried a comment saying no source confirmed the key was
# supported, and it shipped anyway.
#
# The preflight is the right mechanism: it READS the model actually loaded and
# refuses to start on Raw. That check works; the override never did.

# THE PORT IS THE APP'S TO CHOOSE, NOT MINE.
#
# 7860 is the common default and I hard-coded it. Draw Things picked 7859 on
# at least one machine — probably because something else already held 7860.
# Asked once, kept in .env like the key.
if [ -z "$DRAWTHINGS_URL" ]; then
  trouve=""
  for essai in 7860 7859 7861 7862 7863; do
    if curl -s -m 3 -o /dev/null "http://127.0.0.1:$essai/"; then
      trouve="$essai"
      break
    fi
  done
  if [ -n "$trouve" ]; then
    export DRAWTHINGS_URL="http://127.0.0.1:$trouve"
    echo "DRAWTHINGS_URL=http://127.0.0.1:$trouve" >> .env
    echo "  Draw Things repond sur le port $trouve."
    echo ""
  else
    echo "  AUCUN PORT NE REPOND"
    echo ""
    echo "  J'ai essaye 7860, 7859, 7861, 7862, 7863."
    echo ""
    echo "  Dans Draw Things, engrenage a GAUCHE, onglet Advanced,"
    echo "  section API Server : quel numero est ecrit dans Port ?"
    echo ""
    read -r -p "  Tape-le ici : " manuel
    if [ -z "$manuel" ]; then
      read -n 1 -p "  Rien de tape. Appuie sur une touche pour fermer."
      exit 1
    fi
    export DRAWTHINGS_URL="http://127.0.0.1:$manuel"
    echo "DRAWTHINGS_URL=http://127.0.0.1:$manuel" >> .env
    echo ""
  fi
fi

# FORCE THE ENGINE. NEVER FALL BACK SILENTLY.
#
# choisir() returns the "simule" engine when DRAWTHINGS_URL is unset, and
# simule writes coloured rectangles. That is what happened: 37 placeholder
# files were generated, the vision correctly rejected every one, and the only
# clue was one line saying "image engine: simule".
#
# Naming the engine means a broken connection stops the run instead of
# producing 37 files nobody wants.
export MOTEUR_IMAGE="drawthings"

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
