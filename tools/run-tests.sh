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

  # -only-testing scopes this to the fast unit-test target (the retired
  # UI-test target was deleted 2026-09-02; the flag stays so a future test
  # target cannot silently join every normal run).
  LLVM_PROFILE_FILE="$work/default-%p.profraw" \
    xcodebuild test -project "$ROOT/mac4DSTEM.xcodeproj" -scheme mac4DSTEM \
      -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$work/DerivedData" \
      -only-testing:mac4DSTEMTests \
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
  dm4-robustness-test vendor-reader-test load-spec-test datacube-discovery-test load-spec-calibration
  preprocess-crop-bin-test load-spec-roundtrip sidecar-error-detail-test
  two-spec-analysis-test reduced-export-test
  preprocessing-export-test parallax-preprocessing-test parallax-alignment-test
  parallax-aberration-test parallax-subpixel-test parallax-depth-test
  singleslice-ptychography-test result-presentation-test
  scientific-bundle-test
  disk-detector
)
campaign=(
  parallax-preprocessing-test parallax-alignment-test parallax-aberration-test
  parallax-subpixel-test parallax-depth-test singleslice-ptychography-test
  sidecar-result-test result-presentation-test
)

# Inventory — the repo's own review, run at every closeout (docs/v3-plan.md
# §2 numbers). Every tools/ directory must be in exactly one list below; the
# gated ones are `scientific` plus the two `all` extras. Diagnostic runners
# never gate: they need machine-local data. Exits 1 on an unclassified or
# missing runner, or on a live doc claiming work is uncommitted on a clean tree.
diagnostic=(acom-groundtruth bragg-spacing-probe origin-fit-diagnostics
  real-acom-benchmark residency-sweep volume-mmap-probe performance-baseline
  training-dataset-campaign review-record-check)
owner_only=()
retired=()
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
  # Type-scope declarations, not "stored properties": the old metric grepped
  # every `var`/`let` line at any indent, so it counted function locals and
  # computed properties and reported 491 where the file declares 166 at type
  # scope. Docs quoted the wrong number as evidence of progress (found
  # 2026-09-09). This counts declarations at type scope across EVERY type in
  # the file, which is what a grep can honestly say; separating stored from
  # computed needs a parser, because `var x = Y { didSet … }` is stored.
  printf "  %-36s %7s\n" "AppState.swift type-scope decls" "$(grep -cE '^    (@ObservationIgnored )?(var|let) ' "$ROOT/mac4DSTEM/App/AppState.swift")"
  # C5 (2026-09-07): AppState.swift + Support/ResultExport.swift never net
  # positive — the prose rule ("a session that touches AppState moves one
  # responsibility out") was waived four sessions running, so the count is
  # read here instead: against HEAD while either file is dirty, against HEAD^
  # once committed, so the commit being made (or just made) is the one judged.
  local -a heavy=(mac4DSTEM/App/AppState.swift mac4DSTEM/Support/ResultExport.swift)
  local base_ref heavy_now=0 heavy_base=0 n
  if [[ -n "$(git -C "$ROOT" status --porcelain -- "${heavy[@]}")" ]]; then base_ref=HEAD; else base_ref=HEAD^; fi
  # A base that cannot be read is a broken measurement, not a measurement of
  # zero. actions/checkout clones at depth 1, so on a clean CI tree `HEAD^`
  # does not resolve; the read went through `|| true`, returned 0 lines, and
  # the whole 7 509 lines were reported as growth — the inventory job could
  # never pass (found 2026-09-09; the job now checks out with fetch-depth 2).
  if ! git -C "$ROOT" rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null; then
    echo "  AppState + ResultExport lines: $base_ref does not resolve, so growth was NOT measured"
    echo "  ^ the C5 rule needs two commits of history (actions/checkout defaults to fetch-depth 1)"; rc=1
  else
    for f in "${heavy[@]}"; do
      n="$(wc -l < "$ROOT/$f" | tr -d ' ')"; heavy_now=$(( heavy_now + n ))
      n="$( { git -C "$ROOT" show "$base_ref:$f" 2>/dev/null || true; } | wc -l | tr -d ' ')"; heavy_base=$(( heavy_base + n ))
    done
    printf "  %-36s %7s   (%s at %s)\n" "AppState + ResultExport lines" "$heavy_now" "$heavy_base" "$base_ref"
    if (( heavy_now > heavy_base )); then
      echo "  ^ AppState.swift + ResultExport.swift grew by $(( heavy_now - heavy_base )) lines (C5: they never net positive)"; rc=1
    fi
  fi
  printf "  %-36s %7s\n" "UI/ Swift lines" "$(cat "$ROOT"/mac4DSTEM/UI/*.swift | wc -l | tr -d ' ')"
  printf "  %-36s %7s\n" "unit-test lines" "$(swift_lines "$ROOT/mac4DSTEMTests")"
  printf "  %-36s %7s\n" "tools/ Swift lines" "$(swift_lines "$ROOT/tools")"
  printf "  %-36s %7s\n" "live markdown lines" "$(md_lines "$ROOT"/CLAUDE.md "$ROOT"/README.md "$ROOT"/CHANGELOG.md "$ROOT"/ROADMAP.md "$ROOT"/docs/*.md)"
  printf "  %-36s %7s\n" "archive markdown lines" "$(find "$ROOT/docs/archive" -name '*.md' -exec cat {} + | wc -l | tr -d ' ')"
  printf "  %-36s %7s\n" "cold-start set (CLAUDE+status+plan+open-items)" "$(md_lines "$ROOT"/CLAUDE.md "$ROOT"/docs/status.md "$ROOT"/docs/v3-plan.md "$ROOT"/docs/open-items.md)"
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
  # Presentation contract rule 3 (architecture.md, 2026-09-03): the chrome
  # and the columns draw no bar or wash of their own. Not measurable in the
  # NSView tree (SwiftUI's `.bar` hosts no NSVisualEffectView; measured
  # 2026-09-03), so the rule is held here. The scientific panes are exempt.
  if grep -nE '\.background\((\.bar\)|Color\.[a-zA-Z]+\.opacity)' "$ROOT"/mac4DSTEM/UI/*.swift \
       | grep -vE 'ImagePanes|PaneOverlays|LoadConfigurator|MetalImageView|HistogramView'; then
    echo "  ^ custom bar or opacity wash in the chrome (presentation contract rule 3)"; rc=1
  fi
  # Rule 4 (2026-09-03): no fixed frames except the science. A numeric
  # `.frame(...)` in the chrome must come from `FormPolicy`/`WindowPolicy`
  # (FormControls.swift); the panes, overlays and plots are exempt.
  if grep -nE '\.frame\([^)]*: *[0-9]' "$ROOT"/mac4DSTEM/UI/*.swift \
       | grep -vE 'ImagePanes|PaneOverlays|HistogramView|ResultsWorkspace|LoadConfigurator|LayoutPolicy' \
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
  if grep -L 'sources.manifest' "$ROOT"/tools/*/run.sh | grep .; then
    echo "  ^ a harness that neither sources tools/lib/sources.manifest nor says why"; rc=1
  fi
  # AGENTS.md is generated from CLAUDE.md; a stale copy is a wrong document.
  "$ROOT/tools/sync-agents-md.sh" --check || rc=1

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
  local dl sum
  for dl in "$ROOT"/*.dylib(N); do
    dl="${dl:t}"; sum="$(shasum -a 256 "$ROOT/$dl" | cut -d' ' -f1)"
    if ! grep -q "$dl" "$ROOT/NOTICE"; then
      echo "  UNNAMED   $dl is redistributed and NOTICE does not name it"; rc=1
    elif ! grep -q "$sum" "$ROOT/NOTICE"; then
      echo "  HASH      $dl is $sum; NOTICE states a different one"; rc=1
    else
      printf "  %-36s %s\n" "$dl" "${sum[1,16]}…"
    fi
    # An absolute path in a load command is what breaks a relocated, signed
    # bundle. `docs/releasing.md` claimed these were "free of Homebrew paths";
    # they are free of them HERE, and nowhere else — libhdf5 still carries the
    # Homebrew build stamp as a string (2026-09-09).
    if otool -L "$ROOT/$dl" | tail -n +2 | grep -qE '^\s+/(opt|usr/local|Users)/'; then
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

  # A doc that states current truth must not cite a repo path that is not
  # there: the citation is the evidence, and a reader who cannot open it
  # cannot check the claim (CLAUDE.md, "No claim a reader cannot reproduce").
  # Backticked paths rooted in a real top directory only — prose like `1/nm`
  # or `Rx/Ry` is not a path. Three exemptions, each for a reason: plans and
  # designs name what does not exist yet, CHANGELOG.md names what existed at
  # a past version, and `scratchpad/` is gitignored by design.
  local -a truth_docs=("$ROOT"/CLAUDE.md "$ROOT"/README.md "$ROOT"/NOTICE "$ROOT"/CONTRIBUTING.md)
  local d dp
  for d in "$ROOT"/docs/*.md; do
    case "$d" in *plan*.md|*design*.md) ;; *) truth_docs+=("$d");; esac
  done
  # Two families: rooted at the repo, and rooted at the app source directory —
  # `Session/SessionGates.swift` is how these docs cite app files, and one such
  # citation still said `App/` from before the Session/ split (2026-09-09).
  # Only tokens that carry a file extension or end in "/" are judged, so a type
  # name written like a path (`UI/ContentView`) is not mistaken for a file.
  for dp in $(grep -ohE '`(docs|tools|mac4DSTEM|mac4DSTEMTests|Models|Licenses|\.github)/[A-Za-z0-9_./-]+`' "${truth_docs[@]}" | tr -d '`' | sort -u); do
    [[ "$dp" == */ || "$dp" == *.* ]] || continue
    [[ -e "$ROOT/${dp%/}" ]] && continue
    echo "  DEAD PATH $dp   cited by $(cd "$ROOT" && grep -l -- "$dp" "${truth_docs[@]#$ROOT/}" | tr '\n' ' ')"; rc=1
  done
  for dp in $(grep -ohE '`(App|Core|Session|UI|Support|Shaders)/[A-Za-z0-9_./-]+`' "${truth_docs[@]}" | tr -d '`' | sort -u); do
    [[ "$dp" == */ || "$dp" == *.* ]] || continue
    [[ -e "$ROOT/mac4DSTEM/${dp%/}" ]] && continue
    echo "  DEAD PATH mac4DSTEM/$dp   cited by $(cd "$ROOT" && grep -l -- "$dp" "${truth_docs[@]#$ROOT/}" | tr '\n' ' ')"; rc=1
  done
  if [[ -z "$(git -C "$ROOT" status --porcelain)" ]]; then
    # Status claims only ("held uncommitted", "still uncommitted"), not the
    # word in general — the process doc uses it generically.
    # ...and only positive ones: "Nothing is uncommitted" is the opposite claim
    # and is true on a clean tree. It red-lined this gate on 2026-09-09.
    if grep -nEi '(held|still|stays?|remains?|is|are) uncommitted' "$ROOT"/CLAUDE.md "$ROOT"/docs/*.md | grep -viE 'was (still )?uncommitted|at the time|(nothing|none|no [a-z]+) (is|are|remains?) uncommitted'; then
      echo "  ^ live docs claim uncommitted work on a clean tree"; rc=1
    fi
  fi
  return $rc
}

core_build() {
  # The package layers (Package.swift, v2.5 step 2): DSTEMCore (Core/) and
  # DSTEMSession (Session/). Fails the moment either reaches upward into
  # App/, UI/ or Support/, or Core reaches into Session.
  ( cd "$ROOT" && swift build 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]' ) && echo "core: DSTEMCore + DSTEMSession built"
}

case "${1:-unit}" in
  inventory) inventory ;;
  core) core_build ;;
  unit) require_free_space 8 "the xcodebuild unit suite"; unit_tests ;;
  benchmark) require_free_space 4 "the performance baseline"; "$ROOT/tools/performance-baseline/run.sh" ;;
  campaign) require_free_space 8 "the campaign suite"; unit_tests; run_harnesses "${campaign[@]}" ;;
  scientific) require_free_space 4 "the science harnesses"; "$ROOT/tools/lib/fetch-py4dstem.sh"; run_harnesses "${scientific[@]}" ;;
  all) require_free_space 8 "the full suite"; "$ROOT/tools/lib/fetch-py4dstem.sh"; unit_tests; run_harnesses "${scientific[@]}" real-data-acceptance package-test ;;
  *) echo "Usage: tools/run-tests.sh [unit|benchmark|campaign|scientific|all|inventory|core]" >&2; exit 64 ;;
esac
