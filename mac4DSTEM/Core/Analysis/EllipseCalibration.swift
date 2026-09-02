//
//  EllipseCalibration.swift
//  Detector-ellipse calibration. The conic path matches py4DSTEM fit_ellipse_1D;
//  the profile path ports fit_ellipse_amorphous_ring's 11-parameter central
//  Gaussian + asymmetric (Janus) Gaussian ring model.
//

import Foundation

package nonisolated enum EllipseCalibrationModel: String, Sendable, Equatable {
    case conic = "Intensity-weighted conic"
    case asymmetricGaussian = "Asymmetric Gaussian ring"
}

package nonisolated struct EllipseProfileParameters: Sendable, Equatable {
    package let centralIntensity: Double
    package let ringIntensity: Double
    package let centralSigma: Double
    package let innerSigma: Double
    package let outerSigma: Double
    package let background: Double

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(centralIntensity: Double, ringIntensity: Double, centralSigma: Double, innerSigma: Double, outerSigma: Double, background: Double) {
        self.centralIntensity = centralIntensity
        self.ringIntensity = ringIntensity
        self.centralSigma = centralSigma
        self.innerSigma = innerSigma
        self.outerSigma = outerSigma
        self.background = background
    }
}

package nonisolated struct EllipseCalibrationFit: Sendable, Equatable {
    /// Fitted center in py4DSTEM detector order: qx is row, qy is column.
    package let centerQX: Double
    package let centerQY: Double
    package let a: Double
    package let b: Double
    package let theta: Double
    /// Dimensionless residual for the model that was accepted.
    package let normalizedResidual: Double
    package let conicResidual: Double
    package let sampleCount: Int
    package let occupiedAngularBins: Int
    package let model: EllipseCalibrationModel
    package let profile: EllipseProfileParameters?
    /// Populated when profile refinement was attempted but the conic fallback
    /// was retained. This is diagnostic provenance, not a scientific failure.
    package let profileFallbackReason: String?

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(centerQX: Double, centerQY: Double, a: Double, b: Double, theta: Double, normalizedResidual: Double, conicResidual: Double, sampleCount: Int, occupiedAngularBins: Int, model: EllipseCalibrationModel, profile: EllipseProfileParameters?, profileFallbackReason: String?) {
        self.centerQX = centerQX
        self.centerQY = centerQY
        self.a = a
        self.b = b
        self.theta = theta
        self.normalizedResidual = normalizedResidual
        self.conicResidual = conicResidual
        self.sampleCount = sampleCount
        self.occupiedAngularBins = occupiedAngularBins
        self.model = model
        self.profile = profile
        self.profileFallbackReason = profileFallbackReason
    }
}

package nonisolated enum EllipseCalibration {
    package enum FitError: LocalizedError, Equatable {
        case invalidInput(String)
        case insufficientSignal
        case insufficientAngularCoverage(Int)
        case didNotConverge
        case invalidEllipse
        case excessiveResidual(Double)

        package var errorDescription: String? {
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
    package static func fit1D(
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
            package let x: Double
            package let y: Double
            package let value: Double
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
            normalizedResidual: residual, conicResidual: residual,
            sampleCount: samples.count, occupiedAngularBins: occupiedCount,
            model: .conic, profile: nil, profileFallbackReason: nil
        )
    }

    /// Prefer the physically richer amorphous-ring profile, but never discard
    /// a valid conic calibration merely because the profile is absent,
    /// underconstrained, or incompatible with crystalline/overlapping signal.
    package static func fitBestAvailable(
        pattern: DiffractionPattern,
        centerQX: Double,
        centerQY: Double,
        innerRadius: Double,
        outerRadius: Double,
        maximumConicResidual: Double = 0.2,
        maximumProfileResidual: Double = 0.22
    ) throws -> EllipseCalibrationFit {
        // A broad/asymmetric ring can legitimately exceed the strict conic
        // publication residual while still providing a useful profile seed.
        let conic = try fit1D(
            pattern: pattern,
            centerQX: centerQX, centerQY: centerQY,
            innerRadius: innerRadius, outerRadius: outerRadius,
            maximumResidual: max(0.4, maximumConicResidual)
        )
        do {
            return try fitAmorphousRing(
                pattern: pattern, initial: conic,
                centerQX: centerQX, centerQY: centerQY,
                innerRadius: innerRadius, outerRadius: outerRadius,
                maximumResidual: maximumProfileResidual
            )
        } catch {
            guard conic.conicResidual <= maximumConicResidual else { throw error }
            return EllipseCalibrationFit(
                centerQX: conic.centerQX, centerQY: conic.centerQY,
                a: conic.a, b: conic.b, theta: conic.theta,
                normalizedResidual: conic.normalizedResidual,
                conicResidual: conic.conicResidual,
                sampleCount: conic.sampleCount,
                occupiedAngularBins: conic.occupiedAngularBins,
                model: .conic, profile: nil,
                profileFallbackReason: error.localizedDescription
            )
        }
    }

    /// Bounded Levenberg–Marquardt refinement of py4DSTEM's calibration-module
    /// 11-parameter model. We optimize equivalent user-facing `(a,b,theta)`
    /// variables instead of unconstrained `(A,B,C)`, then evaluate the exact
    /// canonical model. This is an intentional numerical-stability deviation:
    /// every candidate remains a physical ellipse.
    package static func fitAmorphousRing(
        pattern: DiffractionPattern,
        initial: EllipseCalibrationFit,
        centerQX: Double,
        centerQY: Double,
        innerRadius: Double,
        outerRadius: Double,
        maximumResidual: Double = 0.22
    ) throws -> EllipseCalibrationFit {
        struct Sample {
            package let x: Double
            package let y: Double
            package let value: Double
        }
        guard pattern.qy > 2, pattern.qx > 2,
              pattern.pixels.count == pattern.qy * pattern.qx,
              innerRadius >= 0, outerRadius > innerRadius,
              maximumResidual > 0 else {
            throw FitError.invalidInput("dimensions or profile bounds are invalid")
        }
        var samples: [Sample] = []
        var minimum = Double.greatestFiniteMagnitude
        var maximum = -Double.greatestFiniteMagnitude
        var globalMaximum = maximum
        for value in pattern.pixels where value.isFinite {
            globalMaximum = max(globalMaximum, Double(value))
        }
        for qx in 0..<pattern.qy {
            let dx = Double(qx) - centerQX
            for qy in 0..<pattern.qx {
                let dy = Double(qy) - centerQY
                let radius = hypot(dx, dy)
                guard radius > innerRadius, radius < outerRadius else { continue }
                let value = Double(pattern.pixels[qx * pattern.qx + qy])
                guard value.isFinite else { continue }
                samples.append(Sample(x: Double(qx), y: Double(qy), value: value))
                minimum = min(minimum, value)
                maximum = max(maximum, value)
            }
        }
        let dynamicRange = maximum - minimum
        guard samples.count >= 32, dynamicRange.isFinite,
              dynamicRange > max(1, abs(maximum)) * 1e-6 else {
            throw FitError.insufficientSignal
        }

        let ringWidth = outerRadius - innerRadius
        let intensityLimit = 5 * max(1, abs(globalMaximum), dynamicRange)
        let sigmaLimit = max(2, outerRadius * 2)
        let centerLimit = max(2, ringWidth)
        let axisMinimum = max(1, innerRadius * 0.5)
        let axisMaximum = max(axisMinimum + 1, outerRadius * 1.5)
        let backgroundLower = minimum - 2 * dynamicRange
        let backgroundUpper = maximum + 2 * dynamicRange

        // [I0,I1,sigma0,sigma1,sigma2,c,x0,y0,a,b,theta]
        var parameters = [
            max(0, globalMaximum - minimum), dynamicRange,
            max(1, innerRadius / 2), max(1, ringWidth / 4), max(1, ringWidth / 4),
            minimum, initial.centerQX, initial.centerQY,
            initial.a, initial.b, initial.theta,
        ]
        let scales = [
            max(1, dynamicRange), max(1, dynamicRange),
            max(1, innerRadius / 2), max(1, ringWidth / 4), max(1, ringWidth / 4),
            max(1, dynamicRange), 1, 1,
            max(1, initial.a), max(1, initial.b), 1,
        ]

        func bounded(_ input: [Double]) -> [Double] {
            var p = input
            p[0] = min(intensityLimit, max(0, p[0]))
            p[1] = min(intensityLimit, max(0, p[1]))
            for index in 2...4 { p[index] = min(sigmaLimit, max(0.25, p[index])) }
            p[5] = min(backgroundUpper, max(backgroundLower, p[5]))
            p[6] = min(Double(pattern.qy - 1), max(0, p[6]))
            p[6] = min(centerQX + centerLimit, max(centerQX - centerLimit, p[6]))
            p[7] = min(Double(pattern.qx - 1), max(0, p[7]))
            p[7] = min(centerQY + centerLimit, max(centerQY - centerLimit, p[7]))
            p[8] = min(axisMaximum, max(axisMinimum, p[8]))
            p[9] = min(axisMaximum, max(axisMinimum, p[9]))
            if p[8] < p[9] {
                p.swapAt(8, 9)
                p[10] += .pi / 2
            }
            p[10].formTruncatingRemainder(dividingBy: .pi)
            if p[10] < 0 { p[10] += .pi }
            return p
        }

        func predictions(_ p: [Double], indices: [Int]) -> [Double] {
            let a = p[8], b = p[9], theta = p[10]
            let sinTheta = sin(theta), cosTheta = cos(theta)
            let a2 = a * a, b2 = b * b
            let sin2 = sinTheta * sinTheta, cos2 = cosTheta * cosTheta
            var A = sin2 / b2 + cos2 / a2
            var B = 2 * (b2 - a2) * sinTheta * cosTheta / (a2 * b2)
            var C = cos2 / b2 + sin2 / a2
            let radius = (a + b) / 2
            let radius2 = radius * radius
            A *= radius2; B *= radius2; C *= radius2
            let twoSigma0 = 2 * p[2] * p[2]
            let twoSigma1 = 2 * p[3] * p[3]
            let twoSigma2 = 2 * p[4] * p[4]
            return indices.map { index in
                let sample = samples[index]
                let dx = sample.x - p[6], dy = sample.y - p[7]
                let ellipticalRadius2 = max(0, A * dx * dx + B * dx * dy + C * dy * dy)
                let delta = sqrt(ellipticalRadius2) - radius
                let ringSigma = delta < 0 ? twoSigma1 : twoSigma2
                return p[0] * exp(-ellipticalRadius2 / twoSigma0)
                    + p[1] * exp(-(delta * delta) / ringSigma) + p[5]
            }
        }

        func optimize(_ start: [Double], indices: [Int]) throws -> [Double] {
            var p = bounded(start)
            var predicted = predictions(p, indices: indices)
            var residual = zip(predicted, indices).map { value, index in
                value - samples[index].value
            }
            var cost = residual.reduce(0) { $0 + $1 * $1 }
            guard cost.isFinite else { throw FitError.didNotConverge }
            var damping = 1e-3
            var acceptedSteps = 0
            let epsilon = 1e-4
            for _ in 0..<80 {
                var columns = [[Double]]()
                columns.reserveCapacity(parameters.count)
                for parameter in parameters.indices {
                    var plus = p, minus = p
                    plus[parameter] += scales[parameter] * epsilon
                    minus[parameter] -= scales[parameter] * epsilon
                    plus = bounded(plus); minus = bounded(minus)
                    let high = predictions(plus, indices: indices)
                    let low = predictions(minus, indices: indices)
                    columns.append(zip(high, low).map { ($0 - $1) / (2 * epsilon) })
                }
                var normal = Array(
                    repeating: [Double](repeating: 0, count: parameters.count),
                    count: parameters.count
                )
                var gradient = [Double](repeating: 0, count: parameters.count)
                for row in parameters.indices {
                    for sampleIndex in residual.indices {
                        gradient[row] += columns[row][sampleIndex] * residual[sampleIndex]
                    }
                    for column in row..<parameters.count {
                        var value = 0.0
                        for sampleIndex in residual.indices {
                            value += columns[row][sampleIndex] * columns[column][sampleIndex]
                        }
                        normal[row][column] = value
                        normal[column][row] = value
                    }
                }
                for diagonal in parameters.indices {
                    normal[diagonal][diagonal] += damping
                        * max(normal[diagonal][diagonal], 1e-12)
                }
                guard let step = solve(normal, rhs: gradient.map { -$0 }) else {
                    damping *= 10
                    continue
                }
                var candidate = p
                for index in parameters.indices { candidate[index] += step[index] * scales[index] }
                candidate = bounded(candidate)
                let trialPrediction = predictions(candidate, indices: indices)
                let trialResidual = zip(trialPrediction, indices).map { value, index in
                    value - samples[index].value
                }
                let trialCost = trialResidual.reduce(0) { $0 + $1 * $1 }
                if trialCost < cost {
                    let relativeImprovement = (cost - trialCost) / max(cost, 1e-20)
                    p = candidate; predicted = trialPrediction; residual = trialResidual
                    cost = trialCost; acceptedSteps += 1
                    damping = max(1e-10, damping / 3)
                    let stepNorm = sqrt(step.reduce(0) { $0 + $1 * $1 })
                    if stepNorm < 1e-7 || relativeImprovement < 1e-10 { break }
                } else {
                    damping *= 10
                }
            }
            guard acceptedSteps > 0, p.allSatisfy(\.isFinite) else {
                throw FitError.didNotConverge
            }
            return p
        }

        let allIndices = Array(samples.indices)
        parameters = try optimize(parameters, indices: allIndices)

        // One robust refit mirrors py4DSTEM's optional outlier refinement while
        // keeping the final acceptance residual defined over every selected pixel.
        let firstPrediction = predictions(parameters, indices: allIndices)
        let firstResiduals = zip(firstPrediction, samples).map { value, sample in
            value - sample.value
        }
        let centerResidual = median(firstResiduals) ?? 0
        let mad = median(firstResiduals.map { abs($0 - centerResidual) }) ?? 0
        if mad > 0 {
            let threshold = 4 * 1.4826 * mad
            let inliers = allIndices.filter { abs(firstResiduals[$0] - centerResidual) <= threshold }
            if inliers.count * 10 >= samples.count * 7, inliers.count < samples.count {
                parameters = try optimize(parameters, indices: inliers)
            }
        }

        let finalPrediction = predictions(parameters, indices: allIndices)
        let finalCost = zip(finalPrediction, samples).reduce(0.0) { partial, pair in
            let error = pair.0 - pair.1.value
            return partial + error * error
        }
        let residual = sqrt(finalCost / Double(samples.count)) / dynamicRange
        guard residual.isFinite, residual <= maximumResidual else {
            throw FitError.excessiveResidual(residual)
        }
        guard hypot(parameters[6] - centerQX, parameters[7] - centerQY) <= centerLimit,
              parameters[8] / parameters[9] <= 5 else {
            throw FitError.invalidEllipse
        }
        return EllipseCalibrationFit(
            centerQX: parameters[6], centerQY: parameters[7],
            a: parameters[8], b: parameters[9], theta: parameters[10],
            normalizedResidual: residual, conicResidual: initial.conicResidual,
            sampleCount: samples.count,
            occupiedAngularBins: initial.occupiedAngularBins,
            model: .asymmetricGaussian,
            profile: EllipseProfileParameters(
                centralIntensity: parameters[0], ringIntensity: parameters[1],
                centralSigma: parameters[2], innerSigma: parameters[3],
                outerSigma: parameters[4], background: parameters[5]
            ),
            profileFallbackReason: nil
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
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
