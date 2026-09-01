# Independent Gate B — ACOM convention fixture

**Disposition: APPROVE for the stated CPU projection/returned-orientation-matrix regression scope.** No required changes found. This is approval of the fixture and its demonstrated discriminators, not a scientific release or blanket ACOM-accuracy approval. Review completed 2026-08-31.

I was not the fixture author. I read the pre-registration, main.swift, runner, reference generator, frozen data, manifest wiring, production projector/matcher/Euler implementation and vendored diffraction conventions. All builds and mutations ran in a disposable copy under `/tmp/mac4dstem-review-recovery-20260831/independent-acom-mutations/source-copy`; no shared source mutations were made.

## Independent control and new mutations

Control completed exit0: Au144 trials, matrix median1.249998°,131 in-plane errors<20°; WS2240 trials, median0.779939°,240<20°; frozen external40 trials, median2.056160°,25<5°.

All five mutations below were selected independently from the author's six and actually compiled/executed. Every mutant returned exit1 at its predicted semantic assertion; no build or environment failure was counted as a successful negative control.

| Mutation | Specific evidence | Disposition |
|---|---|---|
| Mirror azimuth only when generating a hexagonal plan | Au control unchanged; WS2 matrix median62.036379°,16/240 in-plane near; `FAIL: WS2 independent matrix orientation` | Killed |
| Add π only to reported inPlaneAngle, leaving returned Euler matrix untouched | Au matrix median remains1.249998°; near-angle count falls131→13; `FAIL: Au full-angle recovery, not modulo pi` | Killed |
| Replace fixed external lab-frame transform with identity | Both analytic controls unchanged; external median35.504338°,0/40 near; `FAIL: frozen external orientation convention` | Killed |
| Empty one frozen pattern while retaining40 cases | Both analytic controls pass; `FAIL: nonempty external pattern` | Killed |
| Return NaN phi1 in EulerAngles | `FAIL: orientation must be a finite proper rotation` before statistics | Killed |

Logs, exact mutation before/after strings, exit codes and elapsed times are retained in `independent-acom-mutations/results.json` and its six `.log` siblings. The scratch source was restored after every mutation.

## Oracle and provenance attack

- Analytic peak positions use a local orthonormal right-handed basis and direct dot products. They do not call production project/detectorBasis. Sharing reflection intensities and sampled zone axes remains explicit and prevents claiming independent structure-factor or bank-sampling validation. The hex-only mutation demonstrates that the cubic/frozen anchors are not hiding an untested hexagonal projector.
- Physical orientation comparison uses symmetry on the left for lab-axes-in-crystal columns. Independent proper signed permutations give24 cubic operators; six axial rotations plus six basal π rotations give12 proper D6 operators. The trace-angle expression is valid for relative proper rotations. Properness is checked before traces are clamped, so NaN/improper matrices cannot pass through an acos clamp. The generic37.2° oracle control is discriminating for both groups.
- The fixed external frame matrix is not fitted per result: generator x uses py4DSTEM qy and generator y uses qx. Reversing lab z keeps that axis swap proper and matches the source excitation-error convention (py4DSTEM k0=[0,0,-1/lambda], app downstream positive). The lab-frame mutant demonstrably fails. No arbitrary mirror is absorbed by the cubic symmetry oracle.
- All three provenance hashes exactly match recovered `/tmp/acomprobe/{py4-input.json,py4-truth.npy,py4gen.py}`. Tracked generate_reference.py is byte-identical to py4gen.py. The parsed input object is exactly equal. I decoded the NumPy binary directly and compared all360 scalars of40 original3x3 matrices against reference.json: exact equality, maxdifference0. These checks are retained in `independent-acom-mutations/provenance-check.json`.
- The pinned0.14.17 attribution remains the recovered generator-environment attribution, not a new regeneration or parity claim against current vendored source. The fixture README states that distinction correctly. Hashes attest preservation of recovered artifacts, not independent certification of the package provenance.

## Limits kept explicit

This fixture does not validate GPU kernels, actual scientific exports, every raw Euler-angle convention, structure factors, crystallographic sampling quality, invalid user-input refusal policy, scores/reliability, or real acquisition accuracy. The existing acom-orientation-test separately compares raw Euler values to reference Euler values; the new matrix test must not replace it. Normal gate execution constructs the CPU matcher and does not instantiate MetalEngine.shared. The runner does not apply app-target actor-isolation flags, so this is not an isolation/build-target substitute.

Empty/failed-match and nonfinite-output concerns are covered as fixture integrity: every expected trial must execute, valid template indices are required, empty arrays fail, and nonfinite/improper matrices fail. It is not a test of what the app should do on arbitrary malformed/no-signal acquisition data.

The median/count thresholds intentionally tolerate real outliers (15/40 external cases are not within5° in this control). They reject demonstrated systematic convention defects; they do not bound every returned orientation. Do not advertise them as per-pattern scientific accuracy. No production science or calibration thresholds changed.
