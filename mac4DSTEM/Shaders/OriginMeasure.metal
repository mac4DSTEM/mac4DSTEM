//
//  OriginMeasure.metal
//  Role: Per-pattern origin measurement for calibration, following py4DSTEM's
//        get_origin: locate the brightest disk coarsely, then refine with a
//        center of mass restricted to a window of radius r*rscale around it
//        (here floored at r + 1.5 px and iterated; see the refine step).
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
    float rscale;   // CoM window = max(r * rscale, r + 1.5 px) (py4DSTEM default 1.2)
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
    // Seeded in the PIXEL-CENTRE convention the winner below uses
    // (0.5f * (first + last)), not the index convention `qx * 0.5f`. The two
    // differ by half a pixel and the seed is reachable only when no block sum
    // beats -FLT_MAX — an all-NaN pattern, where the centre of mass produces
    // garbage regardless — so this is a convention repair, not a defect fix
    // (S11 found it, S12 confirmed it cosmetic, v2 S13 folded it in while
    // editing this file's neighbourhood).
    float coarseX = 0.5f * float(p.qx - 1);
    float coarseY = 0.5f * float(p.qy - 1);

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

    // ── Refine: CoM within r*rscale, ITERATED on its own centre ───────────
    //
    // DEVIATION from py4DSTEM, which takes ONE centre of mass around the
    // argmax of a Gaussian-filtered pattern. Our coarse centre is a block
    // centre (above) and sits up to bin/2 off the beam; a window of 1.2 r
    // around it truncates the beam on one side and the single pass lands
    // near the block, not the beam. Measured 2026-09-05 (Gate D, scratchpad
    // origin-experiment-ws2): WS2's 16 384 positions all read 63.986 for a
    // beam at 63.738, and the numpy fixed point of the same window converged
    // to 63.714 in five passes from the block centre, 63.738 at 1.6 r. Four
    // passes recentre the window on its own estimate; each pass visits only
    // the window's bounding box, so the total costs less than the old single
    // full-pattern sweep.
    //
    // The window itself: r * rscale, but never less than r + 1.5 px. The
    // probe radius from probeSize is the equivalent-circle radius of the
    // plateau, and the beam's soft edge (the detector's ~1 px fall-off) lies
    // outside it; a window that cuts through that edge is biased by the
    // pixel grid even when centred (numpy, 2026-09-05: 1.2 r iterated reads
    // 0.024 px low on WS2 and 0.27 px off on a synthetic blob; r + 1.5 and
    // anything wider read within 0.009 px on both). A margin in PIXELS, not
    // in r, because the edge is a detector property: large disks keep the
    // tight py4DSTEM window, tiny ones get the whole beam. Pinned by
    // tools/virtual-detector-test (origin_measurement_truth, three
    // sub-pixel centres within 0.05 px). Pixels ON the window boundary are
    // admitted (<=); py4DSTEM's mask is strict (hypot < r * rscale,
    // process/calibration/origin.py get_origin_single_dp). Both are one
    // pixel set at a real-valued radius, and the boundary carries no beam
    // once the floor holds the edge 1.5 px inside it.
    const float win  = max(p.r * p.rscale, p.r + 1.5f);
    const float win2 = win * win;
    float cx = coarseX, cy = coarseY;
    for (uint pass = 0; pass < 4; ++pass) {
        const int y0 = max(0, int(floor(cy - win)));
        const int y1 = min(int(p.qy) - 1, int(ceil(cy + win)));
        const int x0 = max(0, int(floor(cx - win)));
        const int x1 = min(int(p.qx) - 1, int(ceil(cx + win)));
        float sumI = 0.0f, sumIX = 0.0f, sumIY = 0.0f;
        for (int y = y0; y <= y1; ++y) {
            const float dy = float(y) - cy;
            const float dy2 = dy * dy;
            if (dy2 > win2) { continue; }
            const uint rowBase = uint(y) * p.qx;
            for (int x = x0; x <= x1; ++x) {
                const float dx = float(x) - cx;
                if (dx * dx + dy2 > win2) { continue; }
                const float I = max(pat[rowBase + uint(x)], 0.0f);
                sumI  += I;
                sumIX += I * float(x);
                sumIY += I * float(y);
            }
        }
        if (!(sumI > 0.0f)) { break; }          // no mass in the window: keep the last centre
        const float nx = sumIX / sumI, ny = sumIY / sumI;
        const bool settled = fabs(nx - cx) < 1e-4f && fabs(ny - cy) < 1e-4f;
        cx = nx; cy = ny;
        if (settled) { break; }
    }

    outXY[2 * scanIdx]     = cx;
    outXY[2 * scanIdx + 1] = cy;
}
