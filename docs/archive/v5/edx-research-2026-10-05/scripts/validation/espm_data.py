import warnings; warnings.filterwarnings("ignore")
import hyperspy.api as hs, numpy as np, os
base = "<scratch>/edx/espm/generated_datasets/"
for f in sorted(os.listdir(base)):
    s = hs.load(base + f, lazy=True)
    print("==", f, os.path.getsize(base+f), "bytes", s, s.data.dtype)
    md = s.metadata.as_dictionary()
    def walk(d, p=""):
        for k, v in d.items():
            if isinstance(v, dict): walk(v, p + k + ".")
            elif not hasattr(v, "shape") or getattr(v, "size", 0) < 20: print("   ", p + k, "=", v)
    walk(md)
    ax = s.axes_manager.signal_axes[0]; print("   energy axis", ax.offset, ax.scale, ax.units, ax.size)
    for a in s.axes_manager.navigation_axes: print("   nav", a.name, a.size, a.scale, a.units)
    d = np.asarray(s.data)
    tot = d.sum(axis=-1)
    print("   counts/pixel: mean %.2f median %.1f min %d max %d ; frac channels zero %.4f ; max channel value %d ; integer-valued %s" % (tot.mean(), np.median(tot), tot.min(), tot.max(), (d==0).mean(), d.max(), bool(np.all(d==np.round(d)))))
