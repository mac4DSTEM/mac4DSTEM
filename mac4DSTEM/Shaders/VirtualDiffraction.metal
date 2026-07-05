//
//  VirtualDiffraction.metal
//  Role: Virtual (selected-area) diffraction — the reciprocal of virtual
//        imaging. One GPU thread per DETECTOR pixel sums that pixel's value
//        across all scan positions selected by a real-space mask, producing a
//        single [Qy*Qx] diffraction pattern (py4DSTEM: get_virtual_diffraction).
//
//  Data layout: `data` is the full cube flattened row-major as
//      data[(ry*Rx + rx)*Qy*Qx + qy*Qx + qx]
//  `scanMask` is a [Ry*Rx] real-space weight image (VirtualDetector.makeMask
//  built in scan dimensions). Adjacent threads read adjacent addresses within
//  each pattern slice, so reads coalesce despite the large per-position stride.
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

kernel void virtualDiffraction(const device float *data     [[buffer(0)]],
                               const device float *scanMask [[buffer(1)]],
                               device float        *outPat  [[buffer(2)]],
                               constant CubeDims   &d       [[buffer(3)]],
                               uint2 gid [[thread_position_in_grid]])
{
    // gid.x = detector column (qx), gid.y = detector row (qy)
    if (gid.x >= d.qx || gid.y >= d.qy) { return; }

    const uint  qIdx   = gid.y * d.qx + gid.x;
    const ulong patPix = (ulong)d.qy * d.qx;
    const uint  nScan  = d.ry * d.rx;

    float sum = 0.0f;
    for (uint s = 0; s < nScan; ++s) {
        const float w = scanMask[s];
        if (w != 0.0f) { sum += w * data[(ulong)s * patPix + qIdx]; }
    }
    outPat[qIdx] = sum;
}
