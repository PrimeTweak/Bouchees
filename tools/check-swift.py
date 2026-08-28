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
