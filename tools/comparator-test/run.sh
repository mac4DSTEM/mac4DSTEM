#!/bin/zsh
# Break the real-data-acceptance comparator before trusting it.
#
# tools/real-data-acceptance/compare.py decides whether a scientific regression
# in the real-data run is caught. A comparator that has quietly stopped checking
# looks exactly like a passing gate, so every check it makes gets a mutation
# here that must turn it red, and the cases that must stay GREEN are asserted
# too — the 2026-08-31 defect was a comparator going red on a legitimate input.
#
# Lives in its own tools/ directory, and is in run-tests.sh's `scientific`
# array, so it runs on every CI push. real-data-acceptance itself only runs
# under `all` (it needs gitignored multi-GB data), and its run.sh also calls
# this file directly so a broken comparator fails before that ~1 min build.
#
# Pure python + JSON: no build, no data, well under a second.
#
# WHAT THIS SUITE DOES AND DOES NOT ESTABLISH. It proves each check still
# EXISTS. Pinning what each is WORTH is the harder half, and a Gate B sweep of
# 67 mutations on 2026-08-31 found six holes of that kind — every one is now
# covered by a case below, and the fixture magnitudes and shapes were rebuilt
# for it. The known residual is named at the end of the file rather than left
# to be rediscovered.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
COMPARE="$HERE/../real-data-acceptance/compare.py"
SHIPPED_EXPECTED="$HERE/../real-data-acceptance/expected.json"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

# THE FIXTURE. Three entries, each chosen against a defect the review found:
#
#  alpha  large magnitudes, so `rel_tol` can be pinned: a drift can exceed
#         abs_tol while staying inside rel_tol only when the value is big.
#  beta   mid magnitudes, ASYMMETRIC shape [8,9,16,17] — the old fixture used
#         [8,8,16,16], symmetric in BOTH the scan pair and the detector pair,
#         so it could not discriminate any transposition. That is this repo's
#         S8 symmetric-constant lesson, repeated.
#  wsii   modelled on the REAL polycrystal_2D_WS2 golden values, whose virtual
#         image spans 0.24391551..0.24444818 — a dynamic range of 5.3e-4
#         against an abs_tol of 1e-3. Without an entry at this magnitude the
#         suite certifies 30/0 over a gate that accepts a 50% contrast loss.
#
# Every count array is DISTINCT from every other, and none is a palindrome. In
# the real data candidate == afterAbsolute and afterSpacing == peak, which made
# two of the five checks indistinguishable from their neighbours; a fixture that
# copies that degeneracy cannot catch a field mix-up.
cat > "$WORK/base.json" <<'JSON'
[
  {
    "file": "alpha.h5",
    "datasetPath": "/a/data",
    "shape": [4, 5, 6, 7],
    "dtype": "uint16",
    "finitePatternFraction": 1.0,
    "diskProbeRadiusPixels": 2.5,
    "diskSampleCandidateCounts": [52, 43, 40],
    "diskSampleAfterAbsoluteCounts": [50, 42, 39],
    "diskSampleAfterRelativeCounts": [12, 20, 7],
    "diskSampleAfterSpacingCounts": [5, 9, 3],
    "diskSamplePeakCounts": [4, 8, 2],
    "virtualImageMinimum": 128250.0,
    "virtualImageMaximum": 555840.0,
    "virtualImageMean": 383697.163,
    "virtualImageChecksum": 414133653412.0,
    "elapsedSeconds": 1.0
  },
  {
    "file": "beta.h5",
    "datasetPath": "/b/data",
    "shape": [8, 9, 16, 17],
    "dtype": "float32",
    "finitePatternFraction": 1.0,
    "diskProbeRadiusPixels": 6.196223,
    "diskSampleCandidateCounts": [91, 116, 97],
    "diskSampleAfterAbsoluteCounts": [90, 115, 96],
    "diskSampleAfterRelativeCounts": [25, 29, 23],
    "diskSampleAfterSpacingCounts": [12, 14, 10],
    "diskSamplePeakCounts": [11, 13, 9],
    "virtualImageMinimum": 2359.0,
    "virtualImageMaximum": 17592.0,
    "virtualImageMean": 7361.779,
    "virtualImageChecksum": 9449806083.0,
    "elapsedSeconds": 2.0
  },
  {
    "file": "wsii.h5",
    "datasetPath": "/c/data",
    "shape": [64, 128, 32, 16],
    "dtype": "float32",
    "finitePatternFraction": 1.0,
    "diskProbeRadiusPixels": 1.8664341,
    "diskSampleCandidateCounts": [45, 47, 46],
    "diskSampleAfterAbsoluteCounts": [44, 46, 45],
    "diskSampleAfterRelativeCounts": [7, 3, 5],
    "diskSampleAfterSpacingCounts": [6, 2, 4],
    "diskSamplePeakCounts": [3, 1, 2],
    "virtualImageMinimum": 0.24391551,
    "virtualImageMaximum": 0.24444818,
    "virtualImageMean": 0.2441111,
    "virtualImageChecksum": 514429.27979,
    "elapsedSeconds": 3.0
  }
]
JSON

# expected.json carries no elapsedSeconds; strip it so the fixture is shaped
# like the real pinned file rather than like the report.
python3 - "$WORK/base.json" "$WORK/expected.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))
for e in entries:
    e.pop("elapsedSeconds", None)
json.dump(entries, open(sys.argv[2], "w"), indent=2)
PY

# A RED verdict must be a CLEAN REFUSAL — non-zero exit, a FAIL: line, and no
# traceback. An earlier version accepted any non-zero exit, which scored a
# KeyError crash as a pass and hid a deleted missing-dataset check.
check() {
  local name="$1" want="$2" expfile="$3" repfile="$4" out rc
  set +e
  out="$(python3 "$COMPARE" "$expfile" "$repfile" 2>&1)"
  rc=$?
  set -e
  if [[ "$want" == "RED" ]]; then
    if [[ $rc -eq 0 ]]; then
      print "FAIL: $name expected a refusal, got exit 0"; (( fail += 1 )); return
    fi
    if [[ "$out" == *Traceback* ]]; then
      print "FAIL: $name crashed instead of refusing: ${out//$'\n'/ | }"
      (( fail += 1 )); return
    fi
    if [[ "$out" != *"FAIL: "* ]]; then
      print "FAIL: $name exited $rc without a FAIL: line: $out"; (( fail += 1 )); return
    fi
    print "PASS: $name -> refused: ${out##*FAIL: }"
    (( pass += 1 ))
  else
    if [[ $rc -eq 0 ]]; then
      print "PASS: $name -> green as required"; (( pass += 1 ))
    else
      print "FAIL: $name expected GREEN, got exit $rc"
      print "      $out"; (( fail += 1 ))
    fi
  fi
}

# mutate <name> <RED|GREEN> <python expression mutating `report`>
mutate() {
  local name="$1" want="$2" expr="$3"
  python3 - "$WORK/base.json" "$WORK/report.json" "$expr" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
exec(sys.argv[3])
json.dump(report, open(sys.argv[2], "w"), indent=2)
PY
  check "$name" "$want" "$WORK/expected.json" "$WORK/report.json"
}

print "== cases that must stay GREEN =="
mutate "unmutated report"                      GREEN "pass"
mutate "reordered report (the 2026-08-31 bug)"  GREEN "report.reverse()"
mutate "an extra unpinned dataset"             GREEN "report.append(dict(report[0], file='gamma.h5'))"
mutate "extra dataset sorting FIRST"           GREEN "report.insert(0, dict(report[0], file='aaa.h5'))"
mutate "elapsed exactly at the 15 s budget"    GREEN "report[0]['elapsedSeconds'] = 15.0"

print ""
print "== tolerance boundaries, pinned from BOTH sides =="
# Each parameter needs a green case only IT can satisfy, or the two subsume each
# other and either can be deleted with the suite still green (Gate B, 2026-08-31).
# alpha's mean is 383697.163: rel_tol*|v| = 0.767, abs_tol = 1e-3.
mutate "large value, drift inside rel_tol only" GREEN "report[0]['virtualImageMean'] += 0.5"
mutate "large value, drift past rel_tol"        RED   "report[0]['virtualImageMean'] += 1.5"
# wsii's mean is 0.2441111: rel_tol*|v| = 4.9e-7, abs_tol = 1e-3.
mutate "small value, drift inside abs_tol only" GREEN "report[2]['virtualImageMean'] += 5e-4"
mutate "small value, drift past abs_tol"        RED   "report[2]['virtualImageMean'] += 1.5e-3"
# probe radius: abs_tol 1e-4 dominates at every realistic radius (see residual).
mutate "probe radius inside abs_tol"            GREEN "report[0]['diskProbeRadiusPixels'] += 5e-5"
mutate "probe radius past abs_tol"              RED   "report[0]['diskProbeRadiusPixels'] += 1.5e-4"

print ""
print "== permutation and transposition (the S8 symmetric-constant lesson) =="
mutate "scan axes transposed"                  RED "report[1]['shape'] = [9, 8, 16, 17]"
mutate "detector axes transposed"              RED "report[1]['shape'] = [8, 9, 17, 16]"
mutate "peak counts permuted, multiset intact" RED "report[0]['diskSamplePeakCounts'] = [8, 4, 2]"
mutate "candidate counts permuted"             RED "report[1]['diskSampleCandidateCounts'] = [116, 91, 97]"

print ""
print "== field mix-ups (no two golden arrays may be interchangeable) =="
mutate "candidate reads afterAbsolute's value" RED "report[0]['diskSampleCandidateCounts'] = report[0]['diskSampleAfterAbsoluteCounts']"
mutate "peak reads afterSpacing's value"       RED "report[0]['diskSamplePeakCounts'] = report[0]['diskSampleAfterSpacingCounts']"

print ""
print "== mutations that must turn it RED =="
mutate "a pinned dataset disappears"           RED "report.pop(0)"
mutate "all pinned datasets disappear"         RED "report[:] = [dict(report[0], file='gamma.h5')]"
mutate "empty report"                          RED "report[:] = []"
mutate "duplicate filename in the report"      RED "report.append(dict(report[0]))"
mutate "datasetPath changed"                   RED "report[1]['datasetPath'] = '/wrong'"
mutate "dtype changed"                         RED "report[0]['dtype'] = 'uint32'"
mutate "finite fraction below 0.999"           RED "report[0]['finitePatternFraction'] = 0.9985"
mutate "finite fraction is NaN"                RED "report[0]['finitePatternFraction'] = float('nan')"
mutate "after-absolute counts changed"         RED "report[0]['diskSampleAfterAbsoluteCounts'] = [50, 42, 41]"
mutate "after-relative counts changed"         RED "report[0]['diskSampleAfterRelativeCounts'] = [12, 20, 8]"
mutate "after-spacing counts changed"          RED "report[0]['diskSampleAfterSpacingCounts'] = [5, 9, 4]"
mutate "virtualImageMinimum drifts"            RED "report[1]['virtualImageMinimum'] = 2359.5"
mutate "virtualImageMaximum drifts"            RED "report[1]['virtualImageMaximum'] = 17593.0"
# +30000 on 9.449806083e9; rel_tol*|v| is 18899.6, so the drift must clear that.
# The first attempt used +10000 and the suite correctly called it GREEN.
mutate "virtualImageChecksum drifts"           RED "report[1]['virtualImageChecksum'] = 9449836083.0"
mutate "elapsed over the 15 s budget"          RED "report[0]['elapsedSeconds'] = 15.01"
mutate "elapsed is NaN"                        RED "report[0]['elapsedSeconds'] = float('nan')"
mutate "a pinned file renamed in the report"   RED "report[0]['file'] = 'renamed.h5'"

print ""
print "== malformed input must refuse cleanly, never traceback =="
mutate "a null entry in the report"            RED "report.append(None)"
mutate "a bare string entry in the report"     RED "report.append('alpha.h5')"
mutate "an entry with no 'file' key"           RED "report.append({'datasetPath': '/x'})"
mutate "an entry whose 'file' is a list"       RED "report.append(dict(report[0], file=['a','b']))"
mutate "a pinned entry missing a golden key"   RED "del report[0]['virtualImageMean']"

print ""
print "== the empty-input holes, checked separately =="
# Separately, on purpose: one empty+empty case is satisfied by EITHER guard, so
# it stays green when either is deleted. Each needs a case only it can fire on.
print '[]' > "$WORK/empty.json"
print 'null' > "$WORK/nonlist.json"
cp "$WORK/base.json" "$WORK/full-report.json"
check "empty expected.json, report has data"   RED "$WORK/empty.json"    "$WORK/full-report.json"
check "empty report, expected.json has data"   RED "$WORK/expected.json" "$WORK/empty.json"
# The case that isolates `if not actual:` — valid JSON, falsy, not a list. This
# file previously called that guard uncoverable; it is not.
check "report is JSON null, not a list"        RED "$WORK/expected.json" "$WORK/nonlist.json"

print ""
print "== the widening's only promise: unpinned datasets are ANNOUNCED =="
# An unpinned dataset can never fail the gate, so this line is the sole signal
# it exists. Deleting the announcement used to leave the suite fully green.
mutate "unpinned present" GREEN "report.append(dict(report[0], file='zeta.h5'))"
out="$(python3 "$COMPARE" "$WORK/expected.json" "$WORK/report.json" 2>&1)"
if [[ "$out" == *"UNPINNED: 1 dataset(s)"* && "$out" == *zeta.h5* ]]; then
  print "PASS: the UNPINNED line names the uncovered dataset"; (( pass += 1 ))
else
  print "FAIL: no UNPINNED line naming zeta.h5; got: $out"; (( fail += 1 ))
fi
if [[ "$out" == *"PASS: alpha.h5 golden"* ]]; then
  print "PASS: each pinned dataset is announced as checked"; (( pass += 1 ))
else
  print "FAIL: no per-dataset PASS line; got: $out"; (( fail += 1 ))
fi

print ""
print "== the shipped expected.json =="
if python3 -c "
import json,sys
e=json.load(open('$SHIPPED_EXPECTED'))
names=[x['file'] for x in e]
sys.exit(0 if len(names)==len(set(names)) and len(names)>0 else 1)
"; then
  print "PASS: it pins $(python3 -c "import json;print(len(json.load(open('$SHIPPED_EXPECTED'))))") datasets with unique names"
  (( pass += 1 ))
else
  print "FAIL: the shipped expected.json is empty or has duplicate names"
  (( fail += 1 ))
fi

# KNOWN RESIDUAL, stated rather than left to be rediscovered:
#
# 1. `rel_tol` on diskProbeRadiusPixels cannot be pinned by any realistic case.
#    rel_tol*|v| exceeds abs_tol=1e-4 only when the radius is above 50 px; real
#    probe radii here are 1.8-6.2 px, so abs_tol dominates always and deleting
#    rel_tol is undetectable. That is a true statement about the gate, not a gap
#    to paper over with a fake 50 px fixture entry.
# 2. compare.py's `if not actual:` guard is subsumed and no mutation here kills
#    it: a non-list report is refused by by_name's type check and `[]` by the
#    missing-dataset check. It is kept for its clearer message, not for safety.
#    Do not read this suite's green as evidence that line runs. (It was called
#    uncoverable, then shown coverable by a reviewer, then made uncoverable
#    again by the very fix for that reviewer's other finding — the history is in
#    compare.py.)
# 3. compare.py's `abs_tol=1e-3` on the virtual-image fields is LARGER than the
#    whole dynamic range of the real polycrystal_2D_WS2 image (5.3e-4). The wsii
#    entry above makes the tolerance's boundary testable, but does NOT fix the
#    gate: a contrast regression on that dataset can still pass. Tightening it
#    is a scientific call, recorded as an owner decision in docs/open-items.md.
print ""
print "comparator-test: $pass passed, $fail failed"
(( fail == 0 )) || exit 1
