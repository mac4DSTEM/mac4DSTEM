//
//  EllipseCalibration.swift
//  Intensity-weighted conic fit matching py4DSTEM fit_ellipse_1D semantics.
//

import Foundation

nonisolated struct EllipseCalibrationFit: Sendable, Equatable {
    /// Fitted center in py4DSTEM detector order: qx is row, qy is column.
    let centerQX: Double
    let centerQY: Double
    let a: Double
    let b: Double
    let theta: Double
    /// sqrt(sum(residual²) / sum(intensity²)); dimensionless conic error.
    let normalizedResidual: Double
    let sampleCount: Int
    let occupiedAngularBins: Int
}

nonisolated enum EllipseCalibration {
    enum FitError: LocalizedError, Equatable {
        case invalidInput(String)
        case insufficientSignal
        case insufficientAngularCoverage(Int)
        case didNotConverge
        case invalidEllipse
        case excessiveResidual(Double)

        var errorDescription: String? {
            switch self {
            case .invalidInput(let detail):
                return "Cannot fit detector ellipse: \(detail)."
            case .insufficientSignal:
                return "Cannot fit detector ellipse: the selected annulus has no resolved ring signal."
            case .insufficientAngularCoverage(let bins):
                return "Cannot fit detector ellipse: ring signal covers only \(bins) angular bins."
            case .didNotConverge:
                return "Detector ellipse fitting did not converge."
            case .invalidEllipse:
                return "Detector ellipse fitting produced a non-physical conic."
            case .excessiveResidual(let residual):
                return String(format: "Detector ellipse fit residual is too large (%.3f).", residual)
            }
        }
    }

    /// Port of py4DSTEM `fit_ellipse_1D`'s operative model:
    /// `(A dx² + B dx dy + C dy² - 1) * intensity`.
    /// Coordinates deliberately stay in py4DSTEM order (qx=row, qy=column).
    static func fit1D(
        pattern: DiffractionPattern,
        centerQX: Double,
        centerQY: Double,
        innerRadius: Double,
        outerRadius: Double,
        maximumResidual: Double = 0.2
    ) throws -> EllipseCalibrationFit {
        guard pattern.qy > 2, pattern.qx > 2,
              pattern.pixels.count == pattern.qy * pattern.qx,
              centerQX.isFinite, centerQY.isFinite,
              innerRadius >= 0, outerRadius > innerRadius,
              maximumResidual > 0 else {
            throw FitError.invalidInput("dimensions, center, or fit radii are invalid")
        }

        struct Sample {
            let x: Double
            let y: Double
            let value: Double
        }
        var samples = [Sample]()
        samples.reserveCapacity(pattern.pixels.count / 2)
        var minimum = Double.greatestFiniteMagnitude
        var maximum = -Double.greatestFiniteMagnitude
        for qx in 0..<pattern.qy {
            let dx = Double(qx) - centerQX
            for qy in 0..<pattern.qx {
                let dy = Double(qy) - centerQY
                let radius = hypot(dx, dy)
                guard radius > innerRadius, radius <= outerRadius else { continue }
                let value = Double(pattern.pixels[qx * pattern.qx + qy])
                guard value.isFinite else { continue }
                samples.append(Sample(x: Double(qx), y: Double(qy), value: value))
                minimum = min(minimum, value)
                maximum = max(maximum, value)
            }
        }
        guard samples.count >= 20 else {
            throw FitError.invalidInput("the fitting annulus contains too few pixels")
        }
        let dynamicRange = maximum - minimum
        guard dynamicRange.isFinite,
              dynamicRange > max(1, abs(maximum)) * 1e-6 else {
            throw FitError.insufficientSignal
        }

        // Reject spot-only/partial rings before optimization. This is stricter
        // than scipy.leastsq and prevents a plausible conic from four peaks.
        let angularBinCount = 36
        let strongThreshold = minimum + 0.2 * dynamicRange
        var occupied = [Bool](repeating: false, count: angularBinCount)
        for sample in samples where sample.value >= strongThreshold {
            var angle = atan2(sample.y - centerQY, sample.x - centerQX)
            if angle < 0 { angle += 2 * .pi }
            let index = min(angularBinCount - 1, Int(angle / (2 * .pi) * Double(angularBinCount)))
            occupied[index] = true
        }
        let occupiedCount = occupied.filter { $0 }.count
        guard occupiedCount >= angularBinCount / 3 else {
            throw FitError.insufficientAngularCoverage(occupiedCount)
        }

        let initialRadius = (innerRadius + outerRadius) / 2
        var parameters = [centerQX, centerQY,
                          1 / (initialRadius * initialRadius), 0,
                          1 / (initialRadius * initialRadius)]

        func costAndNormal(_ p: [Double], buildNormal: Bool)
            -> (cost: Double, weight: Double, normal: [[Double]], gradient: [Double]) {
            var cost = 0.0
            var weight = 0.0
            var normal = Array(repeating: Array(repeating: 0.0, count: 5), count: 5)
            var gradient = [Double](repeating: 0, count: 5)
            for sample in samples {
                let dx = sample.x - p[0], dy = sample.y - p[1]
                let value = sample.value
                let residual = (p[2] * dx * dx + p[3] * dx * dy
                                + p[4] * dy * dy - 1) * value
                cost += residual * residual
                weight += value * value
                guard buildNormal else { continue }
                let jacobian = [
                    (-2 * p[2] * dx - p[3] * dy) * value,
                    (-p[3] * dx - 2 * p[4] * dy) * value,
                    dx * dx * value,
                    dx * dy * value,
                    dy * dy * value,
                ]
                for row in 0..<5 {
                    gradient[row] += jacobian[row] * residual
                    for column in row..<5 {
                        normal[row][column] += jacobian[row] * jacobian[column]
                    }
                }
            }
            for row in 0..<5 {
                for column in 0..<row { normal[row][column] = normal[column][row] }
            }
            return (cost, weight, normal, gradient)
        }

        var current = costAndNormal(parameters, buildNormal: true)
        guard current.weight > 0, current.cost.isFinite else { throw FitError.insufficientSignal }
        var damping = 1e-3
        var converged = false
        for _ in 0..<100 {
            var system = current.normal
            for diagonal in 0..<5 {
                system[diagonal][diagonal] += damping * max(system[diagonal][diagonal], 1e-12)
            }
            guard let delta = solve(system, rhs: current.gradient.map { -$0 }) else {
                damping *= 10
                continue
            }
            let candidate = zip(parameters, delta).map(+)
            guard isPhysicalConic(candidate) else {
                damping *= 10
                continue
            }
            let trial = costAndNormal(candidate, buildNormal: false)
            if trial.cost < current.cost {
                parameters = candidate
                let relativeStep = sqrt(delta.reduce(0) { $0 + $1 * $1 })
                    / max(1, sqrt(parameters.reduce(0) { $0 + $1 * $1 }))
                current = costAndNormal(parameters, buildNormal: true)
                damping = max(1e-12, damping / 3)
                if relativeStep < 1e-10 {
                    converged = true
                    break
                }
            } else {
                damping *= 10
            }
        }
        guard converged else { throw FitError.didNotConverge }
        guard let ellipse = userParameters(A: parameters[2], B: parameters[3], C: parameters[4])
        else { throw FitError.invalidEllipse }
        let centerDistance = hypot(parameters[0] - centerQX, parameters[1] - centerQY)
        guard centerDistance <= max(outerRadius - innerRadius, 2),
              ellipse.b / ellipse.a >= 0.2,
              ellipse.a <= outerRadius * 1.5,
              ellipse.b >= max(1, innerRadius * 0.25) else {
            throw FitError.invalidEllipse
        }
        let residual = sqrt(current.cost / current.weight)
        guard residual.isFinite, residual <= maximumResidual else {
            throw FitError.excessiveResidual(residual)
        }
        return EllipseCalibrationFit(
            centerQX: parameters[0], centerQY: parameters[1],
            a: ellipse.a, b: ellipse.b, theta: ellipse.theta,
            normalizedResidual: residual, sampleCount: samples.count,
            occupiedAngularBins: occupiedCount
        )
    }

    private static func isPhysicalConic(_ p: [Double]) -> Bool {
        guard p.count == 5, p.allSatisfy(\.isFinite) else { return false }
        return p[2] > 0 && p[4] > 0 && 4 * p[2] * p[4] - p[3] * p[3] > 0
    }

    /// Exact `convert_ellipse_params` convention from py4DSTEM.
    private static func userParameters(A: Double, B: Double, C: Double)
        -> (a: Double, b: Double, theta: Double)? {
        let separation = hypot(A - C, B)
        let smallEigenvalue = (A + C - separation) / 2
        let largeEigenvalue = (A + C + separation) / 2
        guard smallEigenvalue > 0, largeEigenvalue > 0 else { return nil }
        let a = 1 / sqrt(smallEigenvalue)
        let b = 1 / sqrt(largeEigenvalue)
        var theta: Double
        if abs(B) < 1e-15 {
            theta = A < C ? 0 : .pi / 2
        } else {
            theta = atan2(C - A - separation, B)
        }
        theta.formTruncatingRemainder(dividingBy: .pi)
        if theta < 0 { theta += .pi }
        return (a, b, theta)
    }

    private static func solve(_ matrix: [[Double]], rhs: [Double]) -> [Double]? {
        let count = rhs.count
        guard matrix.count == count, matrix.allSatisfy({ $0.count == count }) else { return nil }
        var augmented = matrix.enumerated().map { index, row in row + [rhs[index]] }
        for column in 0..<count {
            var pivot = column
            for row in (column + 1)..<count
                where abs(augmented[row][column]) > abs(augmented[pivot][column]) {
                pivot = row
            }
            guard abs(augmented[pivot][column]) > 1e-20 else { return nil }
            if pivot != column { augmented.swapAt(pivot, column) }
            let divisor = augmented[column][column]
            for index in column...count { augmented[column][index] /= divisor }
            for row in 0..<count where row != column {
                let factor = augmented[row][column]
                for index in column...count {
                    augmented[row][index] -= factor * augmented[column][index]
                }
            }
        }
        return augmented.map { $0[count] }
    }
}
