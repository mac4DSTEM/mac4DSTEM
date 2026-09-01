# The shortest credible path to a shipped v2

**Drafted 2026-09-01.** Purpose: get v2 into users' hands without shipping a
silently wrong number. Sequenced so `/pickup` can continue straight from here.
**This is a recommendation; the scope calls in step 0 are the owner's.**

## Step 0 — DECIDED by the owner, 2026-09-01 (full record: `open-items.md` §Owner decisions)

1. **Group A scope: all five remaining items ship FIXED**, plus the
   ride-alongs — and the **probe-radius defect joins as item 7** below.
2. **The claim: "hand a colleague the recipe" and "promote overnight" are
   DISCARDED from v2** — S19 restates §1. The clean-account run stays
   (owner, local second account); the colleague/second-machine test dies
   with the claim; the **bounded ~30-min promote run stays** (the replay
   feature ships regardless and the run closes its five Track B rows).
3. **Group B splits** (it was in neither of this plan's lists — surfaced
   2026-09-01): the **CIF pair joins v2** (`core-crystal-02`,
   `core-crystal-04`; one session, one fixture, seeded by
   `References/training_dataset/WS2.cif`); the sidecar/restore/DM4 trio
   goes to v2.x as documented limitations.

## Step 1 — Group A, the ones a real user will actually hit (~2–3 sessions remain)

Ordered by how badly each misleads. Each takes **Gate D first** (a controlled
reproduction), then Gate B — the discipline that on 2026-09-01 reproduced one
finding and refuted two others before they reached the docs.

| # | Item | Why first |
|---|---|---|
| 1 | ~~`core-analysis-physics-01` — **DPC angle stores turns, claims radians**~~ **RESOLVED 2026-09-01** | Gate D confirmed the 2π error; the radian fix, legacy migration, independent fixture and separate Gate B review all passed. [Record](archive/v2-session-records/dpc-angle-units.md). |
| 2 | **WS₂ reference-shell selection** (open item, not in the 39) | Silent ~2.26× mis-scale on basal specimens. **Already isolated**: Gold FCC agrees to 0.6% on the same code path, WS₂ is 18.4% off — the estimator is sound, the shell pick is not. |
| 3 | `app-appstate-01` + `support-export-01` — **restored provenance leaks onto fresh products** | **Reproduced at runtime.** Fix the on-screen half and check the export half in the same session. |
| 4 | `core-crystal-01` — **hexagonal IPF legend disagrees with its own colour map** | The legend explains the map wrongly; W4a just made WS₂ reachable. |
| 5 | `ui-02` + `ui-05` + `support-export-05` — **invented and mislabelled units** | Reproduce first: the honest branch was observed working. |
| 6 | **Readiness-row truncation** (found 2026-09-01) | Cuts the *actionable* half of caveats that are already implemented and correct. Cheap. |
| 7 | ~~**Probe radius over-measured**~~ — **DONE 2026-09-01: Gate D confirmed, fixed, Gate B ran (stand-with-corrections, all applied)** ([record](archive/v2-session-records/probe-radius.md)) | The recorded discriminator on real data at last: the shipped 14.1/19.1 px ARE `probeSize(maxDP)` to the digit; the causal proof is within-file nested sub-scans (16.07→16.50→19.07 px as the scan grows). Both call sites feed meanDP (DEVIATION; py4DSTEM's own origin path has the same weakness). Demo kernel 9.649 → 6.93 px (the refuter corrected this record's "drawn 4.5" claim). Scientific 42/42; unit 402/2/0 with the refuter's added pin on the caller-less resident variant. F1.49 queued; manual `.manual` entry unblocked, not built. |
| 8 | ~~**CIF pair** `core-crystal-02` + `core-crystal-04`~~ — **DONE 2026-09-01**: implemented + reproduced, **Gate B ran** (stand-with-corrections, all four applied — hardened 45-case harness, two more declaration tags, E2 residual recorded) ([record](archive/v2-session-records/cif-pair.md)) | Both reproduced at runtime first (MgO imported as CsCl; a truncated WS2 lost its sulfur silently). Fix: refuse non-P1-declared files without expanding operations, refuse loops cut mid-row. The refuter's sharpest find: a cut two-column symmetry loop floor-divided a centering op away and the wrong crystal passed `verifyFamily` — now gated. |

**Ride along, same sessions, near-free:** `ui-07` (Performance inspector still
says "GPU budget" — one word) and Group D's five green-but-worthless tests,
which are what would catch a regression in the above. **The two
owner-promoted UI changes are DONE 2026-09-01 (F1.50 queued; F1.51 scored
PARTLY — the colormap-submenu finding):** the
scan-position X/Y sliders are removed, and the DP/Result colormap pickers are
permanently visible in one compact Display row.

**Defer to v2.x:** Groups C, E, F, and Group B's non-CIF trio (documented
limitations — owner decision 2026-09-01). Cutting them shortens nothing —
they were never the blocking set.

## Step 2 — the clean account, ~20 minutes (Done criterion 4)

A second **macOS user account**, not another person or machine. Drive
**F1.46**: copy a cube plus its `.mac4dstem.h5` sidecar across, open it, follow
what the inspector tells you. Expect to hit the errno-1 refusal on purpose —
**the first remedy the app prints is one it then refuses**; the working one is
**Change…**. Score both halves.

*Why not skip it:* the only previous clean-account run caught three defects no
harness could, and `docs/development-process.md` §9 says a container reset is
not a substitute.

## Step 3 — one bounded unattended run, ~30 minutes (Done criterion 3)

Already narrowed from "overnight" by owner decision 2026-08-28. Use the local
**4.25 GB `036_STEM_SI…h5`**. Rehearse on a cropped view, promote at full
extent, keep the Mac awake, read the summary afterwards, and make **one
deliberate failure halt honestly**. Closes **F1.14, F1.15, F1.19, F1.22, F1.23**.

## Step 4 — finish Track B (~1 session, mostly assistant-drivable)

Currently **31 passed / 9 partly / 19 unverified / 1 blocked** (F1.47–F1.50
queued by the 2026-09-01 sessions; F1.51 and F1.52 PARTLY; **F1.53 is the
owner's consolidated S22 final-playthrough row**). Assistant can
drive **F1.35, F1.38's last gap, F1.8, F1.21, F1.27, F1.30, F1.31, F1.43,
F1.45's In-plane mode**. Owner keeps the judgement rows (**F1.37, F1.40's
wording, F1.42**) and the standing pass **§A–§F**, which Done criterion 13 names
explicitly and which free-form driving cannot discharge.

## Step 5 — S20, the endgame

Version decided on §5's evidence · security review · sign · notarize · staple ·
clean-account launch · tag. **Restate README/CHANGELOG to what a reader can
reproduce**, including whichever §1 sentences step 0 narrowed.

---

## What this deliberately does not do

- **No fresh whole-codebase review.** One ran 2026-08-31 at `24c13d3`, which
  includes W4a and W4b, and **no app code has changed since**. Re-running it
  re-derives the same 75 findings.
- ~~**No S22.**~~ **OVERTURNED by the owner, 2026-09-01 evening.** His
  playthrough verdict ("this is not a good v2") blocks his own Track B
  testing, so S22 moved ahead of the remaining fix queue — design phase first
  (assistant-only), then bounded slices; the UI-pair work is held uncommitted
  and the owner's sittings pause until S22 lands. Decision 7 in
  [`docs/open-items.md`](open-items.md) §Owner decisions.
- **No Groups C/E/F.** v2.x.

## Standing repo-hygiene debt

~~The three-file kickoff tax is **3689 lines**~~ — **the untangle ran
2026-09-01**: the 661-line Track B thread moved verbatim to
[`docs/archive/2026-08-18-trackb-036-and-followups.md`](archive/2026-08-18-trackb-036-and-followups.md),
its live residuals compacted to ~150 lines (two stale entries corrected in
passing: the WS₂ foreign sidecar was re-staged 2026-08-28, and #11 was closed
by W4a), and the S13 origin tombstone trimmed. The tax is now **3347 lines**
(`CLAUDE.md` 349 + `open-items.md` 1994 + `v2-release.md` 1004, measured at
the probe-radius closeout — each session's §9 entry costs what its
open-items compressions save). Rule that
keeps it from returning: **findings ≤20 lines, narrative to a dated archive,
`wc -l` checked at every closeout.** The structural fix stays the one-time v3
migration ([`docs/v3-development-process.md`](v3-development-process.md)),
not a perpetual tidy.
