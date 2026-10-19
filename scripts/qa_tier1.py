#!/usr/bin/env python3
"""QA part 4: tier-1 coverage, and QA_COVERAGE.md.

    scripts/qa_tier1.py <matrix dir> [--sheets <sheets dir>] [--write]

Tier 1 is the v1 plan: the screens and configurations listed in DEFINITION below. For every planned combination (device, configuration, screen) it reads whether the
harness PRODUCED it (a top picture, and a bottom picture for a page that scrolls), and whether it was VIEWED (qa/tier1/viewed.tsv: one line per contact sheet that
somebody looked at, `sheet<TAB>result<TAB>note`, where a sheet's cells are in <sheets dir>/sheets.tsv). A combination that is not produced or not viewed is UNVERIFIED and
is never counted as a pass. Everything outside tier 1 is "tier 2, not planned for v1" and is counted as such. With --write the tables go to QA_COVERAGE.md and
qa/tier1/coverage.csv.
"""
import argparse, collections, csv, datetime, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEVICES = {"pro": "QA17Pro", "max": "QA17ProMax", "se": "QASE"}

T1 = ["onboarding.", "premium.paywall.loaded", "premium.paywall.loading", "premium.paywall.unavailable", "premium.compare", "home.day.full", "home.evening.full",
      "sleep.day.full", "sleep.week.full", "sleep.month.full", "recovery.today.full", "recovery.7d.full", "recovery.30d.full", "recovery.90d.full", "recovery.factor.",
      "insights.all.full", "insights.detail", "coach.hub.full", "coach.answer", "night.windDown.", "night.alarm", "reviews.list", "reviews.weekly.cover",
      "reviews.monthly.cover", "profile.screen", "settings.root", "settings.privacy-center", "settings.data-management", "privacy."]
# Screens a QA part 4 re-photograph row names (QA_LEDGER.md), looked at at the sizes the row names, on the 17 Pro and the SE.
AX = ["coach.", "recovery.today.full", "recovery.7d.full", "recovery.30d.full", "recovery.90d.full", "recovery.factor.", "insights.all.full", "insights.sleep", "insights.recovery",
      "insights.timing", "insights.consistency", "insights.heart", "insights.longTerm", "insights.detail", "insights.history", "sleep.day.full", "sleep.week.full", "sleep.month.full",
      "home.evening.full", "home.day.full", "night.", "privacy.", "profile.", "settings.", "onboarding.", "premium.paywall."]
EX = ["reviews.", "insights.heart", "insights.consistency", "insights.timing", "insights.all.loading", "sleep.day.loading", "sleep.week.loading", "sleep.month.loading"]
LOADING = ["sleep.day.loading", "sleep.week.loading", "sleep.month.loading", "insights.all.loading"]
MAX = ["home.day.full", "home.evening.full", "sleep.day.full", "sleep.week.full", "sleep.month.full", "recovery.today.full", "recovery.7d.full", "recovery.30d.full",
       "recovery.90d.full", "onboarding.paywall", "premium.paywall.loaded", "onboarding.welcome"]
# AX5 is tier 1 only on Settings, Privacy Center, Data management and the paywall (the QA part 4 brief); everywhere else it is tier 2, not planned for v1.
AX5 = ["settings.", "privacy.", "premium.paywall.", "onboarding.paywall"]
# (device, configuration) -> the prefixes of the screens planned there.
DEFINITION = {
    ("pro", "A-light"): T1 + EX, ("pro", "A-dark"): T1 + LOADING, ("pro", "B-AX3-light"): T1 + AX, ("pro", "B-AX5-light"): AX5,
    ("se", "A-light"): T1 + EX, ("se", "A-dark"): T1 + LOADING, ("se", "B-AX3-light"): T1 + AX, ("se", "B-AX5-light"): AX5,
    ("se", "C-BoldText"): ["recovery.today.full"],
    ("se", "D-DoubleLength"): ["home.day.", "home.evening.", "profile.screen"], ("se", "D-Bounded"): ["home.day.", "home.evening.", "profile.screen"],
    ("max", "A-light"): MAX, ("max", "A-dark"): MAX
}

def load_catalog():
    return [c for c in json.load(open(os.path.join(ROOT, "qa", "coverage", "catalog.json"))) if c["platform"] == "iPhone"]

def planned(catalog):
    out = []
    for (dev, cfg), prefixes in DEFINITION.items():
        for c in catalog:
            if any(c["id"].startswith(p) for p in prefixes):
                out.append((dev, cfg, c["id"], c["scrolls"], c["area"]))
    return out

def produced(matrix, dev, cfg, sid, scrolls):
    base = os.path.join(matrix, cfg, DEVICES[dev], sid)
    if not os.path.exists(base + "__top.png"):
        return False
    if scrolls and not (os.path.exists(base + "__bottom.png") or os.path.exists(base + "__noscroll.txt")):
        return False
    return True

RANK = {"PASS": 0, "NOTE": 1, "FINDING": 2}

def viewed_map(sheets_dirs):
    cells = {}
    for sheets_dir in [d for d in sheets_dirs.split(",") if d]:
        path = os.path.join(sheets_dir, "sheets.tsv")
        if not os.path.exists(path):
            continue
        for line in open(path):
            name, dev, screen, cell = line.rstrip("\n").split("\t")
            key = os.path.basename(sheets_dir.rstrip('/')) + "/" + name
            parts = [x.split(":") for x in cell.split(";")]
            if parts and len(parts[0]) == 3:
                # A sheet of several screens: "<config>:<page>:<screen>__<page>.png".
                cells[key] = (dev, None, [(c, f.rsplit("__", 1)[0]) for c, _, f in parts])
            else:
                cells[key] = (dev, screen, [(c, screen) for c, *_ in parts])
    seen = {}
    vpath = os.path.join(ROOT, "qa", "tier1", "viewed.tsv")
    if os.path.exists(vpath):
        for line in open(vpath):
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3 or parts[0] not in cells:
                continue
            dev, _, pairs = cells[parts[0]]
            for cfg, screen in set(pairs):
                key = (dev, cfg, screen)
                prev = seen.get(key)
                if prev is None or RANK.get(parts[1].split()[0], 0) > RANK.get(prev[0].split()[0], 0):
                    seen[key] = (parts[1], parts[2])
    return seen

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("matrix"); ap.add_argument("--sheets", default="", help="comma separated sheet folders"); ap.add_argument("--write", action="store_true")
    a = ap.parse_args()
    catalog = load_catalog()
    plan = planned(catalog)
    seen = viewed_map(a.sheets)
    rows = []
    for dev, cfg, sid, scrolls, area in plan:
        made = produced(a.matrix, dev, cfg, sid, scrolls)
        v = seen.get((dev, cfg, sid))
        if not made:
            status, result, note = "UNVERIFIED", "not produced", ""
        elif v is None:
            status, result, note = "UNVERIFIED", "produced, not viewed", ""
        else:
            status, result, note = "VIEWED", v[0], v[1]
        rows.append((area, sid, dev, cfg, made, v is not None, status, result, note))
    total = len(rows)
    counts = collections.Counter(r[6] if r[6] == "UNVERIFIED" else r[7].split()[0] for r in rows)
    print(total, "planned;", dict(counts))
    if not a.write:
        return
    os.makedirs(os.path.join(ROOT, "qa", "tier1"), exist_ok=True)
    with open(os.path.join(ROOT, "qa", "tier1", "coverage.csv"), "w", newline="") as handle:
        w = csv.writer(handle)
        w.writerow(["area", "screen", "device", "configuration", "produced", "viewed", "status", "result", "note"])
        for r in rows:
            w.writerow(r)
    ids = set(c["id"] for c in catalog)
    all_screens = len(catalog)
    planned_screens = len(set(r[1] for r in rows))
    unver = [r for r in rows if r[6] == "UNVERIFIED"]
    findings = [r for r in rows if r[6] == "VIEWED" and r[7].startswith("FINDING")]
    by_cfg = collections.Counter((r[2], r[3]) for r in rows)
    today = datetime.date.today().isoformat()
    lines = []
    A = lines.append
    A("# QA coverage")
    A("")
    A(f"Written by `scripts/qa_tier1.py` on {today} from `qa/tier1/` (the plan, what the harness produced, and which contact sheets were looked at). The earlier coverage tables, made before the final")
    A("build, are kept in `qa/coverage/` as history; they are not the v1 record.")
    A("")
    A("## What counts")
    A("")
    A("- **Tier 1** is what v1 ships and is judged on: the screens and configurations below. Every tier-1 combination must be **produced** on the final build (a top picture, and a")
    A("  bottom picture for a page that scrolls) and **viewed** (a contact sheet at a size where its text can be read, in `qa/tier1/viewed.tsv`). One that is not is UNVERIFIED, with the reason,")
    A("  and is never counted as a pass.")
    A("- **Tier 2, not planned for v1** is everything else: the other states of each screen (learning, empty, no permission, gap, stale, loading, error) beyond the ones named,")
    A("  the other accessibility settings (Bold Text, Reduce Motion, Increase Contrast, Differentiate Without Color, Button Shapes, On/Off Labels, Reduce Transparency, Smart Invert), the pseudolanguages beyond")
    A("  the two below, right-to-left, the other locales and languages, AX5 outside Settings, Privacy Center, Data management and the paywall, and the Apple Watch matrix. They were photographed in earlier")
    A("  QA parts; they are **not** a pass and not planned for v1.")
    A("- v1 ships English only (no right-to-left language is in the app: `ShippedLanguagesTests`).")
    A("")
    A("## Tier 1 plan")
    A("")
    A("| Device | Configuration | Screens planned |")
    A("| --- | --- | --- |")
    for (dev, cfg), n in sorted(by_cfg.items()):
        A(f"| {DEVICES[dev]} | {cfg} | {n} |")
    A("")
    A("Screens: Welcome and every onboarding step, the paywall (loaded, loading, unavailable, compare), Home (day, evening), Sleep (day, week, month), Recovery (today, 7D, 30D, 90D, each factor),")
    A("Insights (all, an insight), Coach (hub, an answer), Wind-down (every state), the Alarm, Reviews (the list, the weekly and monthly covers), Profile, Settings, the Privacy Center, Data management and")
    A("each delete confirmation. Added so every QA part 4 re-photograph row (QA_LEDGER.md) is looked at in the configuration it names: Coach, Recovery, Insights, Sleep, Home, Night, Privacy, Profile,")
    A("Settings, Onboarding and the paywall at AX3 and AX5 on the 17 Pro and the SE; Bold Text on Recovery; DoubleLength and Bounded String on Home and Profile; Reviews and the loading skeletons.")
    A("")
    A("## Totals")
    A("")
    A("| Planned | Produced | Viewed | PASS | NOTE | FINDING | UNVERIFIED |")
    A("| --- | --- | --- | --- | --- | --- | --- |")
    A(f"| {total} | {sum(1 for r in rows if r[4])} | {sum(1 for r in rows if r[5])} | {counts['PASS']} | {counts['NOTE']} | {counts['FINDING']} | {counts['UNVERIFIED']} |")
    A("")
    A(f"{planned_screens} of the {all_screens} iPhone screens in the catalog are in tier 1; the other {all_screens - planned_screens} (and the 19 Apple Watch screens) are tier 2.")
    A("")
    if unver:
        A("## UNVERIFIED (tier 1)")
        A("")
        grouped = collections.defaultdict(list)
        for r in unver:
            grouped[(r[7], r[2], r[3])].append(r[1])
        for (why, dev, cfg), screens in sorted(grouped.items()):
            A(f"- {why}: {DEVICES[dev]} {cfg}: " + ", ".join(sorted(screens)))
        A("")
    else:
        A("## UNVERIFIED (tier 1)")
        A("")
        A("None: every tier-1 combination was produced on the final build and viewed.")
        A("")
    A("## Findings seen in tier 1")
    A("")
    if findings:
        for r in findings:
            A(f"- {r[1]} on {DEVICES[r[2]]} {r[3]}: {r[7]}: {r[8]}")
    else:
        A("None open: what was seen is in QA_LEDGER.md.")
    A("")
    A("## Every tier-1 combination")
    A("")
    A("`qa/tier1/coverage.csv` has one line per combination: area, screen, device, configuration, produced, viewed, status, result, what was seen.")
    A("")
    open(os.path.join(ROOT, "QA_COVERAGE.md"), "w").write("\n".join(lines) + "\n")

main()
