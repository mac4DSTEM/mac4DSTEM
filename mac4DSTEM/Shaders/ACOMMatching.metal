#include <metal_stdlib>
using namespace metal;

struct ACOMParams {
    uint positions;
    uint templates;
    uint radial;
    uint azimuthal;
};

// Build the azimuthal correlation spectrum for every
// [position, template, frequency] tuple by summing radial rings.
kernel void acomCorrelationSpectrum(
    const device float *experimentalReal [[buffer(0)]],
    const device float *experimentalImaginary [[buffer(1)]],
    const device float *templateReal [[buffer(2)]],
    const device float *templateImaginary [[buffer(3)]],
    device float *correlationReal [[buffer(4)]],
    device float *correlationImaginary [[buffer(5)]],
    constant ACOMParams &params [[buffer(6)]],
    uint index [[thread_position_in_grid]])
{
    const uint total = params.positions * params.templates * params.azimuthal;
    if (index >= total) return;
    const uint frequency = index % params.azimuthal;
    const uint templateIndex = (index / params.azimuthal) % params.templates;
    const uint position = index / (params.azimuthal * params.templates);
    const uint experimentalBase = position * params.radial * params.azimuthal;
    const uint templateBase = templateIndex * params.radial * params.azimuthal;
    float real = 0.0f;
    float imaginary = 0.0f;
    for (uint radial = 0; radial < params.radial; ++radial) {
        const uint offset = radial * params.azimuthal + frequency;
        const float er = experimentalReal[experimentalBase + offset];
        const float ei = experimentalImaginary[experimentalBase + offset];
        const float tr = templateReal[templateBase + offset];
        const float ti = templateImaginary[templateBase + offset];
        real += er * tr + ei * ti;
        imaginary += er * ti - ei * tr;
    }
    correlationReal[index] = real;
    correlationImaginary[index] = imaginary;
}

// Exact inverse DFT over the small (currently 128-bin) azimuthal dimension,
// followed by a deterministic threadgroup argmax. One threadgroup handles one
// [position, template] pair. This avoids publishing the full angle cube back
// to the CPU and keeps template selection identical to the reference path.
kernel void acomInverseArgmax(
    const device float *correlationReal [[buffer(0)]],
    const device float *correlationImaginary [[buffer(1)]],
    device float *bestScores [[buffer(2)]],
    device uint *bestBins [[buffer(3)]],
    constant ACOMParams &params [[buffer(4)]],
    threadgroup float *scores [[threadgroup(0)]],
    threadgroup uint *bins [[threadgroup(1)]],
    uint threadIndex [[thread_index_in_threadgroup]],
    uint3 group [[threadgroup_position_in_grid]])
{
    const uint position = group.z;
    const uint templateIndex = group.y;
    if (position >= params.positions || templateIndex >= params.templates
        || threadIndex >= params.azimuthal) return;
    const uint base = (position * params.templates + templateIndex) * params.azimuthal;
    const float twoPiOverN = 2.0f * M_PI_F / float(params.azimuthal);
    float value = 0.0f;
    for (uint frequency = 0; frequency < params.azimuthal; ++frequency) {
        const float phase = twoPiOverN * float(frequency * threadIndex);
        value += correlationReal[base + frequency] * cos(phase)
            - correlationImaginary[base + frequency] * sin(phase);
    }
    scores[threadIndex] = value / float(params.azimuthal);
    bins[threadIndex] = threadIndex;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint stride = params.azimuthal / 2; stride > 0; stride >>= 1) {
        if (threadIndex < stride && scores[threadIndex + stride] > scores[threadIndex]) {
            scores[threadIndex] = scores[threadIndex + stride];
            bins[threadIndex] = bins[threadIndex + stride];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (threadIndex == 0) {
        const uint output = position * params.templates + templateIndex;
        bestScores[output] = scores[0];
        bestBins[output] = bins[0];
    }
}
