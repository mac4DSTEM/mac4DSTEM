# Independent advisor's read of the 21 cards — 2026-09-30 (read-only; repo at 2f5d90e2)

Judged against ADR 049 (a plateau, not a construction site) and the owner's values: pure macOS, simple, reliable,
intuitive, scientifically correct, no filler. "Polish resolves?" = will the S4–S6 room sessions already queued close it
without a decision. Effort: hours / one session / several. Records cited by path under `docs/`.

## The cards

**1. push2 — Fire the cloud review.** *Premise stale:* `HEAD == origin/main` at 2f5d90e2; nothing is unpushed. The card
is now "start the review". Polish: NO (only he can start it). Unblocks: the whole sitting — ADR 049 defines it as
"findings + cards together". Options: fire today (minutes, no risk) · fire after the sitting (then there are two sittings).
Recommend: fire today, do the one-word cards today, hold the rest for the findings. Never: no last intake; the sitting
happens without it.

**2. ptycho-finish — Finish or remove ptychography.** Problem: the app's ptychography assumes a perfectly focused beam,
but ptychography data are taken with a deliberately defocused one, so on real ptychography data its image is unrelated
to the right one — while the parallax tool beside it already measures that defocus to 0.007 % of py4DSTEM
(`archive/v4/parallax-ptycho-graphene-2026-09-30/record.md`). Polish: NO; exit 4 hangs on it. Options: (a) finish
minimal — a defocus phase on the aperture (`Core/Analysis/PtychographyPreparation.swift:242–262` builds a flat aperture;
the phase term is ~20 lines), one numeric field seeded from the parallax C1, **remove** the difference-map variant
(diverges on the reference cube, undiagnosed): one Gate B session, reference already recorded; risk low, simplicity up.
(b) finish + diagnose DM: + one Gate D of unknown depth. (c) remove ptychography, keep parallax: ~1 050 lines out, one
session, no risk — he already chose keep (2f5d90e2). (d) leave badged: drop, against ADR 049. *Missed by the card:*
parallax inherits two recorded disagreements (edge vignette 0.36 full-frame; the (2,1) higher-order terms ≈ 0 vs ≈ 600 Å)
— label the higher-order fit unvalidated or open-items it; silence is not an option under exit 3. Recommend: (a), with
DM removed now, not "fixed or dropped later" — a plateau does not ship a solver that diverges on its own reference.
Honest note: his precipitate work will never acquire ptychography data; keep is for the app's completeness, and (c) is
the leanest answer if he wants zero reconstruction sessions. Never: half-built ships; the badge understates.

**3. train-drive — Train again with the File probe.** Problem: Train Model… on the bullseye cube judged 0 of 82 because
the default disk template is sized for a solid beam, not a ring; choosing "File probe" as the template source is the
70-second workaround (Export Labels… first — the card's trap is real). Polish: DEPENDS on B-s21 for the default path.
Options: run it now · leave. Recommend: agree, run it — it is also the test of the session's diagnosis ("the kernel is
the blocker" is asserted, not yet shown; if File probe still judges 0/82 the cause is elsewhere). A *decline* is a valid
finish for the C5 lane (ADR 049 says "driven", not "offers a model"); do not chase recall in v4.1. Never: the lane reads
driven-but-broken; exit 4 is arguable.

**4. unfiltered — His "unfiltered" bin-4 cubes are hot-pixel filtered.** Problem: before he ever opened them, 15 detector
pixels — the direct beam's centre and several Bragg-spot centres — were replaced by a neighbourhood median in every
pattern (`archive/v4/parity-28gb-2026-09-30.md`); positions are untouched, intensities at those pixels are not. Polish:
NO — his data, not the app. Options: re-preprocess from the raw (the app bins raw itself; the 28 GB read is proven; hours
of compute, no app risk) · leave + methods note. *Add:* first a one-line check — does any number he reports read those
pixels? A virtual bright-field image sums the direct beam, whose peak pixel is replaced in every pattern; precipitate
density (positions + phase) does not. Recommend: agree — re-preprocess anything intensity-based, and nothing else.
Never: files stay; the record names the pixels.

**5. D1a — Phase-match tolerance.** Problem: how far a detected spot may sit from a phase's predicted spot and still
count; the shipped rule sits inside all four datasets' acceptable bands (`archive/v4/phase-tolerance-results-2026-09-29.md`).
Polish: YES, nothing to do. Options: keep (0 h) · new rule: drop (Gate D + re-pin for no measured gain). Recommend: keep;
the card's own trap (1 px passes T4 by two specks) is the right reason not to touch it. One word. Never: R0 stays.

**6. J-dm4 — Read one Si-SiGe pattern's width/height in GMS.** Problem: for one kind of Digital Micrograph file the app
may read every diffraction pattern with rows and columns swapped; strain axes and the R–Q sign would be silently wrong on
the strain reference dataset. *The prior is not "probably fine":* the reader's own comment (`Core/Data/DM4Reader.swift:185–195`)
takes Rx fastest for the scan pair but Qy fastest for the detector pair — an inconsistent model. Polish: NO — two
minutes at GMS, then one session (ncempy checksum as the fixture; ncempy is what py4DSTEM's `read_dm` uses, so "may
share the assumption" understates it: it is the de-facto convention). Possibly related, to test not assume: open-items'
"#18 campaign can't reproduce the app's Si_SiGe strain". Recommend: both, agree — the cheapest science item on the board.
Never: a possibly transposed strain map ships (exit 3).

**7. B-s21 — Take the ring-probe kernel patch.** Problem: on a ring-shaped (bullseye) beam the default disk finder sizes
its template from the ring's inner shoulder and finds almost nothing; a measured rule sizes it from the outer edge, on
that probe class only (`archive/v4/s21-refuter-2026-09-30.md`). Polish: NO; unblocks train-drive at defaults. Options:
take with the five fixes (one night + Gate B + drive + a re-pin; risk: a default moves on one probe class with n = 1
truth dataset and a bar of 0.5 chosen on 11 files) · ship the quantity + a status hint ("ring-structured probe: outer
edge 11 px — use a File probe or set the radius"; hours, GREEN, no default moves) · re-register: drop (waits forever).
Recommend: **partial disagreement.** For the plateau the hint-plus-quantity is the honest fit (his own probes are compact;
File probe already gives 58 % recall; the threshold rule). Take the patch only if he wants py4DSTEM's public tutorial
cube to work at defaults in v4.1 — a fair wish; then it is the ONE detection-default change of v4.1 and goes before the
C5 drive. Never: 0.12 recall on bullseye at defaults, a documented limit.

**8. F-thronsen — The licence email.** *Premise partly wrong:* the shipped truth map derives from Zenodo data under
CC BY 4.0 (`NOTICE:107–113`) and needs no code permission; the letter matters only for a code port, and none exists nor is
planned under the freeze. Polish: NO, and off the v4.1 path. Options: email for an upstream LICENSE (minutes, good
practice) · nothing until a port. Drop "personal OK only". Recommend: send it when convenient; it gates nothing — take it
off the exit list. Disagree with "this week" as urgency. Never: nothing changes; no port lands (none is planned).

**9. A4-qshell — Q calibration can pick the wrong ring.** Problem: "calibrate the scale from a known crystal" assumes
the innermost visible ring is the crystal's innermost allowed reflection; on Al viewed along [001] — **his matrix, his
usual zone axis** — the {111} ring is absent, so the tool scales {200} as if it were {111}, reads Q 13.5 % low, and still
shows a green "Measured" (`archive/v4/s20-refuter-2026-09-30.md` §4). The app already prints the disagreeing ratio
(Prepare's "Q shell check" row, `UI/PrepareSettings.swift:303`); only the badge lies. Polish: DEPENDS — the label is polish
(hours: badge colour/wording from an existing quantity); the fix is a science session. Same root as D-s20. Options: label
+ app-path check on the demo cube **and on his raw Al-Mg-Si cube** (hours) · shell assignment by ratio sequence (one Gate D;
"threshold-free" is overstated — nearest-ratio has implicit boundaries — but far sturdier than "innermost") · neither: drop.
Recommend: label now (agree) and **promote this card**: it is the one nearest his own results. Measure first: if his own
cube's shell check reads ≈ 1.41, the assignment fix is the one science Gate D worth funding in v4.1. Never: green Q on
cubes where it is 13.5 % low.

**10. A1-drag — Aperture drag warns, no dialog.** Problem: dragging the virtual-detector circle's centre used to silently
overwrite the fitted beam centre; now the Prepare row turns orange with Restore; the file's own recorded centre is still
lost. Polish: YES (small follow-up). Options: keep · keep + park the file's mean (hours, no surface) · dialog/refuse: drop.
Recommend: agree — keep + park. Never: the file's mean is discarded on a centre drag.

**11. A6-frozen — "In memory" wording in a frozen file.** Problem: an inspector title claimed restored values were
"computed this session"; fixed to "In memory" with per-row origins inside a picture-approved file; one row still shows an
empty circle where Prepare says "from session". Polish: YES. Options: ratify · ratify + one-boolean fix (hours + a look) ·
revert: drop. Recommend: agree, ratify with the fix — and write the precedent into the rule (one line in `CLAUDE.md`:
wording that corrects a false claim may change; structure and width may not) so no session asks again. Never: stays.

**12. A7-s15 — R–Q sign on old exports.** Problem: datacubes this app exported before 2026-09-28 do not say which sign
convention their rotation uses; the app labels the row instead of guessing; one reference file (`Si-SiGe_calibrated.h5`)
is known to open with the wrong sign (`archive/v4/s15-rq-legacy-exports-2026-09-30.md`). Polish: YES for the rule; the file
is his hand. Options: keep + re-export (1 min) · auto-convert: drop (refuted). *Add, a rule the reader CAN know:* if the
export's derivation names a source that carries no rotation (a DM4), the rotation was measured in the app → app sign;
mechanical, testable, small Gate D. Recommend: v4.1 = keep + re-export (agree); the derivation rule to After v4.1 unless he
has more such files. Never: the one file keeps a flipped sign.

**13. H-polish — Anything to overrule?** *Premise stale:* the two "need your picture" controls already landed and were
driven (97af1b20 "a way back from Show Objects", 7862138d "a visible Re-measure"). What remains is open-items' S4
proposals (lineage order, legend counts, crop-warning axis order, snake_case provenance keys, the "px" wrap, the drag
sentence) and **one real defect: the bin-2 aperture ring off-centre** (drive 3, shot 52). Polish: YES. Options: look at
the two landed controls and ratify or overrule (minutes) · one room session for the proposals (no new surface) · leave.
Recommend: ratify by looking; the proposals are one session; the bin-2 defect must be reproduced before v4.1 (exit 3).
Never: it stays.

**14. R-toggle — Keep the cube in memory?** Problem: the app always streams from disk; holding the cube in memory makes
every repeated virtual image 20–70× faster on his Mac (84 ms vs 6 s on his 28 GB cube;
`archive/v4/residency-characterisation-2026-09-30/summary.md`) but nothing in the UI can ask for it — the path exists
(`App/AppState+Open.swift:783`: "nothing in the UI requests .resident yet"), the Release cube button is unreachable.
Polish: DEPENDS on exit 5 — only his own analysis tells whether 6 s per aperture move hurts. Options: mock a per-open
toggle showing "28.6 of 64 GB" (one session incl. drive; risk: swap at ≥ 0.7 of RAM measured once, no refuter — the toggle
must show the ratio and warn above ≈ 0.5) · leave streaming and delete the dead button + `fitsResident` (hours) · measure
more: drop for v4.1. Recommend: **disagree with mocking now** — it is new surface the same night the list was frozen. It is
the one freeze exception worth his sentence, decided after his first streamed analysis in the RC build; if he never moves
an aperture twice, delete the dead code. Never: streams; dead button stays.

**15. D-s20 — The true-Q check before judging F.** Problem: orientation templates sometimes fail to recognise themselves
between grid steps; a candidate fix cures most of it but seemed to break one known grain on the demo cube — a comparison
made at a wrong scale (same wrong-ring mechanism as card 9), so nobody knows. Polish: NO. Options: true-Q rerun (minutes,
GREEN) · park F unchecked: drop · adopt the failed-gate rule (one word). *Add:* whatever it says about F, the rerun tells
whether the demo cube is truth-bearing for ACOM at all (grain B 6.50° in both trees) — that matters for every harness that
leans on the demo cube. Recommend: agree, run + adopt the rule; but say now that F is After v4.1 regardless (4.5× CPU on
the default backend, unit classes not run — an improvement, not an exit-3 defect). Never: F parked; the demo cube's
standing unknown.

**16. C-s14d — Build the origin window check.** Problem: on ring-shaped beams the beam-centre refinement drifts along the
ring by ~4 px; no single fix works on all data, but a cheap self-check flags exactly the affected scans
(`archive/v4/s14d-refuter-2026-09-30.md` §4). Polish: DEPENDS — Core quantity now (hours, GREEN); its on-screen line waits
for the drive row. Options: build the quantity · build nothing · gate on it: After v4.1 (a verdict change). Recommend:
agree — build it; it turns a silent 4 px error into a number and touches no verdict. Same cube as cards 3 and 7: if he
never uses ringed probes, quantity-in-the-log + a named limit is the v4.1 answer. Never: silent.

**17. A2-fitanyway — The "Fit anyway" mark after reopen.** Problem: an ellipse he chose to fit on sparse data lost its
warning after save-and-reopen; the mark is now recovered from the session's own history, no file-format change. Polish:
YES (a drive empties the row). Options: keep · schema bump: drop. Recommend: keep. One word. Never: stands after a drive.

**18. A3-library — Built-in crystal library kept.** Problem: the plan wanted the eight built-in crystals deleted; they
feed the live Al-Mg-Si preset. Polish: YES. Options: keep · delete: drop. *Amend:* do the one-line resolver ordering fix in
v4.1 — an imported `Al.cif` silently shadowed by the built-in of the same stem is a user trap, not a someday. Recommend:
keep + the ordering fix. Never: kept; shadowing stays.

**19. A5-scientific — The real-data gate fails without data.** Problem: the suite used to pass silently when the
reference data were missing; now it fails loudly, and an outsider without `References/` sees red unless they set a
variable. Polish: YES. Options: keep · skip-with-warning: drop. Recommend: keep; make sure the red line tells the outsider
what to set. One word. Never: stands.

**20. G-schema5 — v1.0.0 session disks.** Problem: sessions saved by v1.0.0 restore their calibration but not their
detected disks; those are re-detected with today's detector in seconds. Polish: YES. Options: keep the refusal · relax (one
line; restores disks found with August's detector defaults). Recommend: keep — a stale-science restore is worse than 4 s.
One word: does he own any v1.0.0 session he needs? Never: refusal.

**21. K-earlier — Three earlier delegated decisions.** Problem: Core compiled optimised even in Debug; the session
history record v2; training on Apple's MPSGraph rather than bundling MLX. Polish: YES. Options: keep all · name one.
Recommend: keep all three — each is the lean, pure-macOS choice. One word. Never: stand.

## Synthesis

**Order of the sitting.** (1) Fire the cloud review today — nothing is unpushed; the sitting is defined as findings +
cards, so the cards that can wait should. (2) Today, one word each: D1a keep · A2 keep · A3 keep + ordering fix · A5 keep ·
G keep · K keep · A1 keep + park · A6 ratify + fix · A7 keep + re-export · D-s20 "run it, adopt the rule" · F-thronsen
off the list. (3) Two minutes each with an instrument: J-dm4 (GMS width/height) and train-drive (File probe run).
(4) A4-qshell: the label now, and read the shell check on his own raw Al-Mg-Si cube before deciding the fix. (5) ptycho:
finish minimal with DM removed, or remove. (6) B-s21: hint-plus-quantity, or the patch as the one default change.
(7) C-s14d quantity, H-polish room session + the bin-2 aperture Gate D. (8) After his first RC analysis: R-toggle.

**Need a measurement or a look first:** A4 (his cube's shell ratio), R-toggle (his own streamed analysis), unfiltered
(does he report intensities), H-polish (see the two landed controls), train-drive (the 70 s run is the diagnosis).

**Really the same decision:** A4-qshell + D-s20 (the demo cube's Q read from the wrong ring; also decides whether the
demo cube is truth-bearing) · B-s21 + train-drive + C-s14d (the bullseye ring: does v4.1 support ringed probes at
defaults, or name them a limit?) · ptycho-finish + parallax's two residuals (one "kept" verdict, one label).

**The three that shape v4.1:** ptycho (exit 4: the last half-built lane); B-s21 (whether v4.1 has any detection-default
change, and with it a Gate B night); A4-qshell (the only card that can move a number in *his* Al [001] science — the
label is mandatory, the fix is the one science session worth funding). R-toggle is the single freeze exception worth
a sentence, and only after exit 5.

**Premises found wrong or stale in the records:** push2 (HEAD == origin/main; already pushed); H-polish (both "new
surface" controls landed 97af1b20 / 7862138d and were driven); F-thronsen (the truth map is CC BY 4.0 data, not code —
nothing shipped depends on the verbal permission); J-dm4 is understated, not overstated (the reader's own model is
internally inconsistent, so the check is not a formality); A4's "threshold-free" fix is a nearest-ratio classifier.
