#!/usr/bin/env python3
"""Recovers which combinations a viewed sheet showed, when the sheet directory is gone.

The system's /tmp cleanup deleted every contact sheet, screenshot and manifest of the matrix runs after they were viewed (the working files now live in
~/qa-work). Docs/qa/coverage/viewed.tsv survives, and each line's note says what the sheet was: the screen is the sheet's name, the devices ("SE", "17 Pro")
and the configurations ("A-light against B-AX3 and B-AX5", "D-RTL against D-DoubleLength and D-Bounded") are in its first words. This script reads those
and writes Docs/qa/coverage/recovered.tsv (sheet, screen, page, combinations) and recovered_produced.tsv (a sheet that was viewed was produced). A line whose
note does not say its columns is left out, so its combinations stay UNVERIFIED. Coverage marks every recovered combination "(recovered)" because its image
can no longer be looked at again.

    scripts/qa_recover_sheets.py
"""
import json
import os
import re

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
base = os.path.join(root, "Docs", "qa", "coverage")
catalog = {s["id"]: s for s in json.load(open(os.path.join(base, "catalog.json")))}
known = {line.split("\t")[0] for line in open(os.path.join(base, "sheets.tsv"))}

DEVICE = {"SE": "QASE", "Pro": "QA17Pro", "Max": "QA17ProMax"}
C_NAMES = {
    "Reduce Motion": "C-ReduceMotion", "Increase Contrast": "C-IncreaseContrast", "Bold Text": "C-BoldText",
    "Reduce Transparency": "C-ReduceTransparency", "Differentiate Without Color": "C-DifferentiateWithoutColor", "Button Shapes": "C-ButtonShapes",
    "On/Off Labels": "C-OnOffLabels", "Smart Invert": "C-SmartInvert",
}


MARKERS = [
    r"A-(?:light|dark) against", r"D-RTL", r"B-AX3 against", r"A-light against B-AX5", r"FIXED BUILD, A-light", r", Bold Text / Reduce Transparency",
    r", Button Shapes / On/Off Labels", r", Reduce Motion",
]


def head_of(note):
    """The words before the configurations: what the sheet showed (device, screen), nothing from the sentences after."""
    text = re.sub(r"^FIXED BUILD, ", "", note)
    cut = len(text)
    for marker in MARKERS:
        m = re.search(marker, text)
        if m:
            cut = min(cut, m.start())
    if cut == 0:  # "FIXED BUILD, A-light, 17 Pro and SE, ..." names the devices after the configuration
        return text[:60]
    return text[:cut]


def devices(note):
    head = head_of(note)
    found = []
    if re.search(r"\bSE\b", head):
        found.append("QASE")
    if re.search(r"17 Pro(?! Max)", head):
        found.append("QA17Pro")
    if re.search(r"17 Pro Max|\bMax\b", head):
        found.append("QA17ProMax")
    return found


def configs(note):
    head = note[:200]
    if "D-RTL" in head:
        return ["D-RTL", "D-DoubleLength", "D-Bounded"]
    m = re.search(r"A-(light|dark) against B-AX3 and B-AX5", head)
    if m:
        return [f"A-{m.group(1)}", "B-AX3-light", "B-AX5-light"]
    if re.search(r"B-AX3 against B-AX5", head):
        return ["B-AX3-light", "B-AX5-light"]
    if re.search(r"A-light against B-AX5", head):
        return ["A-light", "B-AX5-light"]
    if "Bold Text / Reduce Transparency / Differentiate Without Color" in head:
        return ["C-BoldText", "C-ReduceTransparency", "C-DifferentiateWithoutColor"]
    if "Button Shapes / On/Off Labels / Smart Invert" in head:
        return ["C-ButtonShapes", "C-OnOffLabels", "C-SmartInvert"]
    m = re.search(r"A-(light|dark) against Reduce Motion and Increase Contrast", head)
    if m:
        return [f"A-{m.group(1)}", "C-ReduceMotion", "C-IncreaseContrast"]
    if "FIXED BUILD, A-light" in head:
        return ["A-light"]
    return []


viewed = []
for line in open(os.path.join(base, "viewed.tsv")):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 3 and p[0] not in known:
        viewed.append(p)

sheets = {}
for p in viewed:
    name, note = p[0], p[2]
    if len(p) > 3 and p[3]:
        continue
    screen = name.split("__")[0]
    if screen not in catalog:
        continue
    cfgs, devs = configs(note), devices(note)
    if not cfgs or not devs:
        continue
    page = "top,bottom" if "bottom" in note[:400] or "top and bottom" in note else "top,bottom"
    combos = sorted({f"{c}/{d}" for c in cfgs for d in devs})
    # The two columns of A-light against B-AX* are the same sheet for each device; the same note recorded for the SE sheet and the Pro sheet names both.
    sheets.setdefault(name, (screen, page, combos))

with open(os.path.join(base, "recovered.tsv"), "w") as out:
    for name, (screen, page, combos) in sorted(sheets.items()):
        out.write(f"{name}\t{screen}\t{page}\t{'; '.join(combos)}\n")
made = set()
for name, (screen, page, combos) in sheets.items():
    for combo in combos:
        config, device = combo.split("/")
        made.add((screen, config, device))
with open(os.path.join(base, "recovered_produced.tsv"), "w") as out:
    for screen, config, device in sorted(made):
        scrolls = catalog[screen]["scrolls"]
        out.write(f"{screen}\t{config}\t{device}\t{'top,bottom' if scrolls else 'top,noscroll'}\ttrue\ttrue\t0\n")
print(f"{len(viewed)} viewed sheets without a directory; {len(sheets)} recovered; {len(viewed) - len(sheets)} left out (columns not named); {len(made)} combinations")
