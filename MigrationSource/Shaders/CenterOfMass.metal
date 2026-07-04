//
//  CenterOfMass.metal
//  Role: Differential Phase Contrast core. One GPU thread per scan position
//        computes the intensity-weighted center of mass of its CBED pattern,
//        then subtracts the reference center to give a (shiftX, shiftY) vector.
//        The stack of vectors is the DPC field; integrating it (Fourier method,
//        done on the CPU for now) yields iDPC.
//
//  Output: interleaved float2 per scan position →
//      outVec[2*scanIdx + 0] = comX shift (Qx direction)
//      outVec[2*scanIdx + 1] = comY shift (Qy direction)
//

#include <metal_stdlib>
using namespace metal;

// MUST match CoMParams in MetalEngine.swift.
struct CoMParams {
    uint  ry;
    uint  rx;
    uint  qy;
    uint  qx;
    float cx;
    float cy;
    uint  useOrigins;   // 1 → read per-position reference from `origins`
};

kernel void centerOfMass(const device float *data    [[buffer(0)]],
                         device float        *outVec  [[buffer(1)]],
                         constant CoMParams  &p       [[buffer(2)]],
                         const device float  *origins [[buffer(3)]],
                         uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= p.rx || gid.y >= p.ry) { return; }

    const uint scanIdx = gid.y * p.rx + gid.x;
    const uint patPix  = p.qy * p.qx;
    const device float *pat = data + (ulong)scanIdx * patPix;

    // Reference center: calibrated per-position origin when available
    // (fitted origin map, interleaved [x, y]), else the single global one.
    const float refX = p.useOrigins ? origins[2 * scanIdx]     : p.cx;
    const float refY = p.useOrigins ? origins[2 * scanIdx + 1] : p.cy;

    float sumI  = 0.0f;
    float sumIX = 0.0f;
    float sumIY = 0.0f;

    for (uint y = 0; y < p.qy; ++y) {
        const uint rowBase = y * p.qx;
        const float fy = float(y);
        for (uint x = 0; x < p.qx; ++x) {
            const float I = max(pat[rowBase + x], 0.0f);   // clamp negatives
            sumI  += I;
            sumIX += I * float(x);
            sumIY += I * fy;
        }
    }

    float comX = (sumI > 0.0f) ? (sumIX / sumI) : refX;
    float comY = (sumI > 0.0f) ? (sumIY / sumI) : refY;

    outVec[2 * scanIdx + 0] = comX - refX;   // shift relative to reference
    outVec[2 * scanIdx + 1] = comY - refY;
}
