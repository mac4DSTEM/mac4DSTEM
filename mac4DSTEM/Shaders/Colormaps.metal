//
//  Colormaps.metal
//  Role: GPU-side image display. A fullscreen-triangle vertex shader (no vertex
//        buffer — positions come from vertex_id) plus a fragment shader that
//        reads a single-channel, already-normalized result texture and looks up
//        its color in a 1D colormap LUT texture. Zoom/pan come from a transform.
//
//  Both the diffraction viewer and the real-space result viewer render through
//  this pipeline (see MetalImageView.swift).
//

#include <metal_stdlib>
using namespace metal;

struct VOut {
    float4 position [[position]];
    float2 uv;
};

// xform = (scale, unused, offsetX, offsetY) in normalized texture space.
vertex VOut displayVertex(uint vid [[vertex_id]],
                          constant float4 &xform [[buffer(0)]])
{
    // One oversized triangle covering the viewport.
    const float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    // Matching UVs; v flipped so texture row 0 appears at the TOP.
    const float2 uvs[3] = { float2(0.0, 1.0),  float2(2.0, 1.0),  float2(0.0, -1.0) };

    VOut o;
    o.position = float4(pos[vid], 0.0, 1.0);
    float2 uv = uvs[vid];
    // Apply zoom about the center, then pan.
    o.uv = (uv - 0.5) / max(xform.x, 1e-3) + 0.5 + xform.zw;
    return o;
}

fragment float4 colormapFragment(VOut in [[stage_in]],
                                 texture2d<float> img [[texture(0)]],
                                 texture1d<float> lut [[texture(1)]])
{
    // r32Float data sampled NEAREST (not all GPUs filter r32Float).
    constexpr sampler dataSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    // rgba8 LUT is filterable → smooth color ramp.
    constexpr sampler lutSampler(address::clamp_to_edge, filter::linear);

    // Outside the image bounds (when zoomed/panned) → opaque background.
    if (in.uv.x < 0.0 || in.uv.x > 1.0 || in.uv.y < 0.0 || in.uv.y > 1.0) {
        return float4(0.06, 0.06, 0.07, 1.0);
    }

    float v = clamp(img.sample(dataSampler, in.uv).r, 0.0, 1.0);
    float4 c = lut.sample(lutSampler, v);
    return float4(c.rgb, 1.0);
}

// Pre-colored results (DPC color wheel): sample the RGBA texture directly,
// no LUT. Same vertex shader / zoom-pan transform as the scalar path.
fragment float4 rgbaFragment(VOut in [[stage_in]],
                             texture2d<float> img [[texture(0)]])
{
    constexpr sampler dataSampler(coord::normalized, address::clamp_to_edge, filter::nearest);

    if (in.uv.x < 0.0 || in.uv.x > 1.0 || in.uv.y < 0.0 || in.uv.y > 1.0) {
        return float4(0.06, 0.06, 0.07, 1.0);
    }
    return float4(img.sample(dataSampler, in.uv).rgb, 1.0);
}
