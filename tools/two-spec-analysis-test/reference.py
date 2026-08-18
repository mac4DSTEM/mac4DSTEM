#!/usr/bin/env python3
"""Fixtures for tools/two-spec-analysis-test.

This file writes DATA ONLY. It computes no expected answer, and deliberately
so: the arbiter for this harness is the app's own FULL-EXTENT run restricted to
the overlap, never a second opinion from Python (see main.swift's header). A
reference implementation here would answer a different question — "does the app
agree with numpy?" — and this harness asks "does the app's reduced-view run
agree with its own full-extent run?".

EVERY VALUE IS AN INTEGER stored as float32, and that is load-bearing rather
than tidy. Virtual imaging sums up to qy*qx values per scan position; binning
sums b*b values per output pixel. Sums of integers stay EXACT in float32 as
long as the total stays under 2**24 = 16777216, whatever order either side
accumulates in. That is what lets main.swift assert `==` on a virtual image
across two different reductions instead of picking a tolerance — and a
tolerance is exactly where a real offset defect hides. The largest total this
file can produce is 32*36*1200 = 1382400, a factor of twelve inside the bound.

THE DETECTOR IS NOT SQUARE, and neither is the scan. A square detector lets a
transposed index commute with cropping and pass every comparison — demonstrated
on this repo on 2026-08-18, when transposing EMPAD's decode loop left
tools/load-spec-test entirely green. 32x36 with a 6x7 scan means no two axes
can be swapped without a shape mismatch.

Writes: analysis.h5 (the structured two-spec cube) and random-0..4.h5 (seeded
randomized cubes for the metamorphic property suite).
"""
import pathlib
import sys

try:
    import h5py
    import numpy as np
except ImportError as error:  # loud, never skipped
    sys.stderr.write(
        "two-spec-analysis-test needs h5py and numpy (%s). Set "
        "PYTHON=/path/to/python to an interpreter that has them.\n" % error
    )
    raise SystemExit(1)

root = pathlib.Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)

DATASET_PATH = "4DSTEM_experiment/data/datacubes/datacube_0"


def write_cube(path, cube):
    """Write one 4D float32 cube where H5Reader.discoverPrimaryDataset finds it."""
    assert cube.dtype == np.float32
    assert np.all(cube == np.floor(cube)), "fixture values must be integral"
    assert cube.max() * cube.shape[2] * cube.shape[3] < 2**24, "float32 sums would round"
    with h5py.File(root / path, "w") as f:
        group = f.create_group(DATASET_PATH)
        group.create_dataset("data", data=cube)


def disk(qy, qx, cy, cx, radius, amplitude):
    """A hard-edged disk. Hard edges keep every value an integer; the softness of
    a real probe is irrelevant to the invariances under test, all of which are
    about WHERE a value is read from, not what shape it has."""
    y = np.arange(qy)[:, None]
    x = np.arange(qx)[None, :]
    inside = (y - cy) ** 2 + (x - cx) ** 2 <= radius ** 2
    return np.where(inside, np.float32(amplitude), np.float32(0))


# ---- The structured cube ----------------------------------------------------
# A beam disk whose centre WALKS ACROSS THE SCAN (an integer descan), plus four
# Bragg disks at fixed offsets from it. The walk is what makes a scan crop a
# real test: if the origin were constant, a scan-crop offset error would select
# a different position whose pattern is identical, and the comparison would pass
# on wrong data.
RY, RX, QY, QX = 6, 7, 32, 36
BEAM_RADIUS = 3.0
BEAM_AMPLITUDE = 900
# The same radius as the beam, because that is what a Bragg disk physically IS
# — an image of the probe. A smaller disk correlates weakly against a probe-
# sized kernel and detection finds only the beam, which is how the first version
# of this fixture failed its own sanity check.
BRAGG_RADIUS = 3.0
# FOUR DIFFERENT AMPLITUDES, not one. With a single amplitude the four disks sit
# at (0,+-11) and (+-9,0) around a near-centred beam, which makes the pattern
# almost two-fold symmetric — and a symmetric pattern cannot witness a
# reflection: mirroring maps the disk above onto the disk below with an
# identical sum. The bin-placement checks in main.swift found this the moment
# they were given a real anti-vacuity guard (2026-08-19). Distinct amplitudes
# break every mirror and rotation of this fixture.
BRAGG_AMPLITUDES = [260, 180, 320, 140]
BACKGROUND = 3

# Bragg offsets in (dy, dx). Chosen to stay clear of the detector edge for every
# origin the walk produces, so the disks are whole in every pattern; a disk
# clipped by the detector edge would move its own detected centroid and make a
# "peak moved" failure ambiguous between a crop defect and the fixture.
BRAGG_OFFSETS = [(0, 11), (0, -11), (9, 0), (-9, 0)]

cube = np.zeros((RY, RX, QY, QX), dtype=np.float32)
origins = np.zeros((RY, RX, 2), dtype=np.float32)
for ry in range(RY):
    for rx in range(RX):
        # Integer walk, distinct per position, bounded to +-2 px.
        cy = QY / 2.0 + (ry % 3) - 1
        cx = QX / 2.0 + (rx % 3) - 1
        origins[ry, rx] = (cy, cx)
        pattern = np.full((QY, QX), np.float32(BACKGROUND), dtype=np.float32)
        pattern += disk(QY, QX, cy, cx, BEAM_RADIUS, BEAM_AMPLITUDE)
        for (dy, dx), amplitude in zip(BRAGG_OFFSETS, BRAGG_AMPLITUDES):
            pattern += disk(QY, QX, cy + dy, cx + dx, BRAGG_RADIUS, amplitude)
        cube[ry, rx] = pattern

write_cube("analysis.h5", cube)

# The beam centres, so main.swift can check a re-referenced calibration against
# what the fixture PUT ON DISK rather than against the app's own second opinion.
np.savetxt(root / "origins.txt", origins.reshape(-1, 2), fmt="%.1f")

# ---- Randomized cubes for the metamorphic properties ------------------------
# Seeded, so a failure is reproducible; randomized, so the properties are not
# quietly satisfied by one hand-picked arrangement. Shapes vary, and some
# detector extents deliberately do NOT divide by 4 so the edge-remainder trim
# runs inside the property suite rather than only in the structured cases.
RANDOM_SHAPES = [
    (4, 5, 16, 20),
    (3, 6, 24, 16),
    (5, 4, 18, 28),   # 18 % 4 = 2 — remainder path
    (2, 7, 20, 22),   # 22 % 4 = 2 — remainder path
    (6, 3, 32, 24),
]
for index, (ry, rx, qy, qx) in enumerate(RANDOM_SHAPES):
    rng = np.random.default_rng(20260819 + index)
    data = rng.integers(0, 400, size=(ry, rx, qy, qx)).astype(np.float32)
    # One planted disk per position so the origin-measurement property has
    # something to find; its centre is random but integral.
    for y in range(ry):
        for x in range(rx):
            cy = int(rng.integers(6, qy - 6))
            cx = int(rng.integers(6, qx - 6))
            data[y, x] += disk(qy, qx, cy, cx, 3.0, 600)
    write_cube("random-%d.h5" % index, data)

print("two-spec-analysis-test: fixtures written to %s" % root)
