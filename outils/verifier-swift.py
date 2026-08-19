#!/usr/bin/env python3
"""Vérificateur statique du code Swift.

Ce n'est PAS un compilateur. Il attrape la classe d'erreurs qui a coûté deux
allers-retours la dernière fois : symbole référencé mais jamais défini, type
déclaré deux fois, couleur d'asset manquante, délimiteurs déséquilibrés,
identifiants StoreKit qui ne concordent pas.

Ce qu'il NE peut pas attraper : ambiguïtés de surcharge, isolation d'acteur,
signatures d'API changées, inférence de type. Ces erreurs-là sortiront du
build, et c'est normal.
"""
import json
import os
import re
import sys

RACINE = os.path.join(os.path.dirname(__file__), "..", "ios", "App", "App")
RACINE = os.path.abspath(RACINE)

# Types et symboles fournis par les frameworks, à ne pas signaler comme absents.
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

def fichiers_swift():
    out = []
    for base, _, noms in os.walk(RACINE):
        for n in sorted(noms):
            if n.endswith(".swift"):
                out.append(os.path.join(base, n))
    return out

def sans_chaines_ni_commentaires(src):
    """Retire chaînes et commentaires pour ne pas analyser du texte français."""
    src = re.sub(r'"""(?:.|\n)*?"""', '""', src)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    src = re.sub(r'//[^\n]*', '', src)
    src = re.sub(r'/\*(?:.|\n)*?\*/', '', src)
    return src

def verifier():
    problemes = []
    avertissements = []
    fichiers = fichiers_swift()
    if not fichiers:
        return ["aucun fichier Swift trouvé sous " + RACINE], []

    definitions = {}   # nom -> [fichiers]
    sources = {}

    for chemin in fichiers:
        brut = open(chemin, encoding="utf-8").read()
        code = sans_chaines_ni_commentaires(brut)
        sources[chemin] = (brut, code)
        nom_fichier = os.path.basename(chemin)

        # 1. délimiteurs équilibrés
        for ouvrant, fermant, etiquette in [("{", "}", "accolades"),
                                            ("(", ")", "parenthèses"),
                                            ("[", "]", "crochets")]:
            a, b = code.count(ouvrant), code.count(fermant)
            if a != b:
                problemes.append(f"{nom_fichier} : {etiquette} déséquilibrées ({a} vs {b})")

        # 2. déclarations de types
        for m in re.finditer(
                r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public |private |internal |fileprivate )?'
                r'(?:final )?(struct|class|enum|actor|protocol|typealias)\s+(\w+)', code, re.M):
            definitions.setdefault(m.group(2), []).append(nom_fichier)

    # 3. doublons de type
    for nom, lieux in sorted(definitions.items()):
        if len(lieux) > 1:
            problemes.append(f"type « {nom} » déclaré {len(lieux)} fois : {', '.join(lieux)}")

    # 4. types utilisés mais jamais définis
    definis = set(definitions) | CONNUS
    for chemin, (_, code) in sources.items():
        nom_fichier = os.path.basename(chemin)
        candidats = set()
        # annotation de type explicite  ": Type" ou "-> Type"
        for m in re.finditer(r'(?::\s*|->\s*)\[?([A-Z]\w+)', code):
            candidats.add(m.group(1))
        # appel de constructeur  Type(
        for m in re.finditer(r'\b([A-Z]\w+)\s*\(', code):
            candidats.add(m.group(1))
        for c in sorted(candidats):
            if c not in definis and not c.startswith(("NS", "UI", "CG", "CA", "AV", "SK", "JS")):
                avertissements.append(f"{nom_fichier} : « {c} » utilisé, non défini dans le projet")

    # 5. couleurs d'assets
    assets = os.path.join(RACINE, "Assets.xcassets")
    existants = set()
    if os.path.isdir(assets):
        existants = {d[:-len(".colorset")] for d in os.listdir(assets) if d.endswith(".colorset")}
    for chemin, (brut, _) in sources.items():
        for m in re.finditer(r'Color\("([^"]+)"\)', brut):
            if m.group(1) not in existants:
                problemes.append(f"{os.path.basename(chemin)} : asset couleur « {m.group(1)} » absent")

    # 6. identifiants StoreKit cohérents
    sk = os.path.join(RACINE, "Bouchees.storekit")
    if os.path.exists(sk):
        d = json.load(open(sk, encoding="utf-8"))
        groupes = d.get("subscriptionGroups", [])
        ids_sk = {s["productID"] for g in groupes for s in g.get("subscriptions", [])}
        ids_swift = set()
        for _, (brut, _) in sources.items():
            ids_swift |= set(re.findall(r'"(ca\.bouchees\.[a-z.]+)"', brut))
        ids_swift = {i for i in ids_swift if i.startswith("ca.bouchees.abo")}
        if ids_sk != ids_swift:
            problemes.append(f"identifiants StoreKit divergents — .storekit {sorted(ids_sk)} "
                             f"vs Swift {sorted(ids_swift)}")

    # 7. un seul @main
    mains = [os.path.basename(c) for c, (_, code) in sources.items() if re.search(r'^@main', code, re.M)]
    if len(mains) != 1:
        problemes.append(f"il faut exactement un @main, trouvé {len(mains)} : {mains}")

    # 8. imports manquants pour les frameworks utilisés
    besoins = {
        "SwiftUI": r'\b(View|Color|Text|VStack|Canvas)\b',
        "AVFoundation": r'\bAVCapture',
        "StoreKit": r'\b(Product|AppStore|VerificationResult)\b',
        "JavaScriptCore": r'\bJSContext\b',
        "UIKit": r'\b(UIView|UIScreen|UIApplication|UINotificationFeedbackGenerator)\b',
        "Observation": r'@Observable',
    }
    for chemin, (brut, code) in sources.items():
        imports = set(re.findall(r'^import\s+(\w+)', brut, re.M))
        nom_fichier = os.path.basename(chemin)
        for module, motif in besoins.items():
            if re.search(motif, code) and module not in imports:
                # SwiftUI réexporte parfois; on avertit sans bloquer
                niveau = problemes if module in ("JavaScriptCore", "StoreKit", "AVFoundation") else avertissements
                niveau.append(f"{nom_fichier} : utilise {module} sans l’importer")

    return problemes, avertissements


if __name__ == "__main__":
    problemes, avertissements = verifier()
    print(f"Fichiers analysés : {len(fichiers_swift())}\n")
    if avertissements:
        print("AVERTISSEMENTS")
        for a in avertissements:
            print("  ~ " + a)
        print()
    if problemes:
        print("PROBLÈMES")
        for p in problemes:
            print("  ✕ " + p)
        sys.exit(1)
    print("Aucun problème bloquant détecté.")
    print("Rappel : ceci n’est pas un compilateur. Les erreurs de type et")
    print("d’isolation ne sortiront qu’au build.")
