# Rapport de trous — 2026-09-06

Corpus: **159 recipes**. Thresholds: **12 usable recipes** per combination (enough for a week) and **6 par catégorie** (un parent ne sert pas que des soupers).

"Too old" = recipes whose minimum age is above the age being tested. They do not count.

## The 12 most starved combinations

| Profil | Âge | Telles quelles | Adaptées | Bloquées | Trop vieilles | Manque | Catégories en pénurie |
|---|---|---|---|---|---|---|---|
| no soy | 6-8 months | 60 | 0 | 1 | 98 | — | — |
| no sesame | 6-8 months | 59 | 1 | 1 | 98 | — | — |
| no milk + soy | 6-8 months | 51 | 9 | 1 | 98 | — | — |
| no peanuts + tree nuts + sesame | 6-8 months | 59 | 1 | 1 | 98 | — | — |
| no milk | 6-8 months | 52 | 9 | 0 | 98 | — | — |
| no eggs | 6-8 months | 52 | 9 | 0 | 98 | — | — |
| no peanuts | 6-8 months | 61 | 0 | 0 | 98 | — | — |
| no tree nuts | 6-8 months | 61 | 0 | 0 | 98 | — | — |
| no wheat and triticale | 6-8 months | 57 | 4 | 0 | 98 | — | — |
| no fish | 6-8 months | 59 | 2 | 0 | 98 | — | — |
| no crustaceans and molluscs | 6-8 months | 61 | 0 | 0 | 98 | — | — |
| no mustard | 6-8 months | 61 | 0 | 0 | 98 | — | — |

## The ingredients that block most often

Each line is a **missing substitution rule**. Writing one
often unlocks more recipes than writing a new one.

- **Ricotta** (`ricotta`) — bloque 54 fois
- **Tamari sauce** (`tamari`) — bloque 22 fois
- **Firm tofu** (`tofu`) — bloque 18 fois
- **Pita bread** (`pita`) — bloque 16 fois
- **Sesame seeds** (`sesame_seeds`) — bloque 16 fois
- **Walnuts** (`walnuts`) — bloque 12 fois

## Suggested commission for the next batch

- **2 meal** from 9 months — no milk + eggs + peanuts + tree nuts
    - pool: 42 meals still missing, youngest ages first
- **2 snack** from 12 months — no wheat and triticale
    - pool: 23 snacks still missing, youngest ages first
- **2 meal** from 24 months — no milk
    - pool: 40 meals still missing, youngest ages first
- **2 snack** from 6 months — no milk + eggs
    - pool: 21 snacks still missing, youngest ages first
- **2 meal** from 6 months — no milk + eggs + wheat and triticale
    - pool: 38 meals still missing, youngest ages first
- **2 snack** from 9 months — no peanuts + tree nuts
    - pool: 19 snacks still missing, youngest ages first
- **2 meal** from 9 months — no milk + eggs + peanuts + tree nuts
    - pool: 36 meals still missing, youngest ages first
- **2 snack** from 12 months — no wheat and triticale
    - pool: 17 snacks still missing, youngest ages first
- **2 meal** from 24 months — no milk
    - pool: 34 meals still missing, youngest ages first
- **2 snack** from 6 months — no milk + eggs
    - pool: 15 snacks still missing, youngest ages first

Ce fichier est régénéré par `node tools/gaps.js`. Il alimente
`generation/recipe-prompt.js`, qui transforme la commande en prompt contraint.
