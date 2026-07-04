//
//  OriginMeasure.metal
//  Role: Per-pattern origin measurement for calibration, following py4DSTEM's
//        get_origin: locate the brightest disk coarsely, then refine with a
//        center of mass restricted to a window of radius r*rscale around it.
//
//  DELIBERATE DEVIATION from py4DSTEM: the coarse step there is
//  argmax(gaussian_filter(dp, sigma=r)). A per-thread Gaussian of that width
//  is prohibitively expensive, so we take the argmax over BINNED block sums
//  with bin ≈ r instead — the same "which blob at the disk scale is
//  brightest" question. The windowed-CoM refinement that follows is identical
//  and dominates the final sub-pixel value.
//
//  Output: interleaved [x0, y0] per scan position (X = column, Y = row).
//

#include <metal_stdlib>
using namespace metal;

// MUST match OriginParams in MetalEngine.swift (all 4-byte fields).
struct OriginParams {
    uint  ry;
    uint  rx;
    uint  qy;
    uint  qx;
    float r;        // probe radius estimate (px)
    float rscale;   // CoM window = r * rscale (py4DSTEM default 1.2)
};

kernel void measureOrigin(const device float  *data   [[buffer(0)]],
                          device float         *outXY  [[buffer(1)]],
                          constant OriginParams &p     [[buffer(2)]],
                          uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= p.rx || gid.y >= p.ry) { return; }

    const uint scanIdx = gid.y * p.rx + gid.x;
    const ulong patPix = (ulong)p.qy * p.qx;
    const device float *pat = data + (ulong)scanIdx * patPix;

    // ── Coarse: brightest bin-summed block, bin ≈ probe radius ─────────────
    const uint bin = max(1u, uint(round(p.r)));
    float bestSum = -FLT_MAX;
    float coarseX = float(p.qx) * 0.5f;
    float coarseY = float(p.qy) * 0.5f;

    for (uint by = 0; by < p.qy; by += bin) {
        const uint yEnd = min(by + bin, p.qy);
        for (uint bx = 0; bx < p.qx; bx += bin) {
            const uint xEnd = min(bx + bin, p.qx);
            float s = 0.0f;
            for (uint y = by; y < yEnd; ++y) {
                const uint rowBase = y * p.qx;
                for (uint x = bx; x < xEnd; ++x) {
                    s += pat[rowBase + x];
                }
            }
            if (s > bestSum) {
                bestSum = s;
                coarseX = 0.5f * float(bx + xEnd - 1);
                coarseY = 0.5f * float(by + yEnd - 1);
            }
        }
    }

    // ── Refine: CoM within r*rscale of the coarse center ──────────────────
    const float win2 = (p.r * p.rscale) * (p.r * p.rscale);
    float sumI = 0.0f, sumIX = 0.0f, sumIY = 0.0f;

    for (uint y = 0; y < p.qy; ++y) {
        const float dy = float(y) - coarseY;
        const float dy2 = dy * dy;
        if (dy2 > win2) { continue; }
        const uint rowBase = y * p.qx;
        for (uint x = 0; x < p.qx; ++x) {
            const float dx = float(x) - coarseX;
            if (dx * dx + dy2 > win2) { continue; }
            const float I = max(pat[rowBase + x], 0.0f);
            sumI  += I;
            sumIX += I * float(x);
            sumIY += I * float(y);
        }
    }

    outXY[2 * scanIdx]     = (sumI > 0.0f) ? (sumIX / sumI) : coarseX;
    outXY[2 * scanIdx + 1] = (sumI > 0.0f) ? (sumIY / sumI) : coarseY;
}
