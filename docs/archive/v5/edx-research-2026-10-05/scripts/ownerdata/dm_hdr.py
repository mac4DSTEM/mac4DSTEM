import sys, json, time
from ncempy.io import dm
p=sys.argv[1]
t=time.time()
with dm.fileDM(p, on_memory=False) as f:
    print('numObjects',f.numObjects, 'thumbnail', getattr(f,'thumbnail',None) is not None)
    for i in range(f.numObjects):
        try:
            d=f.getMetadata(i) if hasattr(f,'getMetadata') else {}
        except Exception as e:
            d={'err':str(e)}
        print(i, 'xSize',f.xSize[i],'ySize',f.ySize[i],'zSize',f.zSize[i] if hasattr(f,'zSize') else None, 'zSize2', f.zSize2[i] if hasattr(f,'zSize2') else None,'dtype',f.dataType[i] if hasattr(f,'dataType') else None,'scale',f.scale[i] if hasattr(f,'scale') else None, 'units', f.scaleUnit[i] if hasattr(f,'scaleUnit') else None)
print('t',time.time()-t)
