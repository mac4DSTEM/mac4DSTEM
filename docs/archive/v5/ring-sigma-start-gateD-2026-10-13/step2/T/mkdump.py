import re, sys
src = open('orig/main.swift').read()
def rep(old, new, count=1):
    global src
    n = src.count(old)
    assert n == count, (n, old)
    src = src.replace(old, new)

helpers = '''
// ---- lane T DUMP instrumentation (added; no pass/fail logic changed) ----
// DUMP_SKIP (env, comma list, default empty = the tool's own logic exactly) skips only the pass/fail CHECKS of the
// named sections after their fit calls have run and been dumped, so a variant that FAILs early can still be dumped
// to the end. Keys: profile:<name>, spot:<name>, anyway:<name>, seeded, sweep.
let dumpSkip = Set((ProcessInfo.processInfo.environment["DUMP_SKIP"] ?? "").split(separator: ",").map(String.init))
func skipChecks(_ key: String) -> Bool { dumpSkip.contains(key) }
func dumpNum(_ x: Double) -> String { String(format: "%.9g", x) }
func dumpClean(_ s: String) -> String {
    s.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\\n", with: " ")
}
func dumpFit(_ caseName: String, _ fn: String, _ f: EllipseCalibrationFit) {
    let p = f.profile
    let model = f.model == .conic ? "conic" : "asymmetricGaussian"
    var line = "DUMP|case=\\(caseName)|fn=\\(fn)|model=\\(model)|a=\\(dumpNum(f.a))|b=\\(dumpNum(f.b))"
    line += "|theta=\\(dumpNum(f.theta))|cx=\\(dumpNum(f.centerQX))|cy=\\(dumpNum(f.centerQY))"
    line += "|resid=\\(dumpNum(f.normalizedResidual))"
    line += "|sin=\\(p.map { dumpNum($0.innerSigma) } ?? "nil")|sout=\\(p.map { dumpNum($0.outerSigma) } ?? "nil")"
    line += "|fallback=\\(dumpClean(f.profileFallbackReason ?? "nil"))"
    line += "|cres=\\(dumpNum(f.conicResidual))|n=\\(f.sampleCount)|bins=\\(f.occupiedAngularBins)"
    line += "|i1=\\(p.map { dumpNum($0.ringIntensity) } ?? "nil")|bg=\\(p.map { dumpNum($0.background) } ?? "nil")"
    print(line)
}
func dumpThrew(_ caseName: String, _ fn: String, _ error: Error) {
    print("DUMP|case=\\(caseName)|fn=\\(fn)|threw=\\(dumpClean("\\(error)"))")
}
func traced(_ caseName: String, _ fn: String, _ body: () throws -> EllipseCalibrationFit) throws -> EllipseCalibrationFit {
    do {
        let fit = try body()
        dumpFit(caseName, fn, fit)
        return fit
    } catch {
        dumpThrew(caseName, fn, error)
        throw error
    }
}
// ---- end lane T instrumentation ----
'''
rep('guard CommandLine.arguments.count == 2 else', helpers + '\nguard CommandLine.arguments.count == 2 else')

# 1. cases: fit1D
rep('''    let fit = try EllipseCalibration.fit1D(
        pattern: pattern, centerQX: test.centerQX + 0.8, centerQY: test.centerQY - 0.6,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius
    )
    guard abs(fit.centerQX''', '''    let fit = try traced(test.name, "fit1D") { try EllipseCalibration.fit1D(
        pattern: pattern, centerQX: test.centerQX + 0.8, centerQY: test.centerQY - 0.6,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius
    ) }
    guard abs(fit.centerQX''')

# 2. profile cases
rep('''    let fit = try EllipseCalibration.fitBestAvailable(
        pattern: pattern,
        centerQX: test.centerQX + 0.7, centerQY: test.centerQY - 0.5,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius
    )
    guard fit.model == .asymmetricGaussian,''', '''    let fit = try traced(test.name, "fitBestAvailable") { try EllipseCalibration.fitBestAvailable(
        pattern: pattern,
        centerQX: test.centerQX + 0.7, centerQY: test.centerQY - 0.5,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius
    ) }
    if skipChecks("profile:" + test.name) { continue }
    guard fit.model == .asymmetricGaussian,''')

# 3. overlap
rep('''let fallback = try EllipseCalibration.fitBestAvailable(
    pattern: overlapPattern,
    centerQX: overlap.centerQX, centerQY: overlap.centerQY,
    innerRadius: overlap.innerRadius, outerRadius: overlap.outerRadius,
    maximumConicResidual: 0.4, maximumProfileResidual: 0.001
)''', '''let fallback = try traced(overlap.name, "fitBestAvailable") { try EllipseCalibration.fitBestAvailable(
    pattern: overlapPattern,
    centerQX: overlap.centerQX, centerQY: overlap.centerQY,
    innerRadius: overlap.innerRadius, outerRadius: overlap.outerRadius,
    maximumConicResidual: 0.4, maximumProfileResidual: 0.001
) }''')

# 4. blank
rep('''    _ = try EllipseCalibration.fit1D(
        pattern: blank, centerQX: 20, centerQY: 30, innerRadius: 8, outerRadius: 18
    )''', '''    _ = try traced("blank_annulus", "fit1D") { try EllipseCalibration.fit1D(
        pattern: blank, centerQX: 20, centerQY: 30, innerRadius: 8, outerRadius: 18
    ) }''')

# 5. four-spot x2
rep('''    _ = try EllipseCalibration.fit1D(
        pattern: DiffractionPattern(qy: 60, qx: 80, pixels: spots),
        centerQX: 30, centerQY: 40, innerRadius: 10, outerRadius: 20
    )''', '''    _ = try traced("four_spot", "fit1D") { try EllipseCalibration.fit1D(
        pattern: DiffractionPattern(qy: 60, qx: 80, pixels: spots),
        centerQX: 30, centerQY: 40, innerRadius: 10, outerRadius: 20
    ) }''')
rep('''    _ = try EllipseCalibration.fit1D(
        pattern: DiffractionPattern(qy: 60, qx: 80, pixels: spots),
        centerQX: 30, centerQY: 40, innerRadius: 10, outerRadius: 20,
        acceptSparseCoverage: true
    )''', '''    _ = try traced("four_spot_anyway", "fit1D") { try EllipseCalibration.fit1D(
        pattern: DiffractionPattern(qy: 60, qx: 80, pixels: spots),
        centerQX: 30, centerQY: 40, innerRadius: 10, outerRadius: 20,
        acceptSparseCoverage: true
    ) }''')

# 6. spot loop (default path)
rep('''        let fit = try EllipseCalibration.fitBestAvailable(
            pattern: pattern, centerQX: test.centerQX, centerQY: test.centerQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius)
        guard test.expect == "fit" else {''', '''        let fit = try traced(test.name, "fitBestAvailable") { try EllipseCalibration.fitBestAvailable(
            pattern: pattern, centerQX: test.centerQX, centerQY: test.centerQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius) }
        if skipChecks("spot:" + test.name) { continue }
        guard test.expect == "fit" else {''')
rep('''    } catch let error as EllipseCalibration.FitError {
        guard test.expect == "refuse" else {''', '''    } catch let error as EllipseCalibration.FitError {
        if skipChecks("spot:" + test.name) { continue }
        guard test.expect == "refuse" else {''')

# 7. anyway loop
rep('''        let fit = try EllipseCalibration.fitBestAvailable(
            pattern: pattern, centerQX: test.centerQX, centerQY: test.centerQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius,
            acceptSparseCoverage: true)
        guard test.expectAnyway == "fit" else {''', '''        let fit = try traced(test.name, "fitBestAvailable-anyway") { try EllipseCalibration.fitBestAvailable(
            pattern: pattern, centerQX: test.centerQX, centerQY: test.centerQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius,
            acceptSparseCoverage: true) }
        if skipChecks("anyway:" + test.name) { continue }
        guard test.expectAnyway == "fit" else {''')
rep('''    } catch let error as EllipseCalibration.FitError {
        guard test.expectAnyway == "refuse" else {''', '''    } catch let error as EllipseCalibration.FitError {
        if skipChecks("anyway:" + test.name) { continue }
        guard test.expectAnyway == "refuse" else {''')

# 8. seeded
rep('''    let fit = try EllipseCalibration.fitBestAvailable(
        pattern: pattern, centerQX: test.centerQX + 2.5, centerQY: test.centerQY - 2.0,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius,
        acceptSparseCoverage: true)
    guard fit.sparseCoverage, abs(fit.a / fit.b - 1) < 0.02,''', '''    let fit = try traced("spotty_ring_6_azimuths_seed3.2", "fitBestAvailable-anyway") { try EllipseCalibration.fitBestAvailable(
        pattern: pattern, centerQX: test.centerQX + 2.5, centerQY: test.centerQY - 2.0,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius,
        acceptSparseCoverage: true) }
    if skipChecks("seeded") { throw SkippedChecks() }
    guard fit.sparseCoverage, abs(fit.a / fit.b - 1) < 0.02,''')
rep('''} catch {
    // The seed-centre mutation lands here: moreThanOneRing(38.2, 44.5).
    fail(''', '''} catch is SkippedChecks {
} catch {
    // The seed-centre mutation lands here: moreThanOneRing(38.2, 44.5).
    fail(''')
rep('func skipChecks(_ key: String)', 'struct SkippedChecks: Error {}\nfunc skipChecks(_ key: String)')

# 9. sweep
rep('''    let fit: EllipseCalibrationFit
    do {
        fit = try EllipseCalibration.fit1D(
            pattern: pattern, centerQX: test.startQX, centerQY: test.startQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius)
    } catch {''', '''    // lane T: fitBestAvailable on the same pattern, centre guess and annulus as the sweep's fit1D; outside the checks.
    do {
        _ = try traced(test.name, "fitBestAvailable-sweep") { try EllipseCalibration.fitBestAvailable(
            pattern: pattern, centerQX: test.startQX, centerQY: test.startQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius) }
    } catch {}
    let fit: EllipseCalibrationFit
    do {
        fit = try traced(test.name, "fit1D") { try EllipseCalibration.fit1D(
            pattern: pattern, centerQX: test.startQX, centerQY: test.startQY,
            innerRadius: test.innerRadius, outerRadius: test.outerRadius) }
    } catch {''')
open('dump/main.swift', 'w').write(src)
