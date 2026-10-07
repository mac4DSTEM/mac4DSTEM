#!/usr/bin/env python3
"""WP4b T-Q (2026-10-07): DTSA-II's QualSpectra set (NIST, public domain; 31 EMSA spectra of glass standards, `Qual answers.txt`) in the format
`main --ladder <dir>` reads: per spectrum `<nn>.spectrum.u64` (little-endian uint64 counts) and `<nn>.meta.json`.

    qual_prep.py <out dir> [<"Qual test set" dir>]

Read from the already-unpacked folder (no unzip). The MSA header supplies #NPOINTS, #XPERCHAN, #OFFSET (both in #XUNITS, eV here; converted to keV),
#BEAMKV. The header carries NO detector resolution (only `#EDSDET: SIUTW`), so `resolutionMnKaEV` is not written and the harness default (130 eV) is
used. Truth is the element list of `Qual answers.txt` (lines `K1001 = [O(0.3947 mass frac),Na(...),...,S=1.0003]`; the S= term is the sum, not an
element); the difficulty class (easy / moderate / difficult / very difficult) is the file name's last field. Pure stdlib."""
import json, os, re, sys

out = sys.argv[1]
src = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.environ.get("SP", "."), "ref/qual/Qual test set")
os.makedirs(out, exist_ok=True)
answers = {}
for line in open(os.path.join(src, "Qual answers.txt")):
    m = re.match(r"\s*(K\d+)\s*=\s*\[(.*)\]\s*$", line)
    if m: answers[m.group(1)] = re.findall(r"([A-Z][a-z]?)\([\d.]+ mass frac\)", m.group(2))
files = sorted(f for f in os.listdir(src) if f.endswith(".msa"))
order = {"easy": 0, "moderate": 1, "difficult": 2, "very difficult": 3}
files.sort(key=lambda f: (order[re.search(r" - (.+)\.msa$", f).group(1)], f))
for i, f in enumerate(files):
    hdr, data, inside = {}, [], False
    for ln in open(os.path.join(src, f), encoding="latin-1"):
        ln = ln.strip()
        if ln.startswith("#SPECTRUM"): inside = True; continue
        if ln.startswith("#ENDOFDATA"): break
        if inside:
            data += [float(t) for t in ln.replace(",", " ").split()]
        else:
            m = re.match(r"#(\w+)\s*:\s*(.*)$", ln)
            if m: hdr[m.group(1)] = m.group(2)
    n = int(hdr["NPOINTS"]); assert hdr["XUNITS"].lower() == "ev" and len(data) == n, (f, hdr["XUNITS"], len(data), n)
    key = re.match(r"(K\d+)", f).group(1); cls = re.search(r" - (.+)\.msa$", f).group(1)
    counts = [int(round(v)) for v in data]; assert all(abs(a - b) < 1e-9 for a, b in zip(counts, data))
    import array; a = array.array("Q", counts)
    if sys.byteorder == "big": a.byteswap()
    open(os.path.join(out, f"{i:02d}.spectrum.u64"), "wb").write(a.tobytes())
    json.dump({"file": f, "set": "T-Q", "id": key, "difficulty": cls, "offsetKeV": float(hdr["OFFSET"]) / 1000.0, "scaleKeV": float(hdr["XPERCHAN"]) / 1000.0,
               "beamKeV": float(hdr["BEAMKV"]), "truth": answers[key], "livetimeS": float(hdr.get("LIVETIME", "nan")), "totalCounts": sum(counts),
               "resolutionStatedInHeader": False, "detector": hdr.get("EDSDET")}, open(os.path.join(out, f"{i:02d}.meta.json"), "w"), indent=1)
    print(i, key, cls, hdr["BEAMKV"], "kV", sum(counts), "counts", answers[key])
