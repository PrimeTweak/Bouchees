#!/bin/bash
# Double-clique ceci. Il fait rédiger des recettes par l'IA, les passe au
# validateur, à la norme et à l'invariant, verse celles qui tiennent dans le
# bassin, et republie. La clé d'API vit dans le fichier cle-api.txt à côté
# de ce script (jamais versionné : il est dans .gitignore).
cd "$(dirname "$0")"

if [ ! -f cle-api.txt ]; then
  echo ""
  echo "  Il manque le fichier cle-api.txt à côté de ce script."
  echo "  Une seule ligne dedans :"
  echo "    ANTHROPIC_API_KEY=sk-ant-..."
  echo "  (ou OPENAI_API_KEY=sk-... pour OpenAI)"
  echo ""
  read -n 1 -p "  Appuie sur une touche pour fermer."
  exit 1
fi
set -a; source cle-api.txt; set +a

TOURS="${1:-3}"
echo ""
echo "  GÉNÉRATION — $TOURS tour(s) de 20 recettes demandées"
echo "  Ce qui ne passe pas la norme est rejeté ; c'est normal d'en perdre."
echo "  Les photos ne sont pas faites ici : PHOTOS.command, après."
echo ""
for i in $(seq 1 "$TOURS"); do
  echo "── tour $i ──"
  node tools/cycle.js --recettes-seulement || { echo "  le tour $i a échoué ; on s'arrête ici"; break; }
done

echo ""
echo "── vérification ──"
node tests/test.js | tail -3
node tools/publish.js | head -3
node tools/gaps.js | head -1

echo ""
echo "  ENSUITE"
echo "    1. GitHub Desktop : tu vois data/generated/generated-recipes.json et"
echo "       dist/ modifiés. Lis les nouvelles recettes dans le premier."
echo "    2. Pousse : Render sert le nouveau catalogue."
echo "    3. PHOTOS.command pour leurs photos, quand tu veux."
echo ""
read -n 1 -p "  Appuie sur une touche pour fermer."
