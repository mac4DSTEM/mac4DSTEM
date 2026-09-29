#!/bin/zsh
# No Swift is compiled here, so tools/lib/sources.manifest has nothing to supply.
# Break the real-data gate's own decisions before trusting them (S19, 2026-09-30).
#
# tools/comparator-test/run.sh proves each per-field check of compare.py still
# exists. This file pins what THAT one cannot reach, and what the 2026-09-02/09
# review of the gate ("Acceptance-harness gaps", docs/open-items.md) found missing:
#
#   A. compare.py names EVERY mismatch, not the first (a red gate used to name one
#      symptom and hide the rest).
#   B. compare.py compares peak POSITIONS, not counts: on `ba6360d` one peak moved
#      ~26 px with every count unchanged and the gate stayed green.
#   C. run.sh with no data at all is RED, not `SKIP` + exit 0.
#   D. `run-tests.sh scientific` reaches the real-data harness, and `all` reaches it
#      exactly once.
#   E. the shipped expected.json pins positions on every dataset, so deleting the
#      pin cannot turn (B) off silently.
#
# Pure python + shell, no build, no data, a few seconds. Called by
# tools/run-tests.sh (`scientific`/`all`), and directly.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
COMPARE="$HERE/compare.py"
SHIPPED_EXPECTED="$HERE/expected.json"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-compare-selftest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()  { print "PASS: $1"; (( pass += 1 )) || true; }
bad() { print "FAIL: $1"; (( fail += 1 )) || true; }

# --- A + B: compare.py against a synthetic report with positions --------------
python3 - "$COMPARE" <<'PY' > "$WORK/ab.out"
import copy, json, os, subprocess, sys, tempfile

COMPARE = sys.argv[1]
work = tempfile.mkdtemp()
passed = failed = 0


def entry(name, positions, scan_positions):
    counts = [len(p) for p in positions]
    return {
        "file": name, "datasetPath": "/d/data", "shape": [4, 5, 6, 7], "dtype": "uint16",
        "finitePatternFraction": 1.0, "diskProbeRadiusPixels": 2.5,
        "diskSampleCandidateCounts": [c + 9 for c in counts],
        "diskSampleAfterAbsoluteCounts": [c + 6 for c in counts],
        "diskSampleAfterRelativeCounts": [c + 3 for c in counts],
        "diskSampleAfterSpacingCounts": counts,
        "diskSamplePeakCounts": counts,
        "virtualImageMinimum": 10.0, "virtualImageMaximum": 500.0,
        "virtualImageMean": 300.0, "virtualImageChecksum": 4.0e9,
        "elapsedSeconds": 1.0,
        "diskSampleScanPositions": scan_positions,
        "diskSamplePeakPositions": positions,
    }


# Asymmetric on purpose: x != y for every peak, so an x/y swap is visible.
BASE = [
    entry("alpha.h5",
          [[[10.0, 12.0]], [[5.0, 7.0], [20.5, 9.25], [30.0, 14.0]], [[8.0, 3.0], [16.0, 21.0]]],
          [[0, 0], [2, 2], [3, 4]]),
    entry("beta.h5",
          [[[40.0, 41.0], [44.0, 43.0]], [[15.0, 25.0]], [[6.0, 60.0], [61.0, 6.0], [30.0, 30.5]]],
          [[0, 0], [1, 1], [2, 2]]),
]


def run(expected, report):
    ep, rp = os.path.join(work, "e.json"), os.path.join(work, "r.json")
    exp = copy.deepcopy(expected)
    for e in exp:
        e.pop("elapsedSeconds", None)
    json.dump(exp, open(ep, "w"))
    json.dump(report, open(rp, "w"))
    p = subprocess.run([sys.executable, COMPARE, ep, rp], capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def case(name, want, mutate, contains=(), expected=None):
    """`mutate` edits the report; `contains` are substrings a RED output must carry."""
    global passed, failed
    report = copy.deepcopy(BASE)
    mutate(report)
    rc, out = run(BASE if expected is None else expected, report)
    problems = []
    if "Traceback" in out:
        problems.append("crashed: " + out.replace("\n", " | "))
    if want == "GREEN" and rc != 0:
        problems.append(f"expected green, exit {rc}: " + out.replace("\n", " | "))
    if want == "RED":
        if rc == 0:
            problems.append("expected a refusal, got exit 0")
        elif "FAIL: " not in out:
            problems.append("no FAIL: line: " + out.replace("\n", " | "))
        for s in contains:
            if s not in out:
                problems.append(f"output does not name {s!r}: " + out.replace("\n", " | "))
    if problems:
        failed += 1
        print(f"FAIL: {name}: " + "; ".join(problems))
    else:
        passed += 1
        print(f"PASS: {name} -> {'green as required' if want == 'GREEN' else 'refused'}")


def move(report, ds, pos, k, dx, dy):
    p = report[ds]["diskSamplePeakPositions"][pos][k]
    p[0] += dx
    p[1] += dy


print("== B. positions, not counts ==")
case("unmutated report with positions", "GREEN", lambda r: None)
case("peaks listed in another order within a position", "GREEN",
     lambda r: r[0]["diskSamplePeakPositions"][1].reverse())
case("a peak within 0.04 px in x", "GREEN", lambda r: move(r, 0, 1, 1, 0.04, 0))
case("a peak within 0.04 px in y", "GREEN", lambda r: move(r, 0, 1, 1, 0, 0.04))
case("a peak moved 1 px, counts unchanged (the ba6360d shape)", "RED",
     lambda r: move(r, 0, 2, 0, 1.0, 0),
     contains=("alpha.h5", "scan position (ry=3, rx=4)", "(8.00, 3.00)", "(9.00, 3.00)"))
case("a peak 0.06 px off in x", "RED", lambda r: move(r, 1, 0, 0, 0.06, 0), contains=("beta.h5",))
case("a peak 0.06 px off in y only", "RED", lambda r: move(r, 1, 0, 0, 0, 0.06), contains=("beta.h5",))
case("one peak's x and y swapped", "RED",
     lambda r: r[0]["diskSamplePeakPositions"][1].__setitem__(1, [9.25, 20.5]),
     contains=("alpha.h5",))


def dup_peak(r):
    r[1]["diskSamplePeakPositions"][0][1] = list(r[1]["diskSamplePeakPositions"][0][0])


case("equal count, one peak replaced by a copy of another", "RED", dup_peak, contains=("beta.h5",))


def drop_peak(r):
    r[0]["diskSamplePeakPositions"][1].pop()
    r[0]["diskSamplePeakCounts"][1] -= 1


case("a peak dropped (positions AND count agree with each other)", "RED", drop_peak,
     contains=("alpha.h5",))


def add_peak(r):
    r[0]["diskSamplePeakPositions"][0].append([50.0, 50.0])
    r[0]["diskSamplePeakCounts"][0] += 1


case("a peak added (positions AND count agree with each other)", "RED", add_peak, contains=("alpha.h5",))
case("the report carries no positions though pinned", "RED",
     lambda r: r[0].pop("diskSamplePeakPositions"), contains=("alpha.h5", "diskSamplePeakPositions"))
case("sampled scan positions changed", "RED",
     lambda r: r[0].__setitem__("diskSampleScanPositions", [[0, 0], [2, 2], [3, 3]]),
     contains=("alpha.h5", "diskSampleScanPositions"))
case("positions list shorter than the pinned one", "RED",
     lambda r: r[1]["diskSamplePeakPositions"].pop(), contains=("beta.h5",))

# The reverse direction: expected holds two peaks 0.02 px apart, the report one of
# them and a stranger. Every EXPECTED peak has a near actual peak; only the actual
# stranger has no expected one, so a one-way nearest-neighbour check is green here.
close = copy.deepcopy(BASE)
close[0]["diskSamplePeakPositions"][0] = [[10.0, 12.0], [10.02, 12.0]]
close[0]["diskSamplePeakCounts"][0] = 2
close[0]["diskSampleAfterSpacingCounts"][0] = 2
stranger = copy.deepcopy(close)
stranger[0]["diskSamplePeakPositions"][0] = [[10.0, 12.0], [25.0, 25.0]]
rc, out = run(close, stranger)
if rc != 0 and "FAIL: " in out and "alpha.h5" in out and "Traceback" not in out:
    passed += 1
    print("PASS: an unpinned stranger peak next to a doubled pin -> refused")
else:
    failed += 1
    print("FAIL: an unpinned stranger peak next to a doubled pin: exit", rc, out.replace("\n", " | "))

print("")
print("== A. every mismatch is named, not the first ==")


def many(r):
    r[0]["virtualImageMean"] += 100.0                 # alpha, image
    r[0]["diskProbeRadiusPixels"] += 1.0              # alpha, radius
    r[1]["dtype"] = "float64"                         # beta, exact field
    r[1]["diskSampleAfterRelativeCounts"][2] += 1     # beta, counts
    move(r, 1, 1, 0, 3.0, 0)                          # beta, position


case("five mismatches across two datasets", "RED", many,
     contains=("alpha.h5 virtualImageMean", "alpha.h5 diskProbeRadiusPixels", "beta.h5 dtype",
               "beta.h5 diskSampleAfterRelativeCounts", "beta.h5 scan position (ry=1, rx=1)",
               "5 mismatch"))
case("a missing pinned dataset AND a drifted one", "RED",
     lambda r: (r.pop(0), r[0].__setitem__("virtualImageMinimum", 11.0)),
     contains=("alpha.h5", "beta.h5 virtualImageMinimum"))
case("one pinned dataset malformed AND another drifted", "RED",
     lambda r: (r[0].pop("virtualImageMean"), r[1].__setitem__("dtype", "int8")),
     contains=("alpha.h5", "virtualImageMean", "beta.h5 dtype"))

print(f"AB {passed} {failed}")
PY
cat "$WORK/ab.out" | grep -v '^AB '
read -r _ ab_pass ab_fail <<< "$(grep '^AB ' "$WORK/ab.out")"
(( pass += ab_pass )) || true
(( fail += ab_fail )) || true

# --- C: no data at all is RED ---------------------------------------------------
print ""
print "== C. run.sh with no data is a FAIL, not a SKIP ==="
DATA_EMPTY="$WORK/empty-data"; mkdir -p "$DATA_EMPTY"
DATA_ONE="$WORK/one-data"; mkdir -p "$DATA_ONE"; : > "$DATA_ONE/probe.h5"
check_data() {
  local name="$1" want="$2" dir="$3" out rc
  set +e
  out="$(MAC4DSTEM_TRAINING_DATASET_DIR="$dir" "$HERE/run.sh" --check-data 2>&1)"; rc=$?
  set -e
  if [[ "$want" == RED ]]; then
    if (( rc != 0 )) && [[ "$out" == *"FAIL: "* ]]; then ok "$name -> refused: ${out##*FAIL: }"
    else bad "$name expected a refusal with a FAIL: line; exit $rc: $out"; fi
  else
    if (( rc == 0 )); then ok "$name -> green as required"
    else bad "$name expected GREEN, exit $rc: $out"; fi
  fi
}
check_data "an empty dataset directory"        RED   "$DATA_EMPTY"
check_data "a dataset directory that is gone"  RED   "$WORK/never-existed"
check_data "one .h5 present"                   GREEN "$DATA_ONE"

# --- D: run-tests.sh routes ------------------------------------------------------
print ""
print "== D. scientific reaches the real-data harness; all reaches it once =="
FAKE="$WORK/fake"; mkdir -p "$FAKE/tools/lib" "$FAKE/bin" "$FAKE/home"
cp "$ROOT/tools/run-tests.sh" "$FAKE/tools/run-tests.sh"
print -r -- 'resolve_mac4dstem_developer_dir() { :; }' > "$FAKE/tools/lib/developer-dir.sh"
print -r -- '#!/bin/sh'$'\n''exit 0' > "$FAKE/tools/lib/fetch-py4dstem.sh"
print -r -- '#!/bin/sh'$'\n''exit 0' > "$FAKE/bin/xcodebuild"
# require_free_space reads `df`; this test is about routing, not the disk.
print -r -- '#!/bin/sh'$'\n''echo "Filesystem 1G-blocks Used Available Capacity Mounted"; echo "x 999 1 998 1% /"' > "$FAKE/bin/df"
# A stub for every harness the arrays NAME (not only the directories that exist
# today: a harness being added mid-session must not turn a routing test red).
stub_names=(real-data-acceptance package-test)
for rs in "$ROOT"/tools/*/run.sh; do stub_names+=("${rs:h:t}"); done
stub_names+=($(awk '/^(scientific|campaign)=\(/{f=1; sub(/^[a-z]+=\(/, "")} f{ if ($0 ~ /^\)/) {f=0} else print }' "$ROOT/tools/run-tests.sh" | tr -d '()'))
for d in ${(u)stub_names}; do
  mkdir -p "$FAKE/tools/$d"
  print -r -- '#!/bin/sh'$'\n''echo "STUB '"$d"'"' > "$FAKE/tools/$d/run.sh"
done
print -r -- '#!/bin/sh'$'\n''echo "STUB compare-selftest"' > "$FAKE/tools/real-data-acceptance/compare-selftest.sh"
chmod +x "$FAKE"/tools/*/run.sh "$FAKE/tools/real-data-acceptance/compare-selftest.sh" \
         "$FAKE/tools/lib/fetch-py4dstem.sh" "$FAKE/bin/xcodebuild" "$FAKE/bin/df" "$FAKE/tools/run-tests.sh"
routes() {
  env -u CI -u MAC4DSTEM_NO_REAL_DATA "$@" HOME="$FAKE/home" PATH="$FAKE/bin:$PATH" \
    "$FAKE/tools/run-tests.sh" "$TARGET" 2>&1 || echo "run-tests.sh exited non-zero"
}
count_of() { print -r -- "$1" | grep -c -- "$2" || true; }
TARGET=scientific; out="$(routes env)"
n="$(count_of "$out" '^==> real-data-acceptance$')"
[[ "$n" == 1 ]] && ok "scientific runs real-data-acceptance once" || bad "scientific ran real-data-acceptance $n times: $out"
TARGET=all; out="$(routes env)"
n="$(count_of "$out" '^==> real-data-acceptance$')"
[[ "$n" == 1 ]] && ok "all runs real-data-acceptance exactly once" || bad "all ran real-data-acceptance $n times"
TARGET=scientific; out="$(routes env MAC4DSTEM_NO_REAL_DATA=1)"
n="$(count_of "$out" '^==> real-data-acceptance$')"
if [[ "$n" == 0 && "$out" == *"NOT RUN"* && "$out" == *"STUB compare-selftest"* ]]; then
  ok "MAC4DSTEM_NO_REAL_DATA=1 skips the data run out loud and still runs the comparator self-test"
else bad "MAC4DSTEM_NO_REAL_DATA=1: harness ran $n times, output: $out"; fi
TARGET=scientific; out="$(routes env CI=true)"
n="$(count_of "$out" '^==> real-data-acceptance$')"
if [[ "$n" == 0 && "$out" == *"NOT RUN"* ]]; then ok "CI=true skips the data run out loud"
else bad "CI=true: harness ran $n times"; fi

# --- E: the shipped pin --------------------------------------------------------
print ""
print "== E. the shipped expected.json pins positions on every dataset =="
if python3 - "$SHIPPED_EXPECTED" <<'PY'
import json, sys
e = json.load(open(sys.argv[1]))
bad = [x["file"] for x in e
       if not x.get("diskSamplePeakPositions") or not x.get("diskSampleScanPositions")
       or len(x["diskSamplePeakPositions"]) != len(x["diskSampleScanPositions"])
       or [len(p) for p in x["diskSamplePeakPositions"]] != x["diskSamplePeakCounts"]]
if bad:
    print("no positional pin (or one inconsistent with its counts): " + ", ".join(bad)); sys.exit(1)
PY
then ok "every pinned dataset carries a positional fingerprint consistent with its counts"
else bad "the shipped expected.json lacks positional pins (see above)"; fi

print ""
print "compare-selftest: $pass passed, $fail failed"
(( fail == 0 )) || exit 1
