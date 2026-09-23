#!/usr/bin/env python3
"""precipitate_objects_ref.py -- a Python REFERENCE of mac4DSTEM's class-map -> objects step.

What this is
    An independent, data-free re-implementation, in stdlib + numpy, of
    `PrecipitateSegmentation.classObjects` (and the `measure`,
    `connectedComponents`, `principalAxis`, `labelImage` helpers it uses),
    `PrecipitateStatistics.density`, and `PhaseMapObjectsBridge.labeledMap`,
    written from the Swift source as it stands at HEAD 3d0134a (2026-09-23).
    Every definition below cites the Swift file:line it transcribes.
    Swift `Float` arithmetic is mirrored with numpy float32 scalars in the
    Swift evaluation order (including the flood-fill visit order, which fixes
    the float summation order); `Double` arithmetic is Python float.

What this is NOT
    It is not the app and it never ran the app. No Swift was compiled or
    executed to produce anything here (the container that wrote it has no
    Swift toolchain). Agreement between this file and the Swift tests'
    expected values says the tests' hand arithmetic and this reading of the
    source agree -- it does not prove the Swift binary computes the same.
    scipy is used only in `crosscheck`, as an independent labeller.

Usage
    python3 tools/cloud-analysis/precipitate_objects_ref.py selftest    # expected values of the Swift tests, recomputed
    python3 tools/cloud-analysis/precipitate_objects_ref.py mutate      # one-token mutants of the reference; each must turn a case red
    python3 tools/cloud-analysis/precipitate_objects_ref.py crosscheck  # scipy.ndimage cross-check on random label maps
    python3 tools/cloud-analysis/precipitate_objects_ref.py all         # all three; exit 0 only if every stage is as expected

Swift sources transcribed (paths relative to the repo root):
    SEG = mac4DSTEM/Core/Analysis/Precipitates/PrecipitateSegmentation.swift
    STA = mac4DSTEM/Core/Analysis/Precipitates/PrecipitateStatistics.swift
    BRI = mac4DSTEM/Session/PhaseMapObjectsBridge.swift
"""

import math
import sys
import types

import numpy as np

F = np.float32
FLOAT_MAX = np.finfo(np.float32).max          # Swift Float.greatestFiniteMagnitude
NOT_INDEXED_LABEL = -1                        # BRI:36

# SEG:453-454 -- `for dy in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0)`,
# i.e. the 8 neighbours, dy-major. NEIGHBOURS_4 exists only as a mutation target.
NEIGHBOURS_8 = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
NEIGHBOURS_4 = [(-1, 0), (0, -1), (0, 1), (1, 0)]


class Obj:
    """SEG:48-101 `Object`. lengthPx/widthPx are pixel-centre spans + 1 along/across the axis."""

    def __init__(self, id, pixel_indices, area, centroid_x, centroid_y, length_px, width_px,
                 orientation_degrees, touches_edge, mean_intensity):
        self.id = id
        self.pixel_indices = pixel_indices
        self.area = area
        self.centroid_x = centroid_x
        self.centroid_y = centroid_y
        self.length_px = length_px
        self.width_px = width_px
        self.orientation_degrees = orientation_degrees
        self.touches_edge = touches_edge
        self.mean_intensity = mean_intensity

    def with_id(self, new_id):
        return Obj(new_id, self.pixel_indices, self.area, self.centroid_x, self.centroid_y,
                   self.length_px, self.width_px, self.orientation_degrees, self.touches_edge,
                   self.mean_intensity)


def connected_components(mask, width, height):
    """SEG:440-468. Row-major scan for seeds, iterative stack flood fill (popLast), 8-connected."""
    n = width * height
    labelled = [False] * n
    components = []
    for start in range(n):                                   # SEG:445
        if not mask[start] or labelled[start]:               # SEG:446
            continue
        labelled[start] = True
        stack = [start]
        members = []
        while stack:
            i = stack.pop()                                  # SEG:450 popLast
            members.append(i)
            row, col = i // width, i % width                 # SEG:452
            for dy, dx in NEIGHBOURS_8:                      # SEG:453-454
                r, c = row + dy, col + dx
                if r < 0 or r >= height or c < 0 or c >= width:  # SEG:456
                    continue
                j = r * width + c
                if mask[j] and not labelled[j]:              # SEG:458-461
                    labelled[j] = True
                    stack.append(j)
        components.append(members)
    return components


def principal_axis(cxx, cyy, cxy):
    """SEG:490-515. Larger eigenvector of [[cxx,cxy],[cxy,cyy]], angle folded into (-90, 90].

    Frame: x = column, y = row (SEG:410-411), angle = atan2(vy, vx) measured from +x toward +y.
    """
    trace = cxx + cyy                                        # SEG:493
    diff = cxx - cyy                                         # SEG:494
    discriminant = max(F(0), diff * diff + F(4) * cxy * cxy)  # SEG:495
    root = np.sqrt(discriminant)                             # SEG:496
    lambda1 = (trace + root) / F(2)                          # SEG:497
    lambda2 = (trace - root) / F(2)                          # SEG:498
    if cxy != 0:                                             # SEG:501-503
        vx = lambda1 - cyy
        vy = cxy
    elif cxx >= cyy:                                         # SEG:504-505
        vx, vy = F(1), F(0)
    else:                                                    # SEG:506-507
        vx, vy = F(0), F(1)
    norm = np.sqrt(vx * vx + vy * vy)                        # SEG:509
    if norm > 0:                                             # SEG:510
        vx = vx / norm
        vy = vy / norm
    angle = np.arctan2(vy, vx) * F(180) / F(np.pi)           # SEG:511
    while angle <= -90:                                      # SEG:512
        angle = angle + F(180)
    while angle > 90:                                        # SEG:513
        angle = angle - F(180)
    return lambda1, lambda2, angle


def measure(members, width, height, footprint_values, intensity):
    """SEG:387-438 `measure` (shared by segment() and classObjects)."""
    assert members, "an object needs at least one member"   # SEG:391
    area = len(members)                                      # SEG:393
    sum_x = F(0); sum_y = F(0); sum_i = F(0)
    touches_edge = False
    for i in members:                                        # SEG:396-404
        row, col = i // width, i % width
        sum_x = sum_x + F(col)
        sum_y = sum_y + F(row)
        sum_i = sum_i + F(intensity[i])
        if row == 0 or row == height - 1 or col == 0 or col == width - 1:   # SEG:401
            touches_edge = True
    centroid_x = sum_x / F(area)                             # SEG:405
    centroid_y = sum_y / F(area)                             # SEG:406

    cxx = F(0); cyy = F(0); cxy = F(0)
    for i in members:                                        # SEG:409-415
        dx = F(i % width) - centroid_x
        dy = F(i // width) - centroid_y
        cxx = cxx + dx * dx
        cyy = cyy + dy * dy
        cxy = cxy + dx * dy
    cxx = cxx / F(area); cyy = cyy / F(area); cxy = cxy / F(area)   # SEG:416 (population covariance)

    _, _, axis = principal_axis(cxx, cyy, cxy)               # SEG:418
    peak = -FLOAT_MAX
    for i in members:                                        # SEG:419
        peak = max(peak, F(footprint_values[i]))
    half = F(0.5) * peak                                     # SEG:420
    ax = np.cos(axis * F(np.pi) / F(180))                    # SEG:421
    ay = np.sin(axis * F(np.pi) / F(180))
    u_min = FLOAT_MAX; u_max = -FLOAT_MAX
    v_min = FLOAT_MAX; v_max = -FLOAT_MAX
    for i in members:                                        # SEG:424
        if not F(footprint_values[i]) >= half:
            continue
        dx = F(i % width) - centroid_x                       # SEG:425
        dy = F(i // width) - centroid_y
        u = dx * ax + dy * ay                                # SEG:426 along the axis
        v = -dx * ay + dy * ax                               #        across the axis
        u_min = min(u_min, u); u_max = max(u_max, u)
        v_min = min(v_min, v); v_max = max(v_max, v)
    length = u_max - u_min + F(1) if u_max > u_min else F(1)     # SEG:430
    width_ = v_max - v_min + F(1) if v_max > v_min else F(1)     # SEG:431
    return Obj(0, sorted(members), area, centroid_x, centroid_y, length, width_, axis,
               touches_edge, sum_i / F(area))                # SEG:432-437


def label_image(objects, width, height):
    """SEG:297-306. Object id per pixel (later objects overwrite), 0 elsewhere, Float."""
    pixels = np.zeros(width * height, dtype=np.float32)
    for o in objects:
        for i in o.pixel_indices:
            if 0 <= i < pixels.size:
                pixels[i] = F(o.id)
    return pixels


def density(objects, accepted, analysed_pixels, pixel_size, pixel_unit):
    """STA:98-139 `PrecipitateStatistics.density` (Double arithmetic)."""
    accepted_objects = [o for o in objects if o.id in accepted]          # STA:105
    counted = [o for o in accepted_objects if not o.touches_edge]        # STA:106 edge objects never counted
    edge_excluded = [o for o in accepted_objects if o.touches_edge]      # STA:107
    lengths = sorted(float(o.length_px) for o in counted)                # STA:109
    widths = [float(o.width_px) for o in counted]                        # STA:110
    mean_length = None if not lengths else sum(lengths) / len(lengths)   # STA:112
    n = len(lengths)
    if n == 0:                                                           # STA:113-120
        median_length = None
    elif n % 2 == 1:
        median_length = lengths[n // 2]
    else:
        median_length = (lengths[n // 2 - 1] + lengths[n // 2]) / 2
    mean_width = None if not widths else sum(widths) / len(widths)       # STA:121
    areal = None
    if (pixel_size is not None and math.isfinite(pixel_size) and pixel_size > 0
            and analysed_pixels > 0):                                    # STA:124 refusal rule
        areal = len(counted) / (analysed_pixels * pixel_size * pixel_size)  # STA:125
    return dict(accepted_count=len(counted), edge_count=len(edge_excluded),
                analysed_pixels=analysed_pixels, pixel_size=pixel_size, pixel_unit=pixel_unit,
                areal_density=areal, mean_length=mean_length, median_length=median_length,
                mean_width=mean_width)


def class_objects(labels, width, height, precipitate, matrix, not_indexed, pixel_size, pixel_unit):
    """SEG:308-380 `classObjects`. Role sets must be disjoint; labels in none are indexed 'other'."""
    assert width >= 0 and height >= 0                                    # SEG:318
    assert len(labels) == width * height                                 # SEG:319
    precipitate, matrix, not_indexed = set(precipitate), set(matrix), set(not_indexed)
    if (precipitate & matrix) or (precipitate & not_indexed) or (matrix & not_indexed):
        raise ValueError("role sets must be disjoint")                   # SEG:320-325
    total = len(labels)                                                  # SEG:327
    not_indexed_pixels = sum(1 for x in labels if x in not_indexed)      # SEG:328
    matrix_pixels = sum(1 for x in labels if x in matrix)                # SEG:329
    analysed = total - not_indexed_pixels                                # SEG:330 only not-indexed leave the area
    precipitate_pixels = sum(1 for x in labels if x in precipitate)      # SEG:331
    other_pixels = total - not_indexed_pixels - matrix_pixels - precipitate_pixels  # SEG:332

    next_id = 1
    classes = []
    for label in sorted(precipitate):                                    # SEG:336 ascending label order
        mask = [lab == label for lab in labels]                          # SEG:337 one class at a time
        values = [1.0 if m else 0.0 for m in mask]                       # SEG:338 binary footprint
        raw = [measure(m, width, height, values, values)
               for m in connected_components(mask, width, height)]       # SEG:339-345
        raw.sort(key=lambda o: (-o.area, o.pixel_indices[0]))            # SEG:346-350 area desc, then first index asc
        objects = []
        for o in raw:                                                    # SEG:351-360 ids global across classes
            objects.append(o.with_id(next_id))
            next_id += 1
        dens = density(objects, {o.id for o in objects}, analysed,
                       pixel_size, pixel_unit)                           # SEG:361-364 every object accepted
        pixel_count = sum(o.area for o in objects)                       # SEG:365 includes edge objects
        classes.append(dict(label=label, objects=objects, pixel_count=pixel_count,
                            area_fraction=(pixel_count / analysed) if analysed > 0 else None,  # SEG:368
                            density=dens))
    return dict(width=width, height=height, connectivity=8, classes=classes,   # SEG:374 (a literal)
                matrix_pixels=matrix_pixels, other_pixels=other_pixels,
                not_indexed_pixels=not_indexed_pixels, analysed_pixels=analysed,
                not_indexed_fraction=(not_indexed_pixels / total) if total > 0 else None)  # SEG:377


def labeled_map(results, phase_names, matrix_phase_index):
    """BRI:45-71. results: list of (verdict, phaseIndex); verdict in matrix/indexed/notIndexed/noData."""
    labels = [NOT_INDEXED_LABEL] * len(results)                          # BRI:46
    for index, (verdict, phase_index) in enumerate(results):
        if verdict in ("matrix", "indexed"):                             # BRI:49-50
            labels[index] = phase_index
        else:                                                            # BRI:51-52
            labels[index] = NOT_INDEXED_LABEL
    precipitate, matrix = set(), set()
    for phase_index in range(len(phase_names)):                          # BRI:58-65 every non-matrix phase
        (matrix if phase_index == matrix_phase_index else precipitate).add(phase_index)
    return labels, precipitate, matrix, {NOT_INDEXED_LABEL}              # BRI:67-70


# ==== END REFERENCE ====
# Everything above the marker is the reference and is what `mutate` edits.
# Everything below is the harness and is never mutated.

MARKER = "# ==== END " + "REFERENCE ===="


def _cls(result, label):
    for c in result["classes"]:
        if c["label"] == label:
            return c
    raise KeyError("class %d missing" % label)


def _close(a, b, tol):
    return a is not None and b is not None and abs(float(a) - float(b)) <= tol


def _roles(precipitate, matrix=(0,)):
    return dict(precipitate=set(precipitate), matrix=set(matrix), not_indexed={-1})


def _run(ref, labels, w, h, roles, px=None, unit=None):
    return ref.class_objects(labels, w, h, roles["precipitate"], roles["matrix"],
                             roles["not_indexed"], px, unit)


# ---- Cases. Each returns a list of (description, bool). "T-" cases encode a Swift test's
# ---- expected values (file:line of the test); "X-" cases are extra, derived from the Swift
# ---- doc comments or the refuter's questions, and pinned by NO Swift test.

def t_ana_1(ref):  # PrecipitateSegmentationAnalyticTests.swift:58-93
    labels = [0] * 50
    for c in range(1, 8):
        labels[2 * 10 + c] = 1
    r = _run(ref, labels, 10, 5, _roles([1]))
    o = _cls(r, 1)["objects"][0]
    img = ref.label_image([x for c in r["classes"] for x in c["objects"]], 10, 5)
    return [("area 7", o.area == 7), ("indices 21...27", o.pixel_indices == list(range(21, 28))),
            ("centroidX 4", _close(o.centroid_x, 4, 1e-6)), ("centroidY 2", _close(o.centroid_y, 2, 1e-6)),
            ("orientation 0", _close(o.orientation_degrees, 0, 1e-6)),
            ("length 7", _close(o.length_px, 7, 1e-6)), ("width 1", _close(o.width_px, 1, 1e-6)),
            ("not edge", o.touches_edge is False),
            ("labelImage", all(img[i] == (1 if i in o.pixel_indices else 0) for i in range(50)))]


def t_ana_4(ref):  # PrecipitateSegmentationAnalyticTests.swift:108-136
    labels = [0] * 64
    for k in range(1, 6):
        labels[k * 8 + k] = 1
    o = _cls(_run(ref, labels, 8, 8, _roles([1])), 1)["objects"][0]
    cols = [i % 8 for i in o.pixel_indices]; rows = [i // 8 for i in o.pixel_indices]
    bw, bh = max(cols) - min(cols) + 1, max(rows) - min(rows) + 1
    return [("area 5", o.area == 5), ("orientation 45", _close(o.orientation_degrees, 45, 1e-4)),
            ("length 4*sqrt2+1", _close(o.length_px, 4 * math.sqrt(2) + 1, 1e-4)),
            ("width 1", _close(o.width_px, 1, 1e-6)), ("bbox 5x5", (bw, bh) == (5, 5)),
            ("length > bbox", float(o.length_px) > bw)]


def t_ana_2(ref):  # PrecipitateSegmentationAnalyticTests.swift:147-176
    labels = [0] * 25
    for i in (6, 12, 16):
        labels[i] = 1
    r = _run(ref, labels, 5, 5, _roles([1]))
    c = _cls(r, 1)
    e = [0] * 25
    for i in range(4):
        e[i] = 1
    ec = _cls(_run(ref, e, 5, 5, _roles([1])), 1)
    return [("connectivity 8", r["connectivity"] == 8), ("one object", len(c["objects"]) == 1),
            ("area 3", c["objects"][0].area == 3), ("indices [6,12,16]", c["objects"][0].pixel_indices == [6, 12, 16]),
            ("domino one object", len(ec["objects"]) == 1), ("domino area 4", ec["objects"][0].area == 4)]


def t_ana_3(ref):  # PrecipitateSegmentationAnalyticTests.swift:186-220
    labels = [0] * 36
    for i in (0 * 6 + 3, 5 * 6 + 2, 2 * 6 + 0, 3 * 6 + 5):
        labels[i] = 1
    c = _cls(_run(ref, labels, 6, 6, _roles([1])), 1)
    interior = [0] * 25
    interior[12] = 1
    io = _cls(_run(ref, interior, 5, 5, _roles([1])), 1)["objects"][0]
    return [("4 objects", len(c["objects"]) == 4), ("all edge", all(o.touches_edge for o in c["objects"])),
            ("interior not edge", io.touches_edge is False), ("pixelCount 4", c["pixel_count"] == 4),
            ("acceptedCount 0", c["density"]["accepted_count"] == 0),
            ("edgeCount 4", c["density"]["edge_count"] == 4)]


def t_ana_6(ref):  # PrecipitateSegmentationAnalyticTests.swift:230-247
    labels = [1, 0, 0, 2]
    r = _run(ref, labels, 2, 2, _roles([1, 2]))
    a, b = _cls(r, 1), _cls(r, 2)
    return [("class1 [0]", a["objects"][0].pixel_indices == [0]), ("class2 [3]", b["objects"][0].pixel_indices == [3]),
            ("areas 1,1", a["objects"][0].area == 1 and b["objects"][0].area == 1),
            ("one object each", len(a["objects"]) == 1 and len(b["objects"]) == 1)]


def t_ana_5(ref):  # PrecipitateSegmentationAnalyticTests.swift:255-278
    labels = [0] * 9
    labels[4] = 1

    def d(px):
        return _cls(_run(ref, labels, 3, 3, _roles([1]), px, None if px is None else "nm"), 1)["density"]["areal_density"]
    return [("nil refuses", d(None) is None), ("0 refuses", d(0.0) is None), ("-2.5 refuses", d(-2.5) is None),
            ("nan refuses", d(float("nan")) is None), ("inf refuses", d(float("inf")) is None),
            ("3.0 -> 1/(9*9)", _close(d(3.0), 1.0 / (9.0 * 9.0), 1e-12))]


def t_ana_7a(ref):  # PrecipitateSegmentationAnalyticTests.swift:282-299
    r = _run(ref, [0] * 9, 3, 3, _roles([1]))
    c = _cls(r, 1)
    return [("matrix 9", r["matrix_pixels"] == 9), ("notIndexed 0", r["not_indexed_pixels"] == 0),
            ("other 0", r["other_pixels"] == 0), ("analysed 9", r["analysed_pixels"] == 9),
            ("notIndexedFraction 0", r["not_indexed_fraction"] == 0), ("no objects", c["objects"] == []),
            ("pixelCount 0", c["pixel_count"] == 0), ("areaFraction 0", c["area_fraction"] == 0),
            ("acceptedCount 0", c["density"]["accepted_count"] == 0)]


def t_ana_7b(ref):  # PrecipitateSegmentationAnalyticTests.swift:309-325
    labels = [0] * 25
    labels[12] = 1
    o = _cls(_run(ref, labels, 5, 5, _roles([1])), 1)["objects"][0]
    return [("area 1", o.area == 1), ("indices [12]", o.pixel_indices == [12]),
            ("centroid (2,2)", _close(o.centroid_x, 2, 1e-6) and _close(o.centroid_y, 2, 1e-6)),
            ("orientation 0", _close(o.orientation_degrees, 0, 1e-6)),
            ("length 1", _close(o.length_px, 1, 1e-6)), ("width 1", _close(o.width_px, 1, 1e-6)),
            ("not edge", o.touches_edge is False)]


def _fixture_12x9():  # PhaseMapObjectsTests.swift:42-54
    labels = [0] * (12 * 9)

    def put(row, cols, v):
        for c in cols:
            labels[row * 12 + c] = v
    put(1, range(2, 5), 1); put(2, range(2, 5), 1)
    put(3, range(3, 7), 2); put(4, range(3, 7), 2)
    put(4, range(10, 12), 1); put(5, range(10, 12), 1)
    labels[3 * 12 + 7] = -1; labels[4 * 12 + 7] = -1; labels[5 * 12 + 5] = -1
    return labels


def t_pmo_1(ref):  # PhaseMapObjectsTests.swift:80-127
    r = _run(ref, _fixture_12x9(), 12, 9, _roles([1, 2]))
    one, two = _cls(r, 1), _cls(r, 2)
    a1, a2 = one["objects"]
    b1 = two["objects"][0]
    ids = [o.id for c in r["classes"] for o in c["objects"]]
    return [("12x9", (r["width"], r["height"]) == (12, 9)), ("labels [1,2]", [c["label"] for c in r["classes"]] == [1, 2]),
            ("class1 2 objects", len(one["objects"]) == 2), ("class1 pixelCount 10", one["pixel_count"] == 10),
            ("A1 area 6", a1.area == 6), ("A1 indices", a1.pixel_indices == [14, 15, 16, 26, 27, 28]),
            ("A1 centroid (3,1.5)", _close(a1.centroid_x, 3, 1e-6) and _close(a1.centroid_y, 1.5, 1e-6)),
            ("A1 not edge", not a1.touches_edge), ("A1 length 3", _close(a1.length_px, 3, 1e-6)),
            ("A1 width 2", _close(a1.width_px, 2, 1e-6)), ("A1 orientation 0", _close(a1.orientation_degrees, 0, 1e-6)),
            ("A2 area 4", a2.area == 4),
            ("A2 centroid (10.5,4.5)", _close(a2.centroid_x, 10.5, 1e-6) and _close(a2.centroid_y, 4.5, 1e-6)),
            ("A2 edge", a2.touches_edge is True),
            ("class1 accepted 1", one["density"]["accepted_count"] == 1), ("class1 edgeCount 1", one["density"]["edge_count"] == 1),
            ("class2 1 object", len(two["objects"]) == 1), ("class2 pixelCount 8", two["pixel_count"] == 8),
            ("B1 area 8", b1.area == 8),
            ("B1 centroid (4.5,3.5)", _close(b1.centroid_x, 4.5, 1e-6) and _close(b1.centroid_y, 3.5, 1e-6)),
            ("B1 not edge", not b1.touches_edge), ("B1 length 4", _close(b1.length_px, 4, 1e-6)),
            ("B1 width 2", _close(b1.width_px, 2, 1e-6)),
            ("class2 accepted 1", two["density"]["accepted_count"] == 1), ("class2 edgeCount 0", two["density"]["edge_count"] == 0),
            ("ids unique", len(set(ids)) == len(ids))]


def t_pmo_2(ref):  # PhaseMapObjectsTests.swift:132-156
    labels = [0] * 16
    labels[0] = 1; labels[5] = 1; labels[12] = 1; labels[14] = 1; labels[6] = 2
    r = _run(ref, labels, 4, 4, _roles([1, 2]))
    one, two = _cls(r, 1), _cls(r, 2)
    return [("connectivity 8", r["connectivity"] == 8), ("class1 3 objects", len(one["objects"]) == 3),
            ("areas [2,1,1]", [o.area for o in one["objects"]] == [2, 1, 1]),
            ("first [0,5]", one["objects"][0].pixel_indices == [0, 5]),
            ("class2 1 object", len(two["objects"]) == 1), ("class2 [6]", two["objects"][0].pixel_indices == [6])]


def t_pmo_3(ref):  # PhaseMapObjectsTests.swift:160-184
    r = _run(ref, _fixture_12x9(), 12, 9, _roles([1, 2]))
    one, two = _cls(r, 1), _cls(r, 2)
    class_px = sum(c["pixel_count"] for c in r["classes"])
    only = _run(ref, _fixture_12x9(), 12, 9, _roles([1]))
    return [("notIndexed 3", r["not_indexed_pixels"] == 3), ("analysed 105", r["analysed_pixels"] == 105),
            ("matrix 87", r["matrix_pixels"] == 87), ("other 0", r["other_pixels"] == 0),
            ("notIndexedFraction 3/108", _close(r["not_indexed_fraction"], 3 / 108, 1e-12)),
            ("accounting closes 108", r["matrix_pixels"] + class_px + r["other_pixels"] + r["not_indexed_pixels"] == 108),
            ("class1 areaFraction 10/105", _close(one["area_fraction"], 10 / 105, 1e-12)),
            ("class2 areaFraction 8/105", _close(two["area_fraction"], 8 / 105, 1e-12)),
            ("density analysed 105", one["density"]["analysed_pixels"] == 105 and two["density"]["analysed_pixels"] == 105),
            ("only-1 labels [1]", [c["label"] for c in only["classes"]] == [1]),
            ("only-1 other 8", only["other_pixels"] == 8), ("only-1 analysed 105", only["analysed_pixels"] == 105)]


def t_pmo_4(ref):  # PhaseMapObjectsTests.swift:188-210
    px = 7.4829
    r = _run(ref, _fixture_12x9(), 12, 9, _roles([1, 2]), px, "nm")
    one, two = _cls(r, 1), _cls(r, 2)
    exp = 1.0 / (105.0 * px * px)
    d1, d2 = one["density"]["areal_density"], two["density"]["areal_density"]
    ref_nil = _run(ref, _fixture_12x9(), 12, 9, _roles([1, 2]))
    return [("class1 density", d1 is not None and abs(d1 - exp) / exp <= 1e-9),
            ("class2 density", d2 is not None and abs(d2 - exp) / exp <= 1e-9),
            ("pixelSize/unit carried", one["density"]["pixel_size"] == px and one["density"]["pixel_unit"] == "nm"),
            ("class1 meanLength 3", _close(one["density"]["mean_length"], 3, 1e-6)),
            ("class1 meanWidth 2", _close(one["density"]["mean_width"], 2, 1e-6)),
            ("class2 medianLength 4", _close(two["density"]["median_length"], 4, 1e-6)),
            ("nil px -> nil density", all(c["density"]["areal_density"] is None and c["density"]["pixel_size"] is None
                                          for c in ref_nil["classes"]))]


def t_pmo_5(ref):  # PhaseMapObjectsTests.swift:214-228
    r = _run(ref, _fixture_12x9(), 12, 9, _roles([1, 2, 3]), 7.4829, "nm")
    three = _cls(r, 3)
    un = _cls(_run(ref, _fixture_12x9(), 12, 9, _roles([3])), 3)
    return [("labels [1,2,3]", [c["label"] for c in r["classes"]] == [1, 2, 3]), ("no objects", three["objects"] == []),
            ("pixelCount 0", three["pixel_count"] == 0), ("accepted 0", three["density"]["accepted_count"] == 0),
            ("edge 0", three["density"]["edge_count"] == 0), ("density 0.0 not nil", three["density"]["areal_density"] == 0),
            ("areaFraction 0", three["area_fraction"] == 0), ("meanLength nil", three["density"]["mean_length"] is None),
            ("uncalibrated nil", un["density"]["areal_density"] is None)]


def _six_by_six_results():  # PhaseMapObjectsWiringTests.swift:33-50
    res = [("matrix", 0)] * 36
    for (r, c) in [(1, 1), (1, 2), (2, 1), (2, 2), (4, 4), (4, 5)]:
        res[r * 6 + c] = ("indexed", 1)
    res[0 * 6 + 5] = ("notIndexed", 0)
    res[5 * 6 + 0] = ("notIndexed", 0)
    return res


def _wiring(ref, px, unit):
    labels, p, m, n = ref.labeled_map(_six_by_six_results(), ["Al", "T1"], 0)
    return (p, m, n), ref.class_objects(labels, 6, 6, p, m, n, px, unit)


def t_wir_b(ref):  # PhaseMapObjectsWiringTests.swift:104-121
    (p, m, n), r = _wiring(ref, None, None)
    one = _cls(r, 1)
    return [("roles matrix {0}", m == {0}), ("roles precipitate {1}", p == {1}), ("roles notIndexed {-1}", n == {-1}),
            ("analysed 34", r["analysed_pixels"] == 34), ("notIndexed 2", r["not_indexed_pixels"] == 2),
            ("2 objects", len(one["objects"]) == 2), ("pixelCount 6", one["pixel_count"] == 6)]


def t_wir_d(ref):  # PhaseMapObjectsWiringTests.swift:124-137 (AppState composition modelled as px=nil)
    _, r = _wiring(ref, None, None)
    one = _cls(r, 1)
    return [("2 objects", len(one["objects"]) == 2), ("density nil", one["density"]["areal_density"] is None),
            ("pixelSize nil", one["density"]["pixel_size"] is None)]


def t_wir_c(ref):  # PhaseMapObjectsWiringTests.swift:139-161 (AppState composition modelled as px=2 nm)
    _, r = _wiring(ref, 2.0, "nm")
    one = _cls(r, 1)
    return [("density 1/(34*4)", _close(one["density"]["areal_density"], 1.0 / (34.0 * 2.0 * 2.0), 1e-9)),
            ("unit nm", one["density"]["pixel_unit"] == "nm")]


def _hand_obj(ref, id, length, width, edge):
    return ref.Obj(id, [id - 1], 10, 1, 1, length, width, 0, edge, 100)


def t_pre_d1(ref):  # PrecipitateTests.swift:598-610
    objs = [_hand_obj(ref, 1, 10, 3, False), _hand_obj(ref, 2, 12, 4, False)]
    d = ref.density(objs, {1, 2}, 40000, None, None)
    return [("nil density", d["areal_density"] is None), ("accepted 2", d["accepted_count"] == 2),
            ("edge 0", d["edge_count"] == 0)]


def t_pre_d2(ref):  # PrecipitateTests.swift:620-638
    objs = [_hand_obj(ref, 1, 10, 3, False), _hand_obj(ref, 2, 20, 4, False), _hand_obj(ref, 3, 999, 5, True)]
    d = ref.density(objs, {1, 2, 3}, 1000, 0.01, "nm")
    return [("accepted 2", d["accepted_count"] == 2), ("edge 1", d["edge_count"] == 1),
            ("density 2/(1000*1e-4)", _close(d["areal_density"], 2.0 / (1000 * 0.01 * 0.01), 1e-9)),
            ("meanLength 15", _close(d["mean_length"], 15, 1e-6)), ("medianLength 15", _close(d["median_length"], 15, 1e-6))]


def x_other_label_in_area(ref):  # refuter §7: a label in no role set (Thronsen label 4) IS analysed
    labels = [0] * 16
    labels[5] = 1; labels[10] = 4; labels[11] = 4
    r = ref.class_objects(labels, 4, 4, {1}, {0}, set(), None, None)
    return [("label-4 pixels are 'other'", r["other_pixels"] == 2), ("analysed 16 (label 4 counted)", r["analysed_pixels"] == 16)]


def x_all_not_indexed(ref):  # SEG:368, :377 and STA:124 -- analysed 0 refuses fraction AND density
    r = _run(ref, [-1] * 9, 3, 3, _roles([1]), 2.0, "nm")
    c = _cls(r, 1)
    return [("analysed 0", r["analysed_pixels"] == 0), ("areaFraction nil", c["area_fraction"] is None),
            ("density nil despite px", c["density"]["areal_density"] is None), ("notIndexedFraction 1", r["not_indexed_fraction"] == 1)]


def x_vertical_is_plus_90(ref):  # SEG:65 fold (-90, 90] and SEG:506-507: vertical bar reads +90, never -90
    labels = [0] * 25
    for rr in range(1, 4):
        labels[rr * 5 + 2] = 1
    o = _cls(_run(ref, labels, 5, 5, _roles([1])), 1)["objects"][0]
    return [("orientation +90", _close(o.orientation_degrees, 90, 1e-6)), ("length 3", _close(o.length_px, 3, 1e-6))]


def x_antidiagonal_sign(ref):  # SEG:65-69: row falls as col rises -> negative angle (counter-clockwise on screen)
    labels = [0] * 36
    for k in range(1, 5):
        labels[(5 - k) * 6 + k] = 1
    o = _cls(_run(ref, labels, 6, 6, _roles([1])), 1)["objects"][0]
    return [("orientation -45", _close(o.orientation_degrees, -45, 1e-4))]


def x_tie_break_and_ids(ref):  # SEG:346-360: equal areas ordered by first pixel index; ids run across classes
    labels = [0] * 25
    labels[18] = 1; labels[6] = 1; labels[8] = 2
    r = _run(ref, labels, 5, 5, _roles([1, 2]))
    one, two = _cls(r, 1), _cls(r, 2)
    return [("class1 order [6],[18]", [o.pixel_indices for o in one["objects"]] == [[6], [18]]),
            ("ids 1,2 then 3", [o.id for o in one["objects"]] == [1, 2] and two["objects"][0].id == 3)]


def x_empty_map(ref):  # SEG:377 total 0 -> notIndexedFraction nil; SEG:368 analysed 0 -> areaFraction nil
    r = _run(ref, [], 0, 0, _roles([1]), 1.0, "nm")
    c = _cls(r, 1)
    return [("notIndexedFraction nil", r["not_indexed_fraction"] is None), ("areaFraction nil", c["area_fraction"] is None)]


CASES = [
    ("T-ANA-1 straight needle", t_ana_1), ("T-ANA-4 diagonal needle", t_ana_4),
    ("T-ANA-2 bent corner chain", t_ana_2), ("T-ANA-3 touchesEdge four sides", t_ana_3),
    ("T-ANA-6 corner-adjacent classes", t_ana_6), ("T-ANA-5 pixelSize refusal", t_ana_5),
    ("T-ANA-7a all-matrix map", t_ana_7a), ("T-ANA-7b single pixel", t_ana_7b),
    ("T-PMO-1 12x9 objects/edge", t_pmo_1), ("T-PMO-2 8-connectivity 4x4", t_pmo_2),
    ("T-PMO-3 not-indexed area", t_pmo_3), ("T-PMO-4 density at 7.4829 nm", t_pmo_4),
    ("T-PMO-5 absent class", t_pmo_5),
    ("T-WIR-b bridge 6x6", t_wir_b), ("T-WIR-d uncalibrated", t_wir_d), ("T-WIR-c calibrated", t_wir_c),
    ("T-PRE-D1 density refuses", t_pre_d1), ("T-PRE-D2 density with px", t_pre_d2),
    ("X-1 unassigned label analysed", x_other_label_in_area), ("X-2 all not-indexed", x_all_not_indexed),
    ("X-3 vertical is +90", x_vertical_is_plus_90), ("X-4 anti-diagonal -45", x_antidiagonal_sign),
    ("X-5 tie-break + ids", x_tie_break_and_ids), ("X-6 empty 0x0 map", x_empty_map),
]


def run_selftest(ref, quiet=False):
    failed = []
    for name, fn in CASES:
        try:
            checks = fn(ref)
            bad = [d for d, ok in checks if not ok]
        except Exception as exc:  # a mutant may crash; that is a FAIL, not a harness error
            checks, bad = [], ["raised %s: %s" % (type(exc).__name__, exc)]
        if bad:
            failed.append(name)
        if not quiet:
            print("%s  %-34s %s" % ("FAIL" if bad else "PASS", name,
                                    ("[" + "; ".join(bad) + "]") if bad else "(%d checks)" % len(checks)))
    return failed


# One-token mutants of the reference. expect="killed": at least one T- case must FAIL.
# expect="gap": the mutant is expected to survive every T- case (a definition no Swift test pins).
MUTANTS = [
    ("M1 8- -> 4-connectivity", "for dy, dx in NEIGHBOURS_8:", "for dy, dx in NEIGHBOURS_4:", "killed"),
    ("M2 length drops the +1", "u_max - u_min + F(1)", "u_max - u_min + F(0)", "killed"),
    ("M3 width drops the +1", "v_max - v_min + F(1)", "v_max - v_min + F(0)", "killed"),
    ("M4 edge rule drops bottom row", "row == height - 1", "row == height + 1", "killed"),
    ("M5 edge rule drops right column", "col == width - 1", "col == width + 1", "killed"),
    ("M6 edge rule off-by-one top (M9-like)", "if row == 0 or", "if row == 1 or", "killed"),
    ("M7 orientation sign flipped", "np.arctan2(vy, vx)", "np.arctan2(-vy, vx)", "killed"),
    ("M8 not-indexed kept in area", "analysed = total - not_indexed_pixels", "analysed = total - 0", "killed"),
    ("M9 refusal lets negative px through", "and pixel_size > 0", "and pixel_size != 0", "killed"),
    ("M10 edge objects counted", "if not o.touches_edge]", "if o.touches_edge or True]", "killed"),
    ("M11 median takes upper element", "(lengths[n // 2 - 1] + lengths[n // 2]) / 2", "lengths[n // 2]", "killed"),
    ("M12 classes merged (>= label)", "mask = [lab == label", "mask = [lab >= label", "killed"),
    ("M13 half-max 0.5 -> 1.5 (collapse)", "half = F(0.5) * peak", "half = F(1.5) * peak", "killed"),
    ("M14 tie-break reversed", "(-o.area, o.pixel_indices[0])", "(-o.area, -o.pixel_indices[0])", "gap"),
    ("M15 other labels leave the area (multi-token, gateD-2026-09-21 denominator mutant)", "analysed = total - not_indexed_pixels", "analysed = total - not_indexed_pixels - (total - not_indexed_pixels - matrix_pixels - sum(1 for x in labels if x in precipitate))", "killed"),
]


def run_mutations():
    src = open(__file__, encoding="utf-8").read()
    head, tail = src.split(MARKER, 1)
    ok_all = True
    print("mutant                                   expect   T-cases failed / X-cases failed   verdict")
    for name, old, new, expect in MUTANTS:
        if head.count(old) != 1:
            print("%-40s token %r occurs %d times in the reference -- harness error" % (name, old, head.count(old)))
            ok_all = False
            continue
        mod = types.ModuleType("mutant")
        mod.__dict__["__file__"] = __file__
        exec(compile(head.replace(old, new) + MARKER + tail, "<%s>" % name, "exec"), mod.__dict__)
        failed = run_selftest(mod, quiet=True)
        t_failed = [f.split()[0] for f in failed if f.startswith("T-")]
        x_failed = [f.split()[0] for f in failed if f.startswith("X-")]
        if expect == "killed":
            good = bool(t_failed)
            verdict = "KILLED" if good else "SURVIVED (unexpected)"
        else:
            good = not t_failed
            verdict = ("GAP confirmed: no T- case fails" + ("; caught only by " + ",".join(x_failed) if x_failed else "; no case at all")) \
                if good else "killed by a T- case (gap claim wrong)"
        ok_all &= good
        print("%-40s %-7s  %-18s / %-14s  %s" % (name, expect, ",".join(t_failed) or "-", ",".join(x_failed) or "-", verdict))
    return ok_all


def run_crosscheck(seed=20260923, maps=200):
    """Independent labeller (scipy.ndimage.label, 3x3 structure) and float64 eigen-decomposition."""
    try:
        from scipy import ndimage
    except ImportError:
        print("crosscheck: scipy not available -- skipped")
        return True
    rng = np.random.default_rng(seed)
    this = sys.modules[__name__]
    n_obj = n_axis = 0
    worst_len = worst_ang = 0.0
    problems = []
    for m in range(maps):
        h, w = int(rng.integers(1, 17)), int(rng.integers(1, 17))
        labels = rng.choice([-1, 0, 0, 0, 1, 1, 2, 3], size=h * w).tolist()
        r = class_objects(labels, w, h, {1, 2}, {0}, {-1}, None, None)
        arr = np.array(labels).reshape(h, w)
        for c in r["classes"]:
            lab, count = ndimage.label(arr == c["label"], structure=np.ones((3, 3), dtype=int))
            ours = sorted(tuple(o.pixel_indices) for o in c["objects"])
            theirs = sorted(tuple(np.flatnonzero(lab.ravel() == k).tolist()) for k in range(1, count + 1))
            if ours != theirs:
                problems.append("map %d class %d: partition differs from scipy" % (m, c["label"]))
            for o in c["objects"]:
                n_obj += 1
                rows = np.array(o.pixel_indices) // w
                cols = np.array(o.pixel_indices) % w
                edge = bool((rows == 0).any() or (rows == h - 1).any() or (cols == 0).any() or (cols == w - 1).any())
                if edge != o.touches_edge:
                    problems.append("map %d object %d: touchesEdge differs" % (m, o.id))
                if abs(cols.mean() - o.centroid_x) > 1e-4 or abs(rows.mean() - o.centroid_y) > 1e-4:
                    problems.append("map %d object %d: centroid differs" % (m, o.id))
                cov = np.cov(np.vstack([cols, rows]).astype(float), bias=True) if o.area > 1 else np.zeros((2, 2))
                evals, evecs = np.linalg.eigh(cov)
                if evals[1] - evals[0] < 1e-3:   # isotropic: axis undefined, skip the angle comparison
                    continue
                n_axis += 1
                vx, vy = evecs[0, 1], evecs[1, 1]
                ang = math.degrees(math.atan2(vy, vx))
                while ang <= -90: ang += 180
                while ang > 90: ang -= 180
                d_ang = abs(ang - float(o.orientation_degrees)); d_ang = min(d_ang, 180 - d_ang)
                a = math.radians(ang)
                u = (cols - cols.mean()) * math.cos(a) + (rows - rows.mean()) * math.sin(a)
                span = u.max() - u.min()
                length64 = span + 1 if span > 0 else 1.0
                worst_ang = max(worst_ang, d_ang)
                worst_len = max(worst_len, abs(length64 - float(o.length_px)))
    print("crosscheck: %d random maps, %d objects vs scipy.ndimage.label(3x3) partitions + touchesEdge + centroid; "
          "%d anisotropic objects vs float64 eigh: worst |d orientation| %.2e deg, worst |d length| %.2e px"
          % (maps, n_obj, n_axis, worst_ang, worst_len))
    ok = not problems and worst_ang < 1e-2 and worst_len < 1e-3
    for p in problems[:10]:
        print("  " + p)
    print("crosscheck: %s" % ("PASS" if ok else "FAIL"))
    return ok


def main(argv):
    mode = argv[1] if len(argv) > 1 else "all"
    this = sys.modules[__name__]
    ok = True
    if mode in ("selftest", "all"):
        failed = run_selftest(this)
        print("selftest: %d cases, %d PASS, %d FAIL" % (len(CASES), len(CASES) - len(failed), len(failed)))
        ok &= not failed
    if mode in ("mutate", "all"):
        m_ok = run_mutations()
        print("mutate: %s" % ("every mutant behaved as expected" if m_ok else "UNEXPECTED mutant outcome"))
        ok &= m_ok
    if mode in ("crosscheck", "all"):
        ok &= run_crosscheck()
    if mode not in ("selftest", "mutate", "crosscheck", "all"):
        print(__doc__)
        return 2
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
