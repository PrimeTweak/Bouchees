# Bouchées

Recipes adapted to a child's food allergies and age.

The substitution engine is deterministic: versioned tables decide every swap,
never a language model. An AI writes and illustrates; the tables decide.

**Bouchées is not medical advice.** The swap tables and age guidance are a
starting point and must be reviewed by a professional before real use. For a
diagnosed allergy, the allergist's plan always takes precedence.

## Layout

    engine/         The substitution engine (JavaScript) and its native bridge
    data/           Allergen families, ingredients, substitutions, recipes
    ingest/         Importing external recipes: lexicon, normalizer, adapters
    generation/     Recipe and image generation, vision check, coherence check
    tools/          Gap report, publishing, rolling weeks, the monthly cycle
    server/         API, entitlements, ratings, Stripe and Apple verification
    ios/            The native SwiftUI app
    web/            The web build of the same engine
    tests/          103 tests — `node tests/test.js`

## Everyday commands

    node tests/test.js                    103 tests, run before every push
    node tools/gaps.js                    where recipes are missing
    node tools/cycle.js                   the full monthly cycle
    node tools/weeks.js                   rolling-window status
    node tools/publish.js                 write dist/ for the server
    node server/server.js                 run the API locally

## What the engine guarantees

An adapted recipe never contains an avoided allergen. Allergens are derived
from the ingredient catalogue, never read from external labels. When no safe
substitute exists the recipe is marked `non_adaptable` with a blocking
alert — never a silent removal.

Verified on thousands of profile × age combinations by the test suite.

## Language

The codebase, file names and base UI strings are English. French is a
translation (`ios/App/App/Localization/fr.lproj`).

Recipe content and safety messages are still French — see `README-fr.md`
for why, and what it would take to change.
