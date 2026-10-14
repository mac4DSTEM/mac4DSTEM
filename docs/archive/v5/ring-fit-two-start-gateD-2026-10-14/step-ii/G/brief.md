# Lane G brief — fixture tests and per-variant gates (ring-fit two-start Gate D, step (ii), 2026-10-14)
SP = /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
REPO = /Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM (READ-ONLY for you: never edit, add, commit or push there).
Your lane dir: $SP/lanes/G/. Gate copies: $SP/gates/<name>/mac4DSTEM (make with $SP/gate-copy.sh <name>, then copy files in).
Read first: the record $REPO/docs/archive/v5/ring-fit-two-start-gateD-2026-10-14.md, section "Step (ii) — registration"
(Q5, Q6 are yours), and step 2's lane F2 report $SP/lanes/F2/report.md + its tests $SP/lanes/F2/test-{a,b}/EllipseNoisyRingTests.swift
(house style, the plant renderer, the dead and drift plants). Candidate files (full): $SP/patches/EllipseCalibration.<v>.swift for
v in none c b2 s cbs (and a, b from step 2). Do NOT read or run anything under $SP/ii/ (another lane's runs).

1. Tail plant search (for test-c's third method). Copy lane F's generator $SP/lanes/F/search/main.swift to your lane, add an
   optional 1/r^2 background term to its renderer: value += k * (R / max(r, 1))^2 with r the plain distance from the plant centre
   (k 0.4 or 0.8), and a CLI to run one plant / a small grid. Build it for head and a with $SP/harness/build.sh <out> <main.swift> <v>
   through $SP/heavy-build.sh <log> <cmd...> (a build slot; exit in <log>.exit). Search 192 px plants (R 60-70, eps 0.01/0.03, gap 0,
   noise 0.05-0.15, k 0.4/0.8, seeds 0-9, centre guess truth + (1.3, -0.9), annulus b-20..a+20) for one where HEAD's fit is within
   0.1 % and (a)'s is off by > 1 % (step 2's refuter found such plants at 512 px; S4 showed it at noise >= 5 % with k 0.4). Confirm it
   is a basin (1e-9 and 1e-6 moves of the guess change nothing) under head and a. If no 192 px plant exists, try 256 px; keep the
   test's cost about 1 s. Record the search in report.md (counts) — predictions first.
2. Tests (house style of the F2 files; renderer inside; doc comment with the search counts and the record path
   `archive/v5/ring-fit-two-start-gateD-2026-10-14.md`):
   - test-c/EllipseNoisyRingTests.swift: test-a's two methods (dead, drift: profile, |R-1| <= 0.01, |b/a err| <= 0.01, centre <= 1 px)
     plus a third: the tail plant fits within 1 % (same assertions). For c and cbs.
   - test-s/EllipseNoisyRingTests.swift: the dead and drift plants each fall back to the conic, profileFallbackReason names the move
     from the conic fit (the ringLeftSeed text: "moved the ring ... from the conic fit"). For s.
   - test-b2 = F2's test-b unchanged. For b2.
3. Gates, ONE AT A TIME (never two test hosts), each through `TMPDIR=$SP/gates/<name>/tmp $SP/heavy.sh <log> <copy>/tools/run-tests.sh unit`
   (heavy.sh takes a slot and waits on `drive` and macTEM `unit-*` lock files; exit in <log>.exit), run_in_background, wait for it:
     head-c  = HEAD + test-c      expect RED on exactly the two noisy methods (dead, drift); the tail method green
     a-c     = patch a + test-c   expect RED on exactly the tail method (the mutation test-c claims to catch)
     c       = patch c + test-c   unit + `tools/run-tests.sh core`, green
     cbs     = patch cbs + test-c unit + core, green
     s       = patch s + test-s   unit + core, green
     head-s  = HEAD + test-s      expect RED on exactly the two methods
     b2      = patch b2 + test-b2 unit + core, green
     none    = patch none (no new test) unit + core, green (the refactor alone)
   The patched file goes to mac4DSTEM/Core/Analysis/EllipseCalibration.swift in the copy; the test to mac4DSTEMTests/EllipseNoisyRingTests.swift.
   For RED runs quote the failing methods and assertion text (a filtered class-only rerun with the same flags as run-tests.sh's
   unit_tests is fine for the text). Count passed/failed/skipped by method name against `grep -rh 'func test' mac4DSTEMTests | wc -l`
   in that copy (HEAD 2236; skips are 4 on this machine today, 5 when the owner's recents hold an unmounted-volume entry).
4. Tool: `tools/ellipse-calibration-test/run.sh` (via heavy-build.sh is fine: no test host) in copies none, c, b2, s, cbs: record PASS/FAIL
   and the FAIL line (Q5 predicts FAIL on grains_12_one_annulus under b2, s and cbs; PASS under none and c).
5. Delete build products in your copies afterwards (tmp/DerivedData, .build); keep logs and sources.
Report $SP/lanes/G/report.md: predictions (before each run), the search, the test files, per gate: log, exit, passed/failed/skipped,
failing names + assertion text; the tool results; what you did not run. Final message <= 25 lines.
