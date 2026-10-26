#!/usr/bin/env python3
"""Pixel-by-pixel comparison of two screen-matrix runs (Docs/QA_COVERAGE.md): a baseline taken before a change and a run taken after it.

    scripts/qa_pixeldiff.py <baseline matrix dir> <after matrix dir> <report dir> [--config A-light] [--device QA17Pro]

Both directories are the `matrix` folder QAMatrixTests writes (`<config>/<device>/<screen id>__<page>.png`). Every PNG present in the baseline is looked for in the
after run and compared exactly (decoded RGB, not file bytes). Writes <report dir>/summary.tsv (one line per picture: status, differing pixels, share, bounding box)
and, for each picture that differs, <report dir>/diff/<config>-<device>-<name>.png (the after picture with differing pixels in magenta, the baseline beside it).

`--ignore-top N` crops the first N pixel rows from both pictures (the status bar). Statuses: SAME (identical), DIFF (some pixels differ), MISSING (not in the after run), EXTRA (only in the after run), SIZE (different dimensions).
Exit status: 0 when every baseline picture is SAME, 1 otherwise.
"""
import argparse
import os
import sys

from PIL import Image, ImageChops


def pictures(root, config, device):
    base = os.path.join(root, config, device)
    if not os.path.isdir(base):
        return {}
    return {name: os.path.join(base, name) for name in sorted(os.listdir(base)) if name.endswith(".png")}


def compare(before_path, after_path, ignore_top=0):
    # Opaque screenshots: compare the three colour channels. (getbbox() on an RGBA difference looks at the alpha channel only, which is always 0 here.)
    before = Image.open(before_path).convert("RGB")
    after = Image.open(after_path).convert("RGB")
    if ignore_top:  # the status bar: two simulators do not always show the same override
        before = before.crop((0, ignore_top, before.width, before.height))
        after = after.crop((0, ignore_top, after.width, after.height))
    if before.size != after.size:
        return "SIZE", before.size, after.size, None
    difference = ImageChops.difference(before, after)
    box = difference.getbbox()
    if box is None:
        return "SAME", 0, 0, None
    mask = difference.convert("L").point(lambda value: 255 if value else 0)
    count = mask.histogram()[255]
    return "DIFF", count, box, (before, after, mask)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline")
    parser.add_argument("after")
    parser.add_argument("report")
    parser.add_argument("--config", action="append", default=[])
    parser.add_argument("--device", action="append", default=[])
    parser.add_argument("--ignore-top", type=int, default=0, help="ignore this many pixel rows at the top (the status bar), e.g. 190 on a 17 Pro, 90 on an SE")
    args = parser.parse_args()
    configs = args.config or sorted(os.listdir(args.baseline))
    devices = args.device or ["QA17Pro", "QASE"]
    os.makedirs(os.path.join(args.report, "diff"), exist_ok=True)
    totals = {"SAME": 0, "DIFF": 0, "MISSING": 0, "EXTRA": 0, "SIZE": 0}
    rows = []
    for config in configs:
        for device in devices:
            before = pictures(args.baseline, config, device)
            after = pictures(args.after, config, device)
            for name, path in before.items():
                if name not in after:
                    totals["MISSING"] += 1
                    rows.append((config, device, name, "MISSING", "", "", ""))
                    continue
                status, count, box, images = compare(path, after[name], args.ignore_top)
                totals[status] += 1
                if status == "SAME":
                    continue
                if status == "SIZE":
                    rows.append((config, device, name, status, "", "", f"{count} vs {box}"))
                    continue
                width, height = images[0].size
                rows.append((config, device, name, status, count, f"{100 * count / (width * height):.3f}%", f"{box} (y offset {args.ignore_top})"))
                before_image, after_image, mask = images
                marked = after_image.copy()
                marked.paste(Image.new("RGB", marked.size, (255, 0, 255)), mask=mask)
                sheet = Image.new("RGB", (width * 3, height), (255, 255, 255))
                sheet.paste(before_image, (0, 0))
                sheet.paste(after_image, (width, 0))
                sheet.paste(marked, (width * 2, 0))
                sheet.save(os.path.join(args.report, "diff", f"{config}-{device}-{name}"))
            for name in after:
                if name not in before:
                    totals["EXTRA"] += 1
                    rows.append((config, device, name, "EXTRA", "", "", ""))
    with open(os.path.join(args.report, "summary.tsv"), "w") as handle:
        handle.write("config\tdevice\tpicture\tstatus\tpixels\tshare\tbox\n")
        for row in rows:
            handle.write("\t".join(str(cell) for cell in row) + "\n")
    print(", ".join(f"{key}={value}" for key, value in totals.items()))
    return 0 if totals["DIFF"] + totals["MISSING"] + totals["SIZE"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
