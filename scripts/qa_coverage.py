#!/usr/bin/env python3
"""QA part 3: builds QA_COVERAGE.md and qa/coverage/coverage.csv.

    scripts/qa_coverage.py [--root .]

Reads, under qa/coverage/:
  catalog.json   every screen (id, area, title, tierOne, scrolls, platform), exported by ScreenCatalogTests (QA_CATALOG_JSON=...)
  plan.json      the configurations: name, tier, devices, what each sets, which screens it is planned for
  produced.tsv   one line per produced (screen, configuration, device): pages produced, ready, environmentOK, hierarchy-check issues
  sheets.tsv     one line per contact sheet: sheet file, screens, page, "configuration/device" list
  viewed.tsv     one line per contact sheet somebody looked at: sheet file, result (PASS | FINDING QA-nnn | NOTE ...), what was seen

A (screen, configuration, device) is *produced* when it has a line in produced.tsv, *viewed* when every page it produced that a sheet can show
(top and bottom) is on a sheet in viewed.tsv, and its *result* is the worst result of those sheets. Anything planned and not produced, or
produced and not viewed, is UNVERIFIED and is never counted as a pass (APP_RULES.md R67).
"""
import argparse
import collections
import csv
import json
import os

RANK = {"PASS": 0, "NOTE": 1, "FINDING": 2}


def read_tsv(path):
    rows = []
    if os.path.exists(path):
        with open(path) as handle:
            for line in handle:
                line = line.rstrip("\n")
                if line and not line.startswith("#"):
                    rows.append(line.split("\t"))
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    parser.add_argument("--matrix", help="QAMatrixTests output (<config>/<device>/manifest.jsonl): rewrites qa/coverage/produced.tsv from it")
    parser.add_argument("--sheets", action="append", default=[], help="a contact-sheet directory (its sheets.tsv is appended to qa/coverage/sheets.tsv)")
    args = parser.parse_args()
    base = os.path.join(args.root, "qa", "coverage")
    if args.matrix:
        rebuild_produced(args.matrix, os.path.join(base, "produced.tsv"))
    for directory in args.sheets:
        merge_sheets(directory, os.path.join(base, "sheets.tsv"))
    catalog = {screen["id"]: screen for screen in json.load(open(os.path.join(base, "catalog.json")))}
    plan = json.load(open(os.path.join(base, "plan.json")))

    produced = {}
    for row in read_tsv(os.path.join(base, "produced.tsv")):
        screen, config, device, pages, ready, env_ok, issues = row[:7]
        produced[(screen, config, device)] = {"pages": pages.split(","), "ready": ready == "true", "env": env_ok == "true", "issues": int(issues)}

    # sheet -> the (screen, config, device, page) it shows
    sheet_items = collections.defaultdict(set)
    for row in read_tsv(os.path.join(base, "sheets.tsv")):
        name, screens, page, combos = row[:4]
        for combo in combos.split("; "):
            if "/" not in combo:
                continue
            config, device = combo.split("/", 1)
            for screen in screens.split(","):
                for one_page in page.split(","):
                    sheet_items[name].add((screen, config, device, one_page))
    viewed = {}
    for row in read_tsv(os.path.join(base, "viewed.tsv")):
        sheet, result = row[0], row[1]
        viewed[sheet] = (result, row[2] if len(row) > 2 else "")
    seen_pages = collections.defaultdict(list)  # (screen, config, device) -> [(page, result, note)]
    for sheet, (result, note) in viewed.items():
        for screen, config, device, page in sheet_items.get(sheet, ()):
            seen_pages[(screen, config, device)].append((page, result, note))

    rows = []
    for config in plan["configurations"]:
        for device in config["devices"]:
            for screen_id, screen in sorted(catalog.items()):
                scope = dict(config)
                if device in config.get("per_device", {}):
                    scope["screens"] = config["per_device"][device]
                if screen["platform"] != "iPhone" or not applies(scope, screen):
                    continue
                key = (screen_id, config["name"], device)
                made = produced.get(key)
                if not made:
                    rows.append((screen_id, config["name"], device, "no", "no", "UNVERIFIED: not produced", config["tier"]))
                    continue
                needed = {"top"} | ({"bottom"} if "bottom" in made["pages"] else set())
                got = {page for page, _, _ in seen_pages.get(key, [])}
                if not needed <= got:
                    missing = ", ".join(sorted(needed - got))
                    rows.append((screen_id, config["name"], device, "yes", "no", f"UNVERIFIED: not viewed ({missing})", config["tier"]))
                    continue
                results = [(r, n) for _, r, n in seen_pages[key]]
                worst = max(results, key=lambda item: RANK.get(item[0].split()[0], 0))
                label = worst[0] if worst[0] != "PASS" else "PASS"
                if not made["env"]:
                    label = "FINDING: the configuration did not take effect"
                rows.append((screen_id, config["name"], device, "yes", "yes", label, config["tier"]))

    totals = collections.Counter()
    for _, _, _, produced_flag, viewed_flag, result, _ in rows:
        totals["planned"] += 1
        totals["produced"] += produced_flag == "yes"
        totals["viewed"] += viewed_flag == "yes"
        totals["pass"] += result == "PASS"
        totals["finding"] += result.startswith("FINDING")
        totals["note"] += result.startswith("NOTE")
        totals["unverified"] += result.startswith("UNVERIFIED")

    with open(os.path.join(base, "coverage.csv"), "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["screen", "configuration", "device", "produced", "viewed", "result", "tier"])
        writer.writerows(rows)

    preface_path = os.path.join(base, "preface.md")
    preface = open(preface_path).read().rstrip("\n").split("\n") + [""] if os.path.exists(preface_path) else []
    out = [
        "# QA coverage: screen x configuration",
        "",
        "Generated by `scripts/qa_coverage.py` from `qa/coverage/` (catalog, plan, what the harness produced, the contact sheets, and which sheets were looked at).",
        "A combination counts as verified only if it was **produced** and **viewed** at a readable size (a contact sheet of the screen under several configurations; ",
        "a zoomed crop where the text is small). Anything not viewed is `UNVERIFIED` and is never counted as a pass. `QA_LEDGER.md` has the findings.",
        "",
    ] + preface + [
        "## Totals",
        "",
        "| Planned | Produced | Viewed | PASS | FINDING | NOTE | UNVERIFIED |",
        "|---:|---:|---:|---:|---:|---:|---:|",
        f"| {totals['planned']} | {totals['produced']} | {totals['viewed']} | {totals['pass']} | {totals['finding']} | {totals['note']} | {totals['unverified']} |",
        "",
        "## Configurations",
        "",
        "| Configuration | Tier | Devices | What it sets | Screens |",
        "|---|---|---|---|---|",
    ]
    for config in plan["configurations"]:
        count = sum(1 for r in rows if r[1] == config["name"])
        out.append(f"| {config['name']} | {config['tier']} | {', '.join(config['devices'])} | {config['sets']} | {config['screens']} ({count} combinations) |")
    by_config = collections.defaultdict(collections.Counter)
    for screen, config, device, p, v, result, _ in rows:
        by_config[config]["planned"] += 1
        by_config[config]["produced"] += p == "yes"
        by_config[config]["viewed"] += v == "yes"
        by_config[config]["pass"] += result == "PASS"
        by_config[config]["finding"] += result.startswith("FINDING")
    out += ["", "## By configuration", "", "| Configuration | Planned | Produced | Viewed | PASS | FINDING |", "|---|---:|---:|---:|---:|---:|"]
    for config in plan["configurations"]:
        c = by_config[config["name"]]
        out.append(f"| {config['name']} | {c['planned']} | {c['produced']} | {c['viewed']} | {c['pass']} | {c['finding']} |")
    out += ["", "## Every combination", "", "| Screen | Configuration | Device | Produced | Viewed | Result |", "|---|---|---|---|---|---|"]
    for screen, config, device, p, v, result, _ in rows:
        out.append(f"| {screen} | {config} | {device} | {p} | {v} | {result} |")
    with open(os.path.join(args.root, "QA_COVERAGE.md"), "w") as handle:
        handle.write("\n".join(out) + "\n")
    print(dict(totals))


def rebuild_produced(matrix, out):
    """One line per (screen, configuration, device): the last manifest line wins (a screen re-run replaces its earlier one)."""
    latest = {}
    for config in sorted(os.listdir(matrix)):
        cdir = os.path.join(matrix, config)
        if not os.path.isdir(cdir):
            continue
        for device in sorted(os.listdir(cdir)):
            path = os.path.join(cdir, device, "manifest.jsonl")
            if not os.path.exists(path):
                continue
            for line in open(path):
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                folder = os.path.join(cdir, device)
                pages = [p for p in ("top", "bottom") if os.path.exists(os.path.join(folder, f"{row['id']}__{p}.png"))]
                if not pages:
                    continue
                latest[(row["id"], config, device)] = (",".join(pages), str(row["ready"]).lower(), str(row["environmentOK"]).lower(), row["issues"])
    with open(out, "w") as handle:
        for (screen, config, device), (pages, ready, env_ok, issues) in sorted(latest.items()):
            handle.write(f"{screen}\t{config}\t{device}\t{pages}\t{ready}\t{env_ok}\t{issues}\n")
    print(f"{len(latest)} produced combinations")


def merge_sheets(directory, out):
    existing = set()
    if os.path.exists(out):
        existing = {line.split("\t")[0] for line in open(out) if line.strip()}
    added = 0
    with open(out, "a") as handle:
        for line in open(os.path.join(directory, "sheets.tsv")):
            if line.split("\t")[0] not in existing:
                handle.write(line)
                added += 1
    print(f"{added} sheets added from {directory}")


def applies(config, screen):
    rule = config["screens"]
    if rule == "all":
        return True
    if rule == "tier1":
        return screen["tierOne"]
    if rule == "tabs":
        return screen["id"] in config.get("ids", [])
    return screen["id"] in config.get("ids", [])


if __name__ == "__main__":
    main()
