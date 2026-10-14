# Generate candidate files from master.swift: keep the //<X> ... //</X> blocks whose letter is in the variant, drop the rest.
import re, sys
src=open('master.swift').read()
for name, keep in [('none',''),('c','C'),('b2','B'),('s','S'),('cb','CB'),('cs','CS'),('cbs','CBS')]:
    out=[]; drop=False
    for line in src.split('\n'):
        m=re.match(r'^//<(/?)(!?)([BCS])>$', line)
        if m:
            drop = (m.group(1)=='' and ((m.group(3) not in keep) != (m.group(2)=='!')))
            continue
        if not drop: out.append(line)
    open(f'../patches/EllipseCalibration.{name}.swift','w').write('\n'.join(out))
    print(name, len(out))
