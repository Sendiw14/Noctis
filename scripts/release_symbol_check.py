#!/usr/bin/env python3
"""Release symbol check (QA_LEDGER.md, QA part 1).

Finds every `#if DEBUG` block in the shipped sources, collects the names that exist only inside them (types, functions, properties, cases, launch
flags and keys), then looks inside every Mach-O of a build (app, extensions, Watch app) for those names and for the names the brief requires.
A Release build must contain none of them.

    scripts/release_symbol_check.py <build products dir> [--list] [--quiet]

<build products dir> is the folder that holds the .app, e.g.
    <DerivedData>/Build/Products/Release-iphoneos
Build it with CODE_SIGNING_ALLOWED=NO if there is no signing identity:
    xcodebuild build -project Noctis.xcodeproj -scheme Noctis -configuration Release -destination 'generic/platform=iOS' \
        -derivedDataPath /tmp/dd CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""

Run it on a Debug build too: the same names must be found there (the positive control that proves the check can see them).
Names imported from Apple's frameworks are ignored (a symbol the binary only references is not a symbol it contains).
Exit status: 0 when nothing is found, 1 when something is, 2 on a usage error.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOLDERS = ['Packages/NoctisKit/Sources', 'App', 'NoctisWidgets', 'NoctisAlarmWidget', 'NOCTISWatch', 'NOCTISWatchWidgets']

# Names the QA brief requires to be absent from Release, checked as plain substrings.
REQUIRED = ['useMockHealth', 'mockScenario', 'mockAI', 'mockLatency', 'mockUnauthorized', 'forceTier', 'homeMode', 'homeModeFlipIn',
            'widgetGallery', 'watchMockSnapshot', 'complicationGallery', 'noctisResetState', 'MockHealthKitProvider', 'MockAIProvider',
            'SeededGenerator']

# A DEBUG-only string that is also an ordinary word the shipped app contains: the pseudo-script noun "reminder" (NoctisCount, inside #if DEBUG) is
# also part of shipped enum-case names such as DataInventory's `reminders`, so `strings` shows a bare "reminder" in Release. Proven identical on the commit
# before the release cleanup (84af85e). Adding to this list needs the same proof.
COINCIDENCES = {'reminder'}

DECL = re.compile(r'\b(?:func|var|let|class|struct|enum|protocol|actor|typealias|extension)\s+([A-Za-z_]\w*)')
CASE = re.compile(r'^\s*(?:indirect\s+)?case\s+(.+)$')
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')


def strip_comment(line):
    out, in_string, i = [], False, 0
    while i < len(line):
        c = line[i]
        if c == '\\' and in_string:
            out.append(line[i:i + 2]); i += 2; continue
        if c == '"': in_string = not in_string
        if not in_string and line.startswith('//', i): break
        out.append(c); i += 1
    return ''.join(out)


def debug_only_names():
    """(blocks, names, strings): the DEBUG blocks as (file, first line, last line); the names and strings found only inside them."""
    declared, strings, shipped_tokens, blocks = set(), set(), set(), []
    for folder in FOLDERS:
        for directory, _, files in os.walk(os.path.join(ROOT, folder)):
            if 'Preview Content' in directory: continue
            for name in files:
                if not name.endswith('.swift'): continue
                path = os.path.join(directory, name)
                rel = os.path.relpath(path, ROOT)
                stack, start = [], None
                for number, raw in enumerate(open(path, encoding='utf-8').read().split('\n'), 1):
                    s = raw.strip()
                    if re.match(r'#if\b', s):
                        stack.append(['debug' if re.fullmatch(r'#if\s+DEBUG', s) else 'other', False])
                        if stack[-1][0] == 'debug' and sum(1 for e in stack if e[0] == 'debug') == 1: start = number
                        continue
                    if re.match(r'#(else|elseif)\b', s) and stack:
                        stack[-1][1] = True
                        if stack[-1][0] == 'debug' and start is not None and not any(e[0] == 'debug' and not e[1] for e in stack):
                            blocks.append((rel, start, number)); start = None
                        continue
                    if s.startswith('#endif') and stack:
                        top = stack.pop()
                        if top[0] == 'debug' and not top[1] and start is not None and not any(e[0] == 'debug' and not e[1] for e in stack):
                            blocks.append((rel, start, number)); start = None
                        continue
                    in_debug = any(e[0] == 'debug' and not e[1] for e in stack)
                    line = strip_comment(raw)
                    if in_debug:
                        for m in DECL.finditer(line): declared.add(m.group(1))
                        m = CASE.match(line)
                        if m:
                            for part in re.split(r',\s*(?![^()]*\))', m.group(1)):
                                mm = re.match(r'\s*([A-Za-z_]\w*)', part)
                                if mm: declared.add(mm.group(1))
                        for m in STRING.finditer(line):
                            t = m.group(1)
                            if re.fullmatch(r'-[A-Za-z][\w.-]+|noctis\.[\w.]+|[A-Za-z][\w.-]{5,}', t) and ' ' not in t and '\\(' not in t:
                                strings.add(t)
                    else:
                        for t in IDENT.findall(re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)): shipped_tokens.add(t)
                        for m in STRING.finditer(line): shipped_tokens.add(m.group(1))
    names = sorted(n for n in declared if n not in shipped_tokens and len(n) >= 4)
    flags = sorted(s for s in strings if s not in shipped_tokens and s not in COINCIDENCES)
    return sorted(blocks), names, flags


def macho_files(top):
    found = []
    for directory, _, files in os.walk(top):
        # What ships is the .app and its .appex files; a .dSYM is a separate artifact (debug info, with the names of every framework type it saw).
        if ('.app' not in directory and '.appex' not in directory) or '.dSYM' in directory: continue
        for name in files:
            path = os.path.join(directory, name)
            if os.path.islink(path) or os.path.getsize(path) < 4096: continue
            with open(path, 'rb') as handle:
                if handle.read(4) in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xfe\xed\xfa\xcf', b'\xbe\xba\xfe\xca'): found.append(path)
    return sorted(set(found))


def own_strings(path):
    """The binary's strings minus the names it only imports."""
    out = subprocess.run(['strings', '-a', path], capture_output=True, text=True, errors='replace').stdout
    undefined = set(subprocess.run(['nm', '-u', path], capture_output=True, text=True, errors='replace').stdout.split('\n'))
    return '\n'.join(line for line in out.split('\n') if line not in undefined)


def count_fixed(text_path, patterns, match='substring'):
    """Occurrences per pattern. match: 'substring', 'word' (grep -w) or 'line' (grep -x: the whole string is the name)."""
    if not patterns: return {}
    with tempfile.NamedTemporaryFile('w', suffix='.pats', delete=False) as handle:
        handle.write('\n'.join(patterns) + '\n')
        patterns_path = handle.name
    try:
        flag = {'substring': [], 'word': ['-w'], 'line': ['-x']}[match]
        command = ['grep', '-a', '-o', '-F'] + flag + ['-f', patterns_path, text_path]
        out = subprocess.run(command, capture_output=True, text=True, errors='replace').stdout
    finally:
        os.remove(patterns_path)
    counts = {}
    for line in out.split('\n'):
        if line: counts[line] = counts.get(line, 0) + 1
    return counts


def main(argv):
    args = [a for a in argv[1:] if not a.startswith('--')]
    blocks, names, flags = debug_only_names()
    if '--list' in argv:
        print(f'{len(blocks)} DEBUG blocks in {len({b[0] for b in blocks})} files'); [print(f'  {f}:{a}-{b}') for f, a, b in blocks]
        print(f'{len(names)} DEBUG-only names'); print('  ' + ' '.join(names))
        print(f'{len(flags)} DEBUG-only strings'); print('  ' + ' '.join(flags))
        return 0
    if len(args) != 1:
        print(__doc__); return 2
    binaries = macho_files(args[0])
    if not binaries:
        print('no Mach-O files under', args[0]); return 2
    mangled = {'%d%s' % (len(n), n): n for n in names}
    long_plain = [n for n in names if len(n) >= 10 and re.search(r'[a-z][A-Z]', n)]
    print(f'{len(blocks)} #if DEBUG blocks in {len({b[0] for b in blocks})} files; {len(names)} DEBUG-only names and {len(flags)} DEBUG-only strings to look for')
    total = 0
    for path in binaries:
        with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as handle:
            text = own_strings(path)
            handle.write(text)
            dump = handle.name
        try:
            required = count_fixed(dump, REQUIRED)
            hits = {}
            for key in count_fixed(dump, list(mangled)):
                # a Swift-mangled identifier is its length then its name, and the length is not the tail of a longer number
                exact = len(re.findall(r'(?<![0-9])' + re.escape(key), text))
                if exact: hits[mangled[key]] = hits.get(mangled[key], 0) + exact
            # CamelCase names as whole words (so "numberWord" is not found inside "numberWordInText"), launch flags and keys as whole strings
            for key, c in count_fixed(dump, long_plain, match='word').items(): hits[key] = max(hits.get(key, 0), c)
            for key, c in count_fixed(dump, flags, match='line').items(): hits[key] = hits.get(key, 0) + c
        finally:
            os.remove(dump)
        total += sum(1 for n in REQUIRED if required.get(n, 0)) + len(hits)
        print(f'== {os.path.relpath(path, args[0])} ({len(text) // 1024} KB of its own strings and symbols)')
        print('   required: ' + ', '.join(f'{n}={required.get(n, 0)}' for n in REQUIRED))
        print(f'   other DEBUG-only names and strings found: {len(hits)}' + ('' if '--quiet' in argv or not hits else ' -> ' + ', '.join(f'{n} x{c}' for n, c in sorted(hits.items())[:60])))
    print(f'TOTAL: {len(binaries)} binaries, {total} hits')
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
