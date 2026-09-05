# Rapport de trous — 2026-09-05

Corpus: **72 recipes**. Thresholds: **12 usable recipes** per combination (enough for a week) and **6 par catégorie** (un parent ne sert pas que des soupers).

"Too old" = recipes whose minimum age is above the age being tested. They do not count.

## The 12 most starved combinations

| Profil | Âge | Telles quelles | Adaptées | Bloquées | Trop vieilles | Manque | Catégories en pénurie |
|---|---|---|---|---|---|---|---|
| no milk | 6-8 months | 16 | 9 | 0 | 47 | — | — |
| no eggs | 6-8 months | 16 | 9 | 0 | 47 | — | — |
| no peanuts | 6-8 months | 25 | 0 | 0 | 47 | — | — |
| no tree nuts | 6-8 months | 25 | 0 | 0 | 47 | — | — |
| no wheat and triticale | 6-8 months | 21 | 4 | 0 | 47 | — | — |
| no soy | 6-8 months | 25 | 0 | 0 | 47 | — | — |
| no sesame | 6-8 months | 24 | 1 | 0 | 47 | — | — |
| no fish | 6-8 months | 25 | 0 | 0 | 47 | — | — |
| no crustaceans and molluscs | 6-8 months | 25 | 0 | 0 | 47 | — | — |
| no mustard | 6-8 months | 25 | 0 | 0 | 47 | — | — |
| no sulphites | 6-8 months | 25 | 0 | 0 | 47 | — | — |
| no milk + eggs | 6-8 months | 11 | 14 | 0 | 47 | — | — |

## The ingredients that block most often

Each line is a **missing substitution rule**. Writing one
often unlocks more recipes than writing a new one.

- **Pita bread** (`pita`) — bloque 16 fois
- **Ricotta** (`ricotta`) — bloque 12 fois
- **Walnuts** (`walnuts`) — bloque 12 fois
- **Firm tofu** (`tofu`) — bloque 8 fois
- **Tamari sauce** (`tamari`) — bloque 2 fois

## Suggested commission for the next batch

- **2 meal** from 12 months — no milk + soy
    - pool: 84 meals still missing before a recipe waits the full rotation
- **2 snack** from 24 months — no milk + wheat and triticale
    - pool: 68 snacks still missing before a recipe waits the full rotation
- **2 meal** from 48 months — no eggs + wheat and triticale
    - pool: 82 meals still missing before a recipe waits the full rotation
- **2 snack** from 6 months — no peanuts + tree nuts
    - pool: 66 snacks still missing before a recipe waits the full rotation
- **2 meal** from 9 months — no peanuts + tree nuts + sesame
    - pool: 80 meals still missing before a recipe waits the full rotation
- **2 snack** from 12 months — no milk + eggs + wheat and triticale
    - pool: 64 snacks still missing before a recipe waits the full rotation
- **2 meal** from 24 months — no milk + eggs + peanuts + tree nuts
    - pool: 78 meals still missing before a recipe waits the full rotation
- **2 snack** from 48 months — no fish + crustaceans and molluscs
    - pool: 62 snacks still missing before a recipe waits the full rotation
- **2 meal** from 6 months — no milk
    - pool: 76 meals still missing before a recipe waits the full rotation
- **2 snack** from 9 months — no eggs
    - pool: 60 snacks still missing before a recipe waits the full rotation

Ce fichier est régénéré par `node tools/gaps.js`. Il alimente
`generation/recipe-prompt.js`, qui transforme la commande en prompt contraint.
