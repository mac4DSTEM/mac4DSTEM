# The shortest credible path to a shipped v2

**Drafted 2026-09-01.** Purpose: get v2 into users' hands without shipping a
silently wrong number. Sequenced so `/pickup` can continue straight from here.
**This is a recommendation; the scope calls in step 0 are the owner's.**

## Step 0 — two decisions, five minutes, and everything else depends on them

1. **Group A scope.** [`docs/v2-triage-2026-09-01.md`](v2-triage-2026-09-01.md):
   do all nine Group A items ship *fixed*, or do some ship as **documented
   limitations** in the README? Fixing all nine is ~4–5 sessions; documenting
   the presentation-only ones is ~1.
2. **The claim.** §1 promises "Hand a colleague the recipe" and "Promote
   overnight". If steps 2–3 below are not run, **those two sentences must
   change** — S19 already owns restating them. Narrowing a claim is honest;
   leaving it unverified is not.

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

**Ride along, same sessions, near-free:** `ui-07` (Performance inspector still
says "GPU budget" — one word) and Group D's five green-but-worthless tests,
which are what would catch a regression in the above.

**Defer to v2.x:** Groups C, E, F. Cutting them shortens nothing — they were
never the blocking set.

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

Currently **31 passed / 7 partly / 15 unverified / 1 blocked** (F1.47 was added
for the DPC angle-unit repair). Assistant can
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
- **No S22.** The UX pass now has real evidence, but it is polish; it belongs
  after users exist, not before.
- **No Groups C/E/F.** v2.x.

## Standing repo-hygiene debt

The three-file kickoff tax is **3689 lines** (M1 got it to 1901). The single
biggest win left is the **661-line Track B pass of 2026-08-18** still in the live
`open-items.md`, threaded with live residuals — a focused ~30-minute untangle
that would cut ~20%. Rule that keeps it from returning: **findings ≤20 lines,
narrative to a dated archive, `wc -l` checked at every closeout.**
