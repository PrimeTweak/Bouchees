#!/bin/bash
# Double-clique ceci. Il fabrique le paquet de produits hors ligne.
#
# Deux sources, deux fichiers, jamais fusionnes -- c'est la licence, pas du
# rangement. L'americaine est en domaine public, la canadienne est sous ODbL.
cd "$(dirname "$0")"

TELECHARGEMENTS="$HOME/Downloads"
TRAVAIL="./pack/sources"

echo ""
echo "  BOUCHEES — PAQUET DE PRODUITS HORS LIGNE"
echo "  ========================================"
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

mkdir -p "$TRAVAIL"

# ------------------------------------------------- 2. Le fichier americain
#
# L'adresse de telechargement d'USDA porte la date de la version, donc elle
# change. Je ne la devine pas : tu la prends dans ton navigateur.
#
# Trois formes possibles, parce que Safari decompresse les archives tout seul
# par defaut : le CSV deja range ici, un .zip dans les telechargements, ou un
# dossier deja ouvert par Safari. On regarde les trois.
USDA_CSV=$(ls "$TRAVAIL"/branded_food.csv 2>/dev/null | head -1)

if [ -z "$USDA_CSV" ]; then
  ZIP=$(ls -t "$TELECHARGEMENTS"/*branded_food*.zip \
                "$TELECHARGEMENTS"/FoodData_Central*.zip 2>/dev/null | head -1)
  if [ -n "$ZIP" ]; then
    echo "  Archive trouvee dans tes telechargements :"
    echo "    $(basename "$ZIP")"
    echo "  Extraction de branded_food.csv (2,9 Go une fois ouvert)..."
    unzip -o -j -q "$ZIP" "*branded_food.csv" -d "$TRAVAIL" 2>/dev/null
    USDA_CSV=$(ls "$TRAVAIL"/branded_food.csv 2>/dev/null | head -1)
  fi
fi

if [ -z "$USDA_CSV" ]; then
  # Safari a deja ouvert l'archive : on cherche le CSV dans les dossiers.
  TROUVE=$(find "$TELECHARGEMENTS" -maxdepth 3 -name "branded_food.csv" \
           -type f 2>/dev/null | head -1)
  if [ -n "$TROUVE" ]; then
    echo "  CSV trouve deja decompresse :"
    echo "    $TROUVE"
    echo "  Copie en cours..."
    cp "$TROUVE" "$TRAVAIL/branded_food.csv"
    USDA_CSV="$TRAVAIL/branded_food.csv"
  fi
fi

if [ -z "$USDA_CSV" ]; then
  echo "  IL MANQUE LE FICHIER AMERICAIN"
  echo ""
  echo "  1. Ouvre  fdc.nal.usda.gov/download-datasets"
  echo "  2. Dans le tableau  Latest Downloads , va a la ligne  Branded"
  echo "  3. Clique le bouton  December 2025 (CSV)"
  echo "     427 Mo a telecharger, 2,9 Go une fois ouvert."
  echo "  4. Laisse le resultat dans ton dossier Telechargements,"
  echo "     que le .zip soit ouvert par Safari ou non — les deux marchent."
  echo "  5. Double-clique ce fichier a nouveau"
  echo ""
  echo "  Ces donnees sont en domaine public (CC0). Rien a signer."
  echo ""
  echo "  A refaire seulement quand USDA sort une nouvelle version,"
  echo "  environ deux fois par an. Pas chaque mois."
  echo ""
  read -n 1 -p "  Appuie sur une touche pour fermer."
  exit 1
fi

echo "  Fichier americain : $(basename "$USDA_CSV")"

# --------------------------------------------------- 3. Le fichier canadien
#
# Celle-la ne change pas d'adresse, alors on la prend nous-memes. Environ
# 7 Go : compte une bonne demi-heure sur une connexion ordinaire. Le fichier
# reste sur ton disque, donc la fois suivante il n'y a rien a retelecharger.
OFF_GZ="$TRAVAIL/openfoodfacts-products.jsonl.gz"

if [ ! -f "$OFF_GZ" ]; then
  echo "  Telechargement de la base Open Food Facts (~7 Go)."
  echo "  Tu peux laisser tourner et revenir plus tard."
  echo ""
  curl -L --fail --progress-bar \
    -H "User-Agent: ${OFF_USER_AGENT:-Bouchees/1.0 (https://bouchees.onrender.com)}" \
    -o "$OFF_GZ.partiel" \
    "https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz"
  if [ $? -ne 0 ]; then
    rm -f "$OFF_GZ.partiel"
    echo ""
    echo "  LE TELECHARGEMENT A ECHOUE."
    echo "  Relance : il reprend a zero, mais rien n'est casse."
    echo ""
    read -n 1 -p "  Appuie sur une touche pour fermer."
    exit 1
  fi
  mv "$OFF_GZ.partiel" "$OFF_GZ"
else
  echo "  Base Open Food Facts deja sur le disque."
  echo "  Efface  pack/sources/openfoodfacts-products.jsonl.gz  pour la rafraichir."
fi

# --------------------------------------------------------- 4. La fabrication
echo ""
node tools/build-product-pack.js --usda "$USDA_CSV" --off "$OFF_GZ"
if [ $? -ne 0 ]; then
  echo ""
  read -n 1 -p "  Appuie sur une touche pour fermer."
  exit 1
fi

# ---------------------------------------------------------- 5. Le controle
echo "  CONTROLE DU PAQUET"
node tools/check-pack.js
if [ $? -ne 0 ]; then
  echo ""
  echo "  LE PAQUET N'EST PAS CONFORME. Ne le publie pas."
  echo ""
  read -n 1 -p "  Appuie sur une touche pour fermer."
  exit 1
fi

echo ""
echo "  ENSUITE"
echo "  Les fichiers sont dans  pack/  et ne vont PAS dans Git."
echo "  Ils se deposent comme fichiers de Release sur GitHub."
echo ""
read -n 1 -p "  Appuie sur une touche pour fermer."
