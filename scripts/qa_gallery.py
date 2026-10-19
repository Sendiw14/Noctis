#!/usr/bin/env python3
"""Final gallery: turns the matrix run (A-light and A-dark on the 17 Pro, status bar 9:41) into named JPEGs (quality 92, native size) in one folder per area.

    scripts/qa_gallery.py <matrix dir> <out dir>

Names: NN-<screen>-<state>-<light|dark>.jpg; a page that scrolls has -top, -mid-<n> and -bottom (every scroll position). Onboarding is pinned to light by design, so it is
captured once ("-light" only). Writes <out dir>/gallery.tsv (file, area, screen id, mode, page) for INDEX.md.
"""
import json, os, re, sys
from PIL import Image
matrix, out = sys.argv[1:3]
catalog = {c["id"]: c for c in json.load(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "qa", "coverage", "catalog.json"))) if c["platform"] == "iPhone"}
STATES = ("sleepOnly", "learning", "empty", "noPermission", "gap", "stale", "loading", "error")
LOCKS = ("premium.paywall.recovery30D", "premium.paywall.sleepMonth", "premium.paywall.coachQuestions", "premium.paywall.windDown", "premium.paywall.weeklyReview", "premium.compare",
         "night.tonight.free", "reviews.list.free", "reviews.monthly.locked", "settings.subscription.free")
def area_of(sid):
    if sid in LOCKS: return "14-locks"
    if sid.split(".")[0] in ("home", "sleep", "recovery") and sid.split(".")[-1] in STATES: return "13-states"
    if sid == "insights.all.loading": return "13-states"
    head = sid.split(".")[0]
    if sid.startswith("onboarding.paywall") or sid.startswith("premium."): return "02-paywall"
    return {"onboarding": "01-onboarding", "home": "03-home", "sleep": "04-sleep", "recovery": "05-recovery", "insights": "06-insights", "coach": "07-coach", "night": "08-night",
            "profile": "09-profile-settings-privacy", "settings": "09-profile-settings-privacy", "privacy": "09-profile-settings-privacy", "reviews": "10-reviews", "widgets": "11-system"}.get(head, "99-other")
rows = []; counters = {}
def pages(base):
    files = sorted(f for f in os.listdir(os.path.dirname(base)) if f.startswith(os.path.basename(base) + "__") and f.endswith(".png"))
    out = {}
    for f in files:
        tag = f[len(os.path.basename(base)) + 2:-4]
        if tag in ("top", "bottom") or re.fullmatch(r"p\d+", tag): out[tag] = os.path.join(os.path.dirname(base), f)
    return out
for sid in sorted(catalog, key=lambda s: (area_of(s), list(catalog).index(s))):
    area = area_of(sid)
    modes = ["light"] if sid.startswith("onboarding.") and not sid.startswith("onboarding.paywall") else ["light", "dark"]
    counters[area] = counters.get(area, 0) + 1
    n = counters[area]
    for mode in modes:
        cfg = "A-light" if mode == "light" else "A-dark"
        base = os.path.join(matrix, cfg, "QA17Pro", sid)
        if not os.path.exists(base + "__top.png"): rows.append((f"(missing) {sid}", area, sid, mode, "not produced")); continue
        found = pages(base)
        order = ["top"] + [k for k in sorted(found, key=lambda k: (len(k), k)) if re.fullmatch(r"p\d+", k)] + (["bottom"] if "bottom" in found else [])
        for i, tag in enumerate(order):
            label = "top" if tag == "top" else "bottom" if tag == "bottom" else f"mid-{int(tag[1:])}"
            name = re.sub(r"[^A-Za-z0-9-]", "-", sid.replace(".", "-"))
            fn = f"{n:02d}-{name}-{mode}" + ("" if len(order) == 1 else f"-{label}") + ".jpg"
            os.makedirs(os.path.join(out, area), exist_ok=True)
            Image.open(found[tag]).convert("RGB").save(os.path.join(out, area, fn), "JPEG", quality=92)
            rows.append((os.path.join(area, fn), area, sid, mode, label if len(order) > 1 else "single"))
with open(os.path.join(out, "gallery.tsv"), "w") as h:
    for r in rows: h.write("\t".join(r) + "\n")
print(len(rows), "files;", sum(1 for r in rows if r[0].startswith("(missing)")), "missing")
