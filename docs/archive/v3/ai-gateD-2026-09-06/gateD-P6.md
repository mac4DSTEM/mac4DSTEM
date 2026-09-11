# Gate D — P6: the objects table's first rows render as reflection rows

Trigger: **cause not yet established**. Nothing here can move a scientific
number (the object list, the counts and the density are unchanged either way);
the open question is purely *why* the inspector draws the wrong rows, and the
source alone does not settle it, because the same code renders correctly on the
second segmentation (`11b-objects-table-correct-after-resegment.png`).

## 1. The diagnosis, with its evidence

`PrecipitateSettingsSection` puts **two** `ForEach`es inside **one** `Section`
of the inspector's grouped `Form`:

- `UI/PrecipitateSettings.swift:37` — `ForEach(appState.precipitates.reflections, id: \.id)`
- `UI/PrecipitateSettings.swift:151` — `ForEach(Array(shown), id: \.id)` over the objects

Both key on `Int`, and the two id spaces **overlap**:

- reflection ids come from `PrecipitateReflections.find`'s
  `accepted.enumerated().map { index, raw in Candidate(id: index, …) }`
  (`Core/Analysis/Precipitates/PrecipitateReflections.swift:138`) → **0 … 23**
  for the drive's 24 proposals;
- object ids come from `PrecipitateSegmentation` → **1 … 44** for the drive's
  44 objects.

A SwiftUI `List`/`Form` identifies its rows by the id value within the
container, not per-`ForEach`. Where an id is claimed twice, one subtree is
kept — the first-registered one, the reflection row.

## 2. The observation that would refute it

If the cause were the id collision, then the rows drawn under `Objects` must be
exactly **the intersection of the two id sets**, drawn as reflection rows, and
the object rows must resume at **the first object id that no candidate claims**.
For the drive's run that is: the duplicated block starts at candidate **id 1**
(the second-brightest reflection, `r37, c49`, *not* the brightest `r39, c48`),
runs to candidate id 23, and the object rows resume at **#24**.

The competing account — "the reflections `ForEach` is simply emitted twice by
the view builder" — predicts instead that the block starts at candidate **id 0**
(`r39, c48`, the brightest) and that **all 44** object rows follow it.

The two accounts disagree on two observable things: the first row of the
duplicated block, and where the object rows resume. Either observation refutes
one of them.

## 3. The predicted outcome, stated before looking

Prediction: for `candidateIDs = 0…23` and `objectIDs = 1…44`, the intersection
is `1…23` — 23 ids, minimum 1 — and the smallest object id outside it is 24.
The drive capture must therefore show the duplicated block beginning at
`r37, c49` and the object rows beginning at `#24`, with objects #1…#23
unreachable.

## 4. The experiment and its outcome

Experiment: `PrecipitateTests.testInspectorRowIDsCollideExactlyWhereTheDriveShowedThem`
computes the two id sets from the drive's own cardinalities and asserts the
intersection.

Outcome — the prediction held, and the capture agrees:

- intersection of `0…23` and `1…44` = `1…23`, count 23, minimum 1;
- smallest object id outside it = 24;
- `06a-objects-table-shows-reflections.png` shows, immediately under
  `Objects  44 objects, 5 on the edge`, the rows `r37, c49  18.0 px from beam`
  then `r49, c26  18.2 px from beam` — candidate ids **1 and 2**, not 0
  (the full proposal order in `drive-precipitates.md` step 3b is
  `39,48 · 37,49 · 49,26 · …`);
- `06c-object-rows-start-at-24.png` shows the object rows resuming at `#24`.

The "emitted twice" account is refuted: it required the block to start at
`r39, c48` and all 44 objects to follow.

Why the second segmentation renders correctly (`11b`) is consistent with, and
not evidence against, this account: the collision is resolved when the rows
first acquire identity, and the later diff keeps the resolution it already has
for the ids it has already seen. It is not needed to justify the fix.

## 5. The fix this licenses

Give the two row families **disjoint identities** rather than sharing the
integer id space: `Candidate.rowIdentity` (`"precipitate.reflection.<id>"`) and
`Object.rowIdentity` (`"precipitate.object.<id>"`), keyed by the two `ForEach`es.
Pinned by `testReflectionAndObjectRowIdentitiesNeverCollide`, which is broken
once against the pre-fix `\.id` keying (see `break-P6.log`).
