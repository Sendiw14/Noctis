#!/usr/bin/env python3
"""Contact sheets of a screen-matrix run: many screens on one image, each labelled with its screen id and page.

    scripts/qa_contactsheet.py <matrix dir> <out dir> [--config A-light] [--device QA17Pro] [--per-sheet 12] [--columns 6] [--width 250]

<matrix dir> is the `matrix` folder QAMatrixTests writes. Writes <out dir>/<config>-<device>-<NN>.jpg, 12 pictures per sheet by default, in screen id order.
Only the first page of a screen (`__top.png`, or the single picture) is shown; the full-size pictures stay in the matrix folder.
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFont


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("matrix")
    parser.add_argument("out")
    parser.add_argument("--config", action="append", default=[])
    parser.add_argument("--device", action="append", default=[])
    parser.add_argument("--per-sheet", type=int, default=12)
    parser.add_argument("--columns", type=int, default=6)
    parser.add_argument("--width", type=int, default=250)
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    font = ImageFont.load_default()
    configs = args.config or sorted(os.listdir(args.matrix))
    devices = args.device or ["QA17Pro", "QASE"]
    written = 0
    for config in configs:
        for device in devices:
            folder = os.path.join(args.matrix, config, device)
            if not os.path.isdir(folder):
                continue
            names = sorted(name for name in os.listdir(folder) if name.endswith("__top.png") or ("__" not in name and name.endswith(".png")))
            for start in range(0, len(names), args.per_sheet):
                chunk = names[start:start + args.per_sheet]
                pictures = [Image.open(os.path.join(folder, name)).convert("RGB") for name in chunk]
                height = max(round(picture.height * args.width / picture.width) for picture in pictures)
                rows = -(-len(chunk) // args.columns)
                sheet = Image.new("RGB", (args.columns * (args.width + 8) + 8, rows * (height + 26) + 8), (235, 235, 235))
                draw = ImageDraw.Draw(sheet)
                for index, (name, picture) in enumerate(zip(chunk, pictures)):
                    x = 8 + (index % args.columns) * (args.width + 8)
                    y = 8 + (index // args.columns) * (height + 26)
                    scaled = picture.resize((args.width, round(picture.height * args.width / picture.width)))
                    sheet.paste(scaled, (x, y + 16))
                    draw.text((x, y), name.replace("__top.png", "").replace(".png", "")[:46], fill=(0, 0, 0), font=font)
                sheet.save(os.path.join(args.out, f"{config}-{device}-{start // args.per_sheet + 1:02d}.jpg"), quality=88)
                written += 1
    print(written, "sheets in", args.out)


if __name__ == "__main__":
    main()
