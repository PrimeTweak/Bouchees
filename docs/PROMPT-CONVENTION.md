# Photo prompt convention

Every recipe photo is built from the same seven parts, in the same order.
This document says what each part is for and — more usefully — what went
wrong when it was written differently.

`tools/check-prompts.js` enforces it. A rule nobody checks drifts within
two months, and every rule below exists because something drifted.

---

## The seven parts, in order

```
1  the dish            Homemade banana oat muffins, cooked and ready to eat
2  the presentation    three muffins in paper liners, close together
3  the ingredients     made with wheat flour, rolled oats, cow's milk
4  the framing         low eye-level, close enough to see the crumb
5  the surface         on a light concrete counter, the warm blur of a kitchen behind
6  the light           warm light raking across from the left, deep soft shadows
7  the style           candid home photo, handheld, 85mm macro
```

Under 500 characters, total. Krea and FLUX both stop reading long before
that; a prompt that overruns silently loses its last clauses, and the last
clause is the style.

---

## 1 · The dish

States the dish by NAME, then that it is cooked and ready.

**Measured:** a prompt built only from ingredients produced a bowl of raw
ingredients. The model draws what is named; "wheat flour, oats, milk"
without "muffins" is a picture of flour, oats and milk.

## 2 · The presentation — with a COUNT

`three muffins`, not `muffins`.

**Measured:** "cooling on a wire rack" produced a whole rack — twelve
muffins, each too small to see. A recipe photo has two jobs: make someone
want to cook it, and show what it looks like when it worked. Twelve tiny
muffins do neither.

The count is small everywhere. Nobody needs to see a whole batch; they need
to see one, properly.

## 3 · The ingredients

The four most visible, so the model draws the right dish rather than a
generic one. Never more than four — beyond that the model starts placing
each one as a separate object on the plate.

## 4 · The framing — WITH A DISTANCE

Every framing states how far the camera stands, and every one is close.

**Measured:** nothing used to say the distance, so the model chose whatever
showed everything the prompt named — and the prompt named furniture. The
result was a beige room with twelve small muffins in it.

## 5 · The surface — WITHOUT NAMING FURNITURE AS A SUBJECT

A surface plus what falls away behind it. `on a honed marble counter, warm
wood cabinetry blurred behind`.

**Measured, twice, in opposite directions:**

- Naming "worn wooden table, one corner visible" pulled the camera back to
  include the corner, and the room came with it.
- Then removing all furniture AND adding `no wall, no furniture` left
  nothing to put behind the dish, so the model invented the one background
  not forbidden: a flat grey windowsill.

The close framing in part 4 is what stops the room. With a distance stated,
a surface can be named safely — and it has to be, or the background is
whatever the model has left.

## 6 · The light — WARM AND DIRECTIONAL, ALWAYS

The three variants differ by ANGLE, never by colour temperature.

**Measured:** two of the three used to ask for cool diffuse light — a
morning window, an overcast afternoon — while the style line asked for warm
directional light two clauses later. The model received opposite
instructions and produced the flat grey windowsill.

A kitchen that reads as professional is LIT, not merely daylit.

## 7 · The style

`candid home photo, handheld` — this is a parent's kitchen, not a magazine.
`85mm macro, shallow depth of field` — the background falls away without
being named as absent.

One imperfection, and it usually shows the inside: `one broken open so the
crumb shows`. It earns its place twice — it says a person was here, and it
is the only way to show the crumb, which is what tells a parent whether
their own batch came out right.

---

## The negatives

They ban the WIDE SHOT and STUDIO LIGHTING, which are the real faults.

They must never ban the background itself. `no wall`, `no furniture` and
`no window frame` were removed after they emptied the frame — that is the
second measurement in part 5.

Allergen exclusions are stated positively in the prompt as well as
negatively, because FLUX schnell is distilled without negative guidance and
Draw Things ends up SUBTRACTING the negative rather than steering away from
it. Proven by isolation: identical request, with the negative an embossed
relief, without it a clean photo.

---

## Determinism

Framing, surface, light and imperfection are all chosen from the recipe's
id. The same recipe always produces the same prompt, so a parent reopening
a recipe sees the same picture and a regenerated corpus is comparable to
the previous one.

Never make any of them random.

---

## When a new recipe arrives

Nothing to do. The prompt is built from the recipe, and the convention
applies automatically.

What is worth doing: run `node tools/check-prompts.js` after changing
anything in `generation/images.js`. It reads every recipe in the corpus and
verifies the seven parts, the length, and — the check that would have
caught the light contradiction — that the positive and the negative do not
ask for opposite things.

---

## What this convention cannot do

It cannot tell you whether the photo is good. It can tell you the prompt is
well-formed, deterministic and free of contradictions. Whether the result
looks like a professional kitchen is a judgement, and it stays with the
person looking at it.
