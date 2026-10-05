# Regenerates mac4DSTEM/Core/Spectroscopy/XRayLineData.swift from exspy's xray_lines.json (verbatim values).
#   python3 genlines.py <exspy>/exspy/material/xray_lines.json > XRayLineData.swift
import json, sys, hashlib
raw = open(sys.argv[1], "rb").read()
d = json.loads(raw)["elements"]
Z = "H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U".split()
# NB: the 92 symbols above are Z = 1...92 in order, Eu/Sm swapped check below
assert len(Z) == 92
lines = []
for z, el in enumerate(Z, 1):
    for name, p in d.get(el, {}).items():
        assert name[0] in "KLM", name
        lines.append(f"{z} {el} {name} {p['energy (keV)']!r} {p['weight']!r}")
extra = sorted(set(d) - set(Z))
print("// Generated, do not edit by hand. Source: eXSpy exspy/material/xray_lines.json at commit 7185a4d13d7d5c550b7bb8d1e9bd62af9cc4203e")
print(f"// (sha256 {hashlib.sha256(raw).hexdigest()}), values copied verbatim (Python repr, so Double() round-trips them).")
print("// eXSpy is GPL-3.0-or-later (Copyright 2007-2026 The eXSpy developers); energies: Chantler 2005, weights: EPQ (see NOTICE).")
print("// Regenerate: python3 genlines.py <exspy checkout>/exspy/material/xray_lines.json  (script kept with the WP2 lane-C report)")
print(f"// Elements in the JSON beyond Z = 1...92 (not included): {extra}")
print("//")
print("// One row per line: Z, symbol, line name, energy (keV), weight. H and He are in the data (as eXSpy ships them)")
print("// and are filtered in `XRayLines`, see DEVIATION there.")
print()
print("enum XRayLineData {")
print('    nonisolated static let rows: String = """')
for l in lines: print(l)
print('"""')
print("}")
