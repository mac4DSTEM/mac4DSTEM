# Recovered review — physics, export and UI

Completed 2026-08-31 against `24c13d3` plus the existing working tree. Source/caller/guard review only; no builds, app launches, source mutations or commits.

All **24 initial findings** are retained: **13 confirmed, 11 narrowed**. Corrected severities: **9 high, 11 medium, 4 low**. No runtime reproduction is claimed. Machine-readable detail: `verified-physics-export.json`. Duplicates are explicit: restored metadata overlaps the completed AppState review; Q and R missing-unit scale bars each recur in UI/export.

The highest-priority supported defects are stale restored sampling/provenance after new publication, normalized DPC turns labeled radians, dropped parallax transpose input, global-origin-only ptychography preparation, fabricated reciprocal units, gamma-blind publication colorbar and ACOM region-selection export mixing products. The hexagonal IPF labels disagree with the crystal basis; the initial claim that those labels also appear in the burned caption was refuted.

Other narrowed narratives matter: live iDPC resolves equal row/column sampling, so its anisotropic example was false (restored anisotropic scan maps remain reachable); parallax global-fit switching is not exposed in UI; the square detector has a half-pixel overlay offset but the asserted 56% area error counted stroked boundary centers and is unsupported; non-iDPC provenance also gains domain/status keys; missing units cannot establish what the true omitted unit was.

The session audit covers **5 complete records (S6/S7/S8/S10/S13), 74 grouped claims**, in `audit-s6-s13.json`. Historic run/mutation/data numbers without original logs are marked unverified, never silently treated as false. Dated scientific registrations match 35/36/37/39. Definite record discrepancies:

- S7 names 9 SessionGates tests; landing source has 8.
- S10 says 13 added ReplayPlan tests; dated diff adds 16 (24 to40), and reduced-export is the third manifest-sourced runner, not second.
- S13 scores monotonic jitter MAD confirmed despite its own 0.4826→0.3084 decline. The separate >=3x criterion is satisfied.
- S13 says 2%-kept uncertainty is two orders below2px; Particle_1 at0.1px is only20x below.
- S13 §6 says four demo claims were corrected in §5, but those contradictory claims still remain there.
- S13 Aug29 'first gating run' conflicts with Aug28 registration plus Aug28 commit's claimed green run; actual first execution needs original logs.

S10 explicitly recorded a seam exception despite touching AppState. Later source/visual changes do not refute honest session-time limitations. Original review claims, including overstatements, remain identifiable by exact `originalTitle`.
