# Rapport de trous — 2026-08-23

Corpus : **38 recettes**. Seuils : **12 recettes utilisables** par combinaison (de quoi faire une semaine) et **6 par catégorie** (un parent ne sert pas que des soupers).

« Trop vieilles » = recettes dont l'âge minimal dépasse l'âge testé. Elles ne comptent pas.

## Les 12 combinaisons les plus dépourvues

| Profil | Âge | Telles quelles | Adaptées | Bloquées | Trop vieilles | Manque | Catégories en pénurie |
|---|---|---|---|---|---|---|---|
| sans lait | 6–8 mois | 13 | 9 | 0 | 16 | 3 | Repas (1), Dessert (2) |
| sans œufs | 6–8 mois | 16 | 6 | 0 | 16 | 3 | Repas (1), Dessert (2) |
| sans arachides | 6–8 mois | 22 | 0 | 0 | 16 | 3 | Repas (1), Dessert (2) |
| sans noix | 6–8 mois | 22 | 0 | 0 | 16 | 3 | Repas (1), Dessert (2) |
| sans blé et triticale | 6–8 mois | 18 | 4 | 0 | 16 | 3 | Repas (1), Dessert (2) |
| sans soya | 6–8 mois | 22 | 0 | 0 | 16 | 3 | Repas (1), Dessert (2) |
| sans sésame | 6–8 mois | 21 | 1 | 0 | 16 | 3 | Repas (1), Dessert (2) |
| sans poisson | 6–8 mois | 22 | 0 | 0 | 16 | 3 | Repas (1), Dessert (2) |
| sans crustacés et mollusques | 6–8 mois | 22 | 0 | 0 | 16 | 3 | Repas (1), Dessert (2) |
| sans moutarde | 6–8 mois | 22 | 0 | 0 | 16 | 3 | Repas (1), Dessert (2) |
| sans sulfites | 6–8 mois | 22 | 0 | 0 | 16 | 3 | Repas (1), Dessert (2) |
| sans lait + œufs | 6–8 mois | 11 | 11 | 0 | 16 | 3 | Repas (1), Dessert (2) |

## Ingrédients qui bloquent le plus

Chaque ligne est une **règle de substitution manquante**. En écrire une
débloque souvent plus de recettes que d'en rédiger une nouvelle.

- **Noix de Grenoble** (`noix_grenoble`) — bloque 12 fois

## Commande suggérée pour le prochain lot

- **2 dessert** dès 6 mois — **passe-partout** (sans aucun des 11 allergènes prioritaires)
    - 22 recettes utilisables à 6–8 mois, 16 du corpus visent plus vieux — il manque 2 dessert. Ce trou existe pour TOUS les profils : une seule recette passe-partout les sert tous.
- **2 repas** dès 6 mois — **passe-partout** (sans aucun des 11 allergènes prioritaires)
    - 22 recettes utilisables à 6–8 mois, 16 du corpus visent plus vieux — il manque 1 repas. Ce trou existe pour TOUS les profils : une seule recette passe-partout les sert tous.

Ce fichier est régénéré par `node outils/trous.js`. Il alimente
`generation/prompt-recette.js`, qui transforme la commande en prompt contraint.
