//
//  VirtualAperture.metal
//  Role: Virtual detector imaging. One GPU thread per real-space scan
//        position sums all detector pixels that fall inside an annulus
//        (inner..outer radius about the detector center). The result is a
//        2D real-space image: BF (inner=0), ADF, or HAADF depending on radii.
//
//  Data layout: `data` is the full cube flattened row-major as
//      data[(ry*Rx + rx)*Qy*Qx + qy*Qx + qx]
//

#include <metal_stdlib>
using namespace metal;

// MUST match ApertureParams in MetalEngine.swift (all 4-byte fields).
struct ApertureParams {
    uint  ry;
    uint  rx;
    uint  qy;
    uint  qx;
    float cx;
    float cy;
    float rInner;
    float rOuter;
};

kernel void virtualAperture(const device float    *data    [[buffer(0)]],
                            device float           *outImg  [[buffer(1)]],
                            constant ApertureParams &p      [[buffer(2)]],
                            uint2 gid [[thread_position_in_grid]])
{
    // gid.x = scan column (rx), gid.y = scan row (ry)
    if (gid.x >= p.rx || gid.y >= p.ry) { return; }

    const uint scanIdx = gid.y * p.rx + gid.x;
    const uint patPix  = p.qy * p.qx;
    const device float *pat = data + (ulong)scanIdx * patPix;

    const float rIn2  = p.rInner * p.rInner;
    const float rOut2 = p.rOuter * p.rOuter;

    float sum = 0.0f;
    for (uint y = 0; y < p.qy; ++y) {
        const float dy = float(y) - p.cy;
        const float dy2 = dy * dy;
        const uint rowBase = y * p.qx;
        for (uint x = 0; x < p.qx; ++x) {
            const float dx = float(x) - p.cx;
            const float r2 = dx * dx + dy2;
            // Half-open interval [rIn, rOut) — matches py4DSTEM's detector
            // masks (make_detector) and VirtualDetector.makeMask.
            if (r2 >= rIn2 && r2 < rOut2) {
                sum += pat[rowBase + x];
            }
        }
    }
    outImg[scanIdx] = sum;
}
