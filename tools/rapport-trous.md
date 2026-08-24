# Rapport de trous — 2026-08-24

Corpus: **38 recipes**. Thresholds: **12 usable recipes** per combination (enough for a week) and **6 par catégorie** (un parent ne sert pas que des soupers).

"Too old" = recipes whose minimum age is above the age being tested. They do not count.

## The 12 most starved combinations

| Profil | Âge | Telles quelles | Adaptées | Bloquées | Trop vieilles | Manque | Catégories en pénurie |
|---|---|---|---|---|---|---|---|
| no milk | 6-8 months | 13 | 9 | 0 | 16 | 3 | Meal (1), Dessert (2) |
| no eggs | 6-8 months | 16 | 6 | 0 | 16 | 3 | Meal (1), Dessert (2) |
| no peanuts | 6-8 months | 22 | 0 | 0 | 16 | 3 | Meal (1), Dessert (2) |
| no tree nuts | 6-8 months | 22 | 0 | 0 | 16 | 3 | Meal (1), Dessert (2) |
| no wheat and triticale | 6-8 months | 18 | 4 | 0 | 16 | 3 | Meal (1), Dessert (2) |
| no soy | 6-8 months | 22 | 0 | 0 | 16 | 3 | Meal (1), Dessert (2) |
| no sesame | 6-8 months | 21 | 1 | 0 | 16 | 3 | Meal (1), Dessert (2) |
| no fish | 6-8 months | 22 | 0 | 0 | 16 | 3 | Meal (1), Dessert (2) |
| no crustaceans and molluscs | 6-8 months | 22 | 0 | 0 | 16 | 3 | Meal (1), Dessert (2) |
| no mustard | 6-8 months | 22 | 0 | 0 | 16 | 3 | Meal (1), Dessert (2) |
| no sulphites | 6-8 months | 22 | 0 | 0 | 16 | 3 | Meal (1), Dessert (2) |
| no lait + oeuf | 6-8 months | 22 | 0 | 0 | 16 | 3 | Meal (1), Dessert (2) |

## The ingredients that block most often

Each line is a **missing substitution rule**. Writing one
often unlocks more recipes than writing a new one.

- **Walnuts** (`walnuts`) — bloque 3 fois

## Suggested commission for the next batch

- **2 dessert** from 6 months — **works for everyone** (none of the 11 priority allergens)
    - 22 usable recipes at 6-8 months, 16 du corpus visent plus vieux — il missing 2 dessert. This gap exists for EVERY profile: one recipe that works for all of them fills it.
- **2 meal** from 6 months — **works for everyone** (none of the 11 priority allergens)
    - 22 usable recipes at 6-8 months, 16 du corpus visent plus vieux — il missing 1 meal. This gap exists for EVERY profile: one recipe that works for all of them fills it.

Ce fichier est régénéré par `node tools/gaps.js`. Il alimente
`generation/recipe-prompt.js`, qui transforme la commande en prompt contraint.
