// WHICH node `H5Reader.discoverPrimaryDataset` returns, that the pixels it
// then reads are that node's, and that the calibration anchor lands on it.
// Gate D 2026-09-04 (the rank-3 discovery class), enlarged by the Gate B
// refuter the same day: one case per mutation that survived the first
// harness. See reference.py for each fixture.
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

@main struct DatacubeDiscoveryHarness {
    static func main() async {
        guard CommandLine.arguments.count == 2 else { fail("usage: harness fixture-dir") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])

        func open(_ name: String) -> H5Reader {
            do { return try H5Reader(path: root.appendingPathComponent(name).path) }
            catch { fail("\(name): cannot open: \(error)") }
        }
        /// A refusal here is a FAIL line, never a trap (the first harness let
        /// a thrown error out of main, which exits 133 with no FAIL line).
        func discover(_ name: String) async -> (H5Reader, DatasetDescriptor) {
            let reader = open(name)
            do { return (reader, try await reader.discoverPrimaryDataset()) }
            catch { fail("\(name): unexpected refusal: \(error.localizedDescription)") }
        }
        /// The first pixel of one pattern: every fixture cube is its own flat
        /// index (plus an offset), so this is the node's identity, not just its shape.
        func firstPixel(_ reader: H5Reader, _ d: DatasetDescriptor, ry: Int, rx: Int) async -> Float {
            do {
                let pattern = try await reader.readPattern(LoadView(fullExtentOf: d), ry: ry, rx: rx)
                guard pattern.count == d.qy * d.qx else { fail("\(d.datasetPath): short pattern") }
                return pattern[0]
            } catch { fail("\(d.datasetPath): read failed: \(error)") }
        }
        enum Refusal { case noDataset, sessionSidecar }
        func expectRefusal(_ name: String, _ kind: Refusal) async -> H5Reader {
            let reader = open(name)
            do {
                let d = try await reader.discoverPrimaryDataset()
                fail("\(name): expected a refusal, got \(d.datasetPath) \(d.shape)")
            } catch H5Error.noDatasetFound {
                if kind != .noDataset { fail("\(name): refused as noDatasetFound, expected the sidecar sentence") }
            } catch H5Error.sessionSidecarOpened {
                if kind != .sessionSidecar { fail("\(name): refused as a session sidecar, expected noDatasetFound") }
            } catch { fail("\(name): unexpected error \(error)") }
            return reader
        }
        func expect(_ condition: Bool, _ message: String) { if !condition { fail(message) } }

        // e2 — the deep stored-rank-4 cube beats the shallow labelled stack; the
        // pixels and the calibration anchor are the cube's.
        do {
            let (reader, d) = await discover("e2_shallow_sibling.h5")
            expect(d.datasetPath == "/experiment/scan_1/datacube/data" && d.shape == [3, 4, 6, 5] && d.storedRank == 4,
                   "e2 chose \(d.datasetPath) \(d.shape) storedRank \(d.storedRank)")
            // flat index of (ry 1, rx 2, 0, 0) in (3,4,6,5) = (1*4 + 2) * 30
            expect(await firstPixel(reader, d, ry: 1, rx: 2) == 180, "e2 pixels are not the cube's")
            if let calibration = await reader.pixelCalibration() {
                fail("e2 calibration anchored on the wrong node: rSize \(String(describing: calibration.rSize))")
            }
            print("PASS: a deep rank-4 cube outranks a shallow labelled rank-3 stack; pixels and anchor are the cube's")
        }

        // e3 — the bullseye layout with the slice group sorting first.
        do {
            let (reader, d) = await discover("e3_bullseye_alphabet.h5")
            expect(d.datasetPath == "/4DSTEM_experiment/data/datacubes/polyAu/data" && d.shape == [2, 2, 8, 8],
                   "e3 chose \(d.datasetPath) \(d.shape)")
            expect(await firstPixel(reader, d, ry: 1, rx: 1) == 192, "e3 pixels are not the cube's")
            print("PASS: the legacy probe stack that sorts before the cube is not returned")
        }

        // Labelled non-cubes with nothing else in the file are refused, by each
        // signal on its own, at rank 3 and rank 4, at the file root, and in the
        // legacy v0.12 layout. After a refusal the calibration anchor is empty.
        do {
            _ = await expectRefusal("e4_results_no_attribute.h5", .noDataset)
            _ = await expectRefusal("x4a_rgba_units_only.h5", .noDataset)
            _ = await expectRefusal("x4b_rgba_name_only.h5", .noDataset)
            print("PASS: an RGBA map is refused by its `rgba8` units alone and by its `RGBA` dim alone")
            let reader = await expectRefusal("c3_labelled_stack_only.h5", .noDataset)
            if let stale = await reader.pixelCalibration() {
                fail("c3: after a refusal the anchor must be empty, got rSize \(String(describing: stale.rSize))")
            }
            _ = await expectRefusal("c5_labelled_rank4_only.h5", .noDataset)
            _ = await expectRefusal("x3_root_level_stack.h5", .noDataset)
            print("PASS: a `_labels_` stack is refused at rank 3, at rank 4 and at the file root; the anchor is cleared")
            _ = await expectRefusal("x2_legacy12_stack_only.h5", .noDataset)
            _ = await expectRefusal("x2v_legacy12_vlen_labels.h5", .noDataset)
            let (_, numeric) = await discover("x2n_legacy12_numeric_dim3.h5")
            expect(numeric.shape == [1, 8, 8, 3], "x2n \(numeric.shape)")
            print("PASS: a legacy v0.12 slice stack is refused by its string-typed dim3; a numeric dim3 is not a label (recorded residual)")
        }

        // The sidecar location guarantee, independent of the writer's stamps.
        do {
            _ = await expectRefusal("y1_sidecar_file_root_mark.h5", .sessionSidecar)
            _ = await expectRefusal("y2_sidecar_root_group_mark.h5", .sessionSidecar)
            let (_, d) = await discover("y3_sidecar_mark_and_cube_outside.h5")
            expect(d.datasetPath == "/datacube_root/datacube/data" && d.shape == [3, 4, 6, 5], "y3 \(d.datasetPath) \(d.shape)")
            _ = await expectRefusal("y4_file_root_mark_canonical_name.h5", .sessionSidecar)
            print("PASS: an unstamped node inside a marked sidecar is never a cube; a cube outside the marked subtree opens")
        }

        // x7 — a refused canonical node, then the real cube with its own calibration.
        do {
            let (reader, d) = await discover("x7_canonical_refused_then_cube.h5")
            expect(d.datasetPath == "/zz/real/cube/data" && d.shape == [3, 4, 6, 5], "x7 chose \(d.datasetPath) \(d.shape)")
            let calibration = await reader.pixelCalibration()
            expect(calibration?.rSize == 1.0 && calibration?.qSize == 0.5,
                   "x7 calibration is not the cube's: \(String(describing: calibration))")
            print("PASS: the rule applies at a canonical path too, and the calibration follows the cube")
        }

        // Which of two acceptable nodes wins is a contract: the first in path order.
        do {
            let (reader4, d4) = await discover("x6_two_rank4_cubes.h5")
            let pixel4 = await firstPixel(reader4, d4, ry: 0, rx: 0)
            expect(d4.datasetPath == "/aaa/cube/data" && pixel4 == 0, "x6 chose \(d4.datasetPath) pixel \(pixel4)")
            let (reader3, d3) = await discover("x8_two_rank3.h5")
            let pixel3 = await firstPixel(reader3, d3, ry: 0, rx: 0)
            expect(d3.datasetPath == "/aaa/one/data" && pixel3 == 0, "x8 chose \(d3.datasetPath) pixel \(pixel3)")
            let (reader11, x11) = await discover("x11_unlabelled_rank3_before_rank4.h5")
            let pixel11 = await firstPixel(reader11, x11, ry: 0, rx: 0)
            expect(x11.datasetPath == "/zzz/cube/data" && x11.storedRank == 4 && pixel11 == 10000,
                   "x11 chose \(x11.datasetPath) storedRank \(x11.storedRank) pixel \(pixel11) — the stored-rank preference is gone")
            let (_, x1) = await discover("x1_canonical_rank3_vs_deep_rank4.h5")
            expect(x1.datasetPath == "/4DSTEM_experiment/data/datacubes/datacube_0/data" && x1.shape == [1, 5, 6, 5],
                   "x1 chose \(x1.datasetPath) \(x1.shape)")
            let (reader12, x12) = await discover("x12_root_rank3_before_deep_rank4.h5")
            let pixel12 = await firstPixel(reader12, x12, ry: 0, rx: 0)
            expect(x12.datasetPath == "/zz/real/cube/data" && x12.storedRank == 4 && pixel12 == 10000,
                   "x12 chose \(x12.datasetPath) storedRank \(x12.storedRank) pixel \(pixel12)")
            let (_, x13) = await discover("x13_modern_cube_unrelated_string_sibling.h5")
            expect(x13.datasetPath == "/modern/cube/data" && x13.shape == [2, 3, 4, 5],
                   "x13 chose \(x13.datasetPath) \(x13.shape)")
            print("PASS: a stored rank-4 beats an earlier unlabelled rank-3; of two cubes the first wins; a canonical rank-3 is the file's own declaration and wins")
        }

        // x9 — the anchor's SHAPE half: the fitted-origin maps of a promoted rank-3
        // cube survive a later refused sibling of a different scan shape.
        do {
            let (reader, d) = await discover("x9_origin_maps_anchor.h5")
            expect(d.datasetPath == "/aaa_root/cube/data", "x9 chose \(d.datasetPath)")
            guard let maps = await reader.pixelCalibration()?.originMaps else { fail("x9: origin maps lost — the anchor shape is stale") }
            expect(maps.shape == [1, 7] && maps.fittedQX.first == 3.5, "x9 origin maps \(maps.shape) \(String(describing: maps.fittedQX.first))")
            print("PASS: origin maps survive a later described sibling (anchor path AND shape)")
        }

        // Controls — what must keep opening exactly as before, with the right calibration.
        do {
            let (_, c1) = await discover("c1_rank4_only.h5")
            expect(c1.datasetPath == "/lab/session/scan_07/cube/data" && c1.shape == [3, 4, 6, 5], "c1 \(c1.shape)")
            let (_, c2) = await discover("c2_rank3_cube.h5")
            expect(c2.shape == [1, 5, 6, 5] && c2.storedRank == 3, "c2 \(c2.shape) storedRank \(c2.storedRank)")
            let (reader, c4) = await discover("c4_rank3_noncanonical.h5")
            expect(c4.datasetPath == "/Experiments/line_scan/data" && c4.shape == [1, 7, 16, 12] && c4.storedRank == 3,
                   "c4 \(c4.datasetPath) \(c4.shape)")
            // A promoted rank-3 was stored (N, Qy, Qx): R is dim0 (3.0 nm), Q is
            // dim2 (0.25 1/nm). The stored-rank-4 mapping would read 0.5 1/nm as
            // the real-space size and nothing for Q; a stale anchor would read the
            // sibling's 7.0.
            let calibration = await reader.pixelCalibration()
            expect(calibration?.rSize == 3.0 && calibration?.rUnits == "nm" && calibration?.qSize == 0.25 && calibration?.qUnits == "1/nm",
                   "c4 calibration wrong for a promoted rank-3: \(String(describing: calibration))")
            // The rank-3 contract, pinned: an unlabelled rank-3 array with nothing
            // better in the file opens as one scan row. No size floor, by decision
            // (see H5Reader.datacubeRejection).
            let (_, e1) = await discover("e1_rank3_only.h5")
            expect(e1.shape == [1, 50, 200, 4] && e1.storedRank == 3, "e1 \(e1.shape)")
            print("PASS: rank-4, canonical rank-3, non-canonical rank-3 (with its own R/Q dims) and unlabelled rank-3 files open as before")
        }
    }
}
