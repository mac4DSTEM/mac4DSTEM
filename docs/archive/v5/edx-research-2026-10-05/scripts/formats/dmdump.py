# Minimal DM3/DM4 tag dumper (own code, for inspection only).
import sys, struct
SZ = {2:2,3:4,4:2,5:4,6:4,7:8,8:1,9:1,10:1,11:8,12:8}
FMT = {2:'h',3:'i',4:'H',5:'I',6:'f',7:'d',8:'?',9:'b',10:'b',11:'q',12:'Q'}
class R:
    def __init__(s, b): s.b=b; s.o=0
    def be(s, f): v=struct.unpack_from('>'+f, s.b, s.o)[0]; s.o+=struct.calcsize(f); return v
    def le(s, f): v=struct.unpack_from('<'+f, s.b, s.o)[0]; s.o+=struct.calcsize(f); return v
def dump(path, out, maxlen=120):
    b = open(path,'rb').read()
    r = R(b); ver = r.be('I'); L = 'Q' if ver==4 else 'I'
    r.be(L); order = r.be('I')
    E = '<' if order==1 else '>'
    def sp(): return r.be(L)
    def group(prefix, depth=0):
        r.be('B'); r.be('B'); n = sp()
        for i in range(n):
            tag = r.be('B')
            if tag == 0: break
            ln = r.be('H'); name = b[r.o:r.o+ln].decode('latin-1'); r.o += ln
            if not name: name = f"#{i}"
            if ver == 4: sp()
            p = prefix + "." + name if prefix else name
            if tag == 20: group(p, depth+1)
            elif tag == 21:
                assert b[r.o:r.o+4] == b'%%%%', (p, r.o); r.o += 4
                ninfo = sp(); info = [sp() for _ in range(ninfo)]
                t = info[0]
                if t in SZ:
                    v = struct.unpack_from(E+FMT[t], b, r.o)[0]; r.o += SZ[t]; out.append((p, v))
                elif t == 18:
                    ln2 = info[1]; out.append((p, b[r.o:r.o+ln2])); r.o += ln2
                elif t == 15:
                    nf = info[2]; types = [info[4+2*k] for k in range(nf)]
                    vals = []
                    for ty in types:
                        vals.append(struct.unpack_from(E+FMT[ty], b, r.o)[0]); r.o += SZ[ty]
                    out.append((p, tuple(vals)))
                elif t == 20:
                    et = info[1]
                    if et == 15:
                        nf = info[3]; types = [info[5+2*k] for k in range(nf)]; n_el = info[4+2*nf]
                        es = sum(SZ[t2] for t2 in types)
                        out.append((p, f"<struct array n={n_el}>")); r.o += es*n_el
                    elif et == 18 or et == 20:
                        out.append((p, f"<complex array {info}>")); raise SystemExit("complex array unsupported in dumper")
                    else:
                        n_el = info[2]; nb = n_el*SZ[et]
                        if et == 4 and nb < 2000:
                            s = struct.unpack_from(E+'%dH'%n_el, b, r.o); out.append((p, ''.join(chr(c) for c in s)))
                        else:
                            out.append((p, f"<array type={et} n={n_el} offset={r.o} bytes={nb}>"))
                        r.o += nb
            else:
                raise SystemExit(f"bad tag {tag} at {r.o} {p}")
    group("")
    return ver, order
for fn in sys.argv[1:]:
    out = []
    ver, order = dump(fn, out)
    print("=====", fn.split('/')[-1], "DM", ver, "littleEndian" if order==1 else "bigEndian")
    for p, v in out:
        print(p, "=", (str(v)[:160]))
