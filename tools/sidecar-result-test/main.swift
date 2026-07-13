import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: harness SIDECAR SOURCE")
}
let sidecar = URL(fileURLWithPath: CommandLine.arguments[1])
let source = URL(fileURLWithPath: CommandLine.arguments[2])
let sourceBefore = try Data(contentsOf: source)

let vectors = BraggVectors(
    scanWidth: 3, scanHeight: 2,
    peaks: [
        [BraggPeak(x: 2.5, y: 1.25, intensity: 10)], [],
        [BraggPeak(x: 0.125, y: 4.75, intensity: 99.5)],
        [BraggPeak(x: 3, y: 2, intensity: 1)],
        [BraggPeak(x: 2.25, y: 1.5, intensity: 8)],
        [BraggPeak(x: 5.875, y: 3.125, intensity: 7.5)],
    ]
)
var calibration = PixelCalibration(
    rSize: 1.75, rUnits: "nm", qSize: 0.03125, qUnits: "A^-1", qrFlip: true
)
calibration.qx0Mean = 16
calibration.qy0Mean = 36
calibration.ellipseA = 1.02
calibration.ellipseB = 0.98
calibration.ellipseTheta = 0.35
calibration.qrRotationRad = 0.375
calibration.probeSemiangle = 7.25
calibration.originMaps = PixelOriginMaps(
    shape: [2, 3],
    fittedQX: [10, 11, 12, 20, 21, 22],
    fittedQY: [30, 31, 32, 40, 41, 42],
    measuredQX: [10.25, 11.25, 12.25, 20.25, 21.25, 22.25],
    measuredQY: [29.5, 30.5, 31.5, 39.5, 40.5, 41.5]
)
try BraggVectorEMDWriter.write(
    vectors: vectors, qWidth: 7, qHeight: 5,
    calibration: calibration, to: sidecar
)

let first = ScalarResultMap(
    width: 3, height: 2,
    pixels: [1.5, .nan, -2.25, 4, 5.5, 6.75],
    kind: "virtual_image", displayName: "Virtual BF", valueUnits: "intensity"
)
try BraggVectorEMDWriter.mergeResultMap(
    first, vectors: nil, qWidth: 7, qHeight: 5,
    calibration: calibration, to: sidecar
)
let firstID = BraggVectorEMDWriter.resultNodeName(forKind: first.kind)
let firstSnapshot = try BraggVectorEMDWriter.loadSession(from: sidecar)
guard firstSnapshot.inventory.results.map(\.id) == [firstID],
      firstSnapshot.inventory.currentResultID == firstID,
      firstSnapshot.inventory.hasBraggVectors,
      firstSnapshot.inventory.hasCalibration,
      let restored = firstSnapshot.currentResult else {
    fail("native reload did not find the first named result")
}
guard let restoredCalibration = firstSnapshot.calibration,
      restoredCalibration.rSize == calibration.rSize,
      restoredCalibration.rUnits == calibration.rUnits,
      restoredCalibration.qSize == calibration.qSize,
      restoredCalibration.qUnits == calibration.qUnits,
      restoredCalibration.qrFlip == true,
      restoredCalibration.qrRotationRad == 0.375,
      restoredCalibration.probeSemiangle == 7.25,
      restoredCalibration.ellipseA == 1.02,
      restoredCalibration.ellipseB == 0.98,
      restoredCalibration.ellipseTheta == 0.35,
      restoredCalibration.originMaps?.shape == [2, 3],
      restoredCalibration.originMaps?.fittedQX == calibration.originMaps?.fittedQX,
      restoredCalibration.originMaps?.fittedQY == calibration.originMaps?.fittedQY,
      restoredCalibration.originMaps?.measuredQX == calibration.originMaps?.measuredQX,
      restoredCalibration.originMaps?.measuredQY == calibration.originMaps?.measuredQY else {
    fail("full calibration snapshot did not round-trip")
}
print("PASS: full_calibration_snapshot_roundtrip")
guard restored.width == 3, restored.height == 2,
      restored.kind == first.kind,
      restored.displayName == first.displayName,
      restored.valueUnits == first.valueUnits else {
    fail("native reload metadata or shape mismatch")
}
for index in first.pixels.indices {
    let a = first.pixels[index], b = restored.pixels[index]
    guard (a.isNaN && b.isNaN) || a == b else {
        fail("native reload pixel mismatch at \(index): \(a) vs \(b)")
    }
}
print("PASS: native_reopen_restores_named_scalar_map")

let replacement = ScalarResultMap(
    width: 3, height: 2,
    pixels: [9, 8, 7, 6, 5, 4],
    kind: "strain_exx", displayName: "Strain εxx", valueUnits: "strain"
)
try BraggVectorEMDWriter.mergeResultMap(
    replacement, vectors: nil, qWidth: 7, qHeight: 5,
    calibration: calibration, to: sidecar
)
let replacementID = BraggVectorEMDWriter.resultNodeName(forKind: replacement.kind)
let twoMapSnapshot = try BraggVectorEMDWriter.loadSession(from: sidecar)
guard twoMapSnapshot.inventory.results.map(\.id) == [firstID, replacementID],
      twoMapSnapshot.inventory.currentResultID == replacementID,
      let replaced = twoMapSnapshot.currentResult,
      replaced.pixels == replacement.pixels,
      replaced.kind == replacement.kind else {
    fail("second map did not append or become current")
}
guard let preservedFirst = try BraggVectorEMDWriter.loadResultMap(id: firstID, from: sidecar) else {
    fail("first map disappeared after adding the second")
}
for index in first.pixels.indices {
    let a = first.pixels[index], b = preservedFirst.pixels[index]
    guard (a.isNaN && b.isNaN) || a == b else {
        fail("first map changed after adding the second at \(index)")
    }
}
print("PASS: two_named_maps_enumerate_and_restore_current")

let secondReplacement = ScalarResultMap(
    width: 3, height: 2,
    pixels: [19, 18, 17, 16, 15, 14],
    kind: replacement.kind, displayName: "Strain εxx v2", valueUnits: "strain"
)
try BraggVectorEMDWriter.mergeResultMap(
    secondReplacement, vectors: nil, qWidth: 7, qHeight: 5,
    calibration: calibration, to: sidecar
)
let replacedSnapshot = try BraggVectorEMDWriter.loadSession(from: sidecar)
guard replacedSnapshot.inventory.results.map(\.id) == [firstID, replacementID],
      replacedSnapshot.inventory.currentResultID == replacementID,
      replacedSnapshot.currentResult?.pixels == secondReplacement.pixels,
      replacedSnapshot.currentResult?.displayName == secondReplacement.displayName else {
    fail("same-kind replacement did not retain stable ordering and identity")
}
guard let stillPreservedFirst = try BraggVectorEMDWriter.loadResultMap(
    id: firstID, from: sidecar
), stillPreservedFirst.pixels.count == first.pixels.count else {
    fail("unrelated map disappeared during same-kind replacement")
}
for index in first.pixels.indices {
    let a = first.pixels[index], b = stillPreservedFirst.pixels[index]
    guard (a.isNaN && b.isNaN) || a == b else {
        fail("unrelated map changed during replacement at \(index)")
    }
}
print("PASS: replace_one_preserves_other_map_and_braggvectors")

let rgba = RGBAResultMap(
    width: 3, height: 2,
    rgba: [
        255, 0, 0, 255,   0, 255, 0, 255,   0, 0, 255, 255,
        12, 34, 56, 255,  78, 90, 123, 255,  210, 220, 230, 128,
    ],
    kind: "acom_ipf_z", displayName: "ACOM · IPF · Z", valueUnits: "rgba"
)
try BraggVectorEMDWriter.mergeRGBAResultMap(
    rgba, vectors: nil, qWidth: 7, qHeight: 5,
    calibration: calibration, to: sidecar
)
let rgbaID = BraggVectorEMDWriter.resultNodeName(forKind: rgba.kind)
let rgbaSnapshot = try BraggVectorEMDWriter.loadSession(from: sidecar)
guard rgbaSnapshot.inventory.results.map(\.id) == [firstID, replacementID, rgbaID],
      rgbaSnapshot.inventory.results.last?.storage == .rgba8,
      rgbaSnapshot.inventory.currentResultID == rgbaID,
      rgbaSnapshot.currentResult == nil,
      rgbaSnapshot.currentRGBAResult?.rgba == rgba.rgba,
      rgbaSnapshot.currentRGBAResult?.displayName == rgba.displayName else {
    fail("RGBA result did not append, become current, and round-trip exactly")
}
guard try BraggVectorEMDWriter.loadRGBAResultMap(id: rgbaID, from: sidecar)?.rgba
        == rgba.rgba else {
    fail("direct RGBA result load failed")
}
print("PASS: native_reopen_restores_named_rgba_map")

var updatedCalibration = calibration
updatedCalibration.qrRotationRad = -0.625
updatedCalibration.probeSemiangle = 8.5
try BraggVectorEMDWriter.mergeCalibration(
    updatedCalibration, qWidth: 7, qHeight: 5, to: sidecar
)
let calibrationRewrite = try BraggVectorEMDWriter.loadSession(from: sidecar)
guard calibrationRewrite.calibration?.qrRotationRad == -0.625,
      calibrationRewrite.calibration?.probeSemiangle == 8.5,
      calibrationRewrite.inventory.results.map(\.id) == [firstID, replacementID, rgbaID],
      calibrationRewrite.currentRGBAResult?.rgba == rgba.rgba,
      calibrationRewrite.inventory.currentResultID == rgbaID,
      calibrationRewrite.inventory.hasBraggVectors else {
    fail("calibration-only rewrite did not preserve supported results")
}
print("PASS: calibration_replace_preserves_maps_and_braggvectors")

let removalURL = sidecar.deletingPathExtension().appendingPathExtension("removal.h5")
try FileManager.default.copyItem(at: sidecar, to: removalURL)
try BraggVectorEMDWriter.removeResult(
    kind: rgba.kind, qWidth: 7, qHeight: 5,
    calibration: updatedCalibration, from: removalURL
)
let removalSnapshot = try BraggVectorEMDWriter.loadSession(from: removalURL)
guard removalSnapshot.inventory.results.map(\.id) == [firstID, replacementID],
      removalSnapshot.currentResult?.pixels == secondReplacement.pixels,
      removalSnapshot.currentRGBAResult == nil,
      removalSnapshot.inventory.hasBraggVectors,
      removalSnapshot.inventory.hasCalibration else {
    fail("atomic RGBA removal did not preserve scalar results/BraggVectors/calibration")
}
print("PASS: remove_one_result_preserves_other_supported_objects")

let partialURL = sidecar.deletingPathExtension().appendingPathExtension("partial.h5")
var partial = PixelCalibration(
    rSize: 2.25, rUnits: "nm", qSize: nil, qUnits: nil, qrFlip: nil
)
partial.qx0Mean = 12
partial.qy0Mean = 34
partial.originMaps = PixelOriginMaps(
    shape: [9, 9], fittedQX: [1], fittedQY: [2]
)
try BraggVectorEMDWriter.mergeCalibration(
    partial, qWidth: 7, qHeight: 5, to: partialURL
)
let partialSnapshot = try BraggVectorEMDWriter.loadSession(from: partialURL)
guard partialSnapshot.calibration?.rSize == 2.25,
      partialSnapshot.calibration?.qx0Mean == 12,
      partialSnapshot.calibration?.qy0Mean == 34,
      partialSnapshot.calibration?.originMaps == nil else {
    fail("partial/mismatched calibration was not handled safely")
}
print("PASS: partial_mismatched_origin_keeps_valid_scalars")

let beforeCancellation = try Data(contentsOf: sidecar)
let token = AnalysisCancellationToken()
do {
    try BraggVectorEMDWriter.mergeCalibration(
        calibration, qWidth: 7, qHeight: 5,
        to: sidecar, cancellation: token
    ) { fraction in
        if fraction >= 1 { token.cancel() }
    }
    fail("cancelled merge unexpectedly succeeded")
} catch BraggVectorEMDWriter.WriterError.cancelled {
    // Expected.
}
guard try Data(contentsOf: sidecar) == beforeCancellation else {
    fail("cancelled merge changed the existing sidecar")
}
guard try Data(contentsOf: source) == sourceBefore else {
    fail("session work modified the source dataset")
}
let leftovers = try FileManager.default.contentsOfDirectory(
    at: sidecar.deletingLastPathComponent(), includingPropertiesForKeys: nil
).filter { $0.lastPathComponent.hasPrefix(".\(sidecar.lastPathComponent).") }
guard leftovers.isEmpty else { fail("cancelled merge left a temporary file") }
print("PASS: cancelled_merge_preserves_sidecar_and_source")
print("sidecar-result-test Swift phase: all passed")
