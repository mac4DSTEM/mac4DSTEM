//
//  ColormapExportParityTests.swift
//  The PNG export must equal the screen: the shader looks the LUT up with a
//  linear filter (texel centres at (i + 0.5) / 256), not the nearest index,
//  and the exported colorbar must carry the same gamma as the image.
//

import XCTest
@testable import mac4DSTEM

@MainActor
final class ColormapExportParityTests: XCTestCase {

    private func texel(_ lut: [UInt8], _ i: Int) -> [Double] {
        (0..<3).map { Double(lut[i * 4 + $0]) }
    }

    private func rgb(_ c: (UInt8, UInt8, UInt8)) -> [Double] { [Double(c.0), Double(c.1), Double(c.2)] }

    private func lerp(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] {
        zip(a, b).map { ($0 + ($1 - $0) * t).rounded() }
    }

    /// Old code: no `sampleRGB` exists (does not compile); a nearest-index stand-in gives
    /// v=0.5 -> texel 128 instead of the 127/128 midpoint, and the in-between value another texel.
    func testSampleRGBMatchesShaderLinearFilter() {
        let lut = Colormaps.lutRGBA(.inferno, count: 256)
        XCTAssertEqual(rgb(Colormaps.sampleRGB(lut, 0)), texel(lut, 0))
        XCTAssertEqual(rgb(Colormaps.sampleRGB(lut, 1)), texel(lut, 255))
        // v = 0.5 -> p = 127.5: halfway between texels 127 and 128.
        XCTAssertEqual(rgb(Colormaps.sampleRGB(lut, 0.5)), lerp(texel(lut, 127), texel(lut, 128), 0.5))
        // v = 0.3 -> p = 76.3: 30 % from texel 76 to 77.
        XCTAssertEqual(rgb(Colormaps.sampleRGB(lut, 0.3)), lerp(texel(lut, 76), texel(lut, 77), 0.3 * 256 - 0.5 - 76))
    }

    /// Old code: nearest index round(0.9196*255) = 234; the sampler lerps texels 234/235, 6/255 off in blue.
    func testApplyColormapEqualsSamplerNotNearestTexel() {
        let lut = Colormaps.lutRGBA(.inferno, count: 256)
        let v: Float = 0.9196   // inferno blue: sampler 6/255 off the nearest texel here
        let out = AppState.applyColormap([v], colormap: .inferno, lo: 0, hi: 1, gamma: 1)
        let expected = Colormaps.sampleRGB(lut, Double(v))
        XCTAssertEqual([Int(out[0]), Int(out[1]), Int(out[2])],
                       [Int(expected.0), Int(expected.1), Int(expected.2)])
        let nearest = Int((v * 255).rounded()) * 4
        XCTAssertNotEqual([out[0], out[1], out[2]], [lut[nearest], lut[nearest + 1], lut[nearest + 2]],
                          "must differ from the old nearest-index rounding")
    }

    /// Old code: the bar painted lut[i] with no gamma, so the colour at fraction 0.5 was the
    /// gamma-1 colour, not that of sqrt(0.5).
    func testColorbarRowCarriesGamma() {
        let lut = Colormaps.lutRGBA(.inferno, count: 256)
        let row = AppState.colorbarRowRGB(lut, fraction: 0.5, gamma: 2)
        XCTAssertEqual(rgb(row), rgb(Colormaps.sampleRGB(lut, 0.5.squareRoot())))
        XCTAssertNotEqual(rgb(row), rgb(Colormaps.sampleRGB(lut, 0.5)))
    }
}
