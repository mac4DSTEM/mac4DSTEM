#!/bin/zsh
# One discoverable entry point. Cross-language harnesses stay independent of
# XCTest because they validate Python/EMD/package boundaries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/lib/developer-dir.sh"
resolve_mac4dstem_developer_dir

# Free-space preflight. On 2026-08-06 three consecutive full-suite runs produced
# three *different* failure sets, none related to the code, all caused by a full
# disk, and they were nearly diagnosed as real regressions (docs/v2-scope.md
# §6.6). Measured per-run cost is small — DerivedData 0.2 GB (2026-08-18), plus
# the ~300 MB system log archive `xcodebuild test` writes to /var/tmp per run —
# so the floors below are deliberately margin, not measurement: the failure mode
# is a near-full disk producing varied spurious failures, not a clean ENOSPC.
require_free_space() {
  # NB: `dir`, not `path` — in zsh `path` is tied to $PATH, and declaring it
  # local blanks PATH inside the function (df/awk vanish; caught 2026-08-18).
  local need="$1" what="$2" dir have
  for dir in "$ROOT" "${TMPDIR:-/tmp}"; do
    have="$(df -Pg "$dir" | awk 'NR==2 {print $4}')"
    if [[ -z "$have" ]] || (( have < need )); then
      echo "run-tests.sh: need ${need} GB free for ${what}, have ${have:-?} GB on ${dir}" >&2
      echo "  Free space and re-run; a near-full disk fakes code regressions." >&2
      echo "  tools/free-space.sh reports the known build debris; --clear deletes it." >&2
      exit 69
    fi
  done
}

unit_tests() (
  # Never let an unsigned test build replace the app that Xcode launches from
  # its normal DerivedData directory. HDF5 is loaded lazily, so overwriting a
  # running app can otherwise give the process and bundled dylib different code
  # identities and make macOS reject the library.
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-unit-tests.XXXXXX")"
  trap 'rm -rf "$work"' EXIT

  # CI keeps the result bundle long enough to export S17's sidebar-geometry
  # attachment. Local runs need no bundle and retain the existing behaviour.
  local -a result_bundle_args=()
  if [[ -n "${MAC4DSTEM_XCRESULT_BUNDLE_PATH:-}" ]]; then
    result_bundle_args=(-resultBundlePath "$MAC4DSTEM_XCRESULT_BUNDLE_PATH")
  fi

  # -only-testing scopes this to the fast unit-test target. Without it,
  # adding mac4DSTEMUITests (tools/ui-qc-playthrough) would silently pull a
  # slow, screen-driving UI playthrough into every normal test run.
  LLVM_PROFILE_FILE="$work/default-%p.profraw" \
    xcodebuild test -project "$ROOT/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
      -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$work/DerivedData" \
      -only-testing:mac4DSTEMTests \
      "${result_bundle_args[@]}" \
      CODE_SIGNING_ALLOWED=NO -quiet
)

run_harnesses() {
  for name in "$@"; do
    local started=$(date +%s)
    echo "==> $name"
    "$ROOT/tools/$name/run.sh"
    local finished=$(date +%s)
    echo "<== $name ($((finished - started)) s)"
  done
}

scientific=(
  comparator-test
  calibration-test calibration-readiness-test q-calibration-gate-test
  virtual-detector-test
  virtual-detector-residency
  resident-cropped-view
  disk-detection-test disk-correlation-parity peak-overlay-test fit-overlay-test
  acom-orientation-test acom-matching-test acom-convention-test parity-metric-test cif-symmetry-test
  ws2-crystal-test
  idpc-test cancellation-test
  bragg-export-test sidecar-result-test strain-test strain-frame-test
  ellipse-calibration-test
  dm4-robustness-test vendor-reader-test load-spec-test load-spec-calibration
  preprocess-crop-bin-test load-spec-roundtrip sidecar-error-detail-test
  two-spec-analysis-test reduced-export-test
  preprocessing-export-test parallax-preprocessing-test parallax-alignment-test
  parallax-aberration-test parallax-subpixel-test parallax-depth-test
  singleslice-ptychography-test result-presentation-test
  scientific-bundle-test
)
campaign=(
  parallax-preprocessing-test parallax-alignment-test parallax-aberration-test
  parallax-subpixel-test parallax-depth-test singleslice-ptychography-test
  sidecar-result-test result-presentation-test
)

# Inventory — the repo's own review, run at every closeout (docs/v2.5-plan.md
# §2 numbers). Every tools/ directory must be in exactly one list below; the
# gated ones are `scientific` plus the two `all` extras. Diagnostic runners
# never gate: they need machine-local data. Exits 1 on an unclassified or
# missing runner, or on a live doc claiming work is uncommitted on a clean tree.
diagnostic=(acom-groundtruth bragg-spacing-probe origin-fit-diagnostics
  real-acom-benchmark residency-sweep volume-mmap-probe performance-baseline
  training-dataset-campaign review-record-check)
owner_only=(stage-tb1-ws2-fixture ui-smoke-test)
retired=(ui-qc-playthrough)
support=(lib release)

inventory() {
  local rc=0 name f
  local -a gated=("${scientific[@]}" real-data-acceptance package-test)
  local -a all=("${gated[@]}" "${diagnostic[@]}" "${owner_only[@]}" "${retired[@]}" "${support[@]}")
  echo "== tools/: gated ${#gated[@]}, diagnostic ${#diagnostic[@]}, owner-only ${#owner_only[@]}, retired ${#retired[@]}, support ${#support[@]}"
  for name in "${all[@]}"; do
    [[ -d "$ROOT/tools/$name" ]] || { echo "  MISSING      $name"; rc=1; }
  done
  for f in "$ROOT"/tools/*/; do
    name="$(basename "$f")"
    (( ${all[(Ie)$name]} )) || { echo "  UNCLASSIFIED $name"; rc=1; }
  done

  swift_lines() { find "$@" \( -name '*.swift' -o -name '*.metal' \) -exec cat {} + | wc -l | tr -d ' '; }
  md_lines() { cat "$@" | wc -l | tr -d ' '; }
  echo "== size"
  printf "  %-36s %7s\n" "app Swift+Metal lines" "$(swift_lines "$ROOT/mac4DSTEM")"
  printf "  %-36s %7s\n" "AppState.swift lines" "$(wc -l < "$ROOT/mac4DSTEM/App/AppState.swift" | tr -d ' ')"
  printf "  %-36s %7s\n" "AppState stored properties" "$(grep -cE '^[[:space:]]*(@ObservationIgnored )?(var|let) ' "$ROOT/mac4DSTEM/App/AppState.swift")"
  printf "  %-36s %7s\n" "ContentView.swift lines" "$(wc -l < "$ROOT/mac4DSTEM/UI/ContentView.swift" | tr -d ' ')"
  printf "  %-36s %7s\n" "unit-test lines" "$(swift_lines "$ROOT/mac4DSTEMTests")"
  printf "  %-36s %7s\n" "tools/ Swift lines" "$(swift_lines "$ROOT/tools")"
  printf "  %-36s %7s\n" "live markdown lines" "$(md_lines "$ROOT"/CLAUDE.md "$ROOT"/README.md "$ROOT"/CHANGELOG.md "$ROOT"/ROADMAP.md "$ROOT"/docs/*.md)"
  printf "  %-36s %7s\n" "archive markdown lines" "$(find "$ROOT/docs/archive" -name '*.md' -exec cat {} + | wc -l | tr -d ' ')"
  printf "  %-36s %7s\n" "cold-start set (CLAUDE+open-items+plan)" "$(md_lines "$ROOT"/CLAUDE.md "$ROOT"/docs/open-items.md "$ROOT"/docs/v2.5-plan.md)"
  echo "== app files over 800 lines"
  find "$ROOT/mac4DSTEM" -name '*.swift' -exec wc -l {} + | awk -v r="$ROOT/" '$1 > 800 && $2 != "total" { sub(r, "", $2); printf "  %6d %s\n", $1, $2 }' | sort -rn
  # Candidates only — a build is the proof. 2026-09-02: a reviewer's "no
  # references" claim on PtychographyPreparation.swift was wrong (AppState
  # uses its PtychographyPreparer type); the deletion failed the build.
  echo "== Swift files none of whose top-level types is referenced elsewhere (candidates; prove with a build)"
  local -a types; local t hit
  for f in $(find "$ROOT/mac4DSTEM" -name '*.swift'); do
    types=($(grep -oE '^(public |internal |final |nonisolated |@MainActor |@Observable |@frozen )*(struct|class|enum|actor|protocol) [A-Za-z_][A-Za-z0-9_]*' "$f" | awk '{print $NF}' | sort -u || true))
    (( ${#types[@]} )) || continue   # extension-only files are not judged
    hit=0
    for t in "${types[@]}"; do
      grep -rqw --include='*.swift' --exclude="$(basename "$f")" "$t" "$ROOT/mac4DSTEM" "$ROOT/mac4DSTEMTests" "$ROOT/tools" && { hit=1; break; }
    done
    (( hit )) || echo "  ${f#$ROOT/}  (${(j:, :)types})"
  done
  if [[ -z "$(git -C "$ROOT" status --porcelain)" ]]; then
    if grep -nE 'uncommitted' "$ROOT"/CLAUDE.md "$ROOT"/docs/*.md | grep -vE 'then-uncommitted|was (still )?uncommitted|at the time|inventory'; then
      echo "  ^ live docs claim uncommitted work on a clean tree"; rc=1
    fi
  fi
  return $rc
}

case "${1:-unit}" in
  inventory) inventory ;;
  unit) require_free_space 8 "the xcodebuild unit suite"; unit_tests ;;
  benchmark) require_free_space 4 "the performance baseline"; "$ROOT/tools/performance-baseline/run.sh" ;;
  campaign) require_free_space 8 "the campaign suite"; unit_tests; run_harnesses "${campaign[@]}" ;;
  scientific) require_free_space 4 "the science harnesses"; run_harnesses "${scientific[@]}" ;;
  all) require_free_space 8 "the full suite"; unit_tests; run_harnesses "${scientific[@]}" real-data-acceptance package-test ;;
  *) echo "Usage: tools/run-tests.sh [unit|benchmark|campaign|scientific|all|inventory]" >&2; exit 64 ;;
esac
