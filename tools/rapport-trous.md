# Rapport de trous — 2026-09-12

Corpus: **210 recipes**. Thresholds: **12 usable recipes** per combination (enough for a week) and **6 par catégorie** (un parent ne sert pas que des soupers).

"Too old" = recipes whose minimum age is above the age being tested. They do not count.

## The 12 most starved combinations

| Profil | Âge | Telles quelles | Adaptées | Bloquées | Trop vieilles | Manque | Catégories en pénurie |
|---|---|---|---|---|---|---|---|
| no soy | 6-8 months | 76 | 0 | 1 | 133 | — | — |
| no sesame | 6-8 months | 75 | 1 | 1 | 133 | — | — |
| no milk + soy | 6-8 months | 67 | 9 | 1 | 133 | — | — |
| no peanuts + tree nuts + sesame | 6-8 months | 75 | 1 | 1 | 133 | — | — |
| no milk | 6-8 months | 68 | 9 | 0 | 133 | — | — |
| no eggs | 6-8 months | 68 | 9 | 0 | 133 | — | — |
| no peanuts | 6-8 months | 77 | 0 | 0 | 133 | — | — |
| no tree nuts | 6-8 months | 77 | 0 | 0 | 133 | — | — |
| no wheat and triticale | 6-8 months | 73 | 4 | 0 | 133 | — | — |
| no fish | 6-8 months | 75 | 2 | 0 | 133 | — | — |
| no crustaceans and molluscs | 6-8 months | 77 | 0 | 0 | 133 | — | — |
| no mustard | 6-8 months | 77 | 0 | 0 | 133 | — | — |

## The ingredients that block most often

Each line is a **missing substitution rule**. Writing one
often unlocks more recipes than writing a new one.

- **Ricotta** (`ricotta`) — bloque 120 fois
- **Tamari sauce** (`tamari`) — bloque 28 fois
- **Sesame seeds** (`sesame_seeds`) — bloque 22 fois
- **Firm tofu** (`tofu`) — bloque 18 fois
- **Whole wheat bread** (`bread`) — bloque 16 fois
- **Pita bread** (`pita`) — bloque 16 fois
- **Walnuts** (`walnuts`) — bloque 12 fois

## Suggested commission for the next batch

- **2 meal** from 6 months — no milk + eggs
    - pool: 15 meals still missing, youngest ages first
- **2 meal** from 6 months — no milk + eggs + wheat and triticale
    - pool: 13 meals still missing, youngest ages first
- **2 meal** from 9 months — no peanuts + tree nuts
    - pool: 11 meals still missing, youngest ages first
- **2 meal** from 9 months — no milk + eggs + peanuts + tree nuts
    - pool: 9 meals still missing, youngest ages first
- **2 meal** from 12 months — no wheat and triticale
    - pool: 7 meals still missing, youngest ages first
- **2 meal** from 24 months — no milk
    - pool: 5 meals still missing, youngest ages first
- **2 meal** from 6 months — no milk + eggs
    - pool: 3 meals still missing, youngest ages first
- **2 meal** from 6 months — no milk + eggs + wheat and triticale
    - pool: 1 meals still missing, youngest ages first

Ce fichier est régénéré par `node tools/gaps.js`. Il alimente
`generation/recipe-prompt.js`, qui transforme la commande en prompt contraint.
