//
//  VirtualMask.metal
//  Role: General virtual-detector imaging with an arbitrary detector mask.
//        One thread per scan position sums pattern × mask over the detector.
//        The mask is built on the CPU (VirtualDetector.makeMask) and covers
//        every py4DSTEM detector mode — circle, annulus, rectangle, point,
//        and eventually elliptically-corrected or hand-drawn shapes — with
//        one kernel. The analytic annulus kernel (VirtualAperture.metal)
//        remains the fast path for interactive aperture dragging.
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

kernel void virtualMaskSum(const device float *data   [[buffer(0)]],
                           const device float *mask   [[buffer(1)]],
                           device float        *outImg [[buffer(2)]],
                           constant CubeDims   &d      [[buffer(3)]],
                           uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= d.rx || gid.y >= d.ry) { return; }

    const uint scanIdx = gid.y * d.rx + gid.x;
    const ulong patPix = (ulong)d.qy * d.qx;
    const device float *pat = data + (ulong)scanIdx * patPix;

    float sum = 0.0f;
    for (ulong i = 0; i < patPix; ++i) {
        const float m = mask[i];
        if (m != 0.0f) { sum += m * pat[i]; }
    }
    outImg[scanIdx] = sum;
}
