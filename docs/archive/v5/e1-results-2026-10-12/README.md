# E1 pooled spectra: results (2026-10-12/13)

Built to `../e1-pooling-preregistration-2026-10-08.md` with the owner's cards E1–E6 = a (ADR 065). Implementer: Sonnet 5.5 lane;
Gate B refuter: Haiku 5.5, read-only (PASS WITH CHANGES, four blocking items, all taken in a second round).

**H1–H9 held.** H9 (a) on `References/demo-edx/AlMgSi_4D_EDX.dm4` (machine-local, `tools/demo-edx/run.sh`; the test skips without it):
each truth phase's pool equals `realised_total_eds_counts` as integers (`h9-report.txt`: Al 99 517 / 2 897 px, β″ 4 599 / 126, Q 983 / 25,
vacuum 6 / 24). H9 (b), reported, no bar: the β″ pool's Mg/Si net ratio 0.404 (Garwood 95 % Mg 419–504, Si 1074–1207); truth 0.406.
H7: the four `.txt` recordings were made on 0a1a8106 and again on 5b696589 (the true pre-E1 base), byte-identical (`recording-command.txt`).

**Mutations** (`mutations.txt`): the registration's list plus the refuter's additions (overlap weighting on the mirrored record, nx/ny swap on
a non-square bin, normalised counts, the H9 file test, the recording test, the cache fence, the half-coverage threshold) — each red.

**Amendment to the registration (refuter B4).** The registration says a spectrum pixel joins a label covering "more than 1/2" and that exact
ties join none. The inherited rule (`MaskTransport.labelling`, Core, not changed by E1) is: the largest overlap joins when it is AT LEAST 1/2
and no other class equals it; exact ties between classes join none. So a pixel half in group g and half unlabelled (`groupOf == -1`) joins g.
Under the identity — the only registration the app creates — coverage is 0 or 1, so the case cannot arise in the app today. Pinned by
`testAHalfCoveredPixelBesideNoClassJoinsTheClassAndATieJoinsNone`.

**Refuter B3, fixed:** a compute already past its cancel check could re-cache a forgotten pool's spectrum; cached pool spectra are now fenced
by the catalogue's generation (`testAComputePastItsCancelCheckCannotRecacheAForgottenPool`, red without the fence).

**Deviations (declared):** pools are masks summed lazily like a drawn region (`PoolBuilder.pools` is not called); the badge uses
`validation == "none"` on `SpectrumPool`; `Core/Spectroscopy/` untouched (SpectroKit boundary, ADR 064) — the 4D seam is
`Session/PoolCatalogue.swift`; the identity claim is tied to the cube it was stated for; the picker is sectioned only when pools or notes exist.
**Open, non-blocking:** with a cube but no registration the Phases section shows the registration sentence, not the Crystal Maps line;
`PoolCatalogue.isUnvalidated` repeats Core's predicate. **Unverified on screen.**

**2026-10-13, card P4 b:** the Quantify step now records its result (`result_at`, `result_unit`, `result_wt`, `validation=none`) so the
Results room can list it. The four recordings were regenerated with `TEST_RUNNER_E1_RECORD_DIR`: each gains exactly those four lines;
no existing line changed (diff checked line by line), so H7's "no existing number moves" still holds.
