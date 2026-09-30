# S14-D probe kernels DERIVED from the shipped OriginMeasure.metal (refine step verbatim except the four named parameters).
import sys
REPO='/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM'; OUT=sys.argv[1]
src=open(REPO+'/mac4DSTEM/Shaders/OriginMeasure.metal').read()
marker='    // ── Refine: CoM within r*rscale, ITERATED on its own centre'
assert src.count(marker)==1
head,refine=src.split(marker); refine=marker+refine
# parameters: passes, floor toggle (window = r*rscale when nofloor)
a="const float win  = max(p.r * p.rscale, p.r + 1.5f);"; assert refine.count(a)==1
refine=refine.replace(a,"const float win  = (p.nofloor != 0u) ? p.r * p.rscale : max(p.r * p.rscale, p.r + 1.5f);")
a="for (uint pass = 0; pass < 4; ++pass)"; assert refine.count(a)==1
refine=refine.replace(a,"for (uint pass = 0; pass < p.passes; ++pass)")
structX='struct OriginParamsX { uint ry; uint rx; uint qy; uint qx; float r; float rscale; uint passes; uint nofloor; };\n'
# block-seed variant: the shipped kernel's head with the struct swapped
h=head.replace('kernel void measureOrigin(','kernel void measureOrigin_blk(').replace('constant OriginParams &p','constant OriginParamsX &p')
assert 'struct OriginParams {' in h
i=h.index('// MUST match OriginParams'); j=h.index('};',i)+3
h=h[:i]+structX+h[j:]
blk=h+refine
seeded='''
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
'''+refine
open(OUT+'/s14d.metal','w').write(blk+seeded)
