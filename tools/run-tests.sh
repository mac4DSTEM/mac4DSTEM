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
#
# MEASURED 2026-09-12, because "margin, not measurement" is only defensible
# until someone measures. Sampling free space every 3 s through a full
# `-only-testing:mac4DSTEMTests` run: PEAK CONSUMPTION 1245 MB, and the suite
# completed 602/0 with 7 GB free — i.e. it ran fine BELOW the 8 GB floor that
# was refusing it. The floor was blocking work it did not need to block.
#
# `unit` is therefore 4 GB: 3.2x the measured peak, and the same value
# `scientific` already uses, so this aligns the floors rather
# than inventing a weaker one. It still protects the failure mode above, which
# needs the disk to actually fill mid-run.
#
# `all` and `campaign` KEEP 8. They run the scientific harnesses, package-test
# and real-data-acceptance on top of the unit suite, and nobody has measured
# their peak. Lowering a floor on a target you have not measured is the guess
# this comment exists to prevent.
require_free_space() {
  # NB: `dir`, not `path` — in zsh `path` is tied to $PATH, and declaring it
  # local blanks PATH inside the function (df/awk vanish; caught 2026-08-18).
  local need="$1" what="$2" dir have
  for dir in "$ROOT" "${TMPDIR:-/tmp}"; do
    have="$(df -Pg "$dir" | awk 'NR==2 {print $4}')"
    if [[ -z "$have" ]] || (( have < need )); then
      echo "run-tests.sh: need ${need} GB free for ${what}, have ${have:-?} GB on ${dir}" >&2
      echo "  Free space and re-run; a near-full disk fakes code regressions." >&2
      echo "  Clear build debris (DerivedData, .build) to free disk space." >&2
      exit 69
    fi
  done
}

# The unit tests' host is the app, unsigned and so unsandboxed: it restores the
# window and split geometry that whatever unsigned build ran last saved in
# ~/Library/Preferences. On 2026-09-28 a saved 915-pt window with a 278-pt
# sidebar made every launch abort in the constraint loop (window − sidebar
# ≤ 639 pt crashes, ≥ 640 passes; `open-items.md`), turning the gate red on
# unchanged code. The gate starts from the default geometry instead, and says
# which keys it cleared. The app's own defect is recorded, not hidden, there.
clear_test_host_geometry() {
  local domain="$HOME/Library/Preferences/com.mac4dstem.mac4DSTEM.plist" key
  [[ -f "$domain" ]] || return 0
  defaults export "$domain" - | plutil -p - \
    | sed -n 's/^  "\(NSWindow Frame [^"]*\)" =>.*/\1/p; s/^  "\(NSSplitView Subview Frames [^"]*\)" =>.*/\1/p' \
    | while IFS= read -r key; do
        echo "run-tests.sh: clearing the test host's saved geometry: $key"
        defaults delete "$domain" "$key"
      done
}

unit_tests() (
  clear_test_host_geometry
  # Never let an unsigned test build replace the app that Xcode launches from
  # its normal DerivedData directory. HDF5 is loaded lazily, so overwriting a
  # running app can otherwise give the process and bundled dylib different code
  # identities and make macOS reject the library.
  local work dd
  work="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-unit-tests.XXXXXX")"
  trap 'rm -rf "$work"' EXIT
  # Warm builds (2026-10-14): a lane's repeated runs may reuse one DerivedData by setting MAC4DSTEM_UNIT_DERIVED_DATA to a
  # directory of its own (kept between runs); unset, the build is cold in a throwaway folder — the landing gate stays cold.
  dd="${MAC4DSTEM_UNIT_DERIVED_DATA:-$work/DerivedData}"
  # The scheme runs the suite in parallel (`parallelizable`); the workers are capped at 8, the suite's limit for heavy CPU
  # jobs (load 22-25 on 18 cores through 2026-10-14). MAC4DSTEM_UNIT_PARALLEL=NO runs it serially (the comparison run).
  local -a par=(-parallel-testing-enabled "${MAC4DSTEM_UNIT_PARALLEL:-YES}")
  [[ "${MAC4DSTEM_UNIT_PARALLEL:-YES}" == YES ]] && par+=(-parallel-testing-worker-count "${MAC4DSTEM_UNIT_WORKERS:-8}")

  # -only-testing scopes this to the fast unit-test target (the retired
  # UI-test target was deleted 2026-09-02; the flag stays so a future test
  # target cannot silently join every normal run).
  # CODE_SIGNING_ALLOWED=NO is for this unsigned XCTest path only: never add it to a build you intend to launch.
  # SWIFT_OPTIMIZATION_LEVEL=-O (S4, 2026-10-13): SpectroKit is a versioned
  # dependency and cannot carry its own Debug -O, so in Debug Xcode builds it
  # -Onone (the 936 MB Velox read 20.3 s vs 1.0 s). A command-line setting is
  # the one that reaches a package target; it also makes the test target -O
  # (the app and DSTEMCore already are). Testability stays on (Debug).
  LLVM_PROFILE_FILE="$work/default-%p.profraw" \
    xcodebuild test -project "$ROOT/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
      -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$dd" "${par[@]}" \
      -only-testing:mac4DSTEMTests \
      SWIFT_OPTIMIZATION_LEVEL=-O CODE_SIGNING_ALLOWED=NO -quiet
)

run_harnesses() {
  for name in "$@"; do
    local started=$(date +%s)
    echo "==> $name"
    "$ROOT/tools/harnesses/$name/run.sh"
    local finished=$(date +%s)
    echo "<== $name ($((finished - started)) s)"
  done
}

# real-data-acceptance is NOT in the array below (inventory counts it as gated
# on its own, and `all` runs it explicitly — listing it twice would run it twice).
# `scientific` reaches it here (S19, 2026-09-30): before, only `all` did, and
# `scientific` stayed green three days past ba6360d, which real data would have
# turned red. It FAILS, it does not skip, when the data are gone (its run.sh);
# a machine that never had References/training_dataset says so out loud with
# MAC4DSTEM_NO_REAL_DATA=1, and CI (which sets CI) is such a machine. The
# comparator self-test needs no data and always runs.
real_data() {
  if [[ -n "${MAC4DSTEM_NO_REAL_DATA:-}" || -n "${CI:-}" ]]; then
    echo "==> real-data-acceptance: NOT RUN (MAC4DSTEM_NO_REAL_DATA or CI is set: no real data on this machine)"
    "$ROOT/tools/harnesses/real-data-acceptance/compare-selftest.sh"
    return
  fi
  run_harnesses real-data-acceptance
}

scientific=(
  comparator-test
  calibration-test calibration-readiness-test q-calibration-gate-test
  virtual-detector-test
  virtual-detector-residency
  resident-cropped-view
  disk-detection-test embedding-pca-parity disk-correlation-parity peak-overlay-test fit-overlay-test
  phase-vector-matching
  acom-orientation-test acom-matching-test acom-convention-test acom-mirror-test parity-metric-test cif-symmetry-test
  ws2-crystal-test
  idpc-test cancellation-test tiled-detection-memory-test virtual-detector-memory-test
  bragg-export-test sidecar-result-test strain-test strain-frame-test
  ellipse-calibration-test
  dm4-robustness-test vendor-reader-test load-spec-test datacube-discovery-test load-spec-calibration
  preprocess-crop-bin-test load-spec-roundtrip sidecar-error-detail-test
  two-spec-analysis-test reduced-export-test
  preprocessing-export-test parallax-preprocessing-test parallax-alignment-test
  parallax-aberration-test parallax-subpixel-test parallax-depth-test
  singleslice-ptychography-test result-presentation-test
  scientific-bundle-test
  disk-detector
  rotation-parity-test
  friedel-origin-test
  hdf5-exit-race-test
)
campaign=(
  parallax-preprocessing-test parallax-alignment-test parallax-aberration-test
  parallax-subpixel-test parallax-depth-test singleslice-ptychography-test
  sidecar-result-test result-presentation-test
)

# Inventory — the repo's own review (CI runs it on every push). Every tools/harnesses/ directory (and every other tools/ directory) must be in exactly one list below; the
# gated ones are `scientific` plus the two `all` extras. Diagnostic runners
# never gate: they need machine-local data. Exits 1 on an unclassified or
# missing runner, a failed invariant below, or a live doc claiming work is uncommitted on a clean tree.
diagnostic=()
owner_only=()
retired=()
# Every harness folder lives in tools/harnesses/ and is named in an array above; `support` names the folders that stay
# directly in tools/ (lib, release procedure tools/release/README.md). A folder here that nothing gated runs
# belongs in ../process/archive/mac4DSTEM/tools/.
support=(lib release)

inventory() {
  local rc=0 name f
  local -a gated=("${scientific[@]}" real-data-acceptance package-test)
  local -a harness_names=("${gated[@]}" "${diagnostic[@]}" "${owner_only[@]}" "${retired[@]}")
  echo "== tools/: gated ${#gated[@]}, diagnostic ${#diagnostic[@]}, owner-only ${#owner_only[@]}, retired ${#retired[@]}, support ${#support[@]}"
  for name in "${harness_names[@]}"; do
    [[ -d "$ROOT/tools/harnesses/$name" ]] || { echo "  MISSING      harnesses/$name"; rc=1; }
  done
  for name in "${support[@]}"; do
    [[ -d "$ROOT/tools/$name" ]] || { echo "  MISSING      $name"; rc=1; }
  done
  for f in "$ROOT"/tools/harnesses/*/; do
    name="$(basename "$f")"
    (( ${harness_names[(Ie)$name]} )) || { echo "  UNCLASSIFIED harnesses/$name"; rc=1; }
  done
  for f in "$ROOT"/tools/*/; do
    name="$(basename "$f")"
    [[ "$name" == harnesses ]] && continue
    (( ${support[(Ie)$name]} )) || { echo "  UNCLASSIFIED $name"; rc=1; }
  done

  # Large tracked files (added 2026-09-18): history already carries a removed 6 MB model and two copies of a 4 MB dylib, and a
  # public repo's history is not rewritten. Any tracked file over 1 MiB must be named, with its reason, in tools/large-files.allow.
  echo "== tracked files over 1 MiB"
  local big allow_file="$ROOT/tools/large-files.allow"
  while IFS= read -r big; do
    [[ -z "$big" ]] && continue
    if grep -q "^${big}	" "$allow_file" 2>/dev/null; then
      printf "  %-56s allowed\n" "$big"
    else
      printf "  %-56s NOT IN tools/large-files.allow\n" "$big"; rc=1
    fi
  done < <(git -C "$ROOT" ls-files -z | xargs -0 stat -f '%z %N' | awk '$1 > 1048576 {print $2}')

  # The learned detector runs on the Neural Engine in the app (owner, 2026-09-30): `loadForComparison` loads it
  # on another compute unit or batch, for tools and tests only. One app caller would put a Detect All, or the
  # model a fine-tune is judged against, on other numerics with every unit test green (Gate B, 2026-09-30).
  echo "== the app loads the learned detector on the Neural Engine only"
  local comparison_callers
  comparison_callers=$(grep -rl 'loadForComparison' "$ROOT/mac4DSTEM" | grep -v '/Core/ML/LearnedDiskDetector.swift$' || true)
  if [[ -n "$comparison_callers" ]]; then
    echo "  loadForComparison is called from app code: $comparison_callers"; rc=1
  else
    echo "  no app caller of loadForComparison"
  fi
  # Unvalidated stays labelled (owner, 2026-09-18): the phase-mapping badge
  # and the export key are load-bearing; a session that drops either would
  # ship an unvalidated map as science.
  echo "== unvalidated products stay labelled"
  # The badge is the kit's `InspectorWarning` since 2026-09-30 (same look as the
  # hand-rolled Label it replaced); either spelling of it satisfies the rule.
  if grep -Eq '(Label|InspectorWarning)\("Unvalidated' "$ROOT/mac4DSTEM/UI/PhaseMappingSettings.swift" \
     && grep -q '"validation": "none"' "$ROOT/mac4DSTEM/App/AppState+PhaseMapping.swift" \
     && grep -q 'UNVALIDATED (validation=none)' "$ROOT/mac4DSTEM/Support/ResultExport.swift"; then
    echo "  phase mapping: badge, validation:\"none\" key and the exported caption's UNVALIDATED present"
  else
    echo "  phase mapping: the Unvalidated badge, the validation:\"none\" key or the caption's UNVALIDATED is GONE"; rc=1
  fi

  # DM4 mapping (Gate B 2026-09-28; FormatoKit 0.7.0 switch 2026-10-21): the unit tests pin `readingOptions(forPath:)` alone; a
  # literal storage in `init` kept them green and read a 128 MB file off exFAT into memory again (the defect that panicked this
  # Mac on 28 GB). `init` asks once, and the kit's storage (`.mapped` / `.readIntoMemory`) and the rank-3 file's options follow it.
  echo "== DM4Reader chooses its storage from readingOptions(forPath:)"
  local dm4="$ROOT/mac4DSTEM/Core/Data/DM4Reader.swift"
  if [[ "$(grep -c 'Self.readingOptions(forPath: path)' "$dm4")" == 1 ]] \
     && grep -q 'storage: isMapped ? .mapped : .readIntoMemory' "$dm4" \
     && grep -q 'options: options' "$dm4"; then
    echo "  one readingOptions(forPath:), the kit's storage and the rank-3 mapping follow it"
  else
    echo "  DM4Reader no longer chooses its storage once through readingOptions(forPath:)"; rc=1
  fi


  # Presentation contract rule 3 (architecture.md, 2026-09-03): the chrome
  # and the columns draw no bar or wash of their own. Not measurable in the
  # NSView tree (SwiftUI's `.bar` hosts no NSVisualEffectView; measured
  # 2026-09-03), so the rule is held here. The scientific panes are exempt.
  if grep -nE '\.background\((\.bar\)|Color\.[a-zA-Z]+\.opacity)' "$ROOT"/mac4DSTEM/UI/*.swift \
       | grep -vE 'ImagePanes|PaneOverlays|PhaseClaimOverlay|LoadConfigurator|MetalImageView|HistogramView'; then
    echo "  ^ custom bar or opacity wash in the chrome (presentation contract rule 3)"; rc=1
  fi
  # PhaseClaimOverlay (2026-09-30) is a science-pane overlay like PaneOverlays.
  # Rule 4 (2026-09-03): no fixed frames except the science. A numeric
  # `.frame(...)` in the chrome must come from `LayoutPolicy.swift`; the
  # panes, overlays and plots are exempt.
  if grep -nE '\.frame\([^)]*: *[0-9]' "$ROOT"/mac4DSTEM/UI/*.swift \
       | grep -vE 'ImagePanes|PaneOverlays|PhaseClaimOverlay|HistogramView|ResultsWorkspace|LoadConfigurator|LayoutPolicy' \
       | grep -vE 'LayoutPolicy\.|cropPane|// science'; then
    echo "  ^ a fixed frame outside the science (presentation contract rule 4)"; rc=1
  fi
  # The UI contract (architecture.md, 2026-09-04). UI/ is SwiftUI only, and
  # `HSplitView` in particular is banned: with the real panes inside it the
  # app aborted on launch in AppKit's update-constraints guard (Gate D,
  # `open-items.md`), and it is macOS-only besides. Prose could not hold this
  # — a fix in this repo gets a gate. Comment lines are exempt: the ban is
  # explained in several of them.
  if grep -nE '^[^/]*\b(HSplitView|VSplitView|NSSplitView|NSSplitViewController)\b' \
       "$ROOT"/mac4DSTEM/UI/*.swift; then
    echo "  ^ a split banned by the UI contract (architecture.md 'The UI contract')"; rc=1
  fi
  if grep -nE '^ *import +AppKit' "$ROOT"/mac4DSTEM/UI/*.swift; then
    echo "  ^ import AppKit in UI (architecture.md 'The UI contract')"; rc=1
  fi
  # Every harness compiles Core/ through tools/lib/sources.manifest or says
  # in one comment line why it has nothing to take from it (C2, 2026-09-07).
  # This is the drift class that broke five harnesses on 2026-08-17.
  if grep -L 'sources.manifest' "$ROOT"/tools/harnesses/*/run.sh | grep .; then
    echo "  ^ a harness that neither sources tools/lib/sources.manifest nor says why"; rc=1
  fi

  # Every file inside a folder reference is shipped, so every one must be
  # tracked. The app target copies such a folder into Resources wholesale, so
  # an untracked file in it is invisible on the machine that made it and fatal
  # everywhere else: the owner builds against his local copy while a fresh
  # clone ships the folder with the file missing. Found 2026-09-09 —
  # `.gitignore`'s `*.mlmodel` swallowed the learned detector's model spec, and
  # a negation on the .mlpackage directory does not re-include files beneath it.
  # A redistributed binary must be identified, not described. NOTICE states each
  # committed dylib's SHA-256; a swap that does not update it ships a different
  # library under the same notice, and until 2026-09-09 NOTICE also promised
  # licence texts that were in no bundle and in no clone.
  echo "== redistributed binaries (NOTICE names and hashes each)"
  # Since 2026-10-15 the app embeds none of its own: libhdf5, libsz and libaec are FormatoKit's. Since FormatoKit 0.4.0 they ship as
  # the frameworks FormatoLibHDF5, FormatoLibSZ and FormatoLibAEC (the same three files with install names and load commands rewritten),
  # so the files whose hashes NOTICE states are the pinned checkout's vendored originals (`swift package resolve` puts it in .build/checkouts).
  local dl sum hd="$ROOT/.build/checkouts/FormatoKit/tools/xcframework/vendored"
  [[ -d "$hd" ]] || { echo "  NOT CHECKED  no FormatoKit checkout ($hd); run swift package resolve"; rc=1; }
  for dl in "$hd"/*.dylib(N); do
    dl="${dl:t}"; sum="$(shasum -a 256 "$hd/$dl" | cut -d' ' -f1)"
    if ! grep -q "$dl" "$ROOT/NOTICE"; then
      echo "  UNNAMED   $dl is redistributed and NOTICE does not name it"; rc=1
    elif ! grep -q "$sum" "$ROOT/NOTICE"; then
      echo "  HASH      $dl is $sum; NOTICE states a different one"; rc=1
    else
      printf "  %-36s %s\n" "$dl" "${sum[1,16]}…"
    fi
    # An absolute path in a load command is what breaks a relocated, signed
    # bundle. `tools/release/README.md` claimed these were "free of Homebrew paths";
    # they are free of them HERE, and nowhere else — libhdf5 still carries the
    # Homebrew build stamp as a string (2026-09-09).
    if otool -L "$hd/$dl" | tail -n +2 | grep -qE '^\s+/(opt|usr/local|Users)/'; then
      echo "  ABSPATH   $dl links against an absolute path; a relocated bundle will not load it"; rc=1
    fi
  done

  echo "== bundled folder references (every file must be tracked)"
  local ref bf why
  for ref in $(grep 'lastKnownFileType = folder' "$ROOT/mac4DSTEM.xcodeproj/project.pbxproj" | sed -nE 's/.*path = ([^;]+);.*/\1/p' | tr -d '"'); do
    if [[ ! -d "$ROOT/$ref" ]]; then echo "  MISSING   $ref"; rc=1; continue; fi
    printf "  %-36s %7s files\n" "$ref" "$(find "$ROOT/$ref" -type f | wc -l | tr -d ' ')"
    for bf in $(cd "$ROOT" && find "$ref" -type f); do
      git -C "$ROOT" ls-files --error-unmatch -- "$bf" >/dev/null 2>&1 && continue
      # Name the ignore rule when there is one — that is the whole failure mode
      # here — but not a negation, which is the rule that lets the file IN.
      # `|| true`: check-ignore exits 1 when nothing matches and grep exits 1
      # when it filters the negation away — under `pipefail` either would abort
      # the whole gate here, printing nothing (caught by the negative control).
      why="$( { git -C "$ROOT" check-ignore -v -- "$bf" 2>/dev/null | grep -v ':!' | cut -d: -f1-2; } || true)"
      echo "  UNTRACKED $bf${why:+   $why}"; rc=1
    done
  done

  if [[ -z "$(git -C "$ROOT" status --porcelain)" ]]; then
    # Status claims only ("held uncommitted", "still uncommitted"), not the
    # word in general — the process doc uses it generically.
    # ...and only positive ones: "Nothing is uncommitted" is the opposite claim
    # and is true on a clean tree. It red-lined this gate on 2026-09-09.
    if grep -nEi '(held|still|stays?|remains?|is|are) uncommitted' "$ROOT"/CLAUDE.md "$ROOT"/docs/*.md "$ROOT"/docs/decisions/*.md | grep -viE 'was (still )?uncommitted|at the time|(nothing|none|no [a-z]+) (is|are|remains?) uncommitted'; then
      echo "  ^ live docs claim uncommitted work on a clean tree"; rc=1
    fi
  fi
  return $rc
}

core_build() (
  # The package layers (Package.swift, v2.5 step 2): DSTEMCore (Core/) and
  # DSTEMSession (Session/). Fails the moment either reaches upward into
  # App/, UI/ or Support/, or Core reaches into Session.
  # The exit is taken from swift build itself, not from a pipe: under
  # pipefail, grep -v that selects nothing (a clean build of progress lines
  # only) returned 1 and reported a false failure (2026-10-12).
  local work log rc=0
  work="$(mktemp -d "${TMPDIR:-/tmp}/mac4dstem-core-build.XXXXXX")"
  trap 'rm -rf "$work"' EXIT
  log="$work/swift-build.log"
  cd "$ROOT"
  swift build > "$log" 2>&1 && rc=0 || rc=$?
  grep -vE '^\[[0-9]+/[0-9]+\]' "$log" || true
  if [ "$rc" -eq 0 ]; then
    echo "core: DSTEMCore + DSTEMSession built"
  fi
  return "$rc"
)

case "${1:-unit}" in
  inventory) inventory ;;
  core) core_build ;;
  unit) require_free_space 4 "the xcodebuild unit suite"; unit_tests ;;
  campaign) require_free_space 8 "the campaign suite"; unit_tests; run_harnesses "${campaign[@]}" ;;
  scientific) require_free_space 4 "the science harnesses"; "$ROOT/tools/lib/fetch-py4dstem.sh"; run_harnesses "${scientific[@]}"; real_data ;;
  all) require_free_space 8 "the full suite"; "$ROOT/tools/lib/fetch-py4dstem.sh"; unit_tests; run_harnesses "${scientific[@]}" real-data-acceptance package-test ;;
  *) echo "Usage: tools/run-tests.sh [unit|campaign|scientific|all|inventory|core]" >&2; exit 64 ;;
esac
