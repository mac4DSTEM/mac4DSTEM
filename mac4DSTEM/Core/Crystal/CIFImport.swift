//
//  CIFImport.swift
//  Role: Parser for the subset of CIF (Crystallographic Information File)
//        that actually defines a structure — cell parameters, the atom-site
//        loop, and (if present) the symmetry-equivalent-positions loop used
//        to expand the asymmetric unit to the full cell contents.
//
//  This produces a `CrystalModel` through the same validation every built-in
//  model goes through (`CrystalModel.validationIssues`). Per ROADMAP Priority
//  1 item 3, a new phase is only admitted through the generic model contract
//  with an explicit lattice, atomic basis, symmetry reduction, and structure
//  factors — and the app currently implements symmetry reduction for cubic
//  and hexagonal only. An imported cell that isn't one of those two families
//  is rejected outright here rather than silently coerced onto `.cubic`; that
//  would fabricate an IPF color key and a fundamental-zone sampling that do
//  not correspond to the actual crystal.
//
//  Errors are user-facing: every case names the offending tag, value, or
//  symbol so a scientist can find and fix the problem in their own file.
//

import Foundation

nonisolated enum CIFImportError: LocalizedError, Equatable {
    /// A required cell-parameter or atom-site coordinate tag is absent.
    case missingTag(String)
    /// A numeric value could not be parsed, even after stripping a CIF
    /// standard-uncertainty suffix like `(3)`.
    case unparsableNumber(tag: String, value: String)
    /// No `_atom_site_*` loop was found, or it produced zero rows.
    case noAtomSites
    /// An atom-site label or type symbol did not resolve to a known chemical
    /// element symbol.
    case unknownElementSymbol(String, atomSiteLabel: String)
    /// A `_symmetry_equiv_pos_as_xyz` / `_space_group_symop_operation_xyz`
    /// entry could not be parsed as an affine x,y,z expression.
    case unsupportedSymmetryOperation(String)
    /// The element resolved, but has no electron scattering-factor
    /// parameters (`ScatteringFactors` table), so kinematic structure
    /// factors cannot be computed for it.
    case unsupportedElement(symbol: String, z: Int)
    /// The cell is neither cubic nor hexagonal — the only two point groups
    /// ACOM implements symmetry reduction and IPF coloring for.
    case unsupportedPointGroup(String)
    /// The *cell metric* matches cubic or hexagonal, but the atom positions do
    /// not actually carry that family's defining rotation. Almost always a
    /// trigonal structure in the standard hexagonal setting (a = b, γ = 120°,
    /// but only a 3-fold along c — quartz, calcite, alumina, hematite), or a
    /// tetragonal/orthorhombic cell whose axes happen to be equal. Accepting
    /// these would over-symmetrize the fundamental zone and fabricate an IPF
    /// key, which is exactly what this importer exists to prevent.
    case symmetryNotSupportedByStructure(family: String, expected: String)
    /// The structure *would* carry the family's rotations if the coordinates
    /// were taken at face value, but they are written too coarsely to tell a
    /// real symmetry break from their own rounding. A separate case from
    /// `symmetryNotSupportedByStructure` because the two say opposite things
    /// about the user's structure, and only one of them is true.
    case symmetryUnresolvableAtWrittenPrecision(family: String, decimals: Int)
    /// The assembled model failed `CrystalModel.validationIssues` for a
    /// reason not already surfaced as a more specific case above.
    case invalidModel([String])

    var errorDescription: String? {
        switch self {
        case .missingTag(let tag):
            return "CIF is missing the required tag \(tag)."
        case .unparsableNumber(let tag, let value):
            return "Could not parse a number from \(tag) = \"\(value)\"."
        case .noAtomSites:
            return "CIF has no _atom_site_* loop (or it has no rows) — there is no atomic basis to import."
        case .unknownElementSymbol(let symbol, let label):
            return "Atom site \"\(label)\" has an unrecognized element symbol \"\(symbol)\"."
        case .unsupportedSymmetryOperation(let op):
            return "Could not parse symmetry operation \"\(op)\" as an x,y,z expression."
        case .unsupportedElement(let symbol, let z):
            return "Element \(symbol) (Z=\(z)) has no electron scattering-factor parameters; ACOM cannot use it."
        case .unsupportedPointGroup(let detail):
            return "Cell is not cubic or hexagonal (\(detail)); mac4DSTEM only implements cubic and hexagonal symmetry reduction, so this structure is rejected rather than mismapped onto a point group it doesn't have."
        case .symmetryNotSupportedByStructure(let family, let expected):
            return "Cell parameters look \(family), but the atom positions have no \(expected) — the structure does not actually have \(family) symmetry (a trigonal cell in the hexagonal setting is the usual cause). mac4DSTEM implements symmetry reduction for cubic and hexagonal only, so this is rejected rather than over-symmetrized."
        case .symmetryUnresolvableAtWrittenPrecision(let family, let decimals):
            return "The atom positions are written to \(decimals) decimal places, which is too coarse to confirm \(family) symmetry — at that precision a real symmetry break is indistinguishable from the rounding in the coordinates themselves. mac4DSTEM will not assume the symmetry, because assuming it would fabricate an orientation colour key. Re-export the CIF with more decimal places."
        case .invalidModel(let issues):
            return "Imported crystal model failed validation: \(issues.joined(separator: "; "))."
        }
    }
}

nonisolated enum CIFImport {

    /// Parse `cifText` and build a validated, `.imported` `CrystalModel`.
    /// `fileBaseName` (typically the source filename without extension) is
    /// used to build a stable model id and as the display-name fallback when
    /// the CIF's own `data_` block name is empty.
    static func crystalModel(from cifText: String, fileBaseName: String) throws -> CrystalModel {
        let parsed = try parse(cifText)
        // The metric only proposes a family; the atom positions have to
        // confirm it, or a trigonal cell in the hexagonal setting would be
        // over-symmetrized into `.hexagonal`. See `verifyFamily`.
        let symmetry = try classifyFamily(
            a: parsed.a, b: parsed.b, c: parsed.c,
            alphaDeg: parsed.alpha, betaDeg: parsed.beta, gammaDeg: parsed.gamma
        )
        try verifyFamily(
            symmetry, sites: parsed.sites, coarsestHalfStep: parsed.coarsestHalfStep
        )
        let crystal = Crystal(
            a: parsed.a, b: parsed.b, c: parsed.c,
            alphaDeg: parsed.alpha, betaDeg: parsed.beta, gammaDeg: parsed.gamma,
            sites: parsed.sites
        )
        // Reuse the same "no scattering factor" gate the built-in/custom
        // crystal editors rely on, rather than duplicating its logic. The
        // symbol lookup falls back to the full 1–118 table (not just
        // ScatteringFactors.symbols, which stops at Z=103) so an element like
        // Rf still gets its real symbol in the error, not "Z104".
        if let firstUnsupportedZ = crystal.unsupportedElements.first {
            let symbol = elementZToSymbol[firstUnsupportedZ] ?? "Z\(firstUnsupportedZ)"
            throw CIFImportError.unsupportedElement(symbol: symbol, z: firstUnsupportedZ)
        }

        let sanitizedBase = sanitize(fileBaseName)
        let displayName = (parsed.dataBlockName?.isEmpty == false) ? parsed.dataBlockName! : fileBaseName
        let model = CrystalModel(
            id: "imported_\(sanitizedBase)",
            displayName: displayName,
            crystal: crystal,
            symmetry: symmetry,
            source: .imported
        )
        let issues = model.validationIssues
        guard issues.isEmpty else {
            throw CIFImportError.invalidModel(issues.map(\.message))
        }
        return model
    }

    // MARK: - Parsed intermediate structure

    private struct ParsedStructure {
        var dataBlockName: String?
        var a: Double, b: Double, c: Double
        var alpha: Double, beta: Double, gamma: Double
        var sites: [AtomSite]
        /// Coarsest rounding half-step over every written fractional
        /// coordinate — the precision the whole structure is limited by.
        var coarsestHalfStep: Double
    }

    /// One asymmetric-unit site plus how precisely each of its coordinates was
    /// *written*. `halfStep` is the half-width of the rounding interval of the
    /// literal text — 5e-4 for `0.333`, 0 for `0.2500` (exactly ¼). Symmetry
    /// expansion propagates it, which is the only way to tell "these two images
    /// are the same site, blurred by rounding" from "these are two atoms".
    private struct BaseSite {
        let z: Int
        let occupancy: Double
        let position: SIMD3<Double>
        let halfStep: SIMD3<Double>
    }

    private static func parse(_ text: String) throws -> ParsedStructure {
        let tokens = tokenize(text)

        var dataBlockName: String?
        var cellValues: [String: String] = [:]
        var atomSiteRows: [[String: String]] = []
        var symmetryOps: [String] = []
        var haveSymmetryLoop = false

        func isTag(_ token: String) -> Bool { token.hasPrefix("_") }
        func isLoop(_ token: String) -> Bool { token.lowercased() == "loop_" }
        func isDataBlock(_ token: String) -> Bool { token.lowercased().hasPrefix("data_") }

        var index = 0
        while index < tokens.count {
            let token = tokens[index]

            if isDataBlock(token) {
                if dataBlockName == nil {
                    let name = String(token.dropFirst("data_".count))
                    dataBlockName = name.isEmpty ? nil : name
                }
                index += 1
                continue
            }

            if isLoop(token) {
                index += 1
                var loopTags: [String] = []
                while index < tokens.count, isTag(tokens[index]) {
                    loopTags.append(tokens[index].lowercased())
                    index += 1
                }
                guard !loopTags.isEmpty else { continue }

                var values: [String] = []
                while index < tokens.count,
                      !isTag(tokens[index]), !isLoop(tokens[index]), !isDataBlock(tokens[index]) {
                    values.append(tokens[index])
                    index += 1
                }
                let rowCount = values.count / loopTags.count
                var rows: [[String: String]] = []
                rows.reserveCapacity(rowCount)
                for row in 0..<rowCount {
                    var fields: [String: String] = [:]
                    for (column, tag) in loopTags.enumerated() {
                        fields[tag] = values[row * loopTags.count + column]
                    }
                    rows.append(fields)
                }

                if loopTags.contains("_atom_site_fract_x") {
                    atomSiteRows.append(contentsOf: rows)
                } else if loopTags.contains("_symmetry_equiv_pos_as_xyz")
                    || loopTags.contains("_space_group_symop_operation_xyz") {
                    haveSymmetryLoop = true
                    let key = loopTags.contains("_symmetry_equiv_pos_as_xyz")
                        ? "_symmetry_equiv_pos_as_xyz" : "_space_group_symop_operation_xyz"
                    for row in rows {
                        if let op = row[key] { symmetryOps.append(op) }
                    }
                }
                continue
            }

            if isTag(token) {
                let tag = token.lowercased()
                guard index + 1 < tokens.count else { break }
                cellValues[tag] = tokens[index + 1]
                index += 2
                continue
            }

            // Stray value with no owning tag/loop (e.g. leftover from a
            // construct we don't model) — skip it and keep scanning.
            index += 1
        }

        func requiredNumber(_ tag: String) throws -> Double {
            guard let raw = cellValues[tag] else { throw CIFImportError.missingTag(tag) }
            return try parseNumber(raw, tag: tag)
        }

        let a = try requiredNumber("_cell_length_a")
        let b = try requiredNumber("_cell_length_b")
        let c = try requiredNumber("_cell_length_c")
        let alpha = try requiredNumber("_cell_angle_alpha")
        let beta = try requiredNumber("_cell_angle_beta")
        let gamma = try requiredNumber("_cell_angle_gamma")

        guard !atomSiteRows.isEmpty else { throw CIFImportError.noAtomSites }

        var baseSites: [BaseSite] = []
        baseSites.reserveCapacity(atomSiteRows.count)
        for row in atomSiteRows {
            let label = row["_atom_site_label"] ?? "?"
            guard let xRaw = row["_atom_site_fract_x"] else {
                throw CIFImportError.missingTag("_atom_site_fract_x")
            }
            guard let yRaw = row["_atom_site_fract_y"] else {
                throw CIFImportError.missingTag("_atom_site_fract_y")
            }
            guard let zRaw = row["_atom_site_fract_z"] else {
                throw CIFImportError.missingTag("_atom_site_fract_z")
            }
            let x = try parseNumber(xRaw, tag: "_atom_site_fract_x (\(label))")
            let y = try parseNumber(yRaw, tag: "_atom_site_fract_y (\(label))")
            let zCoord = try parseNumber(zRaw, tag: "_atom_site_fract_z (\(label))")
            let occupancy: Double
            if let occRaw = row["_atom_site_occupancy"] {
                occupancy = try parseNumber(occRaw, tag: "_atom_site_occupancy (\(label))")
            } else {
                occupancy = 1.0
            }
            let symbolSource = row["_atom_site_type_symbol"] ?? label
            let symbol = elementSymbol(from: symbolSource)
            guard let atomicNumber = elementSymbolToZ[symbol] else {
                throw CIFImportError.unknownElementSymbol(symbolSource, atomSiteLabel: label)
            }
            baseSites.append(BaseSite(
                z: atomicNumber, occupancy: occupancy,
                position: SIMD3(x, y, zCoord),
                halfStep: SIMD3(
                    coordinateHalfStep(xRaw), coordinateHalfStep(yRaw), coordinateHalfStep(zRaw)
                )
            ))
        }

        let sites: [AtomSite]
        if haveSymmetryLoop, !symmetryOps.isEmpty {
            let ops = try symmetryOps.map { try parseSymmetryOperation($0) }
            // Duplicate detection is a real-space question, so it needs the
            // cell metric. The site list is irrelevant to `latReal`.
            let lattice = Crystal(
                a: a, b: b, c: c, alphaDeg: alpha, betaDeg: beta, gammaDeg: gamma, sites: []
            ).latReal
            sites = expand(baseSites, using: ops, latReal: lattice)
        } else {
            // No symmetry loop: the listed sites are already the complete
            // cell contents (P1). Wrap anyway — coordinates outside [0,1) are
            // legal CIF, structure factors are periodic so it changes no
            // physics, and leaving them raw would hide a close contact from a
            // detector that only searches the neighbouring cells.
            sites = baseSites.map {
                AtomSite(z: $0.z, fractional: wrap($0.position), occupancy: $0.occupancy)
            }
        }

        let coarsestHalfStep = baseSites.reduce(0.0) {
            max($0, max($1.halfStep.x, max($1.halfStep.y, $1.halfStep.z)))
        }
        return ParsedStructure(
            dataBlockName: dataBlockName,
            a: a, b: b, c: c, alpha: alpha, beta: beta, gamma: gamma,
            sites: sites, coarsestHalfStep: coarsestHalfStep
        )
    }

    // MARK: - Tokenizer

    /// Turns CIF text into a flat token stream: `data_...` block markers,
    /// `loop_`, `_tag` names, and (possibly quoted or semicolon-delimited)
    /// values, with `#` comments stripped outside of quotes/text fields.
    private static func tokenize(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var tokens: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix(";") {
                // Multi-line semicolon text field: collapse to one token.
                var content = String(line.dropFirst())
                index += 1
                while index < lines.count, !lines[index].hasPrefix(";") {
                    content += "\n" + lines[index]
                    index += 1
                }
                if index < lines.count { index += 1 } // consume terminating ';'
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { tokens.append(trimmed) }
                continue
            }
            tokens.append(contentsOf: tokenizeLine(line))
            index += 1
        }
        return tokens
    }

    private static func tokenizeLine(_ line: String) -> [String] {
        var result: [String] = []
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " || c == "\t" { i += 1; continue }
            if c == "#" { break } // rest of line is a comment
            if c == "'" || c == "\"" {
                let quote = c
                var j = i + 1
                var value = ""
                while j < chars.count {
                    if chars[j] == quote {
                        let next = j + 1 < chars.count ? chars[j + 1] : " "
                        if next == " " || next == "\t" { break }
                    }
                    value.append(chars[j])
                    j += 1
                }
                result.append(value)
                i = min(j + 1, chars.count)
                continue
            }
            var value = ""
            while i < chars.count, !chars[i].isWhitespace, chars[i] != "#" {
                value.append(chars[i])
                i += 1
            }
            result.append(value)
        }
        return result
    }

    // MARK: - Numbers

    /// Strips a CIF standard-uncertainty suffix, e.g. `4.0782(3)` -> `4.0782`.
    private static func parseNumber(_ raw: String, tag: String) throws -> Double {
        var text = raw
        if let parenIndex = text.firstIndex(of: "(") {
            text = String(text[text.startIndex..<parenIndex])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(text) else {
            throw CIFImportError.unparsableNumber(tag: tag, value: raw)
        }
        return value
    }

    /// How far a written fractional coordinate may sit from its true value,
    /// judged from the literal text alone.
    ///
    /// Two very different things are written to the same number of decimals.
    /// `0.2500` is *exactly* ¼ — a special position, carrying no error at all.
    /// `0.333` is ⅓ spelled to 3 decimals and is wrong by 3.3e-4, which is 3×
    /// the old fixed 1e-4 dedup tolerance and is why P6₃/mmc magnesium at
    /// ordinary precision expanded to 6 atoms instead of 2 (backlog #14).
    ///
    /// The bound is `10⁻ᵈ`, not half of it, because **CIF writers truncate as
    /// often as they round**: `0.6666` and `0.666666` are both ⅔ truncated,
    /// and truncation error reaches a full ulp of the last decimal, twice what
    /// a rounding assumption allows. Assuming rounding made this erratic in the
    /// worst way — admitting truncated ⅔ at 5 and 7 decimals while rejecting it
    /// at 3, 4 and 6, on which side of the bound the residual happened to land.
    ///
    /// A value landing exactly on a small dyadic rational is treated as exact.
    /// Only denominators 1, 2, 4, 8, 16 are worth testing: a terminating
    /// decimal `m/10ᵈ` can never equal `n/3` in lowest terms, so thirds and
    /// sixths — the hexagonal special positions — are unreachable here by
    /// construction and are handled by the decimal branch below.
    ///
    /// Capped at 1e-2 (2 decimals). Coarser than that is not real published
    /// data, and widening further would start merging atoms that really are
    /// distinct. Such a file keeps its duplicates and is rejected loudly by
    /// `CrystalModel`'s close-contact check rather than silently mangled.
    private static func coordinateHalfStep(_ raw: String) -> Double {
        var text = raw
        if let parenIndex = text.firstIndex(of: "(") {
            text = String(text[text.startIndex..<parenIndex])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(text) else { return 0 }

        for denominator in [1.0, 2, 4, 8, 16] {
            let scaled = value * denominator
            if abs(scaled - scaled.rounded()) <= 1e-12 * max(1, abs(scaled)) { return 0 }
        }

        guard let dot = text.firstIndex(of: ".") else { return 1e-2 }
        let decimals = text.distance(from: text.index(after: dot), to: text.endIndex)
        return min(1e-2, pow(10, -Double(decimals)))
    }

    // MARK: - Element symbols

    /// Strips trailing oxidation-state/isotope markers, e.g. `Si1` -> `Si`,
    /// `Fe3+` -> `Fe`, `O2-` -> `O`.
    private static func elementSymbol(from raw: String) -> String {
        var chars = Array(raw)
        while let last = chars.last, last.isNumber || last == "+" || last == "-" {
            chars.removeLast()
        }
        let stripped = String(chars)
        guard let first = stripped.first else { return stripped }
        // Normalize case: "SI" or "si" -> "Si".
        let rest = stripped.dropFirst().lowercased()
        return String(first).uppercased() + rest
    }

    /// Chemical symbol -> atomic number, covering every element mac4DSTEM
    /// can name (1–118). Elements beyond the scattering-factor table's reach
    /// (Z > 103) still resolve here — they're rejected later, specifically,
    /// as "no scattering factor" rather than "unrecognized symbol".
    private static let elementSymbolToZ: [String: Int] = {
        var map: [String: Int] = [:]
        for (z, symbol) in ScatteringFactors.symbols { map[symbol] = z }
        let beyondTable: [(Int, String)] = [
            (104, "Rf"), (105, "Db"), (106, "Sg"), (107, "Bh"), (108, "Hs"),
            (109, "Mt"), (110, "Ds"), (111, "Rg"), (112, "Cn"), (113, "Nh"),
            (114, "Fl"), (115, "Mc"), (116, "Lv"), (117, "Ts"), (118, "Og"),
        ]
        for (z, symbol) in beyondTable { map[symbol] = z }
        return map
    }()

    /// Reverse of `elementSymbolToZ`, for building error messages that name
    /// an element beyond the scattering-factor table by its real symbol.
    private static let elementZToSymbol: [Int: String] = {
        Dictionary(uniqueKeysWithValues: elementSymbolToZ.map { ($1, $0) })
    }()

    // MARK: - Symmetry operations

    /// One affine fractional-coordinate symmetry operation: `p' = M·p + t`.
    private struct SymOp {
        let rowX: SIMD3<Double>
        let rowY: SIMD3<Double>
        let rowZ: SIMD3<Double>
        let translation: SIMD3<Double>

        func apply(_ p: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(
                rowX.x * p.x + rowX.y * p.y + rowX.z * p.z + translation.x,
                rowY.x * p.x + rowY.y * p.y + rowY.z * p.z + translation.y,
                rowZ.x * p.x + rowZ.y * p.y + rowZ.z * p.z + translation.z
            )
        }
    }

    /// Parses `"x,y,z"`, `"-x,-y,-z"`, `"1/2+x,1/2-y,z"`, `"x-y,x,-z+1/3"`, …
    private static func parseSymmetryOperation(_ raw: String) throws -> SymOp {
        let components = raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard components.count == 3, components.allSatisfy({ !$0.isEmpty }) else {
            throw CIFImportError.unsupportedSymmetryOperation(raw)
        }
        var rows: [SIMD3<Double>] = []
        var translation = SIMD3<Double>(0, 0, 0)
        for (axis, component) in components.enumerated() {
            let (coefficients, constant) = try parseSymmetryComponent(component, raw: raw)
            rows.append(coefficients)
            switch axis {
            case 0: translation.x = constant
            case 1: translation.y = constant
            default: translation.z = constant
            }
        }
        return SymOp(rowX: rows[0], rowY: rows[1], rowZ: rows[2], translation: translation)
    }

    /// Parses one comma-separated component (e.g. `"1/2+x"`) into (x,y,z
    /// coefficients, constant translation).
    private static func parseSymmetryComponent(
        _ component: String, raw: String
    ) throws -> (SIMD3<Double>, Double) {
        let chars = Array(component.lowercased().replacingOccurrences(of: " ", with: ""))
        guard !chars.isEmpty else { throw CIFImportError.unsupportedSymmetryOperation(raw) }

        var coefficients = SIMD3<Double>(0, 0, 0)
        var constant = 0.0
        var i = 0
        while i < chars.count {
            var sign = 1.0
            if chars[i] == "+" { i += 1 } else if chars[i] == "-" { sign = -1.0; i += 1 }
            guard i < chars.count else { throw CIFImportError.unsupportedSymmetryOperation(raw) }

            let numStart = i
            while i < chars.count, chars[i].isNumber || chars[i] == "/" || chars[i] == "." {
                i += 1
            }
            let numericString = String(chars[numStart..<i])
            let hasNumeric = !numericString.isEmpty
            let magnitude = hasNumeric ? try parseFraction(numericString, raw: raw) : 1.0

            if i < chars.count, "xyz".contains(chars[i]) {
                switch chars[i] {
                case "x": coefficients.x += sign * magnitude
                case "y": coefficients.y += sign * magnitude
                default: coefficients.z += sign * magnitude
                }
                i += 1
            } else if hasNumeric {
                constant += sign * magnitude
            } else {
                throw CIFImportError.unsupportedSymmetryOperation(raw)
            }
        }
        return (coefficients, constant)
    }

    private static func parseFraction(_ text: String, raw: String) throws -> Double {
        let parts = text.split(separator: "/")
        if parts.count == 1, let value = Double(parts[0]) { return value }
        if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]),
           denominator != 0 {
            return numerator / denominator
        }
        throw CIFImportError.unsupportedSymmetryOperation(raw)
    }

    /// Applies every symmetry operation to every asymmetric-unit site,
    /// wraps into [0,1) fractional coordinates, and deduplicates positions
    /// that land on the same site.
    ///
    /// The dedup tolerance is *derived from the input*, not fixed. A site on a
    /// special position is mapped onto itself by several operators, and each
    /// image inherits the rounding error of the coordinates it was built from —
    /// amplified by the operator's coefficients, since a row like `x-y` sums
    /// two rounded numbers. Two images are the same atom when they agree to
    /// within the error the *written precision* allows for both of them.
    ///
    /// A fixed tolerance cannot do this job: the old 1e-4 was three times too
    /// tight for ⅓ written as `0.333`, so P6₃/mmc magnesium expanded to 6 atoms
    /// instead of 2 and its structure factors were silently wrong (backlog
    /// #14). Simply loosening it to 5e-3 would still fail at 2 decimals and
    /// would begin merging distinct atoms in large cells.
    ///
    /// A merge additionally requires the two images to be within
    /// `maxMergeDistance` in *real* space, which is what keeps a coarse cell
    /// from collapsing chemistry: fractional tolerance means nothing until it
    /// is multiplied by the lattice.
    private static func expand(
        _ baseSites: [BaseSite], using ops: [SymOp], latReal: [SIMD3<Double>]
    ) -> [AtomSite] {
        /// Ceiling on how far apart two images may be and still be called the
        /// same atom. Rounding residuals live well below it — the worst case
        /// this importer sees is ⅓ truncated to 2 decimals in a 3.2 Å cell,
        /// about 0.06 Å. Real atoms live well above it.
        ///
        /// It is deliberately far tighter than the 0.5 Å close-contact limit,
        /// and the gap between the two is the point: a pair that is too far
        /// apart to be a rounding artefact but too close to be chemistry is
        /// left in place and **rejected** by `CrystalModel.validationIssues`.
        /// Merging that band instead would silently *delete* an atom, which is
        /// the same class of quiet error as #14 with the sign flipped.
        let maxMergeDistance = 0.10
        let usableLattice = latReal.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }

        struct Image {
            let z: Int
            let occupancy: Double
            let position: SIMD3<Double>
            /// Per-axis rounding uncertainty carried into this image.
            let uncertainty: SIMD3<Double>
        }

        var kept: [Image] = []
        for site in baseSites {
            for op in ops {
                let mapped = wrap(op.apply(site.position))
                let uncertainty = SIMD3<Double>(
                    propagate(op.rowX, site.halfStep),
                    propagate(op.rowY, site.halfStep),
                    propagate(op.rowZ, site.halfStep)
                )
                let isDuplicate = kept.contains { existing in
                    guard existing.z == site.z else { return false }
                    let tolerance = existing.uncertainty + uncertainty
                    guard axisDelta(existing.position.x, mapped.x) <= max(tolerance.x, 1e-6),
                          axisDelta(existing.position.y, mapped.y) <= max(tolerance.y, 1e-6),
                          axisDelta(existing.position.z, mapped.z) <= max(tolerance.z, 1e-6)
                    else { return false }
                    guard usableLattice else { return true }
                    return realDistance(existing.position, mapped, latReal) <= maxMergeDistance
                }
                if !isDuplicate {
                    kept.append(Image(
                        z: site.z, occupancy: site.occupancy,
                        position: mapped, uncertainty: uncertainty
                    ))
                }
            }
        }
        return kept.map { AtomSite(z: $0.z, fractional: $0.position, occupancy: $0.occupancy) }
    }

    /// Rounding error of one output coordinate: `|c_x|·δx + |c_y|·δy + |c_z|·δz`
    /// for the operator row `(c_x, c_y, c_z)`. The translation is exact.
    private static func propagate(_ row: SIMD3<Double>, _ halfStep: SIMD3<Double>) -> Double {
        abs(row.x) * halfStep.x + abs(row.y) * halfStep.y + abs(row.z) * halfStep.z
    }

    /// Minimum-image separation along one fractional axis, in [0, 0.5].
    private static func axisDelta(_ x: Double, _ y: Double) -> Double {
        var d = abs(x - y).truncatingRemainder(dividingBy: 1)
        if d > 0.5 { d = 1 - d }
        return d
    }

    /// Real-space separation (Å) of two fractional positions, minimum image
    /// over the 27 neighbouring cells so the cell's skew is respected.
    private static func realDistance(
        _ a: SIMD3<Double>, _ b: SIMD3<Double>, _ latReal: [SIMD3<Double>]
    ) -> Double {
        let base = a - b
        var best = Double.infinity
        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    let f = base + SIMD3<Double>(Double(dx), Double(dy), Double(dz))
                    let cartesian = f.x * latReal[0] + f.y * latReal[1] + f.z * latReal[2]
                    best = min(best, (cartesian * cartesian).sum())
                }
            }
        }
        return best.squareRoot()
    }

    private static func wrap(_ v: SIMD3<Double>) -> SIMD3<Double> {
        func wrapAxis(_ value: Double) -> Double {
            var m = value.truncatingRemainder(dividingBy: 1)
            if m < 0 { m += 1 }
            if abs(m) < 1e-9 || abs(m - 1) < 1e-9 { m = 0 }
            return m
        }
        return SIMD3(wrapAxis(v.x), wrapAxis(v.y), wrapAxis(v.z))
    }

    private static func periodicDistance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let dx = axisDelta(a.x, b.x), dy = axisDelta(a.y, b.y), dz = axisDelta(a.z, b.z)
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    // MARK: - Point-group classification

    /// Determines the family from cell parameters. Only cubic and hexagonal
    /// are accepted, matching the two symmetry reductions ACOM implements
    /// (`ACOMCrystalSymmetry`); every other cell is rejected rather than
    /// silently mapped onto one of these.
    private static func classifyFamily(
        a: Double, b: Double, c: Double, alphaDeg: Double, betaDeg: Double, gammaDeg: Double
    ) throws -> ACOMCrystalSymmetry {
        func lengthsMatch(_ x: Double, _ y: Double) -> Bool {
            abs(x - y) <= 1e-3 * max(1, max(abs(x), abs(y)))
        }
        func angleMatches(_ angle: Double, _ target: Double) -> Bool {
            abs(angle - target) <= 0.05
        }

        let isCubic = lengthsMatch(a, b) && lengthsMatch(a, c)
            && angleMatches(alphaDeg, 90) && angleMatches(betaDeg, 90) && angleMatches(gammaDeg, 90)
        if isCubic { return .cubic }

        let isHexagonal = lengthsMatch(a, b)
            && angleMatches(alphaDeg, 90) && angleMatches(betaDeg, 90) && angleMatches(gammaDeg, 120)
        if isHexagonal { return .hexagonal }

        let detail = String(
            format: "a=%.4g, b=%.4g, c=%.4g Å, α=%.4g°, β=%.4g°, γ=%.4g°",
            a, b, c, alphaDeg, betaDeg, gammaDeg
        )
        throw CIFImportError.unsupportedPointGroup(detail)
    }

    /// The cell metric alone does not determine the point group: a *trigonal*
    /// structure is conventionally given in the hexagonal setting (a = b,
    /// γ = 120°) but carries only a 3-fold along c, and a tetragonal or
    /// orthorhombic cell can have accidentally equal axes. Classifying on the
    /// metric alone therefore silently over-symmetrizes quartz (P3₂21),
    /// calcite (R-3c), alumina, hematite and friends into `.hexagonal`, giving
    /// them a 12-operator reduction and an IPF key they do not have.
    ///
    /// So the metric only *proposes* a family; the structure has to confirm
    /// it. One generator is not enough — it separates the family from the one
    /// directly below it but says nothing about the Laue class *within* the
    /// family, and `.cubic`/`.hexagonal` here mean the **full** m-3m (24
    /// proper rotations) and 6/mmm (12) groups that `OrientationResult`
    /// samples and colors with. So each family is confirmed by two
    /// independent generators:
    ///
    /// | family | generator | rejects |
    /// |---|---|---|
    /// | hexagonal | 6-fold ∥ **c**: `(x,y,z) → (x−y, x, z)` | trigonal (3-fold only): quartz P3₂21, calcite R-3c |
    /// | hexagonal | 2-fold ∥ **a**: `(x,y,z) → (x−y, −y, −z)` | Laue 6/m: apatite P6₃/m |
    /// | cubic | 3-fold ∥ **⟨111⟩**: `(x,y,z) → (z, x, y)` | tetragonal with an accidentally cubic metric |
    /// | cubic | 4-fold ∥ **c**: `(x,y,z) → (−y, x, z)` | Laue m-3: pyrite Pa-3 |
    ///
    /// Together these generate the full group in each case, so passing both is
    /// the property we actually need. Every rotation may be accompanied by a
    /// translation: screw axes and glide planes are ordinary in both families,
    /// and requiring `t = 0` would reject HCP magnesium (6₃ about c,
    /// t = (0,0,½)) and diamond silicon — both shipped built-in models.
    private static func verifyFamily(
        _ family: ACOMCrystalSymmetry, sites: [AtomSite], coarsestHalfStep: Double
    ) throws {
        // Rotation parts in the *fractional* basis, so they are exact integer
        // matrices in either setting and no Cartesian conversion is needed.
        let generators: [(rotation: (SIMD3<Double>) -> SIMD3<Double>, missing: String)]
        let familyName: String
        switch family {
        case .hexagonal:
            familyName = "hexagonal"
            generators = [
                ({ SIMD3($0.x - $0.y, $0.x, $0.z) },
                 "6-fold axis along c (only a 3-fold — i.e. trigonal)"),
                ({ SIMD3($0.x - $0.y, -$0.y, -$0.z) },
                 "2-fold axis along a (Laue class 6/m, not 6/mmm)"),
            ]
        case .cubic:
            familyName = "cubic"
            generators = [
                ({ SIMD3($0.z, $0.x, $0.y) }, "3-fold axis along ⟨111⟩"),
                ({ SIMD3(-$0.y, $0.x, $0.z) },
                 "4-fold axis along c (Laue class m-3, not m-3m)"),
            ]
        case .identity:
            // `classifyFamily` never proposes `.identity` — it either returns
            // cubic/hexagonal or throws. Nothing to verify: the trivial group
            // imposes no rotation, so it cannot be over-symmetrized.
            return
        }
        guard !sites.isEmpty else { return }
        let resolutionLimited = resolutionLimitedTolerance(coarsestHalfStep: coarsestHalfStep)
        for generator in generators
        where !isSymmetry(
            generator.rotation, of: sites, positionTolerance: symmetryPositionTolerance
        ) {
            // Distinguish "this structure lacks the symmetry" from "this file
            // is not written precisely enough to tell". Both are rejections —
            // only the message differs, and only one of them is true.
            if resolutionLimited > symmetryPositionTolerance,
               isSymmetry(
                   generator.rotation, of: sites, positionTolerance: resolutionLimited
               ) {
                throw CIFImportError.symmetryUnresolvableAtWrittenPrecision(
                    family: familyName, decimals: decimalsResolved(from: coarsestHalfStep)
                )
            }
            throw CIFImportError.symmetryNotSupportedByStructure(
                family: familyName, expected: generator.missing
            )
        }
    }

    /// Fractional-coordinate agreement required to call two sites the same.
    ///
    /// Deliberately looser than the merge tolerance in `expand`, because the
    /// residual here is *amplified* rather than bare input rounding: testing
    /// `x ↦ R·x + t` with `t = x_j − R·x₀` gives an image of `R·(x − x₀) + x_j`,
    /// so with a per-coordinate half-step δ and rotation rows summing to
    /// |c| ≤ 2, one axis is uncertain by `2(δ + δ) + δ = 5δ`, and over three
    /// axes the Euclidean residual reaches ≈ 10δ. Magnesium published to the
    /// entirely ordinary 3 decimals (δ = 1e-3) is right at that figure and
    /// would be rejected as trigonal at 1e-3 — a false reject on a shipped
    /// built-in model. This clears 3-decimal data while staying an order of
    /// magnitude below real symmetry breaking: quartz's oxygen misses the
    /// 6-fold by ~0.2 fractional, not 0.005.
    ///
    /// **This is fixed on purpose — do not derive it from the file's written
    /// precision.** Doing so was tried and reverted: it let a coarsely-written
    /// file widen its own gate, and an FCC cell whose face-centre site was
    /// displaced by 0.163 Å was then admitted as full m-3m cubic. The two
    /// tolerances face opposite risks. A too-tight *merge* tolerance is loud —
    /// the duplicates it leaves behind are caught downstream. A too-loose
    /// *point-group* tolerance is silent, and fabricates an IPF colour key,
    /// which is the single outcome this whole check exists to prevent. Coarse
    /// data does not earn a wider gate; it earns the rejection below, which
    /// says precisely that.
    private static let symmetryPositionTolerance = 5e-3

    /// The tolerance the file's own precision would justify (see
    /// `symmetryPositionTolerance` for the ≈10δ derivation). Used **only to
    /// explain a rejection**, never to grant one: when a generator fails the
    /// fixed gate but would pass this one, the honest report is that the
    /// coordinates are written too coarsely to confirm the symmetry — not that
    /// the structure lacks it.
    private static func resolutionLimitedTolerance(coarsestHalfStep: Double) -> Double {
        10 * coarsestHalfStep
    }

    /// Inverse of `coordinateHalfStep`'s decimal branch, so the rejection can
    /// name the precision the file was actually written to.
    private static func decimalsResolved(from halfStep: Double) -> Int {
        guard halfStep > 0 else { return 0 }
        return max(0, Int((-log10(halfStep)).rounded()))
    }

    /// Occupancies are dimensionless and must NOT share the position
    /// tolerance: symmetry-equivalent sites in a refined, disordered structure
    /// routinely differ by a few thousandths, which 1e-3 would read as
    /// different atoms and reject. This is loose enough to absorb refinement
    /// noise and still separate the cases that matter (1.0 vs 0.5 site
    /// sharing).
    private static let symmetryOccupancyTolerance = 0.02

    /// True when some translation `t` makes `x ↦ rotation(x) + t` a symmetry
    /// of the site set — i.e. a *bijection* of it that preserves element and
    /// occupancy.
    ///
    /// Candidate translations come from mapping site 0 onto every compatible
    /// site, which is exhaustive: if the operation is a symmetry then
    /// `R·x₀ + t` must itself land on some site, so that `t` is among those
    /// enumerated. (Site 0 sitting on a special position is irrelevant — the
    /// enumeration ranges over *targets*, not sources.)
    private static func isSymmetry(
        _ rotation: (SIMD3<Double>) -> SIMD3<Double>, of sites: [AtomSite],
        positionTolerance: Double
    ) -> Bool {
        let reference = sites[0]
        let rotatedReference = rotation(reference.fractional)
        for candidate in sites where candidate.z == reference.z
            && abs(candidate.occupancy - reference.occupancy) <= symmetryOccupancyTolerance {
            let translation = candidate.fractional - rotatedReference
            // Surjectivity has to be checked, not argued: finite-tolerance
            // matching is not an equivalence relation, so two distinct sites
            // can both land within tolerance of the SAME target. Without this
            // an FCC cell carrying a split atom — a dumbbell that is at best
            // tetragonal — passes as cubic. Requiring the matched targets to
            // be distinct makes the map a genuine permutation.
            var claimed = Set<Int>()
            let isPermutation = sites.allSatisfy { site in
                let image = wrap(rotation(site.fractional) + translation)
                let target = sites.indices.first { index in
                    !claimed.contains(index)
                        && sites[index].z == site.z
                        && abs(sites[index].occupancy - site.occupancy)
                            <= symmetryOccupancyTolerance
                        && periodicDistance(sites[index].fractional, image)
                            < positionTolerance
                }
                guard let target else { return false }
                claimed.insert(target)
                return true
            }
            if isPermutation { return true }
        }
        return false
    }

    // MARK: - Misc

    private static func sanitize(_ name: String) -> String {
        let mapped = name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        let result = String(mapped)
        return result.isEmpty ? "cif" : result
    }
}
