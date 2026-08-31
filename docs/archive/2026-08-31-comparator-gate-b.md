# The real-data comparator, its Gate B, and the two red harnesses behind it

**2026-08-31. History, not guidance.** The live findings and the open owner
decisions are in [`docs/open-items.md`](../open-items.md); this file holds the
evidence and the narrative so that file can stay short. Nothing here should be
cited as current state.

## What started it

`tools/run-tests.sh all` exited 1 at `real-data-acceptance`:
`FAIL: report count 8, expected 4`. `compare.py` asserted
`len(actual) == len(expected)` and then `zip`ped the two lists positionally, so
the gate was pinned to an exact directory listing — and a file sorting before a
pinned one could compare mismatched pairs.

Not a code regression. `git diff aeaeacc..HEAD` was empty across
`tools/real-data-acceptance/`, and `main.swift` drops a file from the report only
on `H5Error.noDatasetFound` or `H5Error.sessionSidecarOpened`; every other
failure calls `fail()` and aborts loudly. The data directory had grown to eight
readable cubes against four pinned.

**The two hypotheses, both still open.** Either the four large cubes (~8.3 GB)
were off the internal disk on 2026-08-28 — plausible, the machine was recorded
at ~4 GB free — and the gate broke when they returned; or the 2026-08-28
"zero FAIL lines" claim never covered this harness. The named discriminator is a
`report count` line in S19's retained `all` log, which is not in the repo. It was
never run, and the fix landed anyway, justified on the defect being reproducible
on the current tree rather than on the history being settled.

## The fix

Index both sides by the `file` key; match by name. Every pinned dataset must be
present or the comparator refuses, naming the missing files — that is the
disappearance guard the length assert was really buying. Extra unpinned datasets
are announced and allowed.

## Gate B — three refuters, ~20 distinct findings

All three independently confirmed the core: the disappearance guard holds inside
`compare.py`, duplicate names refuse rather than silently last-wins, no extra
entry can shadow or satisfy a pinned check, and the reordering defect is
genuinely fixed and genuinely tested. One put it: *"My findings are about check
strength and value-domain edges, not about the change's core logic."*

**What they refuted, all corrected in place rather than defended:**

- **The 15 s budget** (two refuters, independently). `main.swift` records
  `elapsedSeconds` but never gates on it, so the budget was only in `compare.py`
  and is now pinned-datasets-only. What the length assert really bought was a
  *forcing function*: a new dataset could not go green until a human pinned it.
- **`abs_tol=1e-3` exceeds the whole dynamic range of the real WS₂ virtual image
  (5.3e-4).** A regression halving that image's contrast passes, and also
  satisfies `main.swift`'s own `guard maximum > minimum`. Pre-existing. The
  framing that made it land: *a suite certifying 30/0 over it converts a latent
  hole into an endorsed one.*
- **The "byte-identical inputs" evidence was wrong.** The write-up hand-listed
  four paths; `run.sh` compiles 18 Swift files plus a glob over every `.metal` in
  `Shaders/` — 26 inputs — and three changed, including the unmentioned
  `Shaders/OriginMeasure.metal`. The conclusion survived on checked grounds
  (`measureOriginPSO` is lazy and never dispatched by this harness;
  `Calibration.swift` is compiled but unreferenced; `probeSize` is untouched by
  S13). Root cause: this harness never adopted `tools/lib/sources.manifest`.
- **Both replacement comments were false.** The `main.swift` comment named the
  wrong mechanism in *both* branches it described — with `expected.json` emptied
  the missing-dataset check is vacuous, and if the harness skipped everything it
  aborts before `compare.py` runs at all.
- **"8 of 9 mutations caught" was unciteable** — the mutation list existed
  nowhere a reader could check. An independent 13-mutant sweep found 12 killed,
  1 survivor.
- **The suite's own weaknesses**: neither `math.isclose` parameter was pinned
  (each subsumed the other; `rel_tol` on the probe radius survived a **255×**
  loosening); the fixture's `beta.h5` shape was `[8,8,16,16]`, symmetric in both
  the scan and detector pairs, so no transposition was detectable — the S8
  symmetric-constant lesson repeated; two of the five count arrays equalled their
  neighbours, so a field mix-up passed; and the `UNPINNED` announcement, the
  widening's only compensating promise, was untested.

## The guard whose status changed three times

`if not actual:` was documented as uncoverable; a refuter refuted that (a report
that is valid JSON but not a list — `null`, `0`, `false` — is falsy, and
`by_name` crashed on it otherwise); then the fix for that refuter's *other*
finding, the `by_name` type check, re-subsumed it. It is now redundant again for
a new reason, and carries its full history in the file rather than a fourth
claim. Two of three refuters had confirmed the original "uncoverable" claim —
the panel is what caught it.

## Breaking the test found a defect in the test

The first suite passed 28/28. Crippling the comparator nine ways showed it
**missed the most important mutation**: with the missing-dataset check deleted,
the comparator dies with a `KeyError` traceback and exit 1, and the suite scored
any non-zero exit as a pass. Green for the wrong reason, on the guard the change
claimed to preserve. A RED verdict now requires a clean refusal — non-zero exit,
a `FAIL:` line, no traceback. Two other "misses" in that sweep were the sweep's
own mutation strings failing to match (quote style), which looks identical to a
blind spot; the sweep now asserts each mutation applied.

The hardened suite also caught a bad case of its author's: a checksum drift of
+10,000 on a 9.45e9 value is *inside* `rel_tol`'s 18,900 window, so green was
correct.

## The second red harness, hidden behind the first

`package-test` asserted `LSMinimumSystemVersion = "14.0"`. Commit `aeaeacc`
(S19) is the only commit that raised `MACOSX_DEPLOYMENT_TARGET` 14.0 → 26.0, in
all six configurations; its diff touches `project.pbxproj` and nothing else, and
`package-test/run.sh` is byte-identical across it. After that commit the harness
must fail at line 34 — silently, since `set -euo pipefail` on a bare `test`
prints nothing.

**So S19's commit message — "run-tests.sh all was run end to end on the current
tree: exit 0, 40 harnesses, zero FAIL lines" — cannot describe the tree it
committed.** That message even records verifying `LSMinimumSystemVersion 26.0`
from the built product, the very check that breaks the harness.

It was invisible because `all` aborts at the first failing harness, and
`real-data-acceptance` came first. **A gate that stops at the first red cannot
tell you how many others are red.**

## Result

`run-tests.sh all` — exit 0, 42 started / 42 completed, unit 391 passed /
2 skipped / 0 failed, zero FAIL lines, zero exit-69 refusals, counted by grep
over the retained log. `package-test` passes for the first time since
2026-08-28. The comparator suite is 46 checks; 21 of 22 crippling mutations are
caught, and the 22nd is the documented subsumed guard.
