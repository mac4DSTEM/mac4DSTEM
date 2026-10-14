#!/usr/bin/env python3
# usage: declared.py <copy-root> <names.txt> — declared `func test...` (class.method) vs the names in the log
import re, sys, glob, os
root, names = sys.argv[1:3]
decl = []
for f in sorted(glob.glob(root + "/mac4DSTEMTests/**/*.swift", recursive=True)):
    cls = None
    for line in open(f, errors="replace"):
        m = re.match(r"\s*(?:@\w+\s+)*(?:final\s+|public\s+|private\s+|open\s+)*class\s+(\w+)", line)
        if m: cls = m.group(1)
        m = re.match(r"\s*(?:@\w+\s+)*(?:override\s+)?(?:private\s+|fileprivate\s+)?func\s+(test\w*)\s*\(", line)
        if m: decl.append((cls, m.group(1), os.path.basename(f)))
logged = set(l.split()[0] for l in open(names))
declset = {f"{c}.{m}()" for c, m, _ in decl}
print("declared (grep-style) lines:", len(decl), "unique class.method:", len(declset), "logged:", len(logged))
print("declared but not in log:", sorted(declset - logged))
print("in log but not declared:", sorted(logged - declset))
