// Proves that a refused sidecar open reports WHY, not just THAT it failed —
// under the condition the app actually runs in, for the denial the app actually
// hits.
//
// S1 (2026-08-18): the release owner's restore failure read "HDF5 export failed
// while opening the session sidecar" and nothing else. `H5Reader.swift:164-168`
// installs `H5Eset_auto2(H5E_DEFAULT, nil, nil)`; the HDF5 error state is a
// process-global (`_H5E_stack_g`, no TLS, `Threadsafety: OFF`), so the reason
// was discarded for the writer too.
//
// TWO THINGS THIS FIXTURE GOT WRONG ONCE, both caught by the Gate D second
// reader on 2026-08-19, both worth stating so they are not reintroduced:
//
//  1. A `chmod 000` file is NOT a sandbox analogue. Measured: a sandbox denial
//     is `errno = 1 … 'Operation not permitted'` (EPERM); `chmod 000` is
//     `errno = 13 … 'Permission denied'` (EACCES). Asserting on EACCES would
//     have gone red on the real case — and the Track B row derived from it told
//     the observer that `Permission denied` meant "sandbox", which would have
//     made them rule the sandbox OUT on the single run that decides S1. The
//     denial case therefore runs under `sandbox-exec` (see run.sh) and expects
//     EPERM; the POSIX case is kept as a *separate* case, not as a stand-in.
//  2. Requiring the two messages to merely DIFFER is a weak control: a
//     contaminated error stack yields two different-but-wrong strings and
//     passes. Each case must name its OWN marker, and the cases run in BOTH
//     orders so a stale stack cannot masquerade as a fresh one.
import Foundation

typealias H5EsetAuto2 = @convention(c) (Int64, UnsafeRawPointer?, UnsafeRawPointer?) -> Int32

enum Mode: String {
    case posix     // chmod 000 — expect EACCES
    case sandboxed // readable file, denied by a sandbox profile — expect EPERM
}

func message(openingSidecarAt url: URL) -> String {
    do {
        _ = try BraggVectorEMDWriter.loadSession(from: url)
        return "<no error thrown>"
    } catch {
        return error.localizedDescription
    }
}


/// A small but genuinely valid sidecar, written through the production writer.
func writeRealSidecar(to url: URL) throws {
    let map = ScalarResultMap(
        width: 4, height: 4,
        pixels: (0..<16).map(Float.init),
        kind: "fixture scalar", displayName: "Fixture", valueUnits: "counts"
    )
    let calibration = PixelCalibration(
        rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false
    )
    try BraggVectorEMDWriter.writeScientificBundle(
        maps: [map], calibration: calibration, to: url
    )
}

let work = URL(fileURLWithPath: CommandLine.arguments[1])
// A first pass writes the file that the sandboxed pass will be denied — it must
// exist, and be genuinely valid, before `sandbox-exec` starts.
if CommandLine.arguments[2] == "write-denied-fixture" {
    try! writeRealSidecar(to: work.appendingPathComponent("denied-sandboxed.mac4dstem.h5"))
    exit(0)
}
guard let mode = Mode(rawValue: CommandLine.arguments[2]) else {
    print("FAIL: unknown mode \(CommandLine.arguments[2])"); exit(1)
}
var failures: [String] = []

let notHDF5 = work.appendingPathComponent("not-hdf5.mac4dstem.h5")
let denied = work.appendingPathComponent("denied-\(mode.rawValue).mac4dstem.h5")

// Both denial shapes keep a valid HDF5 signature, so a refusal cannot be
// confused with a format problem.
try! Data("this is plainly not an HDF5 file\n".utf8).write(to: notHDF5)

// The denied file must be a REAL HDF5 file, written by this app's own writer —
// not an 8-byte signature stub. Measured 2026-08-19: with a stub, a sandbox
// denial surfaces as "bad byte number in an address [Bad value]" because HDF5
// fails parsing before it reports the refusal, and the fixture would then pin
// the wrong string. With a real file it reports the refusal itself.
if mode == .posix {
    try! writeRealSidecar(to: denied)
    try! FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
}
// In .sandboxed mode run.sh wrote the file already and denies it by profile.

precondition(FileManager.default.fileExists(atPath: denied.path),
             "the shape under test requires fileExists to still pass")

// The marker each case must name in its own right — not merely "differs".
let deniedMarker = mode == .posix ? "errno = 13" : "errno = 1,"
let deniedWord = mode == .posix ? "permission denied" : "operation not permitted"

func check(round: String, reversed: Bool) {
    // Run in both orders: a stale stack surviving from the previous case would
    // make the second case report the first one's reason.
    let order = reversed ? [("denied", denied), ("not-HDF5", notHDF5)]
                         : [("not-HDF5", notHDF5), ("denied", denied)]
    var seen: [String: String] = [:]
    for (name, url) in order { seen[name] = message(openingSidecarAt: url) }

    let label = "\(round)/\(reversed ? "denied-first" : "format-first")"
    for (name, text) in seen { print("[\(label)] \(name) : \(text)") }

    for (name, text) in seen {
        if !text.contains("opening the session sidecar") {
            failures.append("[\(label)] \(name): lost the operation name")
        }
        if !text.contains("HDF5 reported:") {
            failures.append("[\(label)] \(name): no captured reason — currentErrorStack() returned nil")
        }
    }
    // Each case names its own marker, in either order.
    if let text = seen["denied"] {
        if !text.contains(deniedMarker) || !text.lowercased().contains(deniedWord) {
            failures.append("[\(label)] denied case did not report \(mode == .posix ? "EACCES" : "EPERM"): \(text)")
        }
    }
    if let text = seen["not-HDF5"], !text.lowercased().contains("signature") {
        failures.append("[\(label)] format case did not report a signature problem: \(text)")
    }
    // Retained as a cheap extra: with the capture disabled both collapse to the
    // identical pre-S1 sentence.
    if seen["denied"] == seen["not-HDF5"] {
        failures.append("[\(label)] the two failures are indistinguishable — the pre-S1 behaviour")
    }
}

check(round: "default", reversed: false)
check(round: "default", reversed: true)

guard let path = ProcessInfo.processInfo.environment["MAC4DSTEM_HDF5_PATH"],
      let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
      let symbol = dlsym(handle, "H5Eset_auto2") else {
    print("FAIL: could not install the silencer; the app's condition was never tested")
    exit(1)
}
_ = unsafeBitCast(symbol, to: H5EsetAuto2.self)(0, nil, nil)
print("--- H5Eset_auto2(H5E_DEFAULT, nil, nil) installed: the app's condition ---")
check(round: "silenced", reversed: false)
check(round: "silenced", reversed: true)

if mode == .posix {
    try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: denied.path)
}

if failures.isEmpty {
    print("PASS[\(mode.rawValue)]: a refused sidecar open reports why, silenced or not")
} else {
    for failure in failures { print("FAIL: \(failure)") }
    exit(1)
}
