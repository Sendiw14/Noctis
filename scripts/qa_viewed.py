#!/usr/bin/env python3
"""Records that contact sheets were looked at:

    scripts/qa_viewed.py <PASS|NOTE|FINDING QA-nnn|UNVERIFIED> "what was seen" <sheet> [<sheet> ...] [--screens id,id] [--configs name,name]

Appends one line a sheet to Docs/qa/coverage/viewed.tsv (sheet, result, note, screens, configs). With --screens the result is for those screens on the sheet only;
the other screens on it keep their own lines (or, with none, are PASS only if a line without --screens says so). With --configs the result is for those
configurations' columns on the sheet only (UNVERIFIED there: the column showed something other than the screen, so it is not counted as viewed).
A sheet is recorded only by someone who looked at it at a readable size;
scripts/qa_coverage.py counts a combination as viewed from these lines and nothing else.
"""
import os
import sys

path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Docs", "qa", "coverage", "viewed.tsv")
args = sys.argv[1:]
screens = ""
configs = ""
if "--screens" in args:
    index = args.index("--screens")
    screens = args[index + 1]
    del args[index:index + 2]
if "--configs" in args:
    index = args.index("--configs")
    configs = args[index + 1]
    del args[index:index + 2]
result, note, sheets = args[0], args[1], args[2:]
with open(path, "a") as handle:
    for sheet in sheets:
        handle.write(f"{os.path.basename(sheet)}\t{result}\t{note}\t{screens}\t{configs}\n" if configs else f"{os.path.basename(sheet)}\t{result}\t{note}\t{screens}\n")
print(f"{len(sheets)} sheets recorded as {result}")
