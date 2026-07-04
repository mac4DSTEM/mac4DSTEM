//
//  DPStatistics.metal
//  Role: Whole-cube diffraction statistics — the max and mean pattern over
//        all scan positions (py4DSTEM: get_dp_max / get_dp_mean). The max
//        pattern feeds probe-size estimation for origin calibration; both are
//        useful display modes in their own right.
//
//  One thread per DETECTOR pixel, looping over scan positions. Adjacent
//  threads read adjacent addresses within each pattern slice, so reads
//  coalesce despite the large stride between iterations.
//

#include <metal_stdlib>
using namespace metal;

// MUST match CubeDims in MetalEngine.swift (all 4-byte fields).
struct CubeDims {
    uint ry;
    uint rx;
    uint qy;
    uint qx;
};

kernel void dpStatistics(const device float *data    [[buffer(0)]],
                         device float        *outMax  [[buffer(1)]],
                         device float        *outMean [[buffer(2)]],
                         constant CubeDims   &d       [[buffer(3)]],
                         uint2 gid [[thread_position_in_grid]])
{
    // gid.x = detector column (qx), gid.y = detector row (qy)
    if (gid.x >= d.qx || gid.y >= d.qy) { return; }

    const uint qIdx   = gid.y * d.qx + gid.x;
    const uint nScan  = d.ry * d.rx;
    const ulong patPix = (ulong)d.qy * d.qx;

    float vMax = -FLT_MAX;
    float vSum = 0.0f;
    for (uint s = 0; s < nScan; ++s) {
        const float v = data[(ulong)s * patPix + qIdx];
        vMax = max(vMax, v);
        vSum += v;
    }

    outMax[qIdx]  = vMax;
    outMean[qIdx] = vSum / float(nScan);
}
