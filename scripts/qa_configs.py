#!/usr/bin/env python3
"""QA part 3: the configurations of QA_COVERAGE.md as arguments to scripts/qa_matrix.py, and a runner for a queue of them on one simulator.

    scripts/qa_configs.py list
    scripts/qa_configs.py run <device> <config> [<config> ...] [--derived DIR] [--out DIR] [--resume]

A configuration is a name (the folder under matrix/), the simulator state (appearance, content size, contrast, accessibility defaults), launch
arguments, what the app's environment probe must say for the run to count (a configuration that did not take effect fails instead of being
photographed), and which screens it is for ("all", "tier1", or the six tabs).
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TABS = "home.day.full,home.evening.full,sleep.day.full,recovery.today.full,insights.all.full,coach.hub.full"
BASE_EXPECT = {"increaseContrast": "0", "invertColors": "0", "boldText": "0", "reduceMotion": "0", "reduceTransparency": "0",
               "differentiateWithoutColor": "0", "buttonShapes": "0", "onOffLabels": "0", "layoutDirection": "ltr"}


def expect(**kw):
    values = dict(BASE_EXPECT)
    values.update({k: v for k, v in kw.items() if v is not None})
    return ";".join(f"{k}={v}" for k, v in values.items())


def config(name, *, appearance="light", text="default", contrast=False, ax="", launch="", expectations=None, screens="all", only=""):
    size = {"default": "large", "ax3": "accessibility3", "ax5": "accessibility5"}[text]
    exp = expect(colorScheme=appearance, textSize=size, **(expectations or {}))
    return {"name": name, "appearance": appearance, "text": text, "contrast": contrast, "ax": ax, "launch": launch, "expect": exp, "screens": screens, "only": only}


CONFIGS = {}


def add(c):
    CONFIGS[c["name"]] = c


add(config("A-light"))
add(config("A-dark", appearance="dark"))
add(config("B-AX3-light", text="ax3"))
add(config("B-AX3-dark", text="ax3", appearance="dark"))
add(config("B-AX5-light", text="ax5"))
add(config("B-AX5-dark", text="ax5", appearance="dark", screens="tabs", only=TABS))
C = [
    ("ReduceMotion", "ReduceMotionEnabled", {"reduceMotion": "1"}, False),
    ("IncreaseContrast", "", {"increaseContrast": "1"}, True),
    ("BoldText", "EnhancedTextLegibilityEnabled", {"boldText": "1"}, False),
    ("ReduceTransparency", "EnhancedBackgroundContrastEnabled", {"reduceTransparency": "1"}, False),
    ("DifferentiateWithoutColor", "DifferentiateWithoutColor", {"differentiateWithoutColor": "1"}, False),
    ("ButtonShapes", "ButtonShapesEnabled", {"buttonShapes": "1"}, False),
    ("OnOffLabels", "IncreaseButtonLegibilityEnabled", {"onOffLabels": "1"}, False),
    ("SmartInvert", "InvertColorsEnabled", {"invertColors": "1"}, False),
]
for label, key, exp, contrast in C:
    add(config(f"C-{label}", ax=key, contrast=contrast, expectations=exp, screens="tier1"))
    add(config(f"C-{label}-dark", appearance="dark", ax=key, contrast=contrast, expectations=exp, screens="tabs", only=TABS))
add(config("D-DoubleLength", launch="-NSDoubleLocalizedStrings YES"))
add(config("D-Accented", launch="-NSAccentuateLocalizedStrings YES"))
add(config("D-Bounded", launch="-NSSurroundLocalizedStrings YES"))
add(config("D-RTL", launch="-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES", expectations={"layoutDirection": "rtl"}))
# Sinhala and Tamil words for the units and counts (DEBUG -pseudoScript, R68): the taller glyphs and the longer words, before there is a translation.
add(config("D-PseudoSi", launch="-pseudoScript si", screens="tier1"))
add(config("D-PseudoTa", launch="-pseudoScript ta", screens="tier1"))
# The build has no Sinhala, Tamil or Arabic yet: asked for one, it must fall back to English cleanly (no keys, no blanks) and stay left to right.
for code, locale in [("si", "si_LK"), ("ta", "ta_LK"), ("ar", "ar_SA")]:
    add(config(f"E-lang-{code}", launch=f"-AppleLanguages ({code}) -AppleLocale {locale}", screens="tier1"))
for locale in ["en_LK", "de_DE", "ar_SA", "si_LK", "ta_LK", "th_TH"]:
    add(config(f"E-{locale}", launch=f"-AppleLanguages (en) -AppleLocale {locale}", screens="tier1"))


# The hierarchy checks run where layout is most at risk; elsewhere the screenshots are the evidence.
WITH_CHECKS = {"A-light", "A-dark", "B-AX5-light", "D-RTL"}
# Every page down the screen (not only its top and bottom) for the reference configuration.
WITH_PAGES = {"A-light", "A-dark"}


def run(device, names, out, derived, resume):
    code = 0
    for spec in names:
        # "<name>@t1": the same configuration for the tier-one screens only. "<name>@rewalk": only the screens whose walk did not move, again.
        name, _, suffix = spec.partition("@")
        c = dict(CONFIGS[name])
        # "<name>@only:insights.history+night.": only the screens whose ids start with one of these ('+' between them).
        if suffix.startswith("only:"):
            c["only"] = suffix[len("only:"):].replace("+", ",")
        if suffix == "t1" and c["screens"] == "all":
            c["screens"] = "tier1"
        skip = "gap,sleepOnly,noPermission,loading" if suffix == "core" else ""
        command = [sys.executable, os.path.join(HERE, "qa_matrix.py"), "--out", out, "--config", c["name"], "--device", device, "--appearance", c["appearance"],
                   "--text", c["text"], "--expect", c["expect"]]
        if c["contrast"]:
            command.append("--contrast")
        if c["ax"]:
            command += ["--ax", c["ax"]]
        if c["launch"]:
            command += ["--launch", c["launch"]]
        if c["screens"] == "tier1":
            command.append("--tier1")
        if name not in WITH_CHECKS:
            command.append("--no-checks")
        if skip:
            command += ["--skip-states", skip]
        if name in WITH_PAGES and device.startswith("pro") and not os.environ.get("QA_NO_PAGES"):
            command.append("--pages")
        if c["only"]:
            command += ["--only", c["only"]]
        if derived:
            command += ["--derived", derived]
        if suffix == "rewalk":
            command.append("--rewalk")
        if resume:
            command.append("--resume")
        print("running", spec, "on", device, flush=True)
        code |= subprocess.run(command).returncode
    return code


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0] == "list":
        for n, c in CONFIGS.items():
            print(n, c["screens"], c["expect"])
        sys.exit(0)
    assert args[0] == "run"
    device = args[1]
    rest = args[2:]
    out, derived, resume = os.environ.get("QA_OUT", os.path.expanduser("~/qa-work/qamx")), "", False
    names = []
    i = 0
    while i < len(rest):
        if rest[i] == "--out":
            out = rest[i + 1]; i += 2
        elif rest[i] == "--derived":
            derived = rest[i + 1]; i += 2
        elif rest[i] == "--resume":
            resume = True; i += 1
        else:
            names.append(rest[i]); i += 1
    sys.exit(run(device, names, out, derived, resume))
