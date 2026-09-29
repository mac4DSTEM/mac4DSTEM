# Generates the S14 variant kernels FROM the shipped OriginMeasure.metal (refine step verbatim).
import sys, re
REPO='/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM'
OUT=sys.argv[1]
src=open(REPO+'/mac4DSTEM/Shaders/OriginMeasure.metal').read()
marker='    // ── Refine: CoM within r*rscale, ITERATED on its own centre'
assert src.count(marker)==1
head,refine=src.split(marker)
refine=marker+refine
# V0 seed-only: shipped coarse step, then write the seed and return.
assert head.count('kernel void measureOrigin(')==1
v0=head.replace('kernel void measureOrigin(','kernel void measureOrigin_v0seed(')
v0+='''    outXY[2 * scanIdx]     = coarseX;
    outXY[2 * scanIdx + 1] = coarseY;
}
'''
open(OUT+'/v0seed.metal','w').write(v0)

common='''#include <metal_stdlib>
using namespace metal;
struct OriginParamsX { uint ry; uint rx; uint qy; uint qx; float r; float rscale; uint hw; };
#define MAXQX 512
'''
def box(name, seedonly):
    body=f'''
kernel void {name}(const device float  *data   [[buffer(0)]],
                          device float         *outXY  [[buffer(1)]],
                          constant OriginParamsX &p    [[buffer(2)]],
                          uint2 gid [[thread_position_in_grid]])
{{
    if (gid.x >= p.rx || gid.y >= p.ry) {{ return; }}
    const uint scanIdx = gid.y * p.rx + gid.x;
    const ulong patPix = (ulong)p.qy * p.qx;
    const device float *pat = data + (ulong)scanIdx * patPix;
    const int qy = int(p.qy), qx = int(p.qx), hw = int(p.hw);
    float col[MAXQX];
    for (int x = 0; x < qx; ++x) {{ col[x] = 0.0f; }}
    for (int y = 0; y <= min(hw, qy - 1); ++y) {{
        for (int x = 0; x < qx; ++x) {{ col[x] += pat[y * qx + x]; }}
    }}
    float bestSum = -FLT_MAX;
    float coarseX = 0.5f * float(p.qx - 1);
    float coarseY = 0.5f * float(p.qy - 1);
    for (int y = 0; y < qy; ++y) {{
        if (y > 0) {{
            const int add = y + hw, sub = y - hw - 1;
            if (add < qy) {{ for (int x = 0; x < qx; ++x) {{ col[x] += pat[add * qx + x]; }} }}
            if (sub >= 0) {{ for (int x = 0; x < qx; ++x) {{ col[x] -= pat[sub * qx + x]; }} }}
        }}
        float s = 0.0f;
        for (int x = 0; x <= min(hw, qx - 1); ++x) {{ s += col[x]; }}
        for (int x = 0; x < qx; ++x) {{
            if (x > 0) {{
                if (x + hw < qx) {{ s += col[x + hw]; }}
                if (x - hw - 1 >= 0) {{ s -= col[x - hw - 1]; }}
            }}
            if (s > bestSum) {{ bestSum = s; coarseX = float(x); coarseY = float(y); }}
        }}
    }}
'''
    if seedonly:
        body+='''    outXY[2 * scanIdx]     = coarseX;
    outXY[2 * scanIdx + 1] = coarseY;
}
'''
    else:
        body+=refine
    return body
seeded=common.replace('','')  # placeholder
def seededk():
    b='''
kernel void measureOrigin_seeded(const device float  *data   [[buffer(0)]],
                          device float         *outXY  [[buffer(1)]],
                          constant OriginParamsX &p    [[buffer(2)]],
                          const device float   *seeds  [[buffer(3)]],
                          uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= p.rx || gid.y >= p.ry) { return; }
    const uint scanIdx = gid.y * p.rx + gid.x;
    const ulong patPix = (ulong)p.qy * p.qx;
    const device float *pat = data + (ulong)scanIdx * patPix;
    float coarseX = seeds[2 * scanIdx];
    float coarseY = seeds[2 * scanIdx + 1];
'''
    return b+refine
s=common
s+=box('measureOrigin_box',False)
s+=box('measureOrigin_boxseed',True)
s+=seededk()
open(OUT+'/variants.metal','w').write(s)

# PY: py4DSTEM's get_origin_single_dp refine (single pass, window r*rscale = 1.2 r, as origin-kernel-twin.py `PY`)
def pyk():
    b=seededk().replace('measureOrigin_seeded','measureOrigin_pyseeded')
    a="const float win  = max(p.r * p.rscale, p.r + 1.5f);"
    assert b.count(a)==1
    b=b.replace(a,"const float win  = p.r * p.rscale;")
    a2="for (uint pass = 0; pass < 4; ++pass)"
    assert b.count(a2)==1
    return b.replace(a2,"for (uint pass = 0; pass < 1; ++pass)")
open(OUT+'/variants.metal','a').write(pyk())

# ---- exploratory (post first grid; A2): box with 'nearest'-padded window edges, and WIDE (3 r window) truth proxy
def boxn(name, seedonly):
    b=box(name, seedonly)
    # replace the row/column sums with replicate-padded versions: horizontal slide over corrected column sums
    old_start=b.index("    float bestSum = -FLT_MAX;")
    old_end=b.index("    }\n", b.index("if (s > bestSum)"))  # placeholder, rebuilt below
    head=b[:old_start]
    body='''    float bestSum = -FLT_MAX;
    float coarseX = 0.5f * float(p.qx - 1);
    float coarseY = 0.5f * float(p.qy - 1);
    const device float *rowTop = pat;
    const device float *rowBot = pat + (ulong)(qy - 1) * qx;
    for (int y = 0; y < qy; ++y) {
        if (y > 0) {
            const int add = y + hw, sub = y - hw - 1;
            if (add < qy) { for (int x = 0; x < qx; ++x) { col[x] += pat[add * qx + x]; } }
            if (sub >= 0) { for (int x = 0; x < qx; ++x) { col[x] -= pat[sub * qx + x]; } }
        }
        const float tm = float(max(0, hw - y)), bm = float(max(0, y + hw - (qy - 1)));
        #define CV(i) (col[i] + tm * rowTop[i] + bm * rowBot[i])
        float s = float(hw) * CV(0);
        for (int x = 0; x <= min(hw, qx - 1); ++x) { s += CV(x); }
        for (int x = 0; x < qx; ++x) {
            if (x > 0) { s += CV(min(x + hw, qx - 1)); s -= CV(max(x - hw - 1, 0)); }
            if (s > bestSum) { bestSum = s; coarseX = float(x); coarseY = float(y); }
        }
        #undef CV
    }
'''
    tail = ('''    outXY[2 * scanIdx]     = coarseX;
    outXY[2 * scanIdx + 1] = coarseY;
}
''' if seedonly else refine)
    return head+body+tail
def widek():
    b=seededk().replace('measureOrigin_seeded','measureOrigin_wide')
    a="const float win  = max(p.r * p.rscale, p.r + 1.5f);"
    assert b.count(a)==1
    return b.replace(a,"const float win  = 3.0f * p.r;")
open(OUT+'/variants.metal','a').write(boxn('measureOrigin_boxn',False)+boxn('measureOrigin_boxnseed',True)+widek())
