#!/usr/bin/env python3
"""QA part 3 (QA_COVERAGE.md 4, APP_RULES.md R68): localization readiness.

    scripts/qa_localization.py comments      # gives every String Catalog entry a translator comment it lacks (never overwrites one)
    scripts/qa_localization.py csv           # writes Localizations/needs-translation.csv
    scripts/qa_localization.py report        # counts: keys, comments, plural variations, literals

The catalogs are the source of truth for the English text; no translation is made here (no machine translation, APP_RULES.md R68). The CSV is what a
translator is handed: key, English, comment, context (where it appears), a maximum length hint (the English length x 1.4, which is what a typical
translation needs; a button or a tab label is held to its width, not to this), and the catalog it lives in.
"""
import csv
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGS = [
    "Packages/NoctisKit/Sources/CoachKit/Resources/Coach.xcstrings",
    "Packages/NoctisKit/Sources/NightFeature/Resources/Meditation.xcstrings",
    "Packages/NoctisKit/Sources/ProfileFeature/Resources/Help.xcstrings",
    "Packages/NoctisKit/Sources/DesignSystem/Localizable.xcstrings",
    "Packages/NoctisKit/Sources/NoctisText/Resources/Localizable.xcstrings",
    "App/AppShortcuts.xcstrings",
]


def english(entry):
    loc = entry.get("localizations", {}).get("en", {})
    if "stringUnit" in loc:
        return loc["stringUnit"].get("value", "")
    plural = loc.get("variations", {}).get("plural", {})
    return " | ".join(f"{k}: {v['stringUnit']['value']}" for k, v in plural.items() if "stringUnit" in v)


def placeholders(text):
    found = re.findall(r"%(?:\d+\$)?(?:lld|d|@|f|\.\d+f)|\$\{[A-Za-z]+\}|\{[A-Za-z0-9_]+\}", text)
    return sorted(set(found))


def comment_for(key, value, catalog):
    ph = placeholders(value)
    holders = f" Keeps the placeholder{'s' if len(ph) > 1 else ''} {', '.join(ph)} exactly: they are replaced by numbers, times or names already formatted." if ph else ""
    name = os.path.basename(catalog)
    parts = key.split(".")
    if name == "Coach.xcstrings":
        head = parts[1] if len(parts) > 1 else ""
        rest = ".".join(parts[2:])
        if head == "tpl":
            return (f"Coach's own sentence for the '{rest}' situation in an answer card, built from the person's data on this iPhone. Calm, plain and never "
                    f"medical advice; no cause is claimed.{holders}")
        if head == "q":
            return f"A question Coach offers as a chip ('{rest}'); it is also the text of the question when tapped. Phrase it as the person would ask it.{holders}"
        if head == "router":
            return (f"Words the router looks for in what the person types, to decide it is a '{rest}' question. A list of words and phrases separated by |; "
                    f"give the language's own everyday ways of asking, not a literal translation.")
        if head == "script":
            return f"A fixed reply Coach gives for '{rest}' (it does not read the person's data). Must stay calm, short and kind; review with care.{holders}"
        if head in ("caution", "confidence", "footer", "pattern"):
            return f"A line Coach adds under an answer ('{head}.{rest}'): how much to lean on it.{holders}"
        return f"Coach text '{key}'.{holders}"
    if name == "Meditation.xcstrings":
        category = parts[1] if len(parts) > 1 else ""
        line = parts[2] if len(parts) > 2 else ""
        return (f"Line {line} of the spoken '{category}' guided meditation. Read aloud by the system voice with a pause after it, and shown on screen. "
                f"Short, calm, second person; no breath counts the person cannot follow.{holders}")
    if name == "Help.xcstrings":
        kind = "the question" if key.endswith(".q") else "the answer"
        return f"Help article '{parts[1] if len(parts) > 1 else key}': {kind}, as shown in Settings > Help. Plain language; keep the claims as modest as the English.{holders}"
    if name == "AppShortcuts.xcstrings":
        return (f"A phrase that starts an App Shortcut by voice (Siri). ${{applicationName}} is replaced by the app's name and must stay in the sentence. "
                f"Say it the way a person would speak it.")
    if name == "Localizable.xcstrings" and "DesignSystem" in catalog:
        return "The accessibility label of a back button (VoiceOver reads it; it is not drawn)."
    return f"Text '{key}'.{holders}"


def load(path):
    with open(os.path.join(ROOT, path)) as handle:
        return json.load(handle)


def save(path, data):
    with open(os.path.join(ROOT, path), "w") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False, separators=(",", " : "))
        handle.write("\n")


def cmd_comments():
    added = 0
    for path in CATALOGS:
        data = load(path)
        for key, entry in data["strings"].items():
            if entry.get("comment"):
                continue
            entry["comment"] = comment_for(key, english(entry), path)
            added += 1
        save(path, data)
    print(f"{added} comments added")


def usage_of(key, sources):
    for path, text in sources.items():
        if f'"{key}"' in text or (key.count(".") >= 2 and f'"{".".join(key.split(".")[:2])}.' in text):
            return path
    return ""


def cmd_csv():
    sources = {}
    for folder in ["Packages/NoctisKit/Sources", "App", "NoctisWidgets", "NOCTISWatch", "NOCTISWatchWidgets"]:
        for path in glob.glob(os.path.join(ROOT, folder, "**", "*.swift"), recursive=True):
            sources[os.path.relpath(path, ROOT)] = open(path).read()
    rows = []
    for path in CATALOGS:
        data = load(path)
        for key, entry in sorted(data["strings"].items()):
            value = english(entry)
            first = value.split(" | ")[0].split(": ", 1)[-1] if " | " in value else value
            rows.append([key, value, entry.get("comment", ""), usage_of(key, sources) or os.path.basename(path), max(8, round(len(first) * 1.4)), path])
    # literals in views: not in a catalog yet, so no key; the file and line are the context
    pattern = re.compile(r'\b(Text|Button|Label|NoctisCTA|NoctisTextButton)\("([^"\\]{2,})"|\.(navigationTitle|accessibilityLabel|accessibilityHint)\("([^"\\]{2,})"')
    literals = 0
    for path, text in sorted(sources.items()):
        if "/Tests/" in path:
            continue
        for number, line in enumerate(text.split("\n"), start=1):
            for match in pattern.finditer(line):
                value = match.group(2) or match.group(4)
                if re.fullmatch(r"[\W\d_]*", value):
                    continue
                kind = match.group(1) or match.group(3)
                rows.append([f"literal:{path}:{number}", value, f"A literal in a {kind} in {os.path.basename(path)} that is not in a string catalog yet: it needs a key and a comment before it can be translated.",
                             path, max(8, round(len(value) * 1.4)), "(none)"])
                literals += 1
    os.makedirs(os.path.join(ROOT, "Localizations"), exist_ok=True)
    with open(os.path.join(ROOT, "Localizations", "needs-translation.csv"), "w", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["key", "english", "comment", "context", "max_length_hint", "catalog"])
        writer.writerows(rows)
    print(f"{len(rows)} rows ({literals} literals not yet in a catalog)")


def cmd_report():
    total = with_comment = plural = 0
    for path in CATALOGS:
        data = load(path)
        n = len(data["strings"])
        c = sum(1 for e in data["strings"].values() if e.get("comment"))
        p = sum(1 for e in data["strings"].values() if "variations" in json.dumps(e))
        print(f"{path}: {n} keys, {c} with a comment, {p} with plural variations")
        total += n
        with_comment += c
        plural += p
    print(f"total {total} keys, {with_comment} with a comment, {plural} with plural variations")


if __name__ == "__main__":
    {"comments": cmd_comments, "csv": cmd_csv, "report": cmd_report}[sys.argv[1] if len(sys.argv) > 1 else "report"]()
