# Rapport de trous — 2026-09-05

Corpus: **85 recipes**. Thresholds: **12 usable recipes** per combination (enough for a week) and **6 par catégorie** (un parent ne sert pas que des soupers).

"Too old" = recipes whose minimum age is above the age being tested. They do not count.

## The 12 most starved combinations

| Profil | Âge | Telles quelles | Adaptées | Bloquées | Trop vieilles | Manque | Catégories en pénurie |
|---|---|---|---|---|---|---|---|
| no milk | 6-8 months | 20 | 9 | 0 | 56 | — | — |
| no eggs | 6-8 months | 20 | 9 | 0 | 56 | — | — |
| no peanuts | 6-8 months | 29 | 0 | 0 | 56 | — | — |
| no tree nuts | 6-8 months | 29 | 0 | 0 | 56 | — | — |
| no wheat and triticale | 6-8 months | 25 | 4 | 0 | 56 | — | — |
| no soy | 6-8 months | 29 | 0 | 0 | 56 | — | — |
| no sesame | 6-8 months | 28 | 1 | 0 | 56 | — | — |
| no fish | 6-8 months | 29 | 0 | 0 | 56 | — | — |
| no crustaceans and molluscs | 6-8 months | 29 | 0 | 0 | 56 | — | — |
| no mustard | 6-8 months | 29 | 0 | 0 | 56 | — | — |
| no sulphites | 6-8 months | 29 | 0 | 0 | 56 | — | — |
| no milk + eggs | 6-8 months | 15 | 14 | 0 | 56 | — | — |

## The ingredients that block most often

Each line is a **missing substitution rule**. Writing one
often unlocks more recipes than writing a new one.

- **Pita bread** (`pita`) — bloque 16 fois
- **Ricotta** (`ricotta`) — bloque 12 fois
- **Walnuts** (`walnuts`) — bloque 12 fois
- **Firm tofu** (`tofu`) — bloque 8 fois
- **Tamari sauce** (`tamari`) — bloque 6 fois

## Suggested commission for the next batch

- **2 meal** from 6 months — no milk + eggs + wheat and triticale
    - pool: 74 meals still missing, youngest ages first
- **2 snack** from 9 months — no peanuts + tree nuts
    - pool: 65 snacks still missing, youngest ages first
- **2 meal** from 9 months — no milk + eggs + peanuts + tree nuts
    - pool: 72 meals still missing, youngest ages first
- **2 snack** from 12 months — no wheat and triticale
    - pool: 63 snacks still missing, youngest ages first
- **2 meal** from 24 months — no milk
    - pool: 70 meals still missing, youngest ages first
- **2 snack** from 6 months — no milk + eggs
    - pool: 61 snacks still missing, youngest ages first
- **2 meal** from 6 months — no milk + eggs + wheat and triticale
    - pool: 68 meals still missing, youngest ages first
- **2 snack** from 9 months — no peanuts + tree nuts
    - pool: 59 snacks still missing, youngest ages first
- **2 meal** from 9 months — no milk + eggs + peanuts + tree nuts
    - pool: 66 meals still missing, youngest ages first
- **2 snack** from 12 months — no wheat and triticale
    - pool: 57 snacks still missing, youngest ages first

Ce fichier est régénéré par `node tools/gaps.js`. Il alimente
`generation/recipe-prompt.js`, qui transforme la commande en prompt contraint.
