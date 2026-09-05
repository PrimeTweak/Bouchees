# The recipe standard

Every recipe in the pool — written by hand, imported, or generated — meets
these seven rules. The validator enforces the ones a program can check; the
tasting protocol covers the rest.

## 1. Every ingredient is named in a step, with its preparation

"Mix all the ingredients" is not a step. The apple is *peeled and grated*,
the garlic *minced*, the lentils *drained*. The word used is the catalogue
name, so the engine can swap it in the text when it swaps the ingredient.

## 2. Preparation comes before cooking

Oven on, pan lined, vegetables cut — before anything touches heat. A parent
reads the step they are on, not the whole recipe.

## 3. Equipment and sizes are stated

A 23 × 13 cm loaf pan. A large bowl. A 12-cup muffin tin, lined. The size
decides the cooking time; leaving it out makes the time a guess.

## 4. Temperatures carry both units

200 °C (400 °F). Quebec ovens show either.

## 5. Every cooking step has a duration, and a doneness cue when one helps

"18 to 20 minutes, until browned on top and no pink remains in the centre."
The cue is what the parent trusts; the minutes are what the timer offers.

## 6. One action per step, six to ten steps, twenty words or fewer

Imperative, present tense. A step a parent can do with one hand on a child.

## 7. Yield in what a family eats, plus a keeping note

"Makes 20 meatballs · 4 family portions" rather than "1 loaf". How long it
keeps, and whether it freezes, in the last step or the servings line.

## Age

The engine adds the texture guidance per age. The recipe writes the dish
for the family; the last step says what changes for the youngest — mash,
quarter, cool — when it is not obvious.

## What no rule covers

Taste, rise, real texture. A recipe carries `cookedByAHuman: false` until
someone has made it. The tasting protocol: cook five, write down what was
wrong, and change the rule that let it through.
