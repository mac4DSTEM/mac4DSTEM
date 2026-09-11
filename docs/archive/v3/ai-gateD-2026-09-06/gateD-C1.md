# Gate D — C1: `symmetricEigenTop` returns one subspace iteration, not converged eigenpairs

Date: 2026-09-06. Branch `ml/disk-detector`, HEAD 65fb084.
Trigger: **a change that can move a scientific number** (the PCA basis, the
explained-variance numbers, and every k-means coordinate derived from them).
The second trigger — "the cause of a defect is not yet established" — does
**not** apply: the Gate B refuter established the mechanism experimentally
before this session opened (`gateB/D1-pca-convergence.swift.txt`,
`gateB/one_iteration.py`, `gateB/subspace_replica.py`). This document
re-states the diagnosis in my own words against the primary evidence, states
the refuting observation, and pre-registers the discriminating test.

## 1. The diagnosis

`mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:615-633`:

```swift
615:        var previousValues = [Double](repeating: .infinity, count: k)
616:        for _ in 0..<200 {
...
627:            var maxDelta = 0.0
628:            for c in 0..<k {
629:                let denom = max(abs(previousValues[c]), 1e-12)
630:                maxDelta = max(maxDelta, abs(values[c] - previousValues[c]) / denom)
631:            }
632:            previousValues = values
633:            if maxDelta < 1e-9 { break }
```

On pass 1 every `previousValues[c]` is `.infinity`, so

- `denom = max(abs(.infinity), 1e-12) = .infinity`
- `abs(values[c] - .infinity) / .infinity = .infinity / .infinity = NaN`
- `Swift.max(0.0, .nan) == 0.0` — IEEE `maxNum` semantics, the trap this
  repo already recorded on 2026-09-02 (`memory: fft-session-handoff`,
  `max(0,.nan)==0`).

`maxDelta` is therefore exactly `0.0` on pass 1, `0.0 < 1e-9` is true, and
the loop **always breaks after a single subspace iteration**. The
Rayleigh-Ritz step that follows then diagonalises the Ritz matrix of a
subspace that is one power step away from a random start. Its output is
still a *consistent* set of Ritz pairs (values descending, vectors
orthonormal), which is why the four existing `DiffractionEmbeddingTests`
pass: the top one or two directions of a strongly rank-2 covariance converge
in a single power step, and the suite only ever asserts an aggregate
`explainedVariance.prefix(3).sum() > 0.8`.

Everything past the dominant directions is not a principal axis. On the
three-family fixture the refuter measured the tail 20–36 % low against
`np.linalg.eigh` (`gateB/subspace_replica.py`, `gateB/one_iteration.py`); the
numpy replica reproduces Swift's reported fractions at **1** iteration and
matches `eigh` exactly at 200.

Consequences that reach the user: `Result.basis` rows 2…k−1 are arbitrary
directions in a barely-rotated random subspace; `Result.explainedVariance`
under-reports those components; `Result.coordinates` beyond the first two
components, and therefore the k-means grouping in every run configured with
more than ~2 components, are computed in that wrong basis.

## 2. The observation that would refute it

If the diagnosis were wrong — if the loop really did iterate to convergence
and the tail values were genuine eigenvalues — then for **any** symmetric
matrix, every returned `(v, λ)` would satisfy `C v = λ v` to round-off. In
particular, on a matrix whose eigenvalues are *known by construction* and are
all well separated (so no eigenvalue is degenerate and no subspace ambiguity
can excuse a mismatch), the returned λ would equal the planted ones and each
returned vector would be an eigenvector of the planted matrix.

Conversely, if the loop stops after one power step, a matrix with a *slowly
decaying, well-separated* spectrum must expose it: one power step cannot
separate eigenvalues whose ratios are close to 1, so the returned pairs will
have large residuals `‖C v − λ v‖` even though they remain mutually
orthonormal and their Ritz values remain descending.

This discriminates cleanly against the alternative hypotheses I considered
and reject:

- *"The Jacobi step is wrong"* — refuted: the same Jacobi code diagonalises
  the k×k Ritz matrix correctly (the existing tests' top-2 answers are right,
  and the numpy replica at 200 iterations, using the identical Rayleigh-Ritz
  formulation, reproduces `eigh` to 10 dp).
- *"The covariance accumulation is wrong"* — refuted: `gateB/pca_truth.py`
  builds the covariance by exactly the Swift accumulation
  (`sumOuter/n − mean⊗mean`) and its `eigh` spectrum is the one the 200-
  iteration replica converges to.
- *"200 iterations are simply not enough"* — refuted by the replica: 200
  iterations converge; the printed `iterations used` in
  `gateB/subspace_replica.py` is what the fixed loop needs, and one is not it.

## 3. The discriminating experiment, and its predicted outcome (written before running)

`DiffractionEmbeddingTests.testSymmetricEigenTopReturnsTrueEigenpairs`:
build `C = Σ_j λ_j q_j q_jᵀ` on `d = 64` from an orthonormal basis
`Q` produced by Gram-Schmidt on a fixed deterministic seed, with **8 distinct
planted eigenvalues** `[100, 64, 41, 26, 17, 11, 7, 4.5]` (ratios ≈ 1.55 — far
from 1, so a converged solver separates them easily, and far from 0, so one
power step cannot) and the remaining 56 eigenvalues at `0.5`. Ask
`symmetricEigenTop` for `count = 8` and assert:

1. `‖C v_c − λ_c v_c‖ ≤ 1e-6 · ‖λ_c v_c‖` for every returned pair;
2. the returned values are in descending order;
3. `λ_c` equals the planted `[100, 64, 41, 26, 17, 11, 7, 4.5]` to 1e-8.

**Prediction (stated before the run): the test FAILS on HEAD.** Specifically
the residual assertion fails for the components past the dominant one or two
(c ≥ 2 with near-certainty; c = 1 plausibly too, since 64/100 = 0.64 is not a
fast power-iteration ratio), and assertion 3 fails for those same components
with the reported λ *below* the planted value — a single power step can only
under-estimate a Rayleigh quotient of a non-converged direction. Assertion 2
is predicted to **pass** even on HEAD, because the Rayleigh-Ritz sort is
correct; that is the point of including it — an ordering-only test would not
discriminate.

If instead the test passes on HEAD, the diagnosis is refuted and the tail
error the refuter measured has some other cause.

## 4. Outcome

Run 2026-09-06, log `fix-c/C1-head.log` (exit 65, on its own line in the run;
`fix-c/C1-head-dump.log` carries every assertion message, extracted from the
xcresult). The HEAD eigensolver was left byte-identical apart from a
package-visible overload so the fixture could call it — no behavioural edit.

Result: **FAILED, as predicted** — and worse than predicted. Verbatim, the
first and last of the sixteen messages:

```
XCTAssertLessThanOrEqual failed: ("0.05781847398510529") is greater than ("1e-06")
  - component 0 is not an eigenvector of the matrix it claims to diagonalise:
    relative residual 0.05781847398510529
...
XCTAssertEqualWithAccuracy failed: ("3.3972316855542677") is not equal to ("4.5")
  +/- ("1e-08") - component 7 eigenvalue 3.3972316855542677, planted 4.5
```

Every one of the eight components failed both the residual and the planted-
eigenvalue assertion. The residual grows monotonically with the component
index (0.058, 0.055, 0.049, 0.089, 0.136, 0.282, 0.435, 0.568) and every
reported eigenvalue is BELOW its planted value (99.657/100, 63.798/64,
40.900/41, 25.782/26, 16.648/17, 9.949/11, 5.883/7, 3.397/4.5) — the
signature of a Rayleigh quotient taken on an unconverged direction, exactly
as predicted. The descending-order assertion passed, also as predicted.

**Where the prediction was wrong, and it matters:** I predicted component 0
would converge. It did not — one power step on a spectrum whose top ratio is
64/100 does not converge even the dominant direction. The prediction was too
generous to the code; the defect is broader than the refuter's fixture showed,
because that fixture's covariance happens to be nearly rank-2 (λ0/λ1 large
enough that one step is close), while a general covariance is not.

The end-to-end companion test failed on the same run:
`testPublishedBasisAreEigenpairsOfTheMeanCentredCovariance`, all eight rows,
residual/trace 1.3e-05 … 2.1e-04 against a 1e-06 bar. Its printed
`explainedVariance` values reproduce the Gate B refuter's Swift dump digit for
digit (0.6237959, 0.3742342, 8.416045e-05, …), which independently confirms
that the test's own re-implementation of the log1p / max-normalise / box-bin
pipeline matches production.

The diagnosis survived its refutation test.

## 5. Post-fix

Same tests, same fixtures, after replacing the subspace iteration with
Accelerate LAPACK `dsyevd_` (`fix-c/C1-fixed.log`, exit 0): all six
`DiffractionEmbeddingTests` pass. The planted eigenvalues are recovered to
1e-08 and every relative residual is below 1e-06.

On the end-to-end fixture the worst residual/trace fell from 2.1e-04 to
**1.67e-08** (measured with the bar temporarily set to 1e-30 so the numbers
print; that is how the shipped 1e-06 threshold was chosen — ~60x above the
post-fix floor and ~13x below the smallest HEAD failure). The corrected
explained-variance numbers show how far off the tail was:

| component | HEAD | LAPACK | HEAD error |
|---|---|---|---|
| c2 | 8.416e-05 | 1.0665e-04 | −21 % |
| c5 | 6.964e-05 | 8.786e-05 | −21 % |
| c7 | 5.242e-05 | 8.225e-05 | −36 % |

which reproduces the refuter's "20–36 % low" independently.

**Fixture compute time** (`testPCAExplainsThreeFamiliesInFirstThreeComponents`,
36 positions, binnedSize 16, 8 components, Debug):
0.356 s on HEAD → **0.224 s** with LAPACK. The refuter's alternative — keeping
the iteration and only guarding the NaN — measured 16.6 s, because 200
iterations of an O(k·d²) Swift matvec dominate. LAPACK is both correct and
1.6x faster than the wrong answer.

## 6. What the fix changed beyond the solver

- `Settings.seed` no longer reaches the PCA (there is no random start);
  its doc comment and `SplitMix64`'s now say so, and it stays meaningful for
  k-means++ seeding only.
- `Result.explainedVariance`'s doc comment states its provenance: the
  eigenvalue over the TRACE of the mean-centred covariance, not over the sum
  of the retained eigenvalues — the fractions therefore do not sum to 1.
- Two DEVIATION notes in the file header: py4DSTEM's PCA is sklearn's, exact
  and mean-centred and variance-ordered
  (`References/py4DSTEM-dev/py4DSTEM/process/classification/featurization.py`
  :366-373), which `dsyevd_` matches and the iteration did not; and the
  log1p / max-normalise / box-bin representation has no py4DSTEM counterpart
  at all, so there is no upstream number to check it against.
- The file header's LAPACK paragraph is rewritten: the stated reason for
  avoiding LAPACK ("no build available to verify the choice") is gone, and
  the paragraph now says what the iteration got wrong.
- `-DACCELERATE_NEW_LAPACK` is set in `Package.swift`'s DSTEMCore
  `swiftSettings` and in the Xcode project's `OTHER_SWIFT_FLAGS` (both
  project-level configurations, so the app and test targets that compile
  `Core/` directly inherit it). Without it the Accelerate module exposes only
  the CLAPACK headers Apple deprecated in macOS 13.3 and the build is not
  warning-free. The fixed run's log contains no compiler warnings.
