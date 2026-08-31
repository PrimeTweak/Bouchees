#!/usr/bin/env python3
"""Static checker for the Swift sources.

This is NOT a compiler. It catches the class of mistakes that costs a full
build each time: a symbol referenced but never defined, a type declared twice,
a missing colour asset, unbalanced delimiters, StoreKit identifiers that do
not line up.

What it cannot catch: overload ambiguity, actor isolation, changed API
signatures, type inference. Those come out of the build, and that is fine.
"""
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "ios", "App", "App")
ROOT = os.path.abspath(ROOT)

# Symbols provided by the frameworks — never reported as missing.
CONNUS = set("""
View Text Image Button Color Path Canvas GraphicsContext Circle Rectangle Capsule
RoundedRectangle LinearGradient ScrollView VStack HStack ZStack LazyVGrid LazyVStack
GridItem Spacer Divider List Section NavigationStack TabView Toggle TextField Link
Label ProgressView Alert Group Binding State StateObject ObservedObject Environment
EnvironmentObject FocusState App Scene WindowGroup ToolbarItem Namespace ViewBuilder
UIView UIColor UIScreen UIApplication UIViewRepresentable UINotificationFeedbackGenerator
AVCaptureSession AVCaptureDevice AVCaptureDeviceInput AVCaptureMetadataOutput
AVCaptureMetadataOutputObjectsDelegate AVMetadataObject AVMetadataMachineReadableCodeObject
AVCaptureVideoPreviewLayer AVCaptureConnection AVCaptureOutput
Product AppStore VerificationResult StoreKit
JSContext JSValue
URL URLRequest URLSession URLComponents URLQueryItem HTTPURLResponse URLResourceValues
Data Date UUID Bundle FileManager JSONDecoder JSONEncoder UserDefaults ProcessInfo
Decoder Encoder Encodable Decodable Codable Hashable Identifiable Sendable Equatable
LocalizedError Error Task Dictionary Set Array String Int Double Bool CGFloat CGPoint
CGRect CGSize CGAffineTransform NSObject AnyClass StrokeStyle Angle EdgeInsets
Observation Observable ObservationIgnored MainActor discardableResult unknown
CustomStringConvertible Comparable Collection Sequence Optional Result
ForEach Void Self Any AnyView UTF8 Context Never Character Float Range ClosedRange
Calendar Locale Notification NotificationCenter Timer DispatchQueue Bundle
""".split())

def swift_files():
    out = []
    for base, _, noms in os.walk(ROOT):
        for n in sorted(noms):
            if n.endswith(".swift"):
                out.append(os.path.join(base, n))
    return out

def strip_strings_and_comments(src):
    """Strip strings and comments so prose is never analysed as code."""
    src = re.sub(r'"""(?:.|\n)*?"""', '""', src)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    src = re.sub(r'//[^\n]*', '', src)
    src = re.sub(r'/\*(?:.|\n)*?\*/', '', src)
    return src

def check():
    problems = []
    warnings = []
    files = swift_files()
    if not files:
        return ["no Swift file found under " + ROOT], []

    # A dropped folder is the classic Finder accident: dragging one folder onto
    # another replaces it whole instead of merging. The project has a known
    # floor of source files — fewer than that means something was wiped, and
    # the build would fail thirty minutes later with a confusing error.
    MINIMUM_SOURCES = 12
    if len(files) < MINIMUM_SOURCES:
        return ([f"only {len(files)} Swift file(s) found, expected at least "
                 f"{MINIMUM_SOURCES} — a folder was probably replaced instead of merged"], [])

    definitions = {}   # name -> [files]
    sources = {}

    for path_ in files:
        raw = open(path_, encoding="utf-8").read()
        code = strip_strings_and_comments(raw)
        sources[path_] = (raw, code)
        filename = os.path.basename(path_)

        # 1. balanced delimiters
        for opening, closing, label in [("{", "}", "braces"),
                                        ("(", ")", "parentheses"),
                                        ("[", "]", "brackets")]:
            a, b = code.count(opening), code.count(closing)
            if a != b:
                problems.append(f"{filename}: unbalanced {label} ({a} vs {b})")

        # 2. type declarations
        for m in re.finditer(
                r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public |private |internal |fileprivate )?'
                r'(?:final )?(struct|class|enum|actor|protocol|typealias)\s+(\w+)', code, re.M):
            definitions.setdefault(m.group(2), []).append(filename)

    # 3. doublons de type
    for name, places in sorted(definitions.items()):
        if len(places) > 1:
            problems.append(f"type “{name}” declared {len(places)} times: {', '.join(places)}")

    # 4. types used but never defined
    definis = set(definitions) | CONNUS
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        candidates = set()
        # annotation de type explicite  ": Type" ou "-> Type"
        for m in re.finditer(r'(?::\s*|->\s*)\[?([A-Z]\w+)', code):
            candidates.add(m.group(1))
        # appel de constructeur  Type(
        for m in re.finditer(r'\b([A-Z]\w+)\s*\(', code):
            candidates.add(m.group(1))
        for c in sorted(candidates):
            if c not in definis and not c.startswith(("NS", "UI", "CG", "CA", "AV", "SK", "JS")):
                warnings.append(f"{filename}: “{c}” used but not defined in the project")

    # 5. couleurs d'assets
    assets = os.path.join(ROOT, "Assets.xcassets")
    existing = set()
    if os.path.isdir(assets):
        existing = {d[:-len(".colorset")] for d in os.listdir(assets) if d.endswith(".colorset")}
    for path_, (raw, _) in sources.items():
        for m in re.finditer(r'Color\("([^"]+)"\)', raw):
            if m.group(1) not in existing:
                problems.append(f"{os.path.basename(path_)} : asset couleur « {m.group(1)} » absent")

    # 6. StoreKit identifiers line up
    sk = os.path.join(ROOT, "Bouchees.storekit")
    if os.path.exists(sk):
        d = json.load(open(sk, encoding="utf-8"))
        groupes = d.get("subscriptionGroups", [])
        ids_sk = {s["productID"] for g in groupes for s in g.get("subscriptions", [])}
        ids_swift = set()
        for _, (raw, _) in sources.items():
            ids_swift |= set(re.findall(r'"(ca\.bouchees\.[a-z.]+)"', raw))
        ids_swift = {i for i in ids_swift if i.startswith("ca.bouchees.abo")}
        if ids_sk != ids_swift:
            problems.append(f"StoreKit identifiers diverge — .storekit {sorted(ids_sk)} "
                          f"vs Swift {sorted(ids_swift)}")

    # 7. ambiguous trigonometry — CoreGraphics and the standard library each
    #    expose cos/sin/tan. Mixed with CGPoint they break the build. This is
    #    the mistake that cost a full build.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        for m in re.finditer(r'(?<![\w.])(cos|sin|tan|atan2)\s*\(', code):
            line = code[:m.start()].count("\n") + 1
            problems.append(f"{filename}:{line}: bare “{m.group(1)}(” — ambiguous between "
                          f"CoreGraphics and the standard library; use a typed wrapper")

    # 7b. an optional property called without unwrapping it.
    #     Not a general type check — the checker has no compiler — but this
    #     exact shape cost a build. Scanned line by line: a call on an optional
    #     with no guard, if let, ?. or !. in the twelve lines above it.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        lignes = code.split("\n")
        # Only optionals declared at the top of a type, and only names that are
        # never re-declared as a non-optional elsewhere in the file — a `let x:
        # T` parameter in another struct shadows the property and is not the
        # same variable. Scope is what a real compiler tracks and this cannot.
        optionnels = set(re.findall(r"(?:private\s+)?var\s+(\w+)\s*:\s*\w+\?", code))
        redeclares = set(re.findall(r"\blet\s+(\w+)\s*:\s*\w+(?!\?)", code))
        optionnels -= redeclares
        for nom in optionnels:
            for i, l in enumerate(lignes):
                if not re.search(r"(?<![\w.?!])" + nom + r"\.\w", l):
                    continue
                if re.search(r"(?:guard|if)\s+let\s+" + nom + r"\b", l):
                    continue
                if re.search(r"\b" + nom + r"[?!]\.", l):
                    continue
                # a guard in the surrounding lines counts
                contexte = "\n".join(lignes[max(0, i - 12):i + 1])
                if re.search(r"(?:guard|if)\s+let\s+" + nom + r"\b", contexte):
                    continue
                if re.search(r"\bself\." + nom + r"\s*=", contexte):
                    continue
                problems.append(f"{filename}:{i + 1}: '{nom}' is optional and is called "
                                f"as '{nom}.…' with no guard let, if let, ?. or !")

    # 7c. a style ternary whose two branches are different types.
    #     `on ? Color(.systemBackground) : .secondary` asks the compiler to
    #     unify a Color with a HierarchicalShapeStyle. It refuses, and the
    #     error it emits points at the whole expression rather than the line —
    #     which is why a build can fail with nothing useful in the log.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        for i, l in enumerate(code.split("\n"), 1):
            m = re.search(r"\.(foregroundStyle|background|tint|fill)\((\w+) \? ([^:]+) : (\.[a-z]\w*)", l)
            if m and "Color" in m.group(3):
                problems.append(f"{filename}:{i}: style ternary mixes '{m.group(3).strip()}' "
                                f"with '{m.group(4)}' — give both branches the same type")

    # 7d. a `-> some View` whose body is an `if` with no `else` and no `return`.
    #     That only compiles under @ViewBuilder, and the error Swift emits —
    #     "no return statements in its body" — points at the declaration
    #     without saying the attribute is what is missing.
    #
    #     It cost a build: an insertion landed between an @ViewBuilder line and
    #     the func below it, silently moving the attribute onto the wrong
    #     function. Nothing in the diff looked wrong.
    #
    #     Signatures wrap, so the `func` line and the `-> some View` line are
    #     often different lines: the search starts from `func`, not from the
    #     return type.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        lignes = code.split("\n")
        for i, l in enumerate(lignes):
            if not re.search(r"\bfunc\s+\w+", l):
                continue
            # gather the declaration up to its opening brace
            decl, j = l, i
            while "{" not in decl and j + 1 < len(lignes) and j - i < 5:
                j += 1
                decl += " " + lignes[j]
            if "-> some View" not in decl:
                continue
            avant = [x.strip() for x in lignes[max(0, i - 6):i]]
            if any(x.startswith("@ViewBuilder") for x in avant):
                continue
            indent = len(l) - len(l.lstrip())
            corps = []
            for k in range(j + 1, min(j + 60, len(lignes))):
                if lignes[k].strip() == "}" and (len(lignes[k]) - len(lignes[k].lstrip())) == indent:
                    break
                corps.append(lignes[k])
            texte = "\n".join(corps)
            if not texte.strip():
                continue
            if re.search(r"^\s*return\b", texte, re.M):
                continue
            premier = next((x for x in corps if x.strip()), "")
            if re.match(r"\s*(if|switch)\b", premier):
                problems.append(f"{filename}:{i + 1}: '-> some View' with an if/switch body and "
                                f"no return — it needs @ViewBuilder directly above the func")

    # 7e. a View initialised with an argument label its struct does not declare.
    #     SwiftUI memberwise inits take the stored property names exactly, so
    #     `AllergenGlyph(id:)` against `let identifier: String` fails — and the
    #     error names the parameter it wanted, not the file that called it
    #     wrongly.
    #
    #     Only structs whose stored properties are ALL simple `let name: Type`
    #     are checked, and only calls that use labels for every argument, so a
    #     custom init or a positional call is left alone.
    struct_fields = {}
    struct_defaults = {}
    for path_, (_, code) in sources.items():
        for m in re.finditer(r"struct (\w+): View \{((?:.|\n)*?)\n\}", code):
            nom, corps = m.group(1), m.group(2)
            if re.search(r"\binit\s*\(", corps):
                continue          # a custom init changes the labels
            # Property wrappers count as init parameters too — @Binding, @State
            # with no default, @Environment — and `var body: some View` is not
            # a field at all. Missing either produces false positives, and a
            # checker that cries wolf gets ignored.
            # `var compact = false` has no type annotation and is still an init
            # parameter, so the colon cannot be required.
            champs = set(re.findall(
                r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:private\s+)?(?:let|var)\s+(\w+)\s*[:=]",
                corps, re.M))
            champs.discard("body")
            # A stored property with a default value makes its argument
            # optional at the call site.
            defauts = set(re.findall(
                r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:private\s+)?var\s+(\w+)\s*(?::[^=\n]+)?=",
                corps, re.M))
            # A property wrapper supplies its own value too.
            enveloppes = set(re.findall(
                r"^\s*@(?:State|Environment|FocusState|AppStorage)\b[^\n]*\b(?:var)\s+(\w+)",
                corps, re.M))
            champs -= enveloppes
            # A computed property is not an init parameter. It is followed by
            # `{` on its own line or the next — the same distinction the
            # ViewBuilder rule already makes. Without it, `private var
            # shortVerdict: String { … }` looks like a missing argument.
            lignes_corps = corps.split("\n")
            calculees = set()
            for idx, lc in enumerate(lignes_corps):
                mm = re.match(r"\s*(?:private\s+)?var\s+(\w+)\s*:", lc)
                if not mm:
                    continue
                suite = lc[mm.end():].strip()
                suivante = (lignes_corps[idx + 1] if idx + 1 < len(lignes_corps) else "").strip()
                if suite.endswith("{") or suivante.startswith("{"):
                    calculees.add(mm.group(1))
            champs -= calculees
            if champs:
                struct_fields[nom] = champs
                struct_defaults[nom] = defauts & champs

    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        for i, l in enumerate(code.split("\n"), 1):
            for m in re.finditer(r"\b([A-Z]\w+)\(([^()]*)\)", l):
                nom, args = m.group(1), m.group(2)
                if nom not in struct_fields or not args.strip():
                    continue
                labels = re.findall(r"(?:^|,)\s*(\w+)\s*:", args)
                if len(labels) != len([a for a in args.split(",") if a.strip()]):
                    continue      # a positional argument: not a memberwise init
                inconnus = [x for x in labels if x not in struct_fields[nom]]
                if inconnus:
                    attendus = ", ".join(sorted(struct_fields[nom]))
                    problems.append(f"{filename}:{i}: {nom}({inconnus[0]}:) — that struct "
                                    f"declares no '{inconnus[0]}'  (it has: {attendus})")


                # The "missing argument" half of this rule was tried and
                # removed: telling a stored property from a computed one
                # without a parser produced four false positives across three
                # attempts. A checker that cries wolf gets ignored, and the
                # compiler names this case clearly anyway.
                #
                # What stays is the half that works: a label the struct does
                # not declare, which the compiler reports without saying
                # where the wrong call lives.
    # 7f. a call whose argument labels do not match the function it calls.
    #     `pairFor(id)` against `func pairFor(pour id: String)` fails, and the
    #     error names the label it wanted without saying where the wrong call
    #     lives. Two builds went on that this evening.
    #
    #     Only same-file and cross-file functions with simple signatures are
    #     compared, and only calls with the same number of arguments — enough
    #     to catch a rename, cheap enough to stay quiet otherwise.
    signatures = {}
    for path_, (_, code) in sources.items():
        for m in re.finditer(r"func (\w+)\(([^)]*)\)", code):
            nom, params = m.group(1), m.group(2)
            if not params.strip():
                continue
            etiquettes = []
            ok = True
            for p_ in [x.strip() for x in params.split(",") if x.strip()]:
                mm = re.match(r"(\w+|_)\s+\w+\s*:", p_) or re.match(r"(\w+)\s*:", p_)
                if not mm:
                    ok = False
                    break
                etiquettes.append(mm.group(1))
            if ok and nom not in signatures:
                signatures[nom] = etiquettes

    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        for i, l in enumerate(code.split("\n"), 1):
            # Only calls on `etat` — the app's own state object. Without that
            # anchor the rule matches JSONEncoder().encode(x) against a
            # same-named project function and cries wolf. The receiver has to
            # be one we can actually resolve.
            for m in re.finditer(r"\betat\.(\w+)\(([^()]*)\)", l):
                nom, args = m.group(1), m.group(2)
                if nom not in signatures or not args.strip():
                    continue
                attendues = signatures[nom]
                donnees = [x.strip().split(":")[0].strip() if ":" in x else "_"
                           for x in args.split(",") if x.strip()]
                if len(donnees) != len(attendues):
                    continue
                for d, at in zip(donnees, attendues):
                    if at == "_" or d == at:
                        continue
                    problems.append(f"{filename}:{i}: {nom}({d}:) — that function expects "
                                    f"'{at}:'  (full labels: {', '.join(attendues)})")
                    break

    # 7g. a Sendable struct holding a non-Sendable SwiftUI type.
    #     LocalizedStringKey, Image, Font, AnyView and friends are not
    #     Sendable. Declaring the struct Sendable is a warning under Swift 5
    #     and an ERROR under Swift 6 — worth fixing before the language mode
    #     moves rather than after.
    # Only types the compiler actually refuses. Color and Font ARE Sendable
    # since iOS 17 — listing them produced a false positive on DishArtwork,
    # which has compiled cleanly all along. The list is what the build log
    # named, not what I assumed.
    NON_SENDABLE = ["LocalizedStringKey", "AnyView", "UIImage", "UIColor"]
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        for m in re.finditer(r"struct (\w+)[^{]*\bSendable\b[^{]*\{((?:.|\n)*?)\n\}", code):
            nom, corps = m.group(1), m.group(2)
            ligne = code[:m.start()].count("\n") + 1
            for t in NON_SENDABLE:
                mm = re.search(r"^\s*(?:let|var)\s+(\w+)\s*:\s*" + t + r"\b", corps, re.M)
                if mm:
                    problems.append(f"{filename}:{ligne}: struct {nom} is Sendable but stores "
                                    f"'{mm.group(1)}: {t}', which is not — a warning now, "
                                    f"an error in Swift 6")
                    break

    # 7h. a member called on a project enum that the enum does not declare.
    #     Rewriting Tone.swift renamed six tokens and left twenty call sites
    #     pointing at names that no longer existed — twenty-one compile errors
    #     from one edit. This finds them in a second.
    #
    #     Only enums used as namespaces (Tone, Layout, Type) are checked, and
    #     only static members, so an instance property on a struct is left
    #     alone.
    namespaces = {}
    for path_, (_, code) in sources.items():
        for m in re.finditer(r"enum (\w+) \{((?:.|\n)*?)\n\}", code):
            nom, corps = m.group(1), m.group(2)
            membres = set(re.findall(
                r"^\s*(?:public\s+)?static\s+(?:let|var|func)\s+(\w+)", corps, re.M))
            # a case is a member too
            for c in re.findall(r"^\s*case\s+([\w,\s]+)", corps, re.M):
                membres |= {x.strip().split("(")[0] for x in c.split(",") if x.strip()}
            if membres:
                namespaces[nom] = namespaces.get(nom, set()) | membres

    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        for i, l in enumerate(code.split("\n"), 1):
            for m in re.finditer(r"\b([A-Z]\w+)\.(\w+)\b", l):
                ns, membre = m.group(1), m.group(2)
                if ns not in namespaces or membre in namespaces[ns]:
                    continue
                # `self` and type-level things are not members
                if membre in ("self", "Type", "init", "allCases"):
                    continue
                proches = sorted(namespaces[ns])[:6]
                problems.append(f"{filename}:{i}: {ns}.{membre} — that namespace has no "
                                f"'{membre}'  (it has: {', '.join(proches)}…)")
                break

    # 7i. strokeBorder on a type-erased shape.
    #     `strokeBorder` lives on InsettableShape. AnyShape erases that
    #     conformance, so the call fails to compile — and the error names the
    #     member, not the erasure that caused it. `stroke` is the fix.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        lignes = code.split("\n")
        # names bound to AnyShape in this file
        erased = set(re.findall(r"(?:var|let)\s+(\w+)\s*:\s*AnyShape", code))
        erased |= set(re.findall(r"(\w+)\s*=\s*AnyShape\(", code))
        for i, l in enumerate(lignes, 1):
            m = re.search(r"\b(\w+)\.strokeBorder\b", l)
            if m and m.group(1) in erased:
                problems.append(f"{filename}:{i}: {m.group(1)}.strokeBorder — that value is "
                                f"AnyShape, which erases InsettableShape; use stroke instead")

    # 7j. a `some View` property passed where a ShapeStyle is required.
    #     A gradient IS a ShapeStyle, but `some View` erases that: the opaque
    #     type only promises View. AnyShapeStyle(x), .fill(x) and .background(x,
    #     in:) all reject it, and the error talks about conformance rather than
    #     about the declaration that caused it.
    #
    #     Third build lost to opaque types this evening, after AnyShape and
    #     strokeBorder. Worth a rule.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        opaques = set(re.findall(r"(?:var|let)\s+(\w+)\s*:\s*some View", code))
        if not opaques:
            continue
        for i, l in enumerate(code.split("\n"), 1):
            # `context.fill(path, with:)` inside a Canvas takes a Path, not a
            # style — and a local named `body` there is not the view's body.
            if "context.fill" in l or "with:" in l:
                continue
            for m in re.finditer(r"(?:AnyShapeStyle|\.fill)\(\s*(\w+)\s*[,)]", l):
                if m.group(1) in opaques:
                    problems.append(f"{filename}:{i}: '{m.group(1)}' is declared 'some View', "
                                    f"which erases ShapeStyle — give it its concrete type "
                                    f"(LinearGradient, Color…)")

    # 7k. two declarations of the same property in one type.
    #     I added `var currentWeek: [Recipe]` to a class that already had
    #     `private(set) var currentWeek: String?`. Swift reports it as an
    #     invalid redeclaration plus three follow-on errors from the
    #     Observation macro, none of which name the collision plainly.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        # split into top-level type bodies
        for m in re.finditer(r"^(?:final\s+)?(?:public\s+)?(?:class|struct|enum|actor)\s+(\w+)[^\{]*\{",
                             code, re.M):
            debut = m.end()
            prof, fin = 1, len(code)
            for i in range(debut, len(code)):
                if code[i] == "{": prof += 1
                elif code[i] == "}":
                    prof -= 1
                    if prof == 0: fin = i; break
            corps = code[debut:fin]
            # only declarations at this type's own level, not nested ones
            vus = {}
            for d in re.finditer(r"^    (?:@\w+(?:\([^)]*\))?\s+)*"
                                 r"(?:private\(set\)\s+)?(?:private\s+|public\s+)?"
                                 r"(?:static\s+)?(?:var|let)\s+(\w+)\b", corps, re.M):
                nom = d.group(1)
                ligne = code[:debut + d.start()].count("\n") + 1
                if nom in vus:
                    problems.append(f"{filename}:{ligne}: '{nom}' is declared twice in "
                                    f"{m.group(1)} (first at line {vus[nom]})")
                else:
                    vus[nom] = ligne

    # 7l. a hardcoded colour on a view that also carries glass.
    #     Apple: "SwiftUI automatically uses a vibrant text color that adapts
    #     to maintain legibility against colorful backgrounds." Naming a
    #     colour switches that off — which is exactly what I did, then blamed
    #     the material for not adapting.
    #
    #     Semantic styles (.primary, .secondary, .tertiary) are the point and
    #     are allowed. A verdict colour on a SHAPE is fine too; this only
    #     looks at text and symbols.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        lignes = code.split("\n")
        for i, l in enumerate(lignes):
            if ".glass(" not in l and ".glassEffect(" not in l:
                continue
            # walk back over the chain this modifier belongs to
            for j in range(max(0, i - 8), i):
                m = re.search(r"\.foregroundStyle\(\s*\.(white|black)\b", lignes[j])
                if m and "Text(" in "\n".join(lignes[max(0, j - 3):j + 1]) + lignes[j]:
                    problems.append(
                        f"{filename}:{j + 1}: .foregroundStyle(.{m.group(1)}) on text that "
                        f"sits on glass — use .primary and let the material pick the "
                        f"vibrant tone")
                    break

    # 7m. French anywhere in the code.
    #     Everything that goes INTO the code is written in English. This rule
    #     is what keeps it that way, because French creeps back one comment
    #     at a time.
    #
    #     It reads raw, not code: the parser strips comments and strings
    #     before the other rules run, and comments are exactly where French
    #     survives.
    ACCENTS = "àâäçèéêëîïôùûœ"
    # The product name, words English borrowed, and French quoted AS DATA —
    # a label example is the thing being described, not prose.
    PERMIS = ("Bouchées", "Bouchée", "bouchée", "purée", "sauté", "café", "crêpe",
              "Arôme", "François")
    #     French quoted AS DATA is the exception, and it is marked rather than
    #     guessed: a line ending in `// label text` holds words printed on a
    #     Quebec package, which cannot be translated without breaking the
    #     match.
    for path_, (raw, _) in sources.items():
        filename = os.path.basename(path_)
        for i, l in enumerate(raw.split("\n"), 1):
            if not any(c in l for c in ACCENTS):
                continue
            if l.rstrip().endswith("// label text"):
                continue
            reste = l
            for mot in PERMIS:
                reste = reste.replace(mot, "")
            if any(c in reste for c in ACCENTS):
                problems.append(f"{filename}:{i}: French in the code — "
                                f"everything inside the code is in English")


    # 7n. a safeAreaInset placed inside a NavigationStack.
    #     An inset attached to a view INSIDE the stack survives every screen
    #     pushed on top of it. The overlay stops being visible but keeps its
    #     hit region, so buttons on the pushed screen are drawn correctly and
    #     receive nothing.
    #
    #     That cost four attempts on the wrong file. The rule looks for an
    #     inset that appears after a NavigationStack opens and before it
    #     closes.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        lignes = code.split("\n")
        profondeur = None
        for i, l in enumerate(lignes, 1):
            if "NavigationStack" in l and "{" in l:
                profondeur = 0
            if profondeur is None:
                continue
            profondeur += l.count("{") - l.count("}")
            if profondeur <= 0:
                profondeur = None
                continue
            if ".safeAreaInset(edge: .top" in l:
                problems.append(f"{filename}:{i}: safeAreaInset(.top) inside a "
                                f"NavigationStack — it keeps its hit region over every "
                                f"pushed screen; move it outside the stack")

    # 7o. a GeometryReader whose own frame is fed by what it measures.
    #     The scanner froze on this: an outer GeometryReader carrying
    #     `.frame(height: height)` while an inner one wrote to `height`. The
    #     layout never converged, the main thread spun, and from the outside
    #     it looked like the camera had stopped reading barcodes.
    #
    #     The signal is a file that both writes a @State length from a
    #     GeometryReader and applies that same property as a frame.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        if "GeometryReader" not in code:
            continue
        etats = set(re.findall(r"@State private var (\w+): CGFloat", code))
        for nom in etats:
            ecrit = re.search(r"\b" + nom + r"\s*=\s*\w+\.size\.(width|height)", code)
            cadre = re.search(r"\.frame\((?:width|height):\s*" + nom + r"\b", code)
            if ecrit and cadre:
                ligne = code[:cadre.start()].count("\n") + 1
                problems.append(f"{filename}:{ligne}: '{nom}' is written from a "
                                f"GeometryReader and used as a frame — that is a "
                                f"layout feedback loop; use a Layout instead")

    # 7p. a large bottom padding on content that already carries a
    #     safeAreaInset(.bottom). The inset reserves its own height; a second
    #     reservation for the same bar is what left text clipped behind it on
    #     one screen and floating on another.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        if ".safeAreaInset(edge: .bottom)" not in code:
            continue
        for m in re.finditer(r"\.padding\(\.bottom,\s*(\d+)\)", code):
            if int(m.group(1)) > 40:
                ligne = code[:m.start()].count("\n") + 1
                problems.append(f"{filename}:{ligne}: padding(.bottom, {m.group(1)}) on "
                                f"content that already has a safeAreaInset(.bottom) — "
                                f"two reservations for one bar")

    # 7q. a project type that shadows a SwiftUI name, used unqualified.
    #     The project owns `enum Layout` for its spacing constants. Writing
    #     `struct WrappingRow: Layout` therefore meant "inherit from that
    #     enum", and the compiler answered with four cascading errors — none
    #     of which named the collision.
    #
    #     Shadowing is fine. Using the shadowed name as a conformance without
    #     qualifying it is not.
    SWIFTUI_NAMES = {"Layout", "View", "Shape", "Animation", "Alignment", "Color",
                     "Font", "Image", "Text", "Group", "Section", "List", "Label",
                     "Gesture", "Edge", "Axis", "Material", "Visibility"}
    ombres = set()
    for path_, (_, code) in sources.items():
        for m in re.finditer(r"^(?:final\s+)?(?:public\s+)?(?:struct|enum|class|protocol)\s+(\w+)",
                             code, re.M):
            if m.group(1) in SWIFTUI_NAMES:
                ombres.add(m.group(1))

    if ombres:
        for path_, (_, code) in sources.items():
            filename = os.path.basename(path_)
            for i, l in enumerate(code.split("\n"), 1):
                m = re.search(r"^(?:final\s+)?(?:public\s+)?(?:struct|class|enum)\s+\w+\s*:\s*([\w, ]+)\{?", l)
                if not m:
                    continue
                for conf in [c.strip() for c in m.group(1).split(",")]:
                    if conf in ombres:
                        problems.append(f"{filename}:{i}: conforming to '{conf}', which this "
                                        f"project also defines — write SwiftUI.{conf} or the "
                                        f"compiler picks the local one")

    # 7r. ignoresSafeArea(.top) on a screen with no full-bleed image.
    #     iOS applies the scroll edge effect automatically to any scroll view
    #     UNDER a bar. Extending past the bar switches it off — which is what
    #     left the clock unreadable over a scrolling list.
    #
    #     Apple's own guidance: the status bar belongs on every page unless
    #     the page shows a full-screen image or video. So the modifier is
    #     allowed on a file that draws a hero photo, and nowhere else.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        if "ignoresSafeArea(.container, edges: .top)" not in code:
            continue
        photo = ("heroPhoto" in code or "detailPhoto" in code
                 or "CameraPreview" in code)
        if not photo:
            ligne = code[:code.find("ignoresSafeArea(.container, edges: .top)")].count("\n") + 1
            problems.append(f"{filename}:{ligne}: ignoresSafeArea(.top) with no "
                            f"full-bleed image — it switches off the scroll edge "
                            f"effect and the status bar stops being legible")

    # 7s. a @ViewBuilder stored property constructed with a value.
    #     `@ViewBuilder var bar: Bar` makes the memberwise initialiser take
    #     `() -> Bar`, not `Bar`. Calling `TopBar(bar: bar())` therefore hands
    #     a value where a closure is expected — and the error talks about the
    #     generic parameter, not about the attribute that caused it.
    #
    #     Constructing the same type with a trailing closure is correct and is
    #     not flagged.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        # types that declare a @ViewBuilder stored property, and its name
        builders = {}
        for m in re.finditer(r"(?:struct|final class|class)\s+(\w+)[^{]*\{((?:.|\n)*?)\n\}",
                             code):
            for d in re.finditer(r"@ViewBuilder\s+(?:var|let)\s+(\w+)\s*:", m.group(2)):
                builders.setdefault(m.group(1), set()).add(d.group(1))

        for _, (autre, _) in sources.items():
            for typ, props in builders.items():
                for prop in props:
                    for m in re.finditer(re.escape(typ) + r"\s*\(\s*" + re.escape(prop)
                                         + r"\s*:\s*([^)]*)\)", autre):
                        arg = m.group(1).strip()
                        if arg and not arg.startswith("{"):
                            ligne = autre[:m.start()].count("\n") + 1
                            problems.append(
                                f"{filename}:{ligne}: {typ}({prop}:) is given a value, but "
                                f"'{prop}' is @ViewBuilder — the initialiser expects a "
                                f"closure; drop the attribute or pass a closure")

    # 7t. more than one NavigationStack in the app.
    #     A safeAreaInset reduces the safe area of its DIRECT child, and a
    #     NavigationStack resets it for its content. Four screens each opening
    #     their own meant the tab bar's inset reached none of them — which
    #     produced the dead back button, the pill surviving every pushed
    #     screen, content under the bar, and thirty-six compensating paddings.
    #
    #     One stack, at the root. Screens are content.
    #     A view PRESENTED as a sheet is its own hierarchy and may own a
    #     stack; that is the one exception, and it is named rather than
    #     guessed.
    #     SUPERSEDED BY THE NATIVE TabView. Each Tab owns its own
    #     NavigationStack — that is the structure Apple documents, and it is
    #     what makes the Liquid Glass bar behave. The rule was written for a
    #     hand-rolled bar where one stack at the root was correct; with
    #     TabView it would forbid the right answer.
    #
    #     Kept, narrowed: a file holding a TabView is exempt.
    PRESENTEES = ("ProfileEditor", "PaywallScreen", "SubstitutionRuleSheet",
                  "ChildPickerSheet", "SearchSheet", "TagFlow")
    stacks = []
    for path_, (_, code) in sources.items():
        if "TabView" in code:
            continue
        for m in re.finditer(r"NavigationStack\s*[({]", code):
            avant = code[:m.start()]
            proprios = re.findall(r"(?:^|\n)(?:private )?(?:struct|final class|class) (\w+)",
                                  avant)
            if proprios and proprios[-1] in PRESENTEES:
                continue
            ligne = avant.count("\n") + 1
            stacks.append(f"{os.path.basename(path_)}:{ligne}")
    if len(stacks) > 1:
        problems.append("more than one NavigationStack: " + ", ".join(stacks) +
                        " — a stack resets the safe area, so the tab bar inset "
                        "stops reaching the content; keep one at the root")

    # 7u. a type used across files but declared inside another type.
    #     `enum Route` was inserted inside RootView, making it RootView.Route.
    #     Every other file then failed with "cannot find type Route in scope"
    #     — and the real cause, one level of nesting, was never named.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        lignes = code.split("\n")
        prof = 0
        for i, l in enumerate(lignes, 1):
            m = re.match(r"\s+(?:public )?(?:enum|struct|final class|class|protocol) (\w+)", l)
            if m and prof > 0 and not l.startswith("    private"):
                nom = m.group(1)
                # used from another file?
                # Used UNQUALIFIED elsewhere is the failure. A qualified use
                # — AppState.ProfileTally — is exactly what nesting is for.
                nu = re.compile(r"(?<![.\w])" + re.escape(nom) + r"\b")
                ailleurs = any(nu.search(c) for p2, (_, c) in sources.items()
                               if p2 != path_)
                if ailleurs and len(nom) > 3:
                    problems.append(f"{filename}:{i}: '{nom}' is declared inside another "
                                    f"type but used from other files — nesting makes it "
                                    f"Outer.{nom}, which nothing else can see")
            prof += l.count("{") - l.count("}")

    # 7v. a unicode escape without braces.
    #     Swift writes `\\u{00e9}`. `\\u00e9` is not an escape at all, and the
    #     compiler says "expected hexadecimal code in braces" three times for
    #     one line without naming the missing braces.
    #
    #     This came from a script writing Swift: Python and JavaScript accept
    #     the brace-less form, Swift does not. Writing the character itself is
    #     usually better than either.
    for path_, (raw, _) in sources.items():
        filename = os.path.basename(path_)
        for i, l in enumerate(raw.split("\n"), 1):
            for m in re.finditer(r"\\u(?!\{)([0-9a-fA-F]{2,})", l):
                problems.append(f"{filename}:{i}: '\\u{m.group(1)}' has no braces — "
                                f"Swift needs \\u{{{m.group(1)}}}, or write the "
                                f"character itself")

    # 7w. a guessed top inset.
    #     `padding(.top, 46)` inside a view that ignores the safe area
    #     measures from the physical edge. A Dynamic Island occupies 59, a
    #     notch a different number, an iPad another — so any large constant
    #     there is a height someone guessed.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        if "ignoresSafeArea" not in code:
            continue
        #     Only where it is a BAR being positioned: a padding that follows
        #     the pill, a title or a toolbar row. Spacing between sections of
        #     content is a different thing and legitimately large.
        for m in re.finditer(r"\.padding\(\.top,\s*(\d+)\)", code):
            if int(m.group(1)) <= 30:
                continue
            avant = code[max(0, m.start() - 400):m.start()]
            barre = any(k in avant for k in ("CookingContextHeader", "softTopBar",
                                             "topBar", "MessageBanner", "toolbar"))
            if not barre:
                continue
            ligne = code[:m.start()].count("\n") + 1
            problems.append(f"{filename}:{ligne}: padding(.top, {m.group(1)}) in a file "
                            f"that ignores the safe area — that is a guessed status bar "
                            f"height; let the safe area supply it")

    # 7x. a fading gradient with horizontal margins.
    #     A gradient that dims content has to span the screen. The moment it
    #     has side padding its edges become a visible box — which is what put
    #     an outline under "Start cooking" and above the tab bar.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        lignes = code.split("\n")
        for i, l in enumerate(lignes, 1):
            if "LinearGradient" not in l:
                continue
            fenetre = "\n".join(lignes[max(0, i - 6):i + 2])
            if "Tone.canvas" not in fenetre:
                continue
            if re.search(r"\.padding\(\.horizontal,\s*\d+\)", fenetre):
                problems.append(f"{filename}:{i}: a canvas fade with horizontal padding — "
                                f"its edges draw a box; a fade must span the screen")

    # 7y. a .sheet attached to the Button that triggers it.
    #     The child pill and the search island both did this. They live in a
    #     top bar that SwiftUI rebuilds whenever the layout shifts — and it
    #     shifts as soon as content scrolls under it. So the first tap set the
    #     flag, the view was recreated, the fresh @State came back false, and
    #     the sheet never opened. The second tap landed before the rebuild.
    #
    #     A sheet belongs on an ancestor that does not get rebuilt.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        lignes = code.split("\n")
        for i, l in enumerate(lignes, 1):
            if ".sheet(isPresented:" not in l and ".sheet(item:" not in l:
                continue
            # Walk back over the UNBROKEN modifier chain — consecutive lines
            # starting with a dot — and look at what it hangs off.
            j = i - 2
            while j >= 0 and lignes[j].strip().startswith("."):
                j -= 1
            if j < 0:
                continue

            # The chain belongs to a Button when a `Button {` opened at the
            # same indentation as the brace that closes it. More closing
            # braces than that means a List or a Section ended, and the sheet
            # correctly belongs to the screen.
            creux = len(lignes[j]) - len(lignes[j].lstrip())
            if not lignes[j].strip().startswith("}"):
                continue
            proprietaire = None
            for k in range(j - 1, max(-1, j - 30), -1):
                indent = len(lignes[k]) - len(lignes[k].lstrip())
                if indent == creux and re.match(r"\s*Button\s*[({]", lignes[k]):
                    proprietaire = k
                    break
                if indent < creux:
                    break
            if proprietaire is None:
                continue

            problems.append(f"{filename}:{i}: a .sheet on the Button that opens it — "
                            f"if that button gets rebuilt the flag is lost and the "
                            f"first tap does nothing; move it to a stable ancestor")

    # 7z. a property read off a model that does not declare it.
    #     The checker already catches `Foo(bar:)` when Foo has no `bar`. It
    #     did NOT catch `product.image` and `product.traceTags` — reads, not
    #     calls — so four invented members reached the compiler.
    #
    #     Only for models whose stored properties are all visible in one
    #     struct: guessing at a class with computed members would be noise.
    modeles = {}
    for path_, (_, code) in sources.items():
        for m in re.finditer(r"\nstruct (\w+): [^\n]*(?:Codable|Sendable)[^\n]*\{"
                             r"((?:\n    (?:let|var) [^\n]*)+)", code):
            champs = set(re.findall(r"(?:let|var) (\w+)", m.group(2)))
            modeles[m.group(1)] = champs

    # Computed properties live in extensions and in the rest of the body, so
    # the stored-property list alone is not the type's surface. Everything
    # declared anywhere for that type counts.
    for path_, (_, code) in sources.items():
        for nom in list(modeles):
            for m in re.finditer(r"extension " + nom + r"\b[^\n]*\{"
                                 r"((?:.|\n)*?)\n\}", code):
                modeles[nom] |= set(re.findall(r"(?:let|var|func) (\w+)", m.group(1)))
            for m in re.finditer(r"\nstruct " + nom + r":[^\n]*\{((?:.|\n)*?)\n\}", code):
                modeles[nom] |= set(re.findall(r"(?:let|var|func) (\w+)", m.group(1)))

    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        for nom, champs in modeles.items():
            # find locals typed as this model, then check what is read off them
            for var in set(re.findall(r"(?:let|var) (\w+): " + nom + r"\??\b", code)):
                for m in re.finditer(r"\b" + var + r"\??\.(\w+)", code):
                    membre = m.group(1)
                    if membre in champs or membre in ("self",):
                        continue
                    # methods and protocol members are not stored properties
                    apres = code[m.end():m.end() + 1]
                    if apres == "(":
                        continue
                    ligne = code[:m.start()].count("\n") + 1
                    problems.append(f"{filename}:{ligne}: {var}.{membre} — {nom} "
                                    f"declares no '{membre}'  (it has: "
                                    f"{', '.join(sorted(champs))})")

    # 7aa. glass INSIDE a Button's label.
    #      A glass container swallows the first touch: hitTest: on it returns
    #      itself (FB18201935). Inside a label it sits between the finger and
    #      the button, so the control needs two taps — measured four times on
    #      the detail screen, then again on the pill and on search.
    #
    #      Glass belongs on the Button, not in what the Button draws.
    #      `Button { action } label: { … }` puts the drawing in the SECOND
    #      block, which is where the glass ends up. Scanning the first block
    #      found nothing — the rule matched zero occurrences of the bug it was
    #      written for.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        for m in re.finditer(r"\blabel:\s*\{", code):
            prof = 0
            i = m.end() - 1
            for j in range(i, min(len(code), i + 2400)):
                if code[j] == "{":
                    prof += 1
                elif code[j] == "}":
                    prof -= 1
                    if prof == 0:
                        if re.search(r"\.glass\(", code[i:j]):
                            ligne = code[:m.start()].count("\n") + 1
                            problems.append(
                                f"{filename}:{ligne}: .glass() inside a label: "
                                f"block — a glass container swallows the first "
                                f"touch; put it on the Button instead")
                        break

    # 7ab. an overlay that expands with state.
    #      `.overlay { if expanded { … } }` draws ON TOP without reserving
    #      height, so the revealed content lands across whatever is below it.
    #      That is the ingredient list overlapping the cards under it.
    #
    #      Anything that grows belongs in the layout — a VStack — not an
    #      overlay.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        for m in re.finditer(r"\.overlay\s*(?:\([^)]*\)\s*)?\{", code):
            prof = 0
            i = m.end() - 1
            for j in range(i, min(len(code), i + 1600)):
                if code[j] == "{":
                    prof += 1
                elif code[j] == "}":
                    prof -= 1
                    if prof == 0:
                        corps = code[i:j]
                        # a state-driven reveal, not a static decoration
                        # A badge inside a FIXED-HEIGHT container reserves
                        # nothing because nothing needs reserving — the frame
                        # is already set. The rule is about an overlay on
                        # content whose height is its own.
                        # WHAT THE RULE IS ABOUT: an overlay that UNFOLDS.
                        #
                        # `if showDetails` reveals a list that lands across the
                        # content below, because an overlay reserves no height.
                        # `if isOn` on a badge does not: a checkmark on a tile
                        # covers the tile, which is the point.
                        #
                        # The distinction is the verb, not the size. A reveal
                        # is named show/expand/open; a selection is isOn,
                        # isSelected, selected.
                        revele = re.search(r"\bif\s+(?:show|expand|open|reveal)\w*\b",
                                           corps, re.I)
                        if revele and len(corps) > 120:
                            ligne = code[:m.start()].count("\n") + 1
                            problems.append(
                                f"{filename}:{ligne}: an .overlay that appears on "
                                f"state — an overlay reserves no height, so what "
                                f"it reveals lands across the content below; put "
                                f"it in the layout")
                        break

    # 7ac. a call to a private helper that no longer exists.
    #      Deleting `chips(...)` left one call behind in a branch nothing had
    #      exercised, and the checker reported clean — it verified struct
    #      members and initialisers, never free calls inside a file.
    #
    #      Scoped to PRIVATE helpers declared in the same file, which is the
    #      only case that can be decided without resolving the whole module.
    #      Closures, protocol members and anything from a framework are out of
    #      reach here, and guessing at them would be noise.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        prives = set(re.findall(r"\n\s*private func (\w+)\s*\(", code))
        # every name that was private in this file at some point in the chain
        for m in re.finditer(r"(?<![.\w])(\w+)\s*\(", code):
            nom = m.group(1)
            if nom[0].isupper() or len(nom) < 4:
                continue
            # Swift keywords that take a parenthesis and are not helpers.
            if nom in ("init", "self", "super", "some", "type", "deinit",
                       "subscript", "throws", "rethrows", "await", "async",
                       "repeat", "defer", "catch", "where", "case"):
                continue
            # Free functions the frameworks provide. A name declared nowhere
            # in the file is normal for these; the rule is about OUR helpers.
            if nom in ("withAnimation", "modifier", "sqrt", "round", "floor",
                       "ceil", "sin", "cos", "atan2", "pow", "zip", "stride",
                       "dump", "assert", "precondition", "fatalError",
                       "withCheckedContinuation", "withTaskGroup",
                       "unsafeBitCast", "type", "String", "localized",
                       # compiler directives, not calls
                       # SwiftUI methods used unqualified inside an extension
                       "navigationDestination", "toolbar", "searchable",
                       "overlay", "background", "padding", "frame",
                       "canImport", "available", "compiler", "targetEnvironment",
                       "swift", "os", "arch"):
                continue
            # declared anywhere in this file, private or not?
            if re.search(r"\bfunc " + re.escape(nom) + r"\s*[(<]", code):
                continue
            # a local closure or a parameter with this name?
            if re.search(r"\b(?:let|var)\s+" + re.escape(nom) + r"\b", code):
                continue
            if re.search(r"\b" + re.escape(nom) + r"\s*:\s*\(", code):
                continue
            # only flag names that LOOK like this file's own helpers: they
            # appear exactly once, as a call, and nowhere else
            if len(re.findall(r"\b" + re.escape(nom) + r"\b", code)) != 1:
                continue
            ligne = code[:m.start()].count("\n") + 1
            problems.append(f"{filename}:{ligne}: {nom}(…) is called but declared "
                            f"nowhere in this file — a helper that was deleted "
                            f"while a call survived")

    # 7ad. a permission switch whose branches do not all fill the screen.
    #      Only the authorised branch held a camera preview, which is greedy
    #      by nature; the other two sized themselves to their text. The tab
    #      bar is a safeAreaInset of the content, so it rose to meet them and
    #      sat in the middle of the screen until permission was granted.
    #
    #      The frame belongs on the switch, so a fourth state cannot forget it.
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        for m in re.finditer(r"switch\s+(\w*[Aa]uthoriz\w*|\w*[Pp]ermission\w*)\s*\{",
                             code):
            # the closing brace of the switch
            prof = 0
            i = m.end() - 1
            fin = None
            for j in range(i, min(len(code), i + 1200)):
                if code[j] == "{":
                    prof += 1
                elif code[j] == "}":
                    prof -= 1
                    if prof == 0:
                        fin = j
                        break
            if fin is None:
                continue
            # a frame in the 300 characters that follow?
            apres = code[fin:fin + 300]
            if "maxHeight: .infinity" not in apres:
                ligne = code[:m.start()].count("\n") + 1
                problems.append(f"{filename}:{ligne}: a permission switch with no "
                                f"frame(maxHeight: .infinity) after it — a branch "
                                f"that sizes to its text lets the tab bar rise "
                                f"into the middle of the screen")

    # 7ae. an API newer than the deployment target, with no availability gate.
    #      `Tab`, `TabView(selection:content:)` and `tabBarMinimizeBehavior`
    #      were written against a project whose deploymentTarget is iOS 17.
    #      Fourteen compiler errors, and `grep deploymentTarget ios/project.yml`
    #      would have shown it in one second.
    #
    #      The table is what this project actually uses. It grows when a new
    #      API is adopted, not speculatively.
    APIS_RECENTES = {
        # symbol            first available
        "Tab(":                     18,
        "tabBarMinimizeBehavior":   26,
        "tabViewBottomAccessory":   26,
        "glassEffect":              26,
        "GlassEffectContainer":     26,
        "scrollEdgeEffect":         26,
        "backgroundExtensionEffect": 26,
        "symbolColorRenderingMode": 26,
    }

    cible = 17
    projet = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          "ios", "project.yml")
    if os.path.exists(projet):
        m = re.search(r"iOS:\s*['\"]?(\d+)", open(projet, encoding="utf-8").read())
        if m:
            cible = int(m.group(1))

    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        # the line ranges covered by an availability gate
        protegees = set()
        for m in re.finditer(r"(?:if\s+#available\(iOS\s+(\d+)|@available\(iOS\s+(\d+))",
                             code):
            version = int(m.group(1) or m.group(2))
            debut = code[:m.start()].count("\n") + 1
            # the gate covers its block; approximate by brace depth
            prof, fin = 0, debut
            vu = False
            for j in range(m.end(), len(code)):
                if code[j] == "{":
                    prof += 1; vu = True
                elif code[j] == "}":
                    prof -= 1
                    if vu and prof <= 0:
                        fin = code[:j].count("\n") + 1
                        break
            for ligne in range(debut, fin + 2):
                protegees.add((ligne, version))

        for symbole, requis in APIS_RECENTES.items():
            if requis <= cible:
                continue
            for m in re.finditer(re.escape(symbole), code):
                ligne = code[:m.start()].count("\n") + 1
                # inside a comment?
                debut_ligne = code.rfind("\n", 0, m.start()) + 1
                avant = code[debut_ligne:m.start()]
                if "//" in avant or "*" in avant.strip()[:2]:
                    continue
                couvert = any(l == ligne and v >= requis for l, v in protegees)
                if not couvert:
                    problems.append(f"{filename}:{ligne}: {symbole} needs iOS "
                                    f"{requis}, the deployment target is {cible} "
                                    f"— wrap it in `if #available(iOS {requis}, *)` "
                                    f"or mark the property @available")

    # 7af. a @Binding whose type contradicts the @State it is bound to.
    #      The root holds `@State private var path = NavigationPath()` and a
    #      modifier declared `@Binding var path: [Route]`. Two build failures
    #      on the same pair, because nothing compared them.
    #
    #      Matched by NAME within a file: a @State of a known type, and a
    #      @Binding of the same name declared as something else.
    TYPES_CONNUS = {
        "NavigationPath()": "NavigationPath",
        "[]": None,          # ambiguous, skip
    }
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        etats = {}
        for m in re.finditer(r"@State\s+(?:private\s+)?var\s+(\w+)\s*=\s*([A-Z]\w*)\(\)",
                             code):
            etats[m.group(1)] = m.group(2)
        for m in re.finditer(r"@Binding\s+var\s+(\w+)\s*:\s*([^\n=]+)", code):
            nom, declare = m.group(1), m.group(2).strip()
            attendu = etats.get(nom)
            if attendu and attendu not in declare:
                ligne = code[:m.start()].count("\n") + 1
                problems.append(f"{filename}:{ligne}: @Binding var {nom}: {declare} "
                                f"— but @State var {nom} in this file is "
                                f"{attendu}. The binding cannot convert")

    # 8. properties that shadow a UIKit member. A `var layer` on a UIView
    #    subclass makes the getter call itself and fails the build — exactly
    #    the mistake a blind rename introduces.
    SHADOWED = ["layer", "frame", "bounds", "view", "window", "subviews",
                "superview", "tag", "alpha", "isHidden", "backgroundColor",
                "contentMode", "transform", "center"]
    for path_, (_, code) in sources.items():
        filename = os.path.basename(path_)
        for m in re.finditer(r"class\s+\w+\s*:\s*(UIView|UIViewController|UIControl|UILabel)\b", code):
            tail = code[m.end():m.end() + 1200]
            for prop in SHADOWED:
                if re.search(r"(?<!override )\bvar\s+" + prop + r"\s*:", tail):
                    problems.append(f"{filename}: 'var {prop}' shadows a {m.group(1)} member — "
                                    f"rename it, or mark it override")

    # 9. exactly one @main
    mains = [os.path.basename(c) for c, (_, code) in sources.items() if re.search(r'^@main', code, re.M)]
    if len(mains) != 1:
        problems.append(f"exactly one @main is required, found {len(mains)}: {mains}")

    # 10. missing imports for the frameworks in use
    needs = {
        "SwiftUI": r'\b(View|Color|Text|VStack|Canvas)\b',
        "AVFoundation": r'\bAVCapture',
        "StoreKit": r'\b(Product|AppStore|VerificationResult)\b',
        "JavaScriptCore": r'\bJSContext\b',
        "UIKit": r'\b(UIView|UIScreen|UIApplication|UINotificationFeedbackGenerator)\b',
        "Observation": r'@Observable',
    }
    for path_, (raw, code) in sources.items():
        imports = set(re.findall(r'^import\s+(\w+)', raw, re.M))
        filename = os.path.basename(path_)
        for module, pattern in needs.items():
            if re.search(pattern, code) and module not in imports:
                # SwiftUI sometimes re-exports; warn without blocking
                level = problems if module in ("JavaScriptCore", "StoreKit", "AVFoundation") else warnings
                level.append(f"{filename}: uses {module} without importing it")

    return problems, warnings


if __name__ == "__main__":
    problems, warnings = check()
    print(f"Files analysed: {len(swift_files())}\n")
    if warnings:
        print("WARNINGS")
        for a in warnings:
            print("  ~ " + a)
        print()
    if problems:
        print("PROBLEMS")
        for p in problems:
            print("  ✕ " + p)
        sys.exit(1)
    print("No blocking problem found.")
    print("Reminder: this is not a compiler. Type and isolation errors")
    print("only surface at build time.")
