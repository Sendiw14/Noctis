#!/usr/bin/env python3
"""QA part 4: contact sheets of the tier-1 matrix, to be looked at.

    scripts/qa_tier1_sheets.py <matrix dir> <out dir> [--devices pro,se,max] [--screens prefix,prefix] [--configs A-light,A-dark,B-AX3-light,B-AX5-light,...]

For each device and screen, a sheet holds a configuration's top and bottom pictures side by side, four pictures to a sheet (so a phone is about 340 points wide
and its text can be read); a screen that does not scroll has top pictures only. Writes <out dir>/<device>__<screen>__<n>.png and sheets.tsv
(sheet, device, screen, the "<config>:<page>" cells in order), which scripts/qa_tier1.py reads.
"""
import argparse, os
from PIL import Image, ImageDraw, ImageFont

DEVICES = {"pro": "QA17Pro", "max": "QA17ProMax", "se": "QASE"}

def font(size):
    for p in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            continue
    return ImageFont.load_default()

parser = argparse.ArgumentParser()
parser.add_argument("matrix"); parser.add_argument("out")
parser.add_argument("--devices", default="pro,se,max")
parser.add_argument("--screens", default="")
parser.add_argument("--configs", default="")
parser.add_argument("--screens-per-sheet", type=int, default=0, help="with one configuration: this many screens (top and bottom each) on a sheet")
args = parser.parse_args()
os.makedirs(args.out, exist_ok=True)
prefixes = [p for p in args.screens.split(",") if p]
order = [c for c in args.configs.split(",") if c]
configs = sorted(d for d in os.listdir(args.matrix) if os.path.isdir(os.path.join(args.matrix, d)))
if order:
    configs = [c for c in order if c in configs] + [c for c in configs if c not in order and not order]
rows = []

def make(device, screen, number, chunk):
    tiles = []
    height = 1500
    for c, page, path, label in chunk:
        im = Image.open(path).convert("RGB")
        im = im.resize((int(im.width * height / im.height), height))
        d = ImageDraw.Draw(im); d.rectangle([0, 0, im.width, 40], fill=(0, 0, 0))
        d.text((8, 8), label, fill=(255, 255, 255), font=font(24))
        tiles.append(im)
    width = sum(t.width for t in tiles) + 10 * len(tiles)
    sheet = Image.new("RGB", (width, height), (60, 60, 60)); x = 0
    for t in tiles:
        sheet.paste(t, (x, 0)); x += t.width + 10
    sheet = sheet.resize((int(sheet.width * 0.5), int(sheet.height * 0.5)))
    name = f"{device}__{screen}__{number}.png"
    sheet.save(os.path.join(args.out, name))
    return (name, device, screen, ";".join(f"{c}:{p}" for c, p, _, _ in chunk))

for device in args.devices.split(","):
    folder = DEVICES[device]
    screens = set()
    for c in configs:
        d = os.path.join(args.matrix, c, folder)
        if os.path.isdir(d):
            for f in os.listdir(d):
                if f.endswith("__top.png"):
                    screens.add(f[:-len("__top.png")])
    for screen in sorted(screens):
        if prefixes and not any(screen.startswith(p) for p in prefixes):
            continue
        cells = []
        for c in configs:
            for page in ("top", "bottom"):
                path = os.path.join(args.matrix, c, folder, f"{screen}__{page}.png")
                if os.path.exists(path):
                    cells.append((c, page, path, f"{device} {screen} {c} {page}"))
        step = 4
        if args.screens_per_sheet:
            continue
        for index in range(0, len(cells), step):
            chunk = cells[index:index + step]
            rows.append(make(device, screen, index // step + 1, chunk))
if args.screens_per_sheet:
    for device in args.devices.split(","):
        folder = DEVICES[device]
        cfg = configs[0]
        d = os.path.join(args.matrix, cfg, folder)
        screens = sorted(f[:-len("__top.png")] for f in os.listdir(d) if f.endswith("__top.png") and (not prefixes or any(f.startswith(p) for p in prefixes)))
        for index in range(0, len(screens), args.screens_per_sheet):
            group = screens[index:index + args.screens_per_sheet]
            chunk = []
            for screen in group:
                for page in ("top", "bottom"):
                    path = os.path.join(d, f"{screen}__{page}.png")
                    if os.path.exists(path):
                        chunk.append((cfg, page, path, f"{screen} {page}"))
            name = f"{device}__{cfg}__{index // args.screens_per_sheet + 1:02d}"
            number = ""
            rows.append(make(device, f"{cfg}__{index // args.screens_per_sheet + 1:02d}", 0, chunk)[:3] + (";".join(f"{cfg}:{pg}:{os.path.basename(p)}" for cfg, pg, p, _ in chunk),))
with open(os.path.join(args.out, "sheets.tsv"), "w") as handle:
    for r in rows:
        handle.write("\t".join(r) + "\n")
print(len(rows), "sheets")
