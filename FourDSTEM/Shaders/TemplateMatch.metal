//
//  TemplateMatch.metal
//  Role: ACOM core — the highest-throughput kernel in the app. For each
//        real-space scan position it computes the Normalized Cross-Correlation
//        (NCC) between that position's CBED pattern and every template in a
//        precomputed library, and records the best (and second-best) match.
//
//  Because both the pattern and every template are pre-normalized to zero mean
//  and unit variance, the NCC collapses to a simple mean-of-products:
//        NCC = (1/Npix) * Σ pattern[q] * template[q]
//  which is a pure multiply-accumulate the GPU loves.
//
//  ── STATUS ───────────────────────────────────────────────────────────────
//  This kernel is COMPLETE and compiles. The surrounding pipeline
//  (TemplateLibraryGenerator, OrientationMapper, IPF UI) is the Stage-2 work;
//  this file is here so the showcase GPU code exists and can be reviewed.
//
//  ── PERFORMANCE NOTES (read before tuning) ─────────────────────────────────
//  • texture2d_array slices are capped (commonly 2048) on Apple GPUs. So both
//    `library` and `patterns` must be processed in BATCHES of ≤2048 slices,
//    or stored as plain device buffers instead of texture arrays. The Swift
//    side (OrientationMapper) is responsible for batching; this kernel takes a
//    template offset/count so it can be called once per batch.
//  • The straightforward version below is one thread per scan position looping
//    all templates. The documented optimization is to have a THREADGROUP own a
//    tile of scan positions and cooperatively stream each template into
//    threadgroup memory once (amortizing the template read across the tile).
//    That path is sketched in comments at the bottom; validate NCC values
//    against this simple version before trusting it.
//

#include <metal_stdlib>
using namespace metal;

// MUST match the Swift structs (Stage 2: OrientationResult.swift / OrientationMapper).
struct MatchParams {
    uint nTemplates;     // templates in THIS batch
    uint templateBase;   // global index of batch's first template
    uint rx;             // scan columns
    uint ry;             // scan rows
    uint qy;             // detector rows
    uint qx;             // detector cols
};

struct OrientationHit {
    uint  templateIndex; // global template index of best match
    float bestScore;     // best NCC
    float secondScore;   // 2nd-best NCC (for reliability R = 1 - best/second... see Swift)
};

// ───────────────────────────────────────────────────────────────────────────
// Preprocess: normalize each CBED pattern in-place to zero mean / unit variance.
// `inout` patterns texture array, one slice per scan position. Run before match.
// ───────────────────────────────────────────────────────────────────────────
kernel void normalizePatterns(texture2d_array<float, access::read_write> patterns [[texture(0)]],
                              constant MatchParams &p [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]])
{
    const uint slice = gid.y * p.rx + gid.x;
    if (gid.x >= p.rx || gid.y >= p.ry) { return; }

    const float N = float(p.qx * p.qy);
    float mean = 0.0f;
    for (uint y = 0; y < p.qy; ++y)
        for (uint x = 0; x < p.qx; ++x)
            mean += patterns.read(uint2(x, y), slice).r;
    mean /= N;

    float var = 0.0f;
    for (uint y = 0; y < p.qy; ++y)
        for (uint x = 0; x < p.qx; ++x) {
            float d = patterns.read(uint2(x, y), slice).r - mean;
            var += d * d;
        }
    float invStd = rsqrt(max(var / N, 1e-12f));

    for (uint y = 0; y < p.qy; ++y)
        for (uint x = 0; x < p.qx; ++x) {
            float v = (patterns.read(uint2(x, y), slice).r - mean) * invStd;
            patterns.write(float4(v, 0, 0, 0), uint2(x, y), slice);
        }
}

// ───────────────────────────────────────────────────────────────────────────
// Template matching (simple, correct version).
//   library  : [nTemplates, Qy, Qx]  pre-normalized templates (this batch)
//   patterns : [Nscan, Qy, Qx]        pre-normalized CBED patterns
//   output   : one OrientationHit per scan position (carried across batches)
// ───────────────────────────────────────────────────────────────────────────
kernel void templateMatch(texture2d_array<float, access::read> library  [[texture(0)]],
                          texture2d_array<float, access::read> patterns [[texture(1)]],
                          device OrientationHit               *output   [[buffer(0)]],
                          constant MatchParams                &p        [[buffer(1)]],
                          uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= p.rx || gid.y >= p.ry) { return; }

    const uint scanIdx = gid.y * p.rx + gid.x;
    const float invN   = 1.0f / float(p.qx * p.qy);

    // Seed best/second from any previous batch's result for this position.
    OrientationHit hit = output[scanIdx];

    for (uint t = 0; t < p.nTemplates; ++t) {
        float ncc = 0.0f;
        for (uint y = 0; y < p.qy; ++y) {
            for (uint x = 0; x < p.qx; ++x) {
                float a = patterns.read(uint2(x, y), scanIdx).r;
                float b = library.read(uint2(x, y), t).r;
                ncc += a * b;
            }
        }
        ncc *= invN;

        if (ncc > hit.bestScore) {
            hit.secondScore  = hit.bestScore;
            hit.bestScore    = ncc;
            hit.templateIndex = p.templateBase + t;
        } else if (ncc > hit.secondScore) {
            hit.secondScore = ncc;
        }
    }

    output[scanIdx] = hit;
}

// ───────────────────────────────────────────────────────────────────────────
// OPTIMIZATION SKETCH (Stage 2 — NOT YET ENABLED)
//
// Cooperative tiling to cut global memory traffic:
//   • Launch one threadgroup per TILE of scan positions (e.g. 8×4 = 32 threads,
//     one SIMD group). Each thread keeps its own pattern's running best/second
//     in registers.
//   • Loop templates. For each template, cooperatively load its [Qy*Qx] pixels
//     into `threadgroup float tile[QY*QX]` (split the copy across the 32
//     threads), then `threadgroup_barrier(mem_flags::mem_threadgroup)`.
//   • Every thread then accumulates NCC against the shared template tile from
//     threadgroup memory instead of re-reading global memory per thread.
//   • This amortizes each template read over all threads in the tile — the
//     win grows with tile size, bounded by threadgroup memory (Qy*Qx*4 bytes
//     must fit; for 128×128 that's 64 KB, at the limit — so tile the detector
//     too, or cap Q for ACOM).
//
//   Validate the optimized NCC against this simple kernel on a known case
//   before relying on it.
// ───────────────────────────────────────────────────────────────────────────
