# Source licences — checked 17 August 2026, revised 7 September 2026

Short verdict: **both consumer APIs considered forbid our storage model.**
The pipeline stays source-agnostic; the corpus grows with content we are
allowed to keep.

## Spoonacular (spoonacular.com/food-api/terms)

- No copying or storing of API data, **including derived or transformed
  data** — which is exactly what normalisation into the canonical catalogue is.
- Caching limited to one hour, and only with prior written permission.
- At the end of the subscription: deletion of everything obtained.
- Conclusion: incompatible with the architecture without a specific written
  agreement.

## Edamam (developer.edamam.com, edamam.com/terms/api)

- Human-triggered requests only; no collecting, harvesting or saving; display
  restricted to the user who made the request.
- Caching allowed only for a few macronutrients, in the end user's own
  account, behind a password.
- Attribution badge mandatory on every use.
- The recipe content belongs to the originating sites anyway (Edamam is an
  index) — so even an agreement would not settle the rights.
- Conclusion: incompatible with the architecture.

## Why we do not stream instead of storing

"Call the API live and display without storing" would comply with the terms,
but it is **incompatible with our safety model**: a recipe we cannot store
cannot go through quarantine, minimum-age curation and allergen re-derivation.
An uncurated recipe is a recipe we do not show.

## Sources compatible with the architecture

1. **In-house content**: drafted with AI assistance, validated by a human,
   stored and versioned (the current corpus).
2. **Freely licensed sources** (public domain, Creative Commons allowing
   modification) — the `generique` adapter takes them as they are.
3. **A direct licence agreement** with a content publisher (each source's
   `license` field records that right).

## The fixtures in `ingest/sources/`

`mealdb-fixture.json` and `spoonacular-fixture.json` are **templates written
by the team** in the shape of those APIs: they prove the adapters without
storing any third-party data. Their URLs point at `exemple.test`, their
`source` is `mealdb-demo` / `spoonacular-demo`, and their `license` field says
so in plain words.

Two rules follow from the September revision, both enforced in code:

- An adapter never invents a licence. The old default — "see the provider's
  terms" — labelled team-written templates as third-party data, and a legal
  audit nearly withheld four original recipes on that label alone.
- A document without a `license` field is quarantined by the importer, exactly
  like one without curation. No stated right to store, no import.
