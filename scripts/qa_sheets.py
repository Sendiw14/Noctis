#!/usr/bin/env python3
"""QA part 3: contact sheets from the matrix run (QAMatrixTests output).

    scripts/qa_sheets.py <matrix dir> <output dir> [--screens id,id|prefix*] [--per-sheet 3] [--cell 460] [--pages top,bottom]

<matrix dir> holds <config>/<device>/<screen id>__<page>.png as QAMatrixTests wrote them. For each screen and page, the images of every
configuration and device are laid side by side, `--per-sheet` to a sheet, each under a caption naming the configuration and the device, at
`--cell` points wide, so a sheet can be read at the size it is shown. Writes <output dir>/<screen id>__<page>__<n>.png and sheets.tsv
(sheet, screen, page, configs-and-devices), which scripts/qa_coverage.py reads.
"""
import argparse
import collections
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def font(size):
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc", "/Library/Fonts/Arial.ttf"):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def collect(matrix):
    """{(screen, page): [(config, device, path)]} in a stable order."""
    found = collections.defaultdict(list)
    for config in sorted(os.listdir(matrix)):
        cdir = os.path.join(matrix, config)
        if not os.path.isdir(cdir):
            continue
        for device in sorted(os.listdir(cdir)):
            ddir = os.path.join(cdir, device)
            if not os.path.isdir(ddir):
                continue
            for name in sorted(os.listdir(ddir)):
                if not name.endswith(".png") or "__" not in name:
                    continue
                screen, page = name[:-4].split("__", 1)
                found[(screen, page)].append((config, device, os.path.join(ddir, name)))
    return found


def matches(screen, patterns):
    if not patterns:
        return True
    return any(screen == p or (p.endswith("*") and screen.startswith(p[:-1])) or screen.startswith(p + ".") for p in patterns)


def make_sheet(title, cells, cell_width, out_path):
    caption_h, title_h, gap = 46, 60, 16
    thumbs = []
    for caption, path in cells:
        image = Image.open(path).convert("RGB")
        scale = cell_width / image.width
        thumbs.append((caption, image.resize((cell_width, max(1, round(image.height * scale))), Image.LANCZOS)))
    height = max(t.height for _, t in thumbs)
    width = gap + len(thumbs) * (cell_width + gap)
    sheet = Image.new("RGB", (width, title_h + caption_h + height + gap), (32, 32, 36))
    draw = ImageDraw.Draw(sheet)
    draw.text((gap, 14), title, fill=(255, 255, 255), font=font(30))
    for index, (caption, thumb) in enumerate(thumbs):
        x = gap + index * (cell_width + gap)
        draw.text((x, title_h + 6), caption, fill=(255, 214, 10), font=font(26))
        sheet.paste(thumb, (x, title_h + caption_h))
    sheet.save(out_path)


def make_pair_sheet(title, columns, cell_width, out_path):
    """columns: [(caption, top path, bottom path or None)]: one row of tops and, under it, one row of bottoms where any column has one."""
    caption_h, title_h, gap, label_h = 46, 60, 16, 30
    tops = []
    for caption, top, bottom in columns:
        timg = Image.open(top).convert("RGB")
        tops.append((caption, timg.resize((cell_width, max(1, round(timg.height * cell_width / timg.width))), Image.LANCZOS)))
    bottoms = []
    for caption, top, bottom in columns:
        if bottom:
            bimg = Image.open(bottom).convert("RGB")
            bottoms.append(bimg.resize((cell_width, max(1, round(bimg.height * cell_width / bimg.width))), Image.LANCZOS))
        else:
            bottoms.append(None)
    top_h = max(t.height for _, t in tops)
    bottom_h = max((b.height for b in bottoms if b), default=0)
    width = gap + len(columns) * (cell_width + gap)
    height = title_h + caption_h + top_h + (label_h + bottom_h + gap if bottom_h else 0) + gap
    sheet = Image.new("RGB", (width, height), (32, 32, 36))
    draw = ImageDraw.Draw(sheet)
    draw.text((gap, 14), title, fill=(255, 255, 255), font=font(30))
    for index, (caption, thumb) in enumerate(tops):
        x = gap + index * (cell_width + gap)
        draw.text((x, title_h + 6), caption, fill=(255, 214, 10), font=font(26))
        sheet.paste(thumb, (x, title_h + caption_h))
    if bottom_h:
        y = title_h + caption_h + top_h + 4
        draw.text((gap, y), "bottom of the page", fill=(160, 200, 255), font=font(22))
        for index, thumb in enumerate(bottoms):
            if thumb:
                sheet.paste(thumb, (gap + index * (cell_width + gap), y + label_h))
    sheet.save(out_path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("matrix")
    parser.add_argument("output")
    parser.add_argument("--screens", default="")
    parser.add_argument("--per-sheet", type=int, default=3)
    parser.add_argument("--cell", type=int, default=460)
    parser.add_argument("--pages", default="top,bottom")
    parser.add_argument("--configs", default="", help="only these configurations (comma separated)")
    parser.add_argument("--mode", default="configs", choices=["configs", "screens", "pairs", "spairs"],
                        help="configs: one screen under several configurations per sheet; screens: several screens under one configuration per sheet; "
                             "pairs: one screen under several configurations, the top row and under it the bottom row (the default for coverage)")
    args = parser.parse_args()
    os.makedirs(args.output, exist_ok=True)
    patterns = [p for p in args.screens.split(",") if p]
    pages = args.pages.split(",")
    configs = [c for c in args.configs.split(",") if c]
    found = collect(args.matrix)
    rows = []
    if args.mode == "screens":
        grouped = collections.defaultdict(list)
        for (screen, page), items in sorted(found.items()):
            if not matches(screen, patterns) or (page not in pages and not (page.startswith("p") and "pages" in pages)):
                continue
            for config, device, path in items:
                if not configs or config in configs:
                    grouped[(config, device, page)].append((screen, path))
        for (config, device, page), screens in sorted(grouped.items()):
            for number, start in enumerate(range(0, len(screens), args.per_sheet)):
                chunk = screens[start:start + args.per_sheet]
                name = f"{config}__{device}__{page}__{chunk[0][0]}__{number + 1}.png"
                make_sheet(f"{config} / {device}  ({page})", [(screen, path) for screen, path in chunk], args.cell, os.path.join(args.output, name))
                rows.append((name, ",".join(s for s, _ in chunk), page, f"{config}/{device}"))
        with open(os.path.join(args.output, "sheets.tsv"), "a") as handle:
            for row in rows:
                handle.write("\t".join(row) + "\n")
        print(f"{len(rows)} sheets in {args.output}")
        return 0
    if args.mode == "spairs":
        # Several screens under one configuration and device, each with its top and its bottom: for a first look at one configuration.
        grouped = collections.defaultdict(list)
        for (screen, page), items in sorted(found.items()):
            if page != "top" or not matches(screen, patterns):
                continue
            for config, device, path in items:
                if configs and config not in configs:
                    continue
                bottom = os.path.join(os.path.dirname(path), f"{screen}__bottom.png")
                grouped[(config, device)].append((screen, path, bottom if os.path.exists(bottom) else None))
        for (config, device), screens in sorted(grouped.items()):
            for number, start in enumerate(range(0, len(screens), args.per_sheet)):
                chunk = screens[start:start + args.per_sheet]
                name = f"{config}__{device}__{chunk[0][0]}__{number + 1}.png"
                make_pair_sheet(f"{config} / {device}", [(screen, top, bottom) for screen, top, bottom in chunk], args.cell, os.path.join(args.output, name))
                rows.append((name, ",".join(s for s, _, _ in chunk), "top,bottom", f"{config}/{device}"))
        with open(os.path.join(args.output, "sheets.tsv"), "a") as handle:
            for row in rows:
                handle.write("\t".join(row) + "\n")
        print(f"{len(rows)} sheets in {args.output}")
        return 0
    if args.mode == "pairs":
        by_screen = collections.defaultdict(dict)
        for (screen, page), items in found.items():
            if not matches(screen, patterns) or page not in ("top", "bottom"):
                continue
            for config, device, path in items:
                if not configs or config in configs:
                    by_screen[screen].setdefault((config, device), {})[page] = path
        for screen, combos in sorted(by_screen.items()):
            ordered = sorted(combos.items())
            for number, start in enumerate(range(0, len(ordered), args.per_sheet)):
                chunk = ordered[start:start + args.per_sheet]
                cols = [(f"{c} / {d}", pages_["top"], pages_.get("bottom")) for (c, d), pages_ in chunk if "top" in pages_]
                if not cols:
                    continue
                name = f"{screen}__{number + 1}.png"
                make_pair_sheet(screen, cols, args.cell, os.path.join(args.output, name))
                rows.append((name, screen, "top,bottom", "; ".join(f"{c}/{d}" for (c, d), _ in chunk)))
        with open(os.path.join(args.output, "sheets.tsv"), "a") as handle:
            for row in rows:
                handle.write("\t".join(row) + "\n")
        print(f"{len(rows)} sheets in {args.output}")
        return 0
    for (screen, page), items in sorted(found.items()):
        if not matches(screen, patterns):
            continue
        if page not in pages and not (page.startswith("p") and "pages" in pages):
            continue
        if configs:
            items = [i for i in items if i[0] in configs]
        if not items:
            continue
        # A page that no configuration scrolled to is the same as the top: nothing to compare.
        for number, start in enumerate(range(0, len(items), args.per_sheet)):
            chunk = items[start:start + args.per_sheet]
            name = f"{screen}__{page}__{number + 1}.png"
            cells = [(f"{config} / {device}", path) for config, device, path in chunk]
            make_sheet(f"{screen}  ({page})", cells, args.cell, os.path.join(args.output, name))
            rows.append((name, screen, page, "; ".join(f"{c}/{d}" for c, d, _ in chunk)))
    with open(os.path.join(args.output, "sheets.tsv"), "a") as handle:
        for row in rows:
            handle.write("\t".join(row) + "\n")
    print(f"{len(rows)} sheets in {args.output}")


if __name__ == "__main__":
    sys.exit(main())
