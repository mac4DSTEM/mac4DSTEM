//
//  tools/load-spec-roundtrip — stage L6 (docs/load-pipeline-plan.md).
//
//  THE CLAIM: a load specification survives the session sidecar unchanged, and
//  what comes back out is applied to the SOURCE file rather than used to
//  re-derive from reduced data.
//
//  L6's round-trip, stated as the plan states it: full -> crop+bin -> write ->
//  reopen -> the specification and every calibration value survive identically,
//  and a product from a binned cube is still labelled as such afterwards.
//
//  WHY THE COMPARISON IS ON THE APPLIED VIEW AND NOT ONLY ON THE JSON. Two
//  specifications that decode to equal values still prove nothing if the app
//  then applies them differently. So each case is applied to the same source
//  descriptor on both sides, and the resulting `LoadView` — shape, read crop,
//  discarded edge — is what must match. A specification that round-trips as text
//  and produces a different view would be exactly the silent divergence this
//  stage exists to prevent.
//

import Foundation

var failures: [String] = []

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition { failures.append(message()) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

let source = DatasetDescriptor(
    filePath: "/tmp/source.h5", datasetPath: "/data",
    // Non-square in both spaces, and a detector that does NOT divide by 8, so
    // the edge-remainder trim is part of what must survive.
    shape: [60, 40, 130, 96], dtypeDescription: "uint16", chunkShape: nil
)

let cases: [(String, LoadSpecification)] = [
    ("full extent", .fullExtent),
    ("scan crop", LoadSpecification(
        scanCrop: AxisCrop(yOffset: 7, xOffset: 3, height: 20, width: 15)
    )),
    ("detector crop", LoadSpecification(
        detectorCrop: AxisCrop(yOffset: 11, xOffset: 5, height: 64, width: 48)
    )),
    ("bin only, with an edge remainder", LoadSpecification(detectorBin: 8)),
    ("crop and bin together", LoadSpecification(
        scanCrop: AxisCrop(yOffset: 1, xOffset: 2, height: 30, width: 20),
        detectorCrop: AxisCrop(yOffset: 3, xOffset: 7, height: 100, width: 70),
        detectorBin: 4
    )),
]

@main struct LoadSpecRoundtripHarness {
    static func main() {
        for (name, specification) in cases {
            // ---- 1. The text round-trip -------------------------------------
            guard let json = specification.jsonString else {
                check(specification.isFullExtent,
                      "\(name): a non-full-extent specification failed to encode")
                continue
            }
            guard let decoded = LoadSpecification.decoded(from: json) else {
                check(false, "\(name): encoded but did not decode")
                continue
            }
            check(decoded == specification,
                  "\(name): decoded specification differs from the original")

            // Stable bytes: the same specification must always produce the same
            // string, or a sidecar looks changed when nothing changed.
            check(decoded.jsonString == json,
                  "\(name): re-encoding produced different bytes")

            // ---- 2. The APPLIED round-trip, which is the real claim ---------
            let before = try? LoadView(source: source, specification: specification)
            let after = try? LoadView(source: source, specification: decoded)
            check((before == nil) == (after == nil),
                  "\(name): one side was loadable and the other was not")
            if let before, let after {
                check(before.descriptor.shape == after.descriptor.shape,
                      "\(name): loaded shape \(after.descriptor.shape) != \(before.descriptor.shape)")
                check(before.readDetectorCrop == after.readDetectorCrop,
                      "\(name): the read crop differs after the round trip")
                check(before.discardedDetectorRows == after.discardedDetectorRows
                      && before.discardedDetectorColumns == after.discardedDetectorColumns,
                      "\(name): the edge trim differs after the round trip")

                // ---- 3. Calibration survives identically -------------------
                // Re-referenced on both sides and compared value by value: the
                // point of recording the specification is that a product can be
                // re-labelled later, and a calibration that drifted would make
                // the label wrong rather than missing.
                var calibration = Calibration()
                calibration.origin = OriginMaps(
                    width: source.rx, height: source.ry,
                    measuredX: nil, measuredY: nil,
                    fittedX: (0..<(source.rx * source.ry)).map { Float($0 % 17) + 40 },
                    fittedY: (0..<(source.rx * source.ry)).map { Float($0 % 13) + 50 }
                )
                calibration.originProvenance = .fileMaps
                calibration.probeRadius = 9
                calibration.ellipseA = 1.05
                calibration.ellipseB = 0.95
                calibration.ellipseTheta = 0.25
                calibration.qPixelSize = 0.0125

                let point = CalibrationReReference.DetectorPoint(x: 44, y: 55)
                let outcomeBefore = CalibrationReReference.apply(
                    before, to: calibration, provenance: CalibrationProvenance(),
                    apertureCenter: point
                )
                let outcomeAfter = CalibrationReReference.apply(
                    after, to: calibration, provenance: CalibrationProvenance(),
                    apertureCenter: point
                )
                check(outcomeBefore.calibration.probeRadius == outcomeAfter.calibration.probeRadius,
                      "\(name): probe radius differs after the round trip")
                check(outcomeBefore.calibration.qPixelSize == outcomeAfter.calibration.qPixelSize,
                      "\(name): Q pixel size differs after the round trip")
                check(outcomeBefore.calibration.ellipseA == outcomeAfter.calibration.ellipseA
                      && outcomeBefore.calibration.ellipseB == outcomeAfter.calibration.ellipseB
                      && outcomeBefore.calibration.ellipseTheta == outcomeAfter.calibration.ellipseTheta,
                      "\(name): ellipse differs after the round trip")
                check(outcomeBefore.calibration.origin?.fittedX == outcomeAfter.calibration.origin?.fittedX
                      && outcomeBefore.calibration.origin?.fittedY == outcomeAfter.calibration.origin?.fittedY,
                      "\(name): the re-referenced origin differs after the round trip")
                check(outcomeBefore.apertureCenter == outcomeAfter.apertureCenter,
                      "\(name): the aperture centre differs after the round trip")
                check(outcomeBefore.invalidated == outcomeAfter.invalidated,
                      "\(name): the invalidation list differs after the round trip")
            }

            // ---- 4. The product is still LABELLED as reduced ----------------
            if !specification.isFullExtent {
                check(decoded.provenanceSummary != nil,
                      "\(name): a reduced view has no provenance summary, so a product from it cannot be labelled")
                check(decoded.provenanceSummary == specification.provenanceSummary,
                      "\(name): the provenance label changed across the round trip")
            } else {
                check(decoded.provenanceSummary == nil,
                      "full extent must produce no label — it is the identity, not a reduction")
            }
        }

        // ---- 5. Full extent records NOTHING, and that is the identity -------
        // A sidecar written at full extent must be indistinguishable from one
        // written before L6 existed. Otherwise reopening an old session would
        // look like a specification mismatch.
        check(LoadSpecification.fullExtent.provenanceSummary == nil,
              "full extent produced a provenance label")

        // ---- 6. A specification that does not fit is REFUSED ---------------
        // The case that matters on reopen: a sidecar beside a different cube.
        // It must not be clamped into range — that would load a region the
        // session never described while claiming to restore it.
        let smaller = DatasetDescriptor(
            filePath: "/tmp/other.h5", datasetPath: "/data",
            shape: [10, 10, 32, 32], dtypeDescription: "float32", chunkShape: nil
        )
        let tooBig = LoadSpecification(
            scanCrop: AxisCrop(yOffset: 7, xOffset: 3, height: 20, width: 15)
        )
        check((try? LoadView(source: smaller, specification: tooBig)) == nil,
              "a recorded specification that does not fit the reopened file was accepted")

        // ---- 7. Garbage in the attribute decodes to nothing, not to a guess -
        for text in ["", "{", "null", "{\"detectorBin\":\"eight\"}", "[]"] {
            check(LoadSpecification.decoded(from: text) == nil,
                  "malformed specification text \(text.debugDescription) decoded to something")
        }

        // ---- 8. The replay record (v2 S5) round-trips by the same rules -----
        // The record extends the sidecar format the same way the specification
        // did, so it earns the same harness: equal after the trip, byte-stable
        // on re-encode, ORDER preserved (the pipeline order IS the payload —
        // a serializer that sorted steps would still compare equal as a set
        // and replay strain before disk detection), and garbage decodes to
        // nothing rather than to an empty recipe.
        var recipe = SessionReplayRecord()
        recipe.record(kind: "disk_detection", parameters: ["sigma_cc": "2.0"],
                      at: Date(timeIntervalSince1970: 10))
        recipe.record(kind: "strain", parameters: ["basis_mode": "automatic"],
                      at: Date(timeIntervalSince1970: 20))
        recipe.record(kind: "disk_detection", parameters: ["sigma_cc": "3.5"],
                      at: Date(timeIntervalSince1970: 30))
        check(recipe.steps.map(\.kind) == ["disk_detection", "strain"],
              "a re-run must update its step in place, not append or reorder")
        check(recipe.steps.first?.parameters["sigma_cc"] == "3.5",
              "a re-run must carry the parameters the user settled on")
        if let recipeJSON = recipe.jsonString {
            let decodedRecipe = SessionReplayRecord.parse(recipeJSON)
            check(decodedRecipe == recipe,
                  "the replay record differs after the round trip")
            check(decodedRecipe?.steps.map(\.kind) == ["disk_detection", "strain"],
                  "the pipeline ORDER changed across the round trip")
            check(decodedRecipe?.jsonString == recipeJSON,
                  "re-encoding the replay record produced different bytes")
        } else {
            check(false, "a non-empty replay record failed to encode")
        }
        for text in ["", "{", "null", "{\"steps\":\"none\"}"] {
            check(SessionReplayRecord.parse(text) == nil,
                  "malformed replay text \(text.debugDescription) decoded to something")
        }

        if failures.isEmpty {
            print("load-spec-roundtrip: all passed")
        } else {
            for message in failures.prefix(40) {
                FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            }
            FileHandle.standardError.write(
                Data("load-spec-roundtrip: \(failures.count) failure(s)\n".utf8)
            )
            exit(1)
        }
    }
}
