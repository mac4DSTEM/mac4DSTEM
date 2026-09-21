# Gate D — class-map objects and density denominator

Date: 2026-09-21. Scope: the pure Core bridge from a labelled scan map to
per-class connected components and areal-density inputs. It is not wired to a
`Session` product, export, or UI; phase mapping remains `validation: "none"`.

## Trigger

The first Gate D trigger applies: `analysedPixels` is the denominator of a
reported areal density and an error can move a scientific number. The second
does not: this is a new calculation with an explicit input contract, not a
diagnosis of an unexplained observed failure.

## Diagnosis, refuter, prediction

`notIndexed` is the only refused label role. Matrix, selected precipitate
classes, and labels in no role set are all indexed scan positions, so all stay
in the denominator. Excluding an unselected but indexed class would make the
same accepted-object count report a spuriously higher density. Role sets must
be disjoint; an unassigned label is deliberately recorded as indexed `other`,
not silently refused.

This diagnosis is refuted if an unselected indexed class should reduce the
analysed area, or if spatial components can merge across class labels. The
hand-drawn 12×9 fixture predicts 108 total positions, three `notIndexed`, and
therefore 105 analysed positions even when class 2 is removed from the
selected precipitate set. It also predicts a class-1 six-pixel object and an
8-connected class-2 eight-pixel object remain separate despite touching.

## Experiment and outcome

`PhaseMapObjectsTests` was written before the bridge. Its initial focused build
was red (exit 65) because the interrupted refactor still called the missing
`measure` helper. After implementation, a deliberate mutant changed the
denominator from `total - notIndexedPixels` to also subtract `otherPixels`.
The focused XCTest run was red (exit 65; its own log line
`XCODEBUILD_EXIT=65`):
`testNotIndexedHolesReduceTheAnalysedAreaByTheirCount` failed, while the
source was then restored. The final focused run is named
`phase-map-objects-final-20260921.log`: five bridge tests plus eighteen legacy
`PrecipitateTests` passed (23 tests, exit 0).

## Independent Gate B refuter

An independent reviewer attacked the diagnosis and fixture before closeout. It
could not make the denominator mutant or a cross-class union survive: the
fixture's unselected class becomes eight `other` pixels while still requiring
105 analysed positions, and the touching class-1/class-2 objects pin distinct
areas, coordinates and pixel membership. The reviewer also checked the pinned
upstream source: `py4DSTEM/process/classification/braggvectorclassification.py`
uses `skimage.measure.label(..., connectivity=2)` at lines 337–353 and again
472–487; in 2D that is full (8-neighbour) connectivity. The bridge adopts that
explicit path rather than claiming an unpinned library default. The original
`LabelRoles` precondition message was corrected to say unassigned labels are
indexed `other` labels.

No comparison to a physical density is claimed. The pre-registered ship gate
in `docs/v3-precipitate-classification.md` remains: the classification route
must meet the owner-adjudicated count and beat the image route before it is
wired or called a measurement.
