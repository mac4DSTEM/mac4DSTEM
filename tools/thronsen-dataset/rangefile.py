import requests, io
class RangeFile(io.RawIOBase):
    """A seekable read-only file over HTTP range requests, for h5py."""
    def __init__(self, url, block=8*1024*1024):
        self.url=url; self.pos=0; self.block=block; self.cache={} ; self.bytes_fetched=0
        r=requests.head(url, allow_redirects=True, timeout=60)
        self.size=int(r.headers.get('Content-Length') or 0)
        self.final=r.url
        if self.size==0:
            r=requests.get(self.final, headers={'Range':'bytes=0-0'}, timeout=60)
            self.size=int(r.headers['Content-Range'].split('/')[-1])
    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.pos
    def seek(self, off, whence=0):
        if whence==0: self.pos=off
        elif whence==1: self.pos+=off
        else: self.pos=self.size+off
        return self.pos
    def _block(self, i):
        if i in self.cache: return self.cache[i]
        start=i*self.block; end=min(self.size, start+self.block)-1
        for attempt in range(5):
            try:
                r=requests.get(self.final, headers={'Range':f'bytes={start}-{end}'}, timeout=120)
                if r.status_code in (200,206): break
            except Exception: pass
        data=r.content; self.bytes_fetched+=len(data)
        if len(self.cache)>8: self.cache.pop(next(iter(self.cache)))
        self.cache[i]=data; return data
    def readinto(self, b):
        n=len(b); out=bytearray()
        while len(out)<n and self.pos<self.size:
            i=self.pos//self.block; off=self.pos-i*self.block
            chunk=self._block(i)[off:off+(n-len(out))]
            if not chunk: break
            out+=chunk; self.pos+=len(chunk)
        b[:len(out)]=out; return len(out)
