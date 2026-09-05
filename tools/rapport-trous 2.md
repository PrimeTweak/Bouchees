# Rapport de trous — 2026-09-05

Corpus: **153 recipes**. Thresholds: **12 usable recipes** per combination (enough for a week) and **6 par catégorie** (un parent ne sert pas que des soupers).

"Too old" = recipes whose minimum age is above the age being tested. They do not count.

## The 12 most starved combinations

| Profil | Âge | Telles quelles | Adaptées | Bloquées | Trop vieilles | Manque | Catégories en pénurie |
|---|---|---|---|---|---|---|---|
| no milk | 6-8 months | 49 | 9 | 0 | 95 | — | — |
| no eggs | 6-8 months | 49 | 9 | 0 | 95 | — | — |
| no peanuts | 6-8 months | 58 | 0 | 0 | 95 | — | — |
| no tree nuts | 6-8 months | 58 | 0 | 0 | 95 | — | — |
| no wheat and triticale | 6-8 months | 54 | 4 | 0 | 95 | — | — |
| no soy | 6-8 months | 58 | 0 | 0 | 95 | — | — |
| no sesame | 6-8 months | 57 | 1 | 0 | 95 | — | — |
| no fish | 6-8 months | 52 | 6 | 0 | 95 | — | — |
| no crustaceans and molluscs | 6-8 months | 58 | 0 | 0 | 95 | — | — |
| no mustard | 6-8 months | 58 | 0 | 0 | 95 | — | — |
| no sulphites | 6-8 months | 58 | 0 | 0 | 95 | — | — |
| no milk + eggs | 6-8 months | 44 | 14 | 0 | 95 | — | — |

## The ingredients that block most often

Each line is a **missing substitution rule**. Writing one
often unlocks more recipes than writing a new one.

- **Ricotta** (`ricotta`) — bloque 54 fois
- **Pita bread** (`pita`) — bloque 16 fois
- **Walnuts** (`walnuts`) — bloque 12 fois
- **Firm tofu** (`tofu`) — bloque 8 fois
- **Tamari sauce** (`tamari`) — bloque 6 fois

## Suggested commission for the next batch

- **2 meal** from 9 months — no milk + eggs + peanuts + tree nuts
    - pool: 39 meals still missing, youngest ages first
- **2 snack** from 12 months — no wheat and triticale
    - pool: 32 snacks still missing, youngest ages first
- **2 meal** from 24 months — no milk
    - pool: 37 meals still missing, youngest ages first
- **2 snack** from 6 months — no milk + eggs
    - pool: 30 snacks still missing, youngest ages first
- **2 meal** from 6 months — no milk + eggs + wheat and triticale
    - pool: 35 meals still missing, youngest ages first
- **2 snack** from 9 months — no peanuts + tree nuts
    - pool: 28 snacks still missing, youngest ages first
- **2 meal** from 9 months — no milk + eggs + peanuts + tree nuts
    - pool: 33 meals still missing, youngest ages first
- **2 snack** from 12 months — no wheat and triticale
    - pool: 26 snacks still missing, youngest ages first
- **2 meal** from 24 months — no milk
    - pool: 31 meals still missing, youngest ages first
- **2 snack** from 6 months — no milk + eggs
    - pool: 24 snacks still missing, youngest ages first

Ce fichier est régénéré par `node tools/gaps.js`. Il alimente
`generation/recipe-prompt.js`, qui transforme la commande en prompt contraint.
