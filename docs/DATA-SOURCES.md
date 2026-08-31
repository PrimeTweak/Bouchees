# Where the product data comes from

The scanner answers one question: does this package contain something the
child avoids. Answering it offline, for two countries, means carrying other
people's databases. Two of them, under two different licences, and the
difference between those licences decides the architecture.

This document is the record of what came from where. It is not legal advice.

## The two sources

### United States — USDA FoodData Central, Branded Foods

Public domain, CC0 1.0. USDA states that its food composition data are not
copyrighted and that no permission is needed to use them. They ask, as a
courtesy rather than a condition, to be named as the source.

About two million branded products, roughly 99% of them American, supplied by
the brands themselves through a public-private partnership and refreshed
monthly.

There is nothing to comply with here. The courtesy citation is included
anyway, in the manifest and in the app.

### Canada — Open Food Facts, filtered on Canada

ODbL 1.0. Two conditions: attribution, and share-alike.

Roughly 124,000 products carry a Canadian market tag. Far fewer carry a
complete ingredient list — the pack keeps only those, because an entry that
cannot answer an allergen question is weight.

## Why the files are never merged

The ODbL separates three things, and the whole design turns on which one we
are making.

A **derivative database** is one built by adapting, modifying or extending
theirs. Share-alike applies, and it reaches whatever was mixed in.

A **collective database** is a collection of otherwise independent databases
assembled together. The licence says plainly that this is not a derivative
database, and that share-alike touches only their part of the collection.

A **produced work** is the result of using the database. The licence says
that creating one does not create a derivative database. It needs a notice,
nothing more.

So:

- `products-us.jsonl.gz` and `products-ca.jsonl.gz` are separate files, one
  source per file, neither joined to the other.
- Neither is ever merged into `data/ingredients.json`, `data/substitutions.json`
  or any other table of ours. The engine READS the ingredient text at run time
  and matches it against our catalogue in memory. Nothing is written back.
- The verdict on screen — "contains milk, avoid for this child" — is a
  produced work. It carries a notice. It is not a database.

A country cut helps here: Canadian records come entirely from Open Food Facts,
American records entirely from USDA, with no overlap and no field of one
filled from the other. The OpenStreetMap Foundation, which has lived under
this licence for years, treats two datasets combined this way as independent
so long as a given data type in a given regional cut comes wholly from one
source. That is their reading for their data, not a rule binding on Open Food
Facts — it is the reasoning to have reviewed, not a conclusion to rely on.

`tools/check-pack.js` refuses a pack that breaks any of this. The rule lives
in a checker rather than in someone's memory, for the same reason
`check-repo.js` exists.

## Why the pack derives nothing

The pack carries the ingredient text as printed and works out no allergens.

Precomputing them at build time would make the file far smaller. It would
also freeze the reading: the day the lexicon improves, every product in the
pack keeps the old answer until the next monthly rebuild. On a path where the
output is "safe for your child", a frozen reading is worse than a large file.

It is also cleaner under the licence. A file of our conclusions about their
data is a harder thing to classify than a copy of their text sitting beside
our catalogue.

## What this does not fix

Coverage. Roughly four in five Canadian entries in Open Food Facts have no
ingredient list at all. They are dropped by the builder, so a Canadian product
can be genuinely absent from the pack while existing in the database.

No free or small-company source fixes this. GS1 Canada's certified pool and
the syndication networks that feed the large chains are priced for
enterprises. The licence is not the obstacle; the Canadian data is.

## Notices that must appear

In the app, wherever data from a source is shown:

- Canadian record — "Contains information from Open Food Facts, which is made
  available here under the Open Database License (ODbL)."
- American record — "Data from USDA FoodData Central."

In `pack/manifest.json`, both notices travel with the files, so a pack that is
copied somewhere else still says what it is.

## Rebuilding

`PAQUET.command`, once a month. It wants the USDA CSV from
`fdc.nal.usda.gov/download-datasets` — the address carries the month, so it is
not guessed — and downloads the Open Food Facts dump itself.

The pack is not committed. It is published as a GitHub Release asset and
fetched by the app on first launch.
