# Publishing Bouchées on the App Store

Everything in the code is done (build 192). What remains lives on Render, in
Draw Things and in App Store Connect, and nobody can do it in your place.
This file replaces the older `ios/APP-STORE-REVIEW.md`, which described a
test account, a collected e-mail and a `ContenuLocal.swift` that no longer
exist.

## 1. Render — three environment variables

    BOUCHEES_CONTACT          your real e-mail address (the legal pages show it)
    BOUCHEES_PRIVACY_OFFICER  your name, e.g. "François Lévesque, founder"
    BOUCHEES_ADMIN_SECRET     the same phrase as in cle-api.txt

Without BOUCHEES_CONTACT the pages show bonjour@bouchees.ca — make sure that
address exists, or set the variable.

## 2. Draw Things — one question to settle BEFORE submitting

Open Draw Things and read the name of the selected model.
  - FLUX.1 [schnell], SDXL, SD 1.5: commercial use permitted. Nothing to do.
  - FLUX.1 [dev]: NON-commercial. The 55 photos must be regenerated with
    [schnell] — PHOTOS.command does it, one night on the Mac.

## 3. App Store Connect — the app

  - Privacy Policy URL: https://bouchees.onrender.com/privacy
  - Support URL: https://bouchees.onrender.com/terms (or your own site)
  - Description: end it with this line — Apple requires it for a
    subscription that uses the standard EULA:
      Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
    (or put https://bouchees.onrender.com/terms in the EULA field)
  - App Privacy questionnaire: "Data Not Collected" for everything. The app
    has no account, no analytics, no identifier; purchases are Apple's. Do
    NOT tick "Health & Fitness": a parent's stated food preference is not a
    health record, and the tick invites a heavier review for nothing.
  - Age rating 4+. Primary category Food & Drink, secondary Lifestyle.
    Do NOT submit to the Kids category — the app is for parents. Never
    write "for children" in the title, subtitle or screenshots; write "for
    parents" or "for the family".
  - Screenshots: iPhone 6.7" and 6.1" (iPhone only). Put the scanner and
    the offline mode in the FIRST TWO: a reviewer looks at screenshots
    before opening the app, and those two cannot be a website.

## 4. App Store Connect — the subscription

  - One subscription group.
  - Products, with exactly these identifiers:
      ca.bouchees.abo.mensuel   (1 month)
      ca.bouchees.abo.annuel    (1 year)
  - Introductory offer: 7 days free on each — the app says so.
  - Each product needs a review screenshot (the app's paywall is enough)
    and must be SUBMITTED together with the binary — a pending IAP not
    attached to the build rejects the build.
  - Product localisations: French and English.

## 5. Review notes — paste into App Store Connect

    What the app does
    Bouchées adapts recipes to a child's food allergies and age. The
    adaptation engine is deterministic: versioned tables decide every
    substitution, never a language model.

    No account
    No sign-in exists and none is required; the free tier is fully usable.
    The subscription is StoreKit 2, with Restore Purchases on the same
    screen, visible without subscribing.

    Five-step walkthrough
    1. On first launch, tap an allergen in the demo and watch the recipe
       adapt; then enter a first name and an age (try 9 months) and tick
       Milk and Eggs.
    2. Recipes tab: the week, one meal and one snack a day. Open a recipe:
       every replaced ingredient is named, with the reason.
    3. Scan tab: point at any packaged food barcode. The app reads the
       ingredient list and returns a verdict. Test codes: [three common
       Canadian products you have verified yourself in Open Food Facts].
    4. Family tab → gear → Subscription: in-app purchase, two durations,
       Restore Purchases beside them.
    5. Put the device in airplane mode and reopen: everything already
       downloaded stays usable. That is the main use case — checking a
       recipe in a grocery aisle, often without signal.

    Native, not a website
    Camera barcode reading (AVFoundation), full offline use, profiles
    stored on the device, StoreKit 2, haptics. No web view.

    Medical content
    The app shows a notice on the week, in About and in the Terms: it is
    not medical advice and an allergist's plan takes precedence. Allergen
    tables follow Health Canada's priority allergen list.

    Product data
    Open Food Facts (ODbL) is consulted at scan time; attribution is shown
    on every product sheet.

Pick three real Canadian barcodes, verify them in Open Food Facts the day
you submit, and put them in the notes. A scanner that finds nothing during
review reads as a broken scanner.

## 6. The three likely rejections, and the answer

  - 4.2 Minimum functionality — the classic risk for an app that looks
    like a site. The answer is a demonstration, not an argument: the
    scanner and offline mode in the first two screenshots and in the notes.
  - 3.1.1 In-app purchase — no path to a web checkout anywhere. The iOS
    button calls StoreKit, never Stripe (coded; test it on the device), and
    no text says "cheaper on our site". Restore must be visible unsubscribed.
  - 1.4.1 Physical safety — an allergy app touches safety. What helps: the
    notices, no promise of diagnosis, and "read the label" whenever an
    ingredient is not recognised. Never write "guaranteed allergen-free"
    anywhere — not in the app, not on the store page.

## 7. The binary

  - A Release build signed with your distribution profile (ipa.yml builds;
    App Store signing needs a distribution certificate and an App Store
    provisioning profile, not ad hoc).
  - Version 1.0.0 (1) — ios/project.yml.
  - TestFlight first: install, open the scanner, buy in the sandbox,
    restore, airplane mode. If one fails, the cause is in App Store Connect.

## 8. Before every submission

  - [ ] node tests/test.js passes in full
  - [ ] The in-app purchases are submitted WITH the version
  - [ ] Prices and durations shown match App Store Connect
  - [ ] Airplane mode: the app opens and stays usable
  - [ ] The camera text says exactly what the camera is for
  - [ ] No web payment link in the app
  - [ ] Screenshots show the scanner and offline use
  - [ ] The medical notice is visible on the week without scrolling
  - [ ] Open Food Facts attribution is visible on the product sheet
  - [ ] The three test barcodes in the notes resolve today
