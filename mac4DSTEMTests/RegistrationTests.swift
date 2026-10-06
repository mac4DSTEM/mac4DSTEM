//
//  RegistrationTests.swift
//  v5.0 WP3 lane M (prediction M1, second half): the registration record M2, mask transport by area overlap,
//  pooling, and the simulator's planted transform (`truth_edx_regmismatch.json`, committed as
//  Fixtures/edx-regmismatch-m1.json by tools/demo-edx/dump_m1_fixture.py). Each test names the mutation it
//  catches; each was broken once.
//

import XCTest
import DSTEMCore

final class RegistrationTests: XCTestCase {

    private static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    // MARK: - Hand-computed transports

    /// 4x4 scan -> 2x2 spectrum grid: bin 2, mirrored in x (u = -x/2 + 5/4, v = y/2 - 1/4).
    private let mirror = RegistrationRecordM2(matrix: [-0.5, 0, 1.25, 0, 0.5, -0.25], source: .typed,
                                              scanWidth: 4, scanHeight: 4, spectrumWidth: 2, spectrumHeight: 2)

    /// P3. Scan pixels x=0,1 land on spectrum column 1 (the mirror), y=0,1 on row 0. The mask is the whole
    /// block {0,1}x{0,1} (spectrum pixel (1,0) fully) plus (2,2), (3,2), (2,3) of the block {2,3}x{2,3}
    /// (spectrum pixel (0,1), 3 of 4 scan pixels = overlap 0.75). Row-major v*2+u: [F, T, T, F]; reading the
    /// map without its reflection gives [T, F, F, T].
    /// Mutations: flip the sign of `a00` in `transport` (u = +x/2 ...) — red; threshold 0.5 -> 0.8 — red.
    func testAReflectionTransportEqualsTheHandComputedMask() throws {
        XCTAssertTrue(mirror.isReflection)
        XCTAssertEqual(mirror.determinant, -0.25, accuracy: 1e-15)
        var scan = [Bool](repeating: false, count: 16)
        for (x, y) in [(0, 0), (1, 0), (0, 1), (1, 1), (2, 2), (3, 2), (2, 3)] { scan[y * 4 + x] = true }
        let t = try MaskTransport.transport(mask: scan, registration: mirror)
        let (mask, report) = MaskTransport.region(t)
        XCTAssertEqual(mask, [false, true, true, false])
        XCTAssertEqual(t.overlap[0][1], 1, accuracy: 1e-12)
        XCTAssertEqual(t.overlap[0][2], 0.75, accuracy: 1e-12)
        XCTAssertEqual(report.pixelsIncluded, 2)
        XCTAssertEqual(report.partialIncluded, 1, "(0,1) is covered at 0.75")
        XCTAssertEqual(report.edgeIncluded, 0)
        XCTAssertEqual(report.touchedExcluded, 0)
        XCTAssertEqual(report.regionArea, 1.75, accuracy: 1e-12)
        XCTAssertEqual(report.retainedFraction, 1, accuracy: 1e-12)
        XCTAssertEqual(report.outsideFraction, 0, accuracy: 1e-12)
    }

    /// A quarter-covered spectrum pixel is dropped and counted as eroded.
    /// Mutation: include `overlap > 0` instead of `>= 1/2` — red.
    func testALessThanHalfCoveredPixelIsDroppedAndReported() throws {
        var scan = [Bool](repeating: false, count: 16)
        scan[2 * 4 + 2] = true                                     // (2,2): 1/4 of spectrum pixel (0,1)
        let t = try MaskTransport.transport(mask: scan, registration: mirror)
        let (mask, report) = MaskTransport.region(t)
        XCTAssertEqual(mask, [false, false, false, false])
        XCTAssertEqual(report.touchedExcluded, 1)
        XCTAssertEqual(t.overlap[0][2], 0.25, accuracy: 1e-12)
    }

    /// A half-pixel shift: one scan pixel straddles two spectrum pixels at exactly 1/2 each; the tie is IN
    /// (a rounding error in the overlap must not flip it).
    /// Mutation: membership `overlap > 1/2` instead of `>= 1/2` (in `TransportedLabels.mask`) — red.
    func testATieAtExactlyHalfIsIncludedOnBothSides() throws {
        let shift = RegistrationRecordM2(matrix: [1, 0, 0.5, 0, 1, 0], source: .typed,
                                         scanWidth: 4, scanHeight: 1, spectrumWidth: 5, spectrumHeight: 1)
        let t = try MaskTransport.transport(mask: [false, true, false, false], registration: shift)
        XCTAssertEqual(t.overlap[0].map { ($0 * 100).rounded() / 100 }, [0, 0.5, 0.5, 0, 0])
        XCTAssertEqual(MaskTransport.region(t).mask, [false, true, true, false, false])
    }

    /// P4. The identity changes nothing: the mask, no partial pixels, no edge, nothing outside.
    /// Mutation: swap x and y in the corner map — red on a non-square grid.
    func testTheIdentityTransportIsANoOp() throws {
        let identity = RegistrationRecordM2.identity(width: 7, height: 5)
        XCTAssertEqual(identity.source, .identityFromOneRun)
        var scan = [Bool](repeating: false, count: 35)
        for i in [0, 3, 4, 8, 13, 20, 21, 34] { scan[i] = true }
        let t = try MaskTransport.transport(mask: scan, registration: identity)
        let (mask, report) = MaskTransport.region(t)
        XCTAssertEqual(mask, scan)
        XCTAssertEqual(report.partialIncluded, 0)
        XCTAssertEqual(report.edgeIncluded, 0)
        XCTAssertEqual(report.outsideFraction, 0, accuracy: 1e-12)
        XCTAssertEqual(report.pixelsIncluded, 8)
        XCTAssertEqual(t.edgePixels.filter { $0 }.count, 0)
    }

    /// A rotation by 90 degrees is a non-axis-aligned-looking map the clipper must handle: (x, y) -> (y, -x + 3)
    /// puts scan pixel (x, y) on spectrum pixel (y, 3 - x) exactly.
    /// Mutation: clip against the bounding box instead of the polygon — still red only for shears, so this
    /// pins the rotation; swap the two clip planes' directions — red.
    func testARightAngleRotationLandsOnTheExpectedPixel() throws {
        let rot = RegistrationRecordM2(matrix: [0, 1, 0, -1, 0, 3], source: .typed,
                                       scanWidth: 4, scanHeight: 3, spectrumWidth: 3, spectrumHeight: 4)
        var scan = [Bool](repeating: false, count: 12)
        scan[1 * 4 + 3] = true                                      // (x=3, y=1) -> (u=1, v=0)
        let mask = MaskTransport.region(try MaskTransport.transport(mask: scan, registration: rot)).mask
        XCTAssertEqual(mask.firstIndex(of: true), 0 * 3 + 1)
        XCTAssertEqual(mask.filter { $0 }.count, 1)
    }

    /// A singular registration and a wrong-size mask are refused by name.
    /// Mutation: drop the invertibility guard — red.
    func testASingularRegistrationIsRefused() {
        let flat = RegistrationRecordM2(matrix: [1, 0, 0, 1, 0, 0], source: .typed,
                                        scanWidth: 2, scanHeight: 2, spectrumWidth: 2, spectrumHeight: 2)
        XCTAssertThrowsError(try MaskTransport.transport(mask: [true, false, false, true], registration: flat))
        XCTAssertThrowsError(try MaskTransport.transport(mask: [true], registration: .identity(width: 2, height: 2)))
    }

    /// The record round-trips byte for byte and names its source.
    /// Mutation: drop `.sortedKeys` or `source` from the encoding — red.
    func testTheRecordRoundTripsByteIdentically() throws {
        let r = RegistrationRecordM2(matrix: [-0.5, 0, 32.75, 0, 0.5, 0.75], source: .simulatorTruth,
                                     sourceNote: "truth_edx_regmismatch.json",
                                     scanWidth: 64, scanHeight: 48, spectrumWidth: 32, spectrumHeight: 24)
        let back = try XCTUnwrap(RegistrationRecordM2.decode(r.canonicalJSON))
        XCTAssertEqual(back, r)
        XCTAssertEqual(back.canonicalJSON, r.canonicalJSON)
        XCTAssertTrue(r.canonicalJSON.contains("\"source\":\"simulatorTruth\""))
        let inv = try XCTUnwrap(r.applyInverse(u: 0, v: 0))
        XCTAssertEqual(inv.x, 65.5, accuracy: 1e-12)
        XCTAssertEqual(inv.y, -1.5, accuracy: 1e-12)
        XCTAssertNil(RegistrationRecordM2.decode("{\"matrix\":[1,2]}"))
    }

    /// P6. Landmarks fit the planted affine exactly, tolerate 0.1 px of noise, and collinear points give nil.
    /// Mutation: swap the u and v right-hand sides — red.
    func testLandmarksRecoverThePlantedTransform() throws {
        let planted = RegistrationRecordM2(matrix: [-0.5, 0, 32.75, 0, 0.5, 0.75], source: .simulatorTruth,
                                           scanWidth: 64, scanHeight: 48, spectrumWidth: 32, spectrumHeight: 24)
        let pts: [(Double, Double)] = [(2, 3), (60, 5), (10, 40), (55, 45), (30, 20)]
        let exact = pts.map { (scan: (x: $0.0, y: $0.1), spectrum: planted.apply(x: $0.0, y: $0.1)) }
        let fit = try XCTUnwrap(RegistrationRecordM2.fit(landmarks: exact, scanWidth: 64, scanHeight: 48,
                                                        spectrumWidth: 32, spectrumHeight: 24))
        for (a, b) in zip(fit.matrix, planted.matrix) { XCTAssertEqual(a, b, accuracy: 1e-9) }
        XCTAssertEqual(fit.source, .typed)
        let noise: [(Double, Double)] = [(0.1, -0.1), (-0.1, 0.1), (0.05, 0.1), (-0.1, -0.05), (0.1, 0.1)]
        let noisy = zip(exact, noise).map { (scan: $0.scan, spectrum: ($0.spectrum.u + $1.0, $0.spectrum.v + $1.1)) }
        let nf = try XCTUnwrap(RegistrationRecordM2.fit(landmarks: noisy, scanWidth: 64, scanHeight: 48,
                                                       spectrumWidth: 32, spectrumHeight: 24))
        for (x, y) in [(0.0, 0.0), (63.0, 0.0), (0.0, 47.0), (63.0, 47.0)] {
            let (u0, v0) = planted.apply(x: x, y: y), (u1, v1) = nf.apply(x: x, y: y)
            XCTAssertLessThan(abs(u1 - u0), 0.5); XCTAssertLessThan(abs(v1 - v0), 0.5)
        }
        let line = (0..<4).map { (scan: (x: Double($0), y: 0.0), spectrum: (u: Double($0), v: 0.0)) }
        XCTAssertNil(RegistrationRecordM2.fit(landmarks: line, scanWidth: 4, scanHeight: 4, spectrumWidth: 4, spectrumHeight: 4))
    }

    // MARK: - Pooling

    /// The count-exact pool: whole pixels summed, integer counts preserved, the pool carries its source's badge
    /// and its own raggedness. Spectrum grid 2x2 x 3 channels with distinct counts per pixel, on the mirror map.
    /// Mutations: weight the pool by overlap (counts then non-integer / unequal) — red; drop `validation` — red.
    func testAPoolIsTheExactSumOfWholePixelsAndInheritsTheBadge() throws {
        var counts = [UInt32]()
        for p in 0..<4 { for c in 0..<3 { counts.append(UInt32(10 * (p + 1) + c)) } }   // pixel p: 10(p+1)+c
        let image = DenseSpectrumImage(ny: 2, nx: 2, channels: 3, counts: counts)
        var scan = [Bool](repeating: false, count: 16)
        for (x, y) in [(0, 0), (1, 0), (0, 1), (1, 1), (2, 2), (3, 2), (2, 3)] { scan[y * 4 + x] = true }
        let pool = try PoolBuilder.pool(image: image, scanMask: scan, registration: mirror, name: "Q",
                                        kind: "phase", validation: PoolBuilder.phaseMapValidation)
        // Included pixels p = v*2+u: (u=1,v=0) is p = 1 and (u=0,v=1) is p = 2, so (20 + c) + (30 + c).
        XCTAssertEqual(pool.mask, [false, true, true, false])
        XCTAssertEqual(pool.counts, [UInt64(20 + 30), UInt64(21 + 31), UInt64(22 + 32)])
        XCTAssertEqual(pool.pixelCount, 2)
        XCTAssertEqual(pool.partialPixels, 1)
        XCTAssertEqual(pool.edgePixels, 0)
        XCTAssertEqual(pool.footprintArea, 1.75, accuracy: 1e-12, "7 scan pixels x 1/4")
        XCTAssertEqual(pool.retainedFraction, 1, accuracy: 1e-12)
        XCTAssertEqual(pool.purity, 0.875, accuracy: 1e-12, "(1 + 0.75) / 2 pixels")
        XCTAssertEqual(pool.validation, "none")
        XCTAssertTrue(pool.isUnvalidated)
        let drawn = try PoolBuilder.pool(image: image, scanMask: scan, registration: mirror, name: "Drawn 1", kind: "drawn")
        XCTAssertNil(drawn.validation)
        XCTAssertFalse(drawn.isUnvalidated)
        // A registration onto another grid than the image's is refused.
        let wrong = RegistrationRecordM2.identity(width: 3, height: 3)
        XCTAssertThrowsError(try PoolBuilder.pool(image: image, scanMask: [Bool](repeating: true, count: 9),
                                                  registration: wrong, name: "x", kind: "drawn"))
    }

    // MARK: - The simulator (prediction M1)

    private struct M1Fixture {
        let registration: RegistrationRecordM2
        let names: [String]
        let labels4D: [Int]
        let group: [Int]
        let outside: [Double]
        let expected: [Double]
        let realised: [Int]
    }

    private func fixture() throws -> M1Fixture {
        let data = try Data(contentsOf: Self.dir.appendingPathComponent("Fixtures/edx-regmismatch-m1.json"))
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let affine = try XCTUnwrap(j["affine_2x3"] as? [[Double]])
        let scan = try XCTUnwrap(j["scan"] as? [Int]), eds = try XCTUnwrap(j["eds"] as? [Int])
        return M1Fixture(
            registration: RegistrationRecordM2(matrix: affine[0] + affine[1], source: .simulatorTruth,
                                               sourceNote: "truth_edx_regmismatch.json",
                                               scanWidth: scan[0], scanHeight: scan[1], spectrumWidth: eds[0], spectrumHeight: eds[1]),
            names: try XCTUnwrap(j["phase_names"] as? [String]),
            labels4D: try XCTUnwrap(j["labels_4d"] as? String).map { Int(String($0))! },
            group: try XCTUnwrap(j["eds_group_map"] as? [Int]),
            outside: try XCTUnwrap(j["eds_outside_fraction"] as? [Double]),
            expected: try XCTUnwrap(j["eds_expected_counts"] as? [Double]),
            realised: try XCTUnwrap(j["realised_total_eds_counts_by_group"] as? [Int]))
    }

    /// P5, the membership half (always runs): the planted affine, applied to the truth's 4D phase masks, gives
    /// the generator's EDS group on every pixel the 4D scan fully covers EXCEPT the pixels tied between two phases
    /// at 1/2 : 1/2, which are unlabelled by the tie rule (the generator breaks them to the lowest index); the 78
    /// edge pixels are flagged (23 half outside, 55 wholly outside); wholly-outside pixels are never labelled.
    /// Mutations: use the un-mirrored matrix (a00 = +0.5) — the agreement check goes red; compare outside
    /// fraction against 0.25 — the edge count goes red; restore the lowest-index tie-break — the tie count goes red.
    func testThePlantedTransformRecoversTheGeneratorsGroupsAndFlagsTheEdge() throws {
        let f = try fixture()
        let t = try MaskTransport.transport(labels: f.labels4D, classCount: f.names.count, registration: f.registration)
        let labels = t.labels, tied = t.tiedPixels
        let edge = t.edgePixels
        XCTAssertEqual(edge.filter { $0 }.count, 78, "the generator's outside_fraction > 0 count")
        var disagree = 0, tiedAgreeingWithTruthTieBreak = 0
        for p in 0..<labels.count {
            XCTAssertEqual(1 - t.insideGrid[p], f.outside[p], accuracy: 1e-9, "outside fraction at pixel \(p)")
            if tied[p] {
                XCTAssertEqual(labels[p], -1, "a tied pixel is unlabelled, pixel \(p)")
                if f.outside[p] < 1 { tiedAgreeingWithTruthTieBreak += 1 }
            } else if f.outside[p] < 1, labels[p] != f.group[p] {
                disagree += 1
            }
            if f.outside[p] == 1 { XCTAssertEqual(labels[p], -1, "pixel \(p) is wholly outside the 4D scan") }
        }
        XCTAssertEqual(disagree, 0, "every labelled pixel agrees with the generator's group")
        XCTAssertEqual((0..<labels.count).filter { f.outside[$0] == 0.5 }.count, 23)
        XCTAssertEqual((0..<labels.count).filter { f.outside[$0] == 1 }.count, 55)
        XCTAssertEqual(t.tiedExcluded, tiedAgreeingWithTruthTieBreak, "wholly-outside pixels carry no overlap, so none is tied")
        XCTAssertEqual(t.tiedExcluded, 41, "pixels excluded as ties (recorded from the run, round 3 report)")
    }

    /// Tie rule (b), hand case: scan columns split 1 : 1 over one spectrum pixel (each class overlaps it at exactly
    /// 1/2) is unlabelled and counted; a 3 : 1 split is labelled with the majority.
    /// Mutation: restore the lowest-index tie-break (label the first of the tied classes) — red.
    func testATieBetweenPhasesIsUnlabelledAndCounted() throws {
        let bin = RegistrationRecordM2(matrix: [0.5, 0, -0.25, 0, 0.5, -0.25], source: .typed,
                                       scanWidth: 2, scanHeight: 2, spectrumWidth: 1, spectrumHeight: 1)
        let tie = try MaskTransport.transport(labels: [0, 1, 0, 1], classCount: 2, registration: bin)
        XCTAssertEqual(tie.labels, [-1])
        XCTAssertEqual(tie.tiedExcluded, 1)
        let major = try MaskTransport.transport(labels: [0, 1, 1, 1], classCount: 2, registration: bin)
        XCTAssertEqual(major.labels, [1])
        XCTAssertEqual(major.tiedExcluded, 0)
    }

    /// Pools from a label map carry their purity: a 3 : 1 pixel pools with the majority at purity 3/4, retained 1.
    /// Mutation: `purity: 1` in `PoolBuilder.pools` — red.
    func testLabelPoolsCarryFootprintAndPurity() throws {
        let bin = RegistrationRecordM2(matrix: [0.5, 0, -0.25, 0, 0.5, -0.25], source: .typed,
                                       scanWidth: 2, scanHeight: 2, spectrumWidth: 1, spectrumHeight: 1)
        let image = DenseSpectrumImage(ny: 1, nx: 1, channels: 1, counts: [7])
        let t = try MaskTransport.transport(labels: [0, 1, 1, 1], classCount: 2, registration: bin)
        let pools = try PoolBuilder.pools(image: image, transported: t, names: ["a", "b"], kind: "phase", validation: "none")
        XCTAssertEqual(pools[1].counts, [7])
        XCTAssertEqual(pools[1].purity, 0.75, accuracy: 1e-12)
        XCTAssertEqual(pools[1].retainedFraction, 1, accuracy: 1e-12)
        XCTAssertEqual(pools[1].footprintArea, 0.75, accuracy: 1e-12)
        XCTAssertEqual(pools[0].pixelCount, 0)
    }

    /// A pathological matrix is refused, not trapped on in `Int()`.
    /// Mutation: drop the entry guard and the Double clamp — the test process traps.
    func testAnAbsurdMatrixThrows() {
        let huge = RegistrationRecordM2(matrix: [1e300, 0, 0, 0, 1, 0], source: .typed,
                                        scanWidth: 2, scanHeight: 2, spectrumWidth: 2, spectrumHeight: 2)
        XCTAssertThrowsError(try MaskTransport.transport(mask: [true, true, true, true], registration: huge))
        let far = RegistrationRecordM2(matrix: [1, 0, 1e8, 0, 1, 0], source: .typed,
                                       scanWidth: 2, scanHeight: 2, spectrumWidth: 2, spectrumHeight: 2)
        XCTAssertEqual(MaskTransport.region(try MaskTransport.transport(mask: [true, true, true, true], registration: far)).mask,
                       [false, false, false, false])
    }

    /// Round 3 (Fable's Gate B): on a 2x-binned grid every boundary pixel sits at exactly 1/2, so membership must not
    /// follow float noise. The planted affine with its u-offset moved by +-1e-7 px, and the affine that
    /// `fit(landmarks:)` returns from exact landmarks (error ~1e-14), give the unperturbed labels.
    /// Mutation: `TransportedLabels.tolerance` 1e-6 -> 1e-9 — red (28 of 768 labels flip at +1e-7).
    func testLabelsDoNotFollowFloatNoise() throws {
        let f = try fixture()
        let base = try MaskTransport.transport(labels: f.labels4D, classCount: f.names.count, registration: f.registration).labels
        for dU in [1e-7, -1e-7, 1e-12] {
            var m = f.registration.matrix; m[2] += dU
            let r = RegistrationRecordM2(matrix: m, source: .typed, scanWidth: 64, scanHeight: 48, spectrumWidth: 32, spectrumHeight: 24)
            let moved = try MaskTransport.transport(labels: f.labels4D, classCount: f.names.count, registration: r).labels
            XCTAssertEqual(moved, base, "u-offset \(dU) changed \(zip(moved, base).filter { $0 != $1 }.count) labels")
        }
        let pts: [(Double, Double)] = [(2, 3), (60, 5), (10, 40), (55, 45), (30, 20)]
        let landmarks = pts.map { (scan: (x: $0.0, y: $0.1), spectrum: f.registration.apply(x: $0.0, y: $0.1)) }
        let fitted = try XCTUnwrap(RegistrationRecordM2.fit(landmarks: landmarks, scanWidth: 64, scanHeight: 48,
                                                           spectrumWidth: 32, spectrumHeight: 24))
        let viaFit = try MaskTransport.transport(labels: f.labels4D, classCount: f.names.count, registration: fitted).labels
        XCTAssertEqual(viaFit, base, "the fitted affine must label like the planted one")
    }

    /// P5, the counts half (the file is the generator's seed-42 `--regmismatch` output): pools from the transported masks over the real simulated EDS cube
    /// (`References/demo-edx/AlMgSi_4D_EDX_regmismatch.dm4`, skipped when absent) match the generator's expected
    /// counts, summed over exactly the pooled pixels, within exact-Poisson 2 sigma, per phase; and pooling is
    /// the partition (no pixel in two pools).
    /// Mutation: use the un-mirrored matrix — red by orders of magnitude.
    func testPerPhasePoolsFromTheSimulatedFileMatchTruthWithinPoisson() throws {
        let path = Self.dir.deletingLastPathComponent().appendingPathComponent("References/demo-edx/AlMgSi_4D_EDX_regmismatch.dm4").path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path), "References/demo-edx not generated")
        let f = try fixture()
        let objects = try DM4Experiment.list(path: path)
        let eds = try XCTUnwrap(objects.first { $0.role == .eds })
        XCTAssertEqual(eds.dimensions, [32, 24, 4096])
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(eds.dataOffset))
        let raw = try XCTUnwrap(try handle.read(upToCount: eds.dataByteCount))
        let cube: [UInt32] = raw.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        // File order is (channel, y, x), x fastest; the image wants (y, x, channel).
        let nx = 32, ny = 24, nch = 4096
        var dense = [UInt32](repeating: 0, count: nx * ny * nch)
        for c in 0..<nch { for p in 0..<(nx * ny) { dense[p * nch + c] = cube[c * nx * ny + p] } }
        let image = DenseSpectrumImage(ny: ny, nx: nx, channels: nch, counts: dense)

        let t = try MaskTransport.transport(labels: f.labels4D, classCount: f.names.count, registration: f.registration)
        let pools = try PoolBuilder.pools(image: image, transported: t, names: f.names, kind: "phase",
                                          validation: PoolBuilder.phaseMapValidation)
        XCTAssertEqual(pools.reduce(0) { $0 + $1.pixelCount }, 768 - 55 - t.tiedExcluded,
                       "every pixel but the 55 wholly outside and the tied ones is in one pool")
        for (g, pool) in pools.enumerated() {
            let expected = (0..<(nx * ny)).filter { pool.mask[$0] }.reduce(0.0) { $0 + f.expected[$1] }
            let observed = Double(pool.totalCounts)
            let z = (observed - expected) / expected.squareRoot()
            XCTContext.runActivity(named: "M1 pool \(f.names[g]): pixels \(pool.pixelCount), partial \(pool.partialPixels), edge \(pool.edgePixels), observed \(Int(observed)), expected \(String(format: "%.1f", expected)), z \(String(format: "%.2f", z))") { _ in }
            XCTAssertLessThan(abs(z), 2, "\(f.names[g]): \(observed) vs \(expected)")
            XCTAssertTrue(pool.isUnvalidated)
        }
        let masks = pools.map(\.mask)
        for p in 0..<(nx * ny) { XCTAssertLessThanOrEqual(masks.filter { $0[p] }.count, 1) }
    }

    /// The same chain on a synthetic scene that is always available: an 8x6 scan with four phases in vertical bands
    /// and 4x3 spectrum grid under the simulator's kind of transform (bin 2, mirror x, shift 1 px right/up), counts
    /// that depend only on the pixel's TRUE group. The pools equal the hand sum exactly.
    /// Mutation: un-mirror the matrix — red.
    func testASyntheticSceneRecoversItsPoolsExactly() throws {
        // Scan pixel x covers u in [4 - x/2, 4.5 - x/2]: x 8,9 -> u = 0 (past the scan's right edge: spectrum
        // column 0 is wholly outside the 4D grid), x 6,7 -> u = 1, x 4,5 -> u = 2, x 2,3 -> u = 3, and x 0,1 land
        // past the spectrum grid's left... right edge (u >= 3.5): outside the spectrum image. v = y/2 - 1/4 puts
        // y 0,1 on row 0, 2,3 on row 1, 4,5 on row 2.
        let reg = RegistrationRecordM2(matrix: [-0.5, 0, 4.25, 0, 0.5, -0.25], source: .simulatorTruth,
                                       scanWidth: 8, scanHeight: 6, spectrumWidth: 4, spectrumHeight: 3)
        // Scan phases by column: x 0-1 -> 0, 2-5 -> 1, 6-7 -> 2.
        let phase4D = (0..<48).map { i -> Int in let x = i % 8; return x < 2 ? 0 : (x < 6 ? 1 : 2) }
        // The EDS counts depend only on the TRUE group of the pixel: u = 1 is phase 2, u = 2, 3 phase 1, u = 0 saw
        // nothing of the scan. Channel 0 = 100 (g + 1), channel 1 = g.
        var counts = [UInt32](repeating: 0, count: 12 * 2)
        for p in 0..<12 {
            let u = p % 4
            guard u > 0 else { continue }
            let g = u == 1 ? 2 : 1
            counts[p * 2] = UInt32(100 * (g + 1)); counts[p * 2 + 1] = UInt32(g)
        }
        let image = DenseSpectrumImage(ny: 3, nx: 4, channels: 2, counts: counts)
        let t = try MaskTransport.transport(labels: phase4D, classCount: 3, registration: reg)
        let pools = try PoolBuilder.pools(image: image, transported: t, names: ["a", "b", "c"], kind: "phase", validation: "none")
        XCTAssertEqual(pools[0].pixelCount, 0, "phase 0 (x 0-1) lands past the spectrum grid")
        XCTAssertEqual(pools[0].outsideFraction, 1, accuracy: 1e-12)
        XCTAssertEqual(pools[2].counts, [UInt64(3 * 300), UInt64(3 * 2)], "column u = 1, three rows, group 2")
        XCTAssertEqual(pools[2].pixelCount, 3)
        XCTAssertEqual(pools[1].pixelCount, 6, "columns u = 2 and 3, three rows")
        XCTAssertEqual(pools[1].counts, [UInt64(6 * 200), UInt64(6 * 1)])
        XCTAssertEqual(t.edgePixels, (0..<12).map { $0 % 4 == 0 }, "column u = 0 is wholly outside the 4D scan")
    }
}
