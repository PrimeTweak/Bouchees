# Rapport de trous — 2026-09-02

Corpus: **43 recipes**. Thresholds: **12 usable recipes** per combination (enough for a week) and **6 par catégorie** (un parent ne sert pas que des soupers).

"Too old" = recipes whose minimum age is above the age being tested. They do not count.

## The 12 most starved combinations

| Profil | Âge | Telles quelles | Adaptées | Bloquées | Trop vieilles | Manque | Catégories en pénurie |
|---|---|---|---|---|---|---|---|
| no milk | 6-8 months | 13 | 9 | 0 | 21 | 1 | Meal (1) |
| no eggs | 6-8 months | 16 | 6 | 0 | 21 | 1 | Meal (1) |
| no peanuts | 6-8 months | 22 | 0 | 0 | 21 | 1 | Meal (1) |
| no tree nuts | 6-8 months | 22 | 0 | 0 | 21 | 1 | Meal (1) |
| no wheat and triticale | 6-8 months | 18 | 4 | 0 | 21 | 1 | Meal (1) |
| no soy | 6-8 months | 22 | 0 | 0 | 21 | 1 | Meal (1) |
| no sesame | 6-8 months | 21 | 1 | 0 | 21 | 1 | Meal (1) |
| no fish | 6-8 months | 22 | 0 | 0 | 21 | 1 | Meal (1) |
| no crustaceans and molluscs | 6-8 months | 22 | 0 | 0 | 21 | 1 | Meal (1) |
| no mustard | 6-8 months | 22 | 0 | 0 | 21 | 1 | Meal (1) |
| no sulphites | 6-8 months | 22 | 0 | 0 | 21 | 1 | Meal (1) |
| no milk + eggs | 6-8 months | 11 | 11 | 0 | 21 | 1 | Meal (1) |

## The ingredients that block most often

Each line is a **missing substitution rule**. Writing one
often unlocks more recipes than writing a new one.

- **Walnuts** (`walnuts`) — bloque 12 fois
- **Firm tofu** (`tofu`) — bloque 8 fois

## Suggested commission for the next batch

- **2 meal** from 6 months — **works for everyone** (none of the 11 priority allergens)
    - 22 usable recipes at 6-8 months, 21 du corpus visent plus vieux — il missing 1 meal. This gap exists for EVERY profile: one recipe that works for all of them fills it.
- **2 meal** from 24 months — no tree nuts
    - pool: 91 meals still missing before a recipe waits the full rotation
- **2 snack** from 48 months — no wheat and triticale
    - pool: 90 snacks still missing before a recipe waits the full rotation
- **2 meal** from 6 months — no soy
    - pool: 89 meals still missing before a recipe waits the full rotation
- **2 snack** from 9 months — no sesame
    - pool: 88 snacks still missing before a recipe waits the full rotation
- **2 meal** from 12 months — no fish
    - pool: 87 meals still missing before a recipe waits the full rotation
- **2 snack** from 24 months — no crustaceans and molluscs
    - pool: 86 snacks still missing before a recipe waits the full rotation
- **2 meal** from 48 months — no mustard
    - pool: 85 meals still missing before a recipe waits the full rotation
- **2 snack** from 6 months — no sulphites
    - pool: 84 snacks still missing before a recipe waits the full rotation
- **2 meal** from 9 months — no milk + eggs
    - pool: 83 meals still missing before a recipe waits the full rotation

Ce fichier est régénéré par `node tools/gaps.js`. Il alimente
`generation/recipe-prompt.js`, qui transforme la commande en prompt contraint.
