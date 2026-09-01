# Independent ACOM convention gate

Run `tools/acom-convention-test/run.sh`. It compiles production Bragg types,
crystal, plan and CPU matcher using the shared source manifest. No local data,
Python, py4DSTEM install or Metal device is needed for the normal gate.
`tools/run-tests.sh scientific` includes it, so CI will run it after a push.

The experiment was registered in
[`review-recovery.md`](../../docs/archive/v2-session-records/review-recovery.md)
before the first run. This tests projection conventions and returned orientation
matrices; it does not certify general indexing accuracy or scientific exports.

## Independent truth and limitations

- Analytic FCC Au: 18 generic template axes × 8 asymmetric in-plane rotations.
- Analytic hexagonal WS2: 30 axes × the same 8 rotations.
- Frozen external FCC Au: all 40 patterns and original lab matrices from
  py4DSTEM **0.14.17**, seed 7, generated during the interrupted investigation.

Analytic peak coordinates are dot products onto a right-handed basis built in
the harness. They never call production `project` or `detectorBasis`. Expected
orientations come from that basis; independent proper cubic/D6 operators make
the comparison aware of crystal symmetry. Every match must execute and return
a finite proper rotation. An oracle check must reject a generic 37.2° error.

The analytic fixtures still share crystal structure factors and sample axes
from the production bank: they do **not** independently validate those pieces.
The frozen patterns provide an external cubic anchor independent of both.
They are not parity against the newer vendored py4DSTEM source lock, and their
nontrivial outliers are retained. The bounds reject convention regressions;
they are not product-level accuracy thresholds. No threshold in the app changes.

The matrix assertion compares physical orientation, not raw Euler triples:
the app reduces the orientation by crystal symmetry. Comparing a raw matrix
directly with its reported template basis was the previously refuted remedy.
The auxiliary in-plane check does not replace the independent matrix assertion.

## Frozen-reference provenance

`reference.json` contains inputs, original py4DSTEM lab matrices and SHA-256
hashes of the recovered input, NumPy truth array and generator. App lab axes
are (column,row,downstream); py4DSTEM axes are (row,column,upstream). The fixed
proper rotation `[[0,1,0],[1,0,0],[0,0,-1]]` maps between these frames.

`generate_reference.py` preserves the original generator, including its NumPy 2
compatibility shims. It is an **offline provenance aid**, not executed by the
gate. Run it in a scratch directory with py4DSTEM 0.14.17 to regenerate
`py4-input.json` and `py4-truth.npy`; rebaseline only through scientific review.
The generator version and its shims are not claims about supported app APIs.

## Break before trusting

`python3 tools/acom-convention-test/check_mutations.py /tmp/acom-mutations`
runs a control and six mutations in disposable source copies, retaining logs.
Each must fail at its predicted semantic assertion, not at compilation:

| Mutation | Predicted discriminator |
|---|---|
| Swap projected x/y | Au independent matrix orientation |
| Reflect projected y | Au independent matrix orientation |
| Build returned matrix from template zero | Au independent matrix orientation |
| Drop the correlation-shift sign reversal | Au independent matrix orientation |
| Make the orientation oracle always return zero | Generic wrong-orientation self-check |
| Return no orientation for every match | No skipped failed match |

Control measurements and actual mutation dispositions are recorded in the
session evidence, not inferred from this table. Gate B must also try candidates
the author did not choose. GPU execution, real acquisitions, UI and export
metadata remain outside this gate.
