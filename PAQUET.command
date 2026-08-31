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
# Celle-la ne change pas d'adresse, alors on la prend nous-memes.
#
# LA REPRISE COMPTE ICI. Sept gigaoctets sur une connexion residentielle, ca
# se coupe. Sans -C - une coupure a 90 % renvoie a zero, et le fichier partiel
# est GARDE en cas d'echec precisement pour que le prochain lancement reprenne
# ou celui-ci s'est arrete.
OFF_GZ="$TRAVAIL/openfoodfacts-products.jsonl.gz"
OFF_URL="https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz"
AGENT="${OFF_USER_AGENT:-Bouchees/1.0 (https://bouchees.onrender.com)}"

if [ ! -f "$OFF_GZ" ]; then
  # Place disponible, en Go. Il faut le telechargement, le CSV americain
  # deja ouvert, et de quoi ecrire le paquet.
  LIBRE=$(df -g "$TRAVAIL" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$LIBRE" ] && [ "$LIBRE" -lt 14 ]; then
    echo "  ESPACE DISQUE INSUFFISANT"
    echo ""
    echo "  Il reste $LIBRE Go. Il en faut environ 14 :"
    echo "    7 a 10 Go  la base Open Food Facts"
    echo "    2,9 Go     le CSV americain deja ouvert"
    echo "    le reste   le paquet lui-meme"
    echo ""
    read -n 1 -p "  Appuie sur une touche pour fermer."
    exit 1
  fi

  if [ -f "$OFF_GZ.partiel" ]; then
    DEJA=$(du -h "$OFF_GZ.partiel" | cut -f1)
    echo "  Reprise du telechargement precedent ($DEJA deja recus)."
  else
    echo "  Telechargement de la base Open Food Facts (7 a 10 Go)."
  fi
  echo "  Tu peux laisser tourner et revenir plus tard."
  echo "  Si ca coupe, relance : ca reprendra ou c'etait rendu."
  echo ""

  curl -L --fail --progress-bar -C - -H "User-Agent: $AGENT" \
       -o "$OFF_GZ.partiel" "$OFF_URL"
  CODE=$?

  # 33 : le serveur refuse la reprise. On repart proprement, une fois.
  if [ $CODE -eq 33 ]; then
    echo "  Reprise refusee par le serveur, on repart du debut."
    rm -f "$OFF_GZ.partiel"
    curl -L --fail --progress-bar -H "User-Agent: $AGENT" \
         -o "$OFF_GZ.partiel" "$OFF_URL"
    CODE=$?
  fi

  if [ $CODE -ne 0 ]; then
    echo ""
    echo "  LE TELECHARGEMENT S'EST ARRETE."
    echo "  Ce qui est recu est garde. Relance ce fichier : ca reprendra."
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
echo "  Tu peux effacer  pack/sources/  pour recuperer une dizaine de Go."
echo "  Garde-le si tu comptes refabriquer le paquet bientot."
echo ""
read -n 1 -p "  Appuie sur une touche pour fermer."
