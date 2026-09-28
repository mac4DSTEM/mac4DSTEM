//
//  T6 — volumetric precipitate density, synthetic foil.
//  docs/archive/v4/volumetric-density-preregistration-2026-09-28.md §7 fixes
//  every parameter below; none may change after seeing output.
//
//  Model: field S = 2400 nm square, pixel p = 2.5 nm (960 x 960). Plates are
//  zero-thickness discs of diameter d (R = d/2), beam along z, foil 0 <= z <= t.
//  theta' edge-on: normal uniform in {x, y}, s = 1. T1: normal uniform in
//  {(+-1, +-1, 1)/sqrt3}, s = sqrt(2/3). h = d*s is the disc's extent along z.
//  Centres uniform in x, y in [-R, S+R], z in [-h/2, t+h/2]. A plate's
//  footprint = its in-foil points (grid in its own plane, spacing <= p/4)
//  floored to pixels. A plate whose footprint, dilated one pixel (8-neigh),
//  meets an accepted one is rejected; generation stops at 1 % occupied
//  in-field pixels. Truth N_V = accepted / ((S+2R)^2 (t+h)).
//  Counting: PrecipitateSegmentation.classObjects on the 0/1 label map,
//  objects with touchesEdge == false (PrecipitateStatistics' rule).
//  Estimators (ratio = estimate / truth), A = analysedPixels * p^2:
//   (a) (1/A) sum 1/(t + L_i s)
//   (b) N / (A (t + dhat s)), dhat from mean L_i by inverting
//       dhat (t + (pi/4) dhat s)/(t + dhat s) = mean L
//   (c) w_i = S^2/((S-bx_i)(S-by_i)), N_w = sum w, weighted mean L, then (b)
//   naive N / (A t)
//  Bar: |mean ratio - 1| <= 0.05 per cell. Seeds >= 20 until the SEM of every
//  estimator's ratio (absolute, on the ratio) <= 0.015, cap 400.

import Foundation

// MARK: - Fixed parameters (§7)

// Areal mode (archive/v4/areal-edge-correction-gateD-2026-09-28.md): T6_MODE=areal
// scores the app's areal density (current edge rule) and the Miles–Lantuéjoul
// corrected one against truth = accepted / (S + 2R)^2, with d 190 cells added.
let arealMode = ProcessInfo.processInfo.environment["T6_MODE"] == "areal"
let fieldNm = Double(ProcessInfo.processInfo.environment["T6_FIELD_NM"] ?? "") ?? 2400.0
// Diagnostics only (§8: D1 halves the pixel, D2 shortens every length by one
// pixel). Unset, they are the registered values and run 1 reproduces exactly.
let env = ProcessInfo.processInfo.environment
let pixelNm = Double(env["T6_PIXEL_NM"] ?? "") ?? 2.5
let lengthOffsetPx = Double(env["T6_LENGTH_OFFSET_PX"] ?? "") ?? 0
let W = Int((fieldNm / pixelNm).rounded()), H = W
// Hypothesis M (areal record): reject overlaps on a canvas covering the whole
// generation box, so margin plates compete like in-field ones. Off = run 1.
let rejectExtended = ProcessInfo.processInfo.environment["T6_REJECT_EXTENDED"] == "1"
let coverageTarget = 0.01
let minSeeds = 20, maxSeeds = arealMode ? 3000 : 400
let semTarget = arealMode ? 0.01 : 0.015
let passBar = arealMode ? 0.03 : 0.05

enum PlateClass: String { case thetaPrime = "theta' edge-on", t1 = "T1 {111}" }

struct Cell { let cls: PlateClass; let d: Double; let t: Double; let index: Int }

struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
}

// MARK: - Estimator helpers

/// f(d) = d (t + (pi/4) d s) / (t + d s): Nie & Muddle mean apparent diameter.
func meanApparent(_ d: Double, t: Double, s: Double) -> Double {
    d * (t + (Double.pi / 4) * d * s) / (t + d * s)
}

/// Invert f by bisection on [1e-6, 10 * target].
func invertApparent(_ target: Double, t: Double, s: Double) -> Double {
    var lo = 1e-6, hi = 10 * target
    precondition(meanApparent(hi, t: t, s: s) >= target, "bisection bracket does not enclose the root")
    for _ in 0..<200 {
        let mid = 0.5 * (lo + hi)
        if meanApparent(mid, t: t, s: s) < target { lo = mid } else { hi = mid }
    }
    return 0.5 * (lo + hi)
}

// MARK: - One seed

struct SeedResult {
    var counted = 0, edge = 0, accepted = 0, rejected = 0
    var insideZ = 0
    var ratios = [Double](repeating: .nan, count: 4)  // a, b, c, naive
}

func runSeed(_ cell: Cell, seedIndex: Int) -> SeedResult {
    let d = cell.d, t = cell.t, R = d / 2
    let s = cell.cls == .thetaPrime ? 1.0 : (2.0 / 3.0).squareRoot()
    let h = d * s
    var rng = SplitMix64(state: UInt64(cell.index) &* 0x100000001B3 &+ UInt64(seedIndex) &* 0xD6E8FEB86659FD93 &+ 0x1234_5678)
    _ = rng.next(); _ = rng.next()

    let m = rejectExtended ? Int((R / pixelNm).rounded(.up)) + 2 : 0
    let We = W + 2 * m, He = H + 2 * m
    var occupied = [Bool](repeating: false, count: We * He)
    var stamp = [Int32](repeating: 0, count: We * He)
    var stampID: Int32 = 0
    var occupiedCount = 0
    let target = Int((coverageTarget * Double(W * H)).rounded(.up))
    var res = SeedResult()
    var fp: [Int] = []
    fp.reserveCapacity(4096)
    let step0 = pixelNm / 4
    let nGrid = Int((2 * R / step0).rounded(.up))
    let step = 2 * R / Double(nGrid)
    let inv3 = 1.0 / 3.0.squareRoot()

    while occupiedCount < target {
        let cx = -R + rng.uniform() * (fieldNm + 2 * R)
        let cy = -R + rng.uniform() * (fieldNm + 2 * R)
        let cz = -h / 2 + rng.uniform() * (t + h)
        var n: (Double, Double, Double)
        let bits = rng.next()
        if cell.cls == .thetaPrime {
            n = (bits & 1 == 0) ? (1, 0, 0) : (0, 1, 0)
        } else {
            n = ((bits & 1 == 0 ? 1 : -1) * inv3, (bits & 2 == 0 ? 1 : -1) * inv3, inv3)
        }
        // in-plane orthonormal basis: u = n x z / |n x z|, v = n x u
        var u = (n.1, -n.0, 0.0)
        let ul = (u.0 * u.0 + u.1 * u.1).squareRoot()
        u = (u.0 / ul, u.1 / ul, 0)
        let v = (n.1 * u.2 - n.2 * u.1, n.2 * u.0 - n.0 * u.2, n.0 * u.1 - n.1 * u.0)

        stampID += 1
        fp.removeAll(keepingCapacity: true)
        for i in 0..<nGrid {
            let a = -R + (Double(i) + 0.5) * step
            for j in 0..<nGrid {
                let b = -R + (Double(j) + 0.5) * step
                if a * a + b * b > R * R { continue }
                let z = cz + a * u.2 + b * v.2
                if z < 0 || z > t { continue }
                let x = cx + a * u.0 + b * v.0
                let y = cy + a * u.1 + b * v.1
                let px = Int((x / pixelNm).rounded(.down)) + m, py = Int((y / pixelNm).rounded(.down)) + m
                if px < 0 || px >= We || py < 0 || py >= He { continue }
                let idx = py * We + px
                if stamp[idx] != stampID { stamp[idx] = stampID; fp.append(idx) }
            }
        }
        var clash = false
        outer: for idx in fp {
            let r = idx / We, c = idx % We
            for dr in -1...1 {
                let rr = r + dr
                if rr < 0 || rr >= He { continue }
                for dc in -1...1 {
                    let cc = c + dc
                    if cc < 0 || cc >= We { continue }
                    if occupied[rr * We + cc] { clash = true; break outer }
                }
            }
        }
        if clash { res.rejected += 1; continue }
        res.accepted += 1
        if cz >= 0 && cz <= t { res.insideZ += 1 }
        for idx in fp {
            occupied[idx] = true
            let r = idx / We - m, c = idx % We - m
            if r >= 0 && r < H && c >= 0 && c < W { occupiedCount += 1 }
        }
    }

    // Labels and the app's own counting path.
    var labels = [Int32](repeating: 0, count: W * H)
    for r in 0..<H { for c in 0..<W where occupied[(r + m) * We + (c + m)] { labels[r * W + c] = 1 } }
    let roles = PrecipitateSegmentation.LabelRoles(
        precipitateClasses: [1], matrix: [0], notIndexed: [])
    let map = PrecipitateSegmentation.classObjects(
        labels: labels, width: W, height: H, roles: roles,
        pixelSize: pixelNm, pixelUnit: "nm")
    precondition(map.classes.count == 1, "expected one class")
    let cls = map.classes[0]
    precondition(cls.pixelCount == occupiedCount, "object pixels \(cls.pixelCount) != occupied \(occupiedCount)")
    let counted = cls.objects.filter { !$0.touchesEdge }
    res.counted = counted.count
    res.edge = cls.objects.count - counted.count
    let density = PrecipitateStatistics.density(
        objects: cls.objects, accepted: Set(cls.objects.map(\.id)),
        analysedPixels: map.analysedPixels, frameWidth: W, frameHeight: H,
        pixelSize: pixelNm, pixelUnit: "nm")
    precondition(density.acceptedCount == counted.count, "density.acceptedCount \(density.acceptedCount) != counted \(counted.count)")
    precondition(density.edgeCount == res.edge, "density.edgeCount mismatch")
    precondition(map.analysedPixels == W * H)

    if arealMode {
        // Truth: visible plates per area. Weight = the inverse fraction of box
        // positions clear of the forbidden border row, in pixels.
        let lambda = Double(res.accepted) / ((fieldNm + 2 * R) * (fieldNm + 2 * R))
        let A = Double(map.analysedPixels) * pixelNm * pixelNm
        var sumW = 0.0
        for o in counted {
            var cmin = Int.max, cmax = -1, rmin = Int.max, rmax = -1
            for i in o.pixelIndices {
                let r = i / W, c = i % W
                cmin = min(cmin, c); cmax = max(cmax, c); rmin = min(rmin, r); rmax = max(rmax, r)
            }
            let bx = Double(cmax - cmin + 1), by = Double(rmax - rmin + 1)
            sumW += Double(W * H) / ((Double(W) - bx - 1) * (Double(H) - by - 1))
        }
        res.ratios = [(Double(counted.count) / A) / lambda, (sumW / A) / lambda,
                      (density.arealDensity ?? .nan) / lambda, (sumW / A) / lambda]
        return res
    }
    let truth = Double(res.accepted) / ((fieldNm + 2 * R) * (fieldNm + 2 * R) * (t + h))
    let A = Double(map.analysedPixels) * pixelNm * pixelNm
    let N = Double(counted.count)
    guard N > 0 else { return res }
    var sumInv = 0.0, sumL = 0.0, sumW = 0.0, sumWL = 0.0
    for o in counted {
        let L = (Double(o.lengthPx) - lengthOffsetPx) * pixelNm
        var cmin = Int.max, cmax = -1, rmin = Int.max, rmax = -1
        for i in o.pixelIndices {
            let r = i / W, c = i % W
            cmin = min(cmin, c); cmax = max(cmax, c); rmin = min(rmin, r); rmax = max(rmax, r)
        }
        let bx = Double(cmax - cmin + 1) * pixelNm, by = Double(rmax - rmin + 1) * pixelNm
        precondition(bx < fieldNm && by < fieldNm, "counted object spans the field")
        let w = fieldNm * fieldNm / ((fieldNm - bx) * (fieldNm - by))
        sumInv += 1 / (t + L * s)
        sumL += L
        sumW += w; sumWL += w * L
    }
    let nA = sumInv / A
    let dHat = invertApparent(sumL / N, t: t, s: s)
    let nB = N / (A * (t + dHat * s))
    let dHatW = invertApparent(sumWL / sumW, t: t, s: s)
    let nC = sumW / (A * (t + dHatW * s))
    let naive = N / (A * t)
    res.ratios = [nA / truth, nB / truth, nC / truth, naive / truth]
    return res
}

// MARK: - One cell

struct CellSummary {
    var cell: Cell
    var seeds = 0
    var meanCounted = 0.0, meanEdge = 0.0, rejectionRate = 0.0
    var mean = [Double](repeating: 0, count: 4)
    var sem = [Double](repeating: 0, count: 4)
    var insideFraction = 0.0, expectedInside = 0.0
    var hitCap = false
}

func runCell(_ cell: Cell) -> CellSummary {
    var ratios: [[Double]] = [[], [], [], []]
    var counted = 0, edge = 0, acc = 0, rej = 0, inside = 0
    var n = 0
    var hitCap = false
    while true {
        let r = runSeed(cell, seedIndex: n)
        n += 1
        counted += r.counted; edge += r.edge; acc += r.accepted; rej += r.rejected; inside += r.insideZ
        for k in 0..<4 { ratios[k].append(r.ratios[k]) }
        if n >= minSeeds {
            var worst = 0.0
            for k in 0..<4 {
                let m = ratios[k].reduce(0, +) / Double(n)
                let v = ratios[k].reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(n - 1)
                worst = max(worst, (v / Double(n)).squareRoot())
            }
            if worst <= semTarget { break }
        }
        if n >= maxSeeds { hitCap = true; break }
    }
    var s = CellSummary(cell: cell)
    s.seeds = n
    s.meanCounted = Double(counted) / Double(n)
    s.meanEdge = Double(edge) / Double(n)
    s.rejectionRate = Double(rej) / Double(acc + rej)
    for k in 0..<4 {
        let m = ratios[k].reduce(0, +) / Double(n)
        let v = ratios[k].reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(n - 1)
        s.mean[k] = m
        s.sem[k] = (v / Double(n)).squareRoot()
    }
    let sf = cell.cls == .thetaPrime ? 1.0 : (2.0 / 3.0).squareRoot()
    s.insideFraction = Double(inside) / Double(acc)
    s.expectedInside = cell.t / (cell.t + cell.d * sf)
    s.hitCap = hitCap
    return s
}

// MARK: - Internal self-checks (harness, not §7)

func selfChecks() {
    // Bisection round trip, both classes.
    for s in [1.0, (2.0 / 3.0).squareRoot()] {
        for t in [50.0, 100, 200] {
            for d in [20.0, 100] {
                let back = invertApparent(meanApparent(d, t: t, s: s), t: t, s: s)
                precondition(abs(back - d) < 1e-6, "bisection round trip failed")
            }
        }
    }
    // SplitMix64 is deterministic and roughly uniform.
    var a = SplitMix64(state: 42), b = SplitMix64(state: 42)
    var sum = 0.0
    for _ in 0..<100000 { let x = a.uniform(); precondition(x == b.uniform() && x >= 0 && x < 1); sum += x }
    precondition(abs(sum / 100000 - 0.5) < 0.01, "rng mean off")
    // A single object through the app's counter: a 1-px line of 40 px, interior.
    var labels = [Int32](repeating: 0, count: W * H)
    for r in 100..<140 { labels[r * W + 200] = 1 }
    let m = PrecipitateSegmentation.classObjects(
        labels: labels, width: W, height: H,
        roles: .init(precipitateClasses: [1], matrix: [0], notIndexed: []),
        pixelSize: pixelNm, pixelUnit: "nm")
    precondition(m.classes[0].objects.count == 1 && !m.classes[0].objects[0].touchesEdge, "one interior object expected")
    precondition(abs(m.classes[0].objects[0].lengthPx - 40) <= 1.01, "line length \(m.classes[0].objects[0].lengthPx)")
}

// MARK: - Main

@main
struct T6 {
    static func main() {
        let start = Date()
        selfChecks()
        var cells: [Cell] = []
        for cls in [PlateClass.thetaPrime, .t1] {
            for d in (arealMode ? [20.0, 100.0, 190.0] : [20.0, 100.0]) {
                for t in [50.0, 100, 200] {
                    cells.append(Cell(cls: cls, d: d, t: t, index: cells.count))
                }
            }
        }
        let box = ResultBox(count: cells.count)
        DispatchQueue.concurrentPerform(iterations: cells.count) { i in
            box.set(i, runCell(cells[i]))
        }
        let results = box.all()

        print("T6 volumetric density, field \(Int(fieldNm)) nm, pixel \(pixelNm) nm (\(W)x\(H)), length offset \(lengthOffsetPx) px, ratio = estimate / true N_V")
        print("(a) registered per-object 1/(t+L s); (b) Nie-Muddle class-level; (c) (b)+Miles-Lantuejoul weights; naive N/(A t)")
        print("bar |mean-1| <= \(passBar); seeds >= \(minSeeds) until SEM <= \(semTarget) for all four, cap \(maxSeeds)")
        var allPass = [true, true, true, true]
        let names = arealMode ? ["current", "corrected", "app", "corrected"] : ["(a)", "(b)", "(c)", "naive"]
        for r in results {
            var line = String(format: "%-14@ d=%3d t=%3d seeds=%3d%@ cnt=%6.1f edge=%5.1f rej=%5.1f%%",
                              r.cell.cls.rawValue as NSString, Int(r.cell.d), Int(r.cell.t), r.seeds,
                              (r.hitCap ? "*" : " ") as NSString,
                              r.meanCounted, r.meanEdge, 100 * r.rejectionRate)
            for k in 0..<4 {
                let ok = abs(r.mean[k] - 1) <= passBar
                if !ok { allPass[k] = false }
                line += String(format: "  %@ %.3f+-%.3f %@", names[k] as NSString, r.mean[k], r.sem[k], (ok ? "PASS" : "FAIL") as NSString)
            }
            print(line)
        }
        print("(* = hit the seed cap before SEM target)")
        var worstDev = 0.0
        for r in results {
            let dev = r.insideFraction - r.expectedInside
            worstDev = max(worstDev, abs(dev))
            print(String(format: "sanity %-14@ d=%3d t=%3d centre z in [0,t]: %.4f expected %.4f (dev %+.4f)",
                         r.cell.cls.rawValue as NSString, Int(r.cell.d), Int(r.cell.t),
                         r.insideFraction, r.expectedInside, dev))
        }
        print(String(format: "sanity worst |deviation| = %.4f", worstDev))
        for k in 0..<4 {
            print("VERDICT \(names[k]): \(allPass[k] ? "PASS" : "FAIL")")
        }
        print(String(format: "runtime %.1f s", Date().timeIntervalSince(start)))
    }
}

final class ResultBox: @unchecked Sendable {
    private var items: [CellSummary?]
    private let lock = NSLock()
    init(count: Int) { items = Array(repeating: nil, count: count) }
    func set(_ i: Int, _ v: CellSummary) { lock.lock(); items[i] = v; lock.unlock() }
    func all() -> [CellSummary] { items.map { $0! } }
}
