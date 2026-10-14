#!/usr/bin/env python3
# usage: count.py <unit-log> <copy-root> <names-out>  — counts unique test methods by outcome from the xcodebuild log
import re, sys, subprocess, os
log, root, out = sys.argv[1:4]
seen = {}
lines = open(log, errors="replace").read().split("\n")
# a name split by interleaved xcodebuild output: "Test case '<name prefix><timestamp noise>" then, within 6 lines,
# "<name rest>()' passed on '" (seen: the cut falls inside the class name or between method and "()")
for i, line in enumerate(lines):
    m = re.match(r"Test case '([\w.]*?)(?=\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)", line)
    if m:
        for j in range(i + 1, min(i + 7, len(lines))):
            m2 = re.match(r"([\w.]*\(\))' (passed|failed|skipped) on '", lines[j])
            if m2:
                full = m.group(1) + m2.group(1)
                if re.fullmatch(r"\w+\.\w+\(\)", full): seen.setdefault(full, set()).add(m2.group(2))
                break
for line in lines:
    # parallel clones interleave output, so a line can lose its "Test case " prefix: match the quoted name anywhere
    m = re.search(r"'(\w+\.\w+\(\))' (passed|failed|skipped) on '", line)
    if m: seen.setdefault(m.group(1), set()).add(m.group(2))
res = {"passed": [], "failed": [], "skipped": []}
mixed = []
for n, o in sorted(seen.items()):
    if len(o) > 1: mixed.append((n, sorted(o)))
    for k in ("failed", "skipped", "passed"):
        if k in o: res[k].append(n); break
funcs = int(subprocess.run(f"grep -rh 'func test' {root}/mac4DSTEMTests | wc -l", shell=True, capture_output=True, text=True).stdout)
open(out, "w").write("".join(f"{n} {k}\n" for k in ("passed","failed","skipped") for n in res[k]))
print(f"passed {len(res['passed'])} failed {len(res['failed'])} skipped {len(res['skipped'])} total {len(seen)}; func test in copy {funcs}")
print("failed:", res["failed"]); print("skipped:", res["skipped"]); print("mixed outcome names:", mixed)
