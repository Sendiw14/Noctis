#!/usr/bin/env python3
"""QA part 3: runs QAMatrixTests (the screen catalog) under one configuration on one simulator.

    scripts/qa_matrix.py --out DIR --config A-dark --device pro --appearance dark [--text default|ax1..ax5|xs..xxxl]
                         [--contrast] [--ax ReduceMotionEnabled,BoldTextEnabled] [--launch "-NSDoubleLocalizedStrings YES"]
                         [--expect "colorScheme=dark;boldText=1"] [--areas home,sleep] [--only home.day,sleep.day] [--tier1] [--resume]

The simulator is put in the configuration with `simctl ui` (appearance, content size, increase contrast) and, for the accessibility settings
`simctl ui` does not have, by writing the com.apple.Accessibility defaults of the simulated device. Every setting the run claims is then
read back from the app by the environment probe (QA_EXPECT), so a configuration that did not take effect fails instead of being photographed.
Output: DIR/matrix/<config>/<device>/ (see Tests/UITests/QAMatrixTests.swift).
"""
import argparse
import os
import subprocess
import sys

DEVICES = {
    "se": ("012EDB6B-2D63-40D6-A391-BA63BA86ADFD", "QASE"),
    "pro": ("A49F16C6-6984-4928-9218-E007AF63F0F4", "QA17Pro"),
    "max": ("C1BF1779-56B3-49C4-8829-DD48FAC6F1E0", "QA17ProMax"),
}
# Second simulators of the same models share the work (their screenshots go in the same folders): created with `simctl create`, see QA_COVERAGE.md.
if os.environ.get("QA_EXTRA_DEVICES"):
    for entry in os.environ["QA_EXTRA_DEVICES"].split(","):
        key, udid, folder = entry.split(":")
        DEVICES[key] = (udid, folder)

SIZES = {
    "default": "large", "xs": "extra-small", "ax1": "accessibility-medium", "ax2": "accessibility-large", "ax3": "accessibility-extra-large",
    "ax4": "accessibility-extra-extra-large", "ax5": "accessibility-extra-extra-extra-large",
}

# com.apple.Accessibility keys the settings are stored under, each verified by reading the setting back from the app (QA_LEDGER.md's API table):
#   ReduceMotionEnabled -> reduceMotion, EnhancedTextLegibilityEnabled -> boldText, EnhancedBackgroundContrastEnabled -> reduceTransparency,
#   DifferentiateWithoutColor -> differentiateWithoutColor, ButtonShapesEnabled -> buttonShapes, IncreaseButtonLegibilityEnabled -> onOffLabels,
#   InvertColorsEnabled -> invertColors. (BoldTextEnabled, OnOffSwitchLabelsEnabled and IncreaseButtonLegibility are read by nothing.)
ACCESSIBILITY_KEYS = [
    "ReduceMotionEnabled", "EnhancedTextLegibilityEnabled", "EnhancedBackgroundContrastEnabled", "DifferentiateWithoutColor", "ButtonShapesEnabled",
    "IncreaseButtonLegibilityEnabled", "InvertColorsEnabled", "ClassicInvertColorsEnabled",
]

AREAS = ["Onboarding", "Home", "Sleep", "Recovery", "Insights", "Coach", "Night", "Reviews", "Premium", "Profile", "Settings", "Privacy", "Widgets"]

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(*command, check=True):
    return subprocess.run(command, check=check, capture_output=True, text=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--device", required=True, choices=DEVICES)
    parser.add_argument("--appearance", default="light", choices=["light", "dark"])
    parser.add_argument("--text", default="default", choices=SIZES)
    parser.add_argument("--contrast", action="store_true")
    parser.add_argument("--ax", default="", help="comma separated com.apple.Accessibility keys to turn on")
    parser.add_argument("--launch", default="")
    parser.add_argument("--expect", default="")
    parser.add_argument("--areas", default="", help="comma separated, as the test names: home,sleep,...")
    parser.add_argument("--only", default="")
    parser.add_argument("--tier1", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--rewalk", action="store_true",
                        help="visit only the screens a walk found not to move (a __noscroll marker) and walk them again, from three heights")
    parser.add_argument("--skip-states", default="", help="comma separated state names left out of the tabs (the core pass)")
    parser.add_argument("--pages", action="store_true", help="photograph every page down the screen, not only its top and its bottom")
    parser.add_argument("--no-checks", action="store_true", help="skip the hierarchy checks (they cost a snapshot at each end of every page)")
    parser.add_argument("--derived", default=os.environ.get("QA_DERIVED", ""))
    args = parser.parse_args()

    udid, _ = DEVICES[args.device]
    run("xcrun", "simctl", "boot", udid, check=False)
    run("xcrun", "simctl", "bootstatus", udid, "-b")
    run("xcrun", "simctl", "ui", udid, "appearance", args.appearance)
    run("xcrun", "simctl", "ui", udid, "content_size", SIZES[args.text])
    run("xcrun", "simctl", "ui", udid, "increase_contrast", "enabled" if args.contrast else "disabled")
    wanted = {k for k in args.ax.split(",") if k}
    for key in ACCESSIBILITY_KEYS:
        run("xcrun", "simctl", "spawn", udid, "defaults", "write", "com.apple.Accessibility", key, "-bool", "YES" if key in wanted else "NO")
    for key in wanted - set(ACCESSIBILITY_KEYS):
        run("xcrun", "simctl", "spawn", udid, "defaults", "write", "com.apple.Accessibility", key, "-bool", "YES")

    areas = [a.strip().capitalize() for a in args.areas.split(",") if a.strip()] or AREAS
    env = dict(os.environ)
    env.update({
        "TEST_RUNNER_QA_OUT": args.out,
        "TEST_RUNNER_QA_DEVICE_NAME": DEVICES[args.device][1],
        "TEST_RUNNER_QA_CONFIG": args.config,
        "TEST_RUNNER_QA_EXPECT": args.expect,
        "TEST_RUNNER_QA_LAUNCH_EXTRA": args.launch,
        "TEST_RUNNER_QA_ONLY": args.only,
        "TEST_RUNNER_QA_TIER1": "1" if args.tier1 else "0",
        "TEST_RUNNER_QA_RESUME": "1" if args.resume else "0",
        "TEST_RUNNER_QA_REWALK": "1" if args.rewalk else "0",
        "TEST_RUNNER_QA_CHECKS": "0" if args.no_checks else "1",
        "TEST_RUNNER_QA_PAGES": "1" if args.pages else "0",
        "TEST_RUNNER_QA_SKIP_STATES": args.skip_states,
    })
    command = [
        "xcodebuild", "test-without-building", "-project", os.path.join(PROJECT_DIR, "Noctis.xcodeproj"), "-scheme", "Noctis",
        "-destination", f"platform=iOS Simulator,id={udid}",
        "-resultBundlePath", os.path.join(args.out, f"xcresult-{args.config}-{args.device}-{os.getpid()}.xcresult"),
    ]
    if args.derived:
        command += ["-derivedDataPath", args.derived]
    for area in areas:
        command += [f"-only-testing:NoctisUITests/QAMatrixTests/test{area}"]
    os.makedirs(args.out, exist_ok=True)
    log = os.path.join(args.out, f"run-{args.config}-{args.device}.log")
    with open(log, "w") as handle:
        result = subprocess.run(command, env=env, stdout=handle, stderr=subprocess.STDOUT, cwd=PROJECT_DIR)
    print(f"{args.config} / {args.device}: exit {result.returncode}, log {log}")
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
