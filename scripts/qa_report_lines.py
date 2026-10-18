#!/usr/bin/env python3
"""Fills the two lists in QA_REPORT.md (sections 3 and 4) from QA_LEDGER.md: one line per UNVERIFIED row and one per OPEN row, with its id, severity
and a one-line reason. Run after the ledger changes: scripts/qa_report_lines.py. The text between the markers is replaced; nothing else is touched."""
import os, re
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rows = []
for line in open(os.path.join(root, "QA_LEDGER.md"), encoding="utf-8"):
    if line.startswith("| QA-"):
        p = [x.strip() for x in line.split("|")]
        rows.append(p)
def one(p, n=210):
    text = p[3].replace("|", "/")
    text = re.split(r"(?<=[.:;]) ", text)[0]
    return text if len(text) <= n else text[:n].rsplit(" ", 1)[0] + " ..."
def lines(status):
    return "\n".join(f"- **{p[1]}** ({p[2]}, {p[4]}): {one(p)}" for p in rows if p[5] == status)
path = os.path.join(root, "QA_REPORT.md")
text = open(path, encoding="utf-8").read()
for marker, status in (("UNVERIFIED-LIST", "UNVERIFIED"), ("OPEN-LIST", "OPEN")):
    block = f"<!-- {marker} -->\n{lines(status)}\n<!-- /{marker} -->"
    pattern = re.compile(rf"<!-- {marker} -->.*?<!-- /{marker} -->", re.S)
    if pattern.search(text):
        text = pattern.sub(lambda m: block, text)
    else:
        placeholder = "{unver_lines}" if status == "UNVERIFIED" else "{open_lines}"
        text = text.replace(placeholder, block)
open(path, "w", encoding="utf-8").write(text)
print(len([p for p in rows if p[5] == "UNVERIFIED"]), "unverified,", len([p for p in rows if p[5] == "OPEN"]), "open")
