# 050 — The owner's sitting of 2026-09-30: twenty-one answers, and what v4.1 now is

Dates: 2026-09-30 (night)

Status: **accepted** (owner, by the decision sheet — each card answered with its option; his notes verbatim below).

The sheet (a page with each problem in plain words, the options with effort and risk, a recommendation and an
independent second opinion; the owner picks and pastes the answers) is the format he wants kept for every future
decision: "i liked the format of answering questions with context". The advisor's read is archived with the session
records; the cards themselves were the Board's.

## What changes in ADR 049

The freeze on **new themes** stands (parity themes 2–7, EDX, live acquisition stay out). Inside the shipped features
the bar is raised: **v4.1 means parity with py4DSTEM for what the app already ships**, and four half-built pieces are
finished rather than removed or badged:

1. **Ptychography — finish both methods, correctly, against py4DSTEM with a ground truth** ("our goal is to have feature
   parity with py4DSTEM, this is very important for the product … deliver both, correct, compare with py4dstem, figure
   out a way to get a ground truth"). Not the recommendation (finish minimal, drop the difference map).
2. **Training — a useful feature, a priority** ("this feature has to be good, we have a lot more computation power and
   we have the ANE, lets turn this into a useful feature for users").
3. **Preprocessing of raw data in the app is part of v4.1.0** — load the raw cube (DM4), calibrate, crop / bin / stride,
   save an `.h5` the app opens directly; oriented on py4DSTEM's own preprocessing; its own entry and sheet like "Open
   with Options". (Much of it exists as Preprocess & Export DataCube — calibration readiness, real-space crop, Q binning,
   py4DSTEM EMD — and has never been driven on his raw data; stride and a named hot-pixel filter are missing.)
4. **Keep the cube in memory — the one new control of v4.1** ("speed is a big plus, we claim to have live processing …
   we implement this and explore new possibilities beyond v4.1"). Mock first, then build and drive.

## The twenty-one answers

| Card | Answer | Where it goes |
|---|---|---|
| Start the cloud review | now | Owner fires it (brief `archive/v4/polish-and-review-session-plan.md`). |
| Phase-match tolerance | keep R0 | Closed. |
| Aperture drag | keep, and park the file's recorded centre too | Polish room (Prepare). |
| "In memory" wording (frozen file) | ratify, allow the empty-circle predicate fix | Polish room; CLAUDE.md gains the precedent: wording that corrects a false claim may change in a frozen file, structure and width may not. |
| R–Q sign on old exports | keep label-only; owner re-exports Si-SiGe once | Owner. |
| "Fit anyway" from lineage | keep | Closed (drive empties the row). |
| Built-in crystal library | keep, fix the name-shadowing order — "i may change this later, i am not happy with the bloat it causes for no reason" | Polish room; the library's size is a candidate for the lean audit after v4.1. |
| Real-data gate fails closed | keep | Closed; the red line names the variable. |
| v1.0.0 session disks | keep the refusal | Closed. |
| Core `-O`, ADR 047, ADR 048 | keep all three | Closed. |
| Candidate F / true-Q check | run it; adopt "a failed reproduction closes an item" | Science lane (with the Q-shell check). Rule added to CLAUDE.md. |
| Thronsen licence email | nothing until a port — "we compare our approach to theirs but this is nothing that touches a licence. remove the Thronsen licence issue from the repo" | ADR 042's owed action closed: no code is ported or planned; the truth map is CC BY 4.0 data, attributed in NOTICE (attribution stays). |
| Si-SiGe.dm4 width × height in GMS | leave it | Recorded as a named limit of the DM4 reader (scan-fastest files: the detector pair's order is unverified against GMS); not on the v4.1 path. |
| Train again with File probe | run it — "this feature has to be good … lets turn this into a useful feature for users, this is a priority" | Owner's run now; the training lane below. |
| "Unfiltered" cubes are filtered | first check whether any reported number reads those pixels — and preprocessing of raw data joins v4.1.0 (above) | Owner's check; the preprocessing lane. |
| Ptychography | finish, and diagnose the difference map (above) | The reconstruction lane. |
| Ring-shaped beams (S21) | take the patch with the five fixes — "think about the following … py4DSTEM does it, no? figure out why and how and we fix this, no fancy solutions … without compromising the detection for normal probes" | The training lane opens with that question: py4DSTEM's kernel is the measured probe image itself, not a synthetic disk sized by a radius estimate; the app has that source (File probe / vacuum scan) but does not default to it. Measure, then decide patch vs default. |
| Q calibration picks the wrong ring | badge "unchecked" when the ratio disagrees; check the app path on the demo cube and his raw Al–Mg–Si cube | Science lane (hours), then the ring-assignment fix if his cube reads ≈ 1.41. |
| Polish list from the drives | ratify the two landed controls by looking; one room session; the bin-2 aperture defect reproduced first | Polish room. |
| Beam-centre self-check | build the number, no verdict change | Training/ring lane (hours). |
| Keep the cube in memory | mock the per-open toggle (above) | The one new control; after the mock. |

## Why

The owner is the user: "i need to do some actual scientific work after that with it". His answers trade a smaller
v4.1 for one that does what py4DSTEM does on his data, in his app, with the hardware he now has. The freeze on new
themes keeps it a plateau; the four finishes are the shipped features' own gaps.
