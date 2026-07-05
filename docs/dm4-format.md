# Gatan DM4 (DigitalMicrograph) file format — reader spec

Implementation specification for a native Swift `.dm4` reader in mac4DSTEM. The goal
is a future import path: read a raw `.dm4` (a 4D-STEM datacube + calibration
metadata) and convert it to the app's working representation (eventually an HDF5),
with automatic calibration extraction.

**Verification status (2026-07-05):** the byte layout and the two type tables below
were cross-checked against the authoritative **openNCEM `ncempy.io.dm`** source
(the reader py4DSTEM delegates to), RosettaSciIO/HyperSpy's independent reader, and
the Jefferis/NTU DM3/DM4 write-ups. The `_encodedTypeSizes` and `_DM2NPDataTypes`
tables, the DM4 `>u8` special type, the big-endian structure reads, the DM4
per-tag/subgroup byte count, and the <1000-byte inline-array threshold were all
confirmed verbatim against ncempy. `py4DSTEM/io/filereaders/read_dm.py` was confirmed
to delegate all byte parsing to `ncempy.io.dm` and to apply the object-selection,
calibration-indexing, voltage grep, and TitanX reshape logic described below.

## Sources
- openNCEM `ncempy.io.dm` (`fileDM`): `https://raw.githubusercontent.com/ercius/openNCEM/master/ncempy/io/dm.py` — the format authority to reproduce.
- RosettaSciIO / HyperSpy: `rsciio/digitalmicrograph/_api.py` — independent implementation.
- Format write-ups: Jefferis/ImageJ "DM3 Image Format" and the NTU "Digital Micrograph file format" spec.
- Local: `References/py4DSTEM-dev/py4DSTEM/io/filereaders/read_dm.py` (py4DSTEM's DM path — delegates to ncempy).

---

## 1. File structure (byte-exact)

### 1.1 Header — all big-endian

| Offset | Field | DM3 | DM4 | Meaning |
|---|---|---|---|---|
| 0 | `version` | `>u4` | `>u4` | 3 or 4 |
| 4 | `rootlen` | `>u4` | `>u8` | root tag-directory size in bytes |
| 8 (DM3) / 12 (DM4) | `byteord` | `>u4` | `>u4` | **1 = little-endian data (PC)**, 0 = big-endian |

ncempy requires `byteord == 1` (raises otherwise); all modern DM files are LE.

**`SPECIAL` type** = `uint32` (DM3) or **`uint64` (DM4)**, always **big-endian**. Used for:
number-of-tags, per-tag byte count, `%%%%` `ninfo`, encoded-type value, struct
lengths/field-count, array length. **The 8-byte DM4 length is the single most
important DM3→DM4 difference — reading one as 4 bytes desyncs the whole stream.**

### 1.2 Tag group / directory tree (recursive)

**Tag group:**
```
i1        is_sorted   (1 = sorted; informational)
i1        is_open     (0 = closed; informational)
SPECIAL   nTags       (big-endian)
repeat nTags: one tag entry
```
Do **not** rely on `is_sorted`; always walk all `nTags`.

**Tag entry:**
```
i1        tag         (0x15=21 → data tag; 0x14=20 → subgroup; 0x00 → end)
i2be      ltname      (label length; may be 0)
a[ltname] tname       (label; may be empty for list indices)

if DM4:   SPECIAL  tagByteCount   (NEW in DM4 — for BOTH data tags AND subgroups)
if tag == 21: read data tag payload (§1.3)
if tag == 20: recurse into tag group (§1.2)
```
The DM4 `tagByteCount` lets a reader **seek past** any tag/type it doesn't understand.
Build paths by joining labels with `.` (e.g. `ImageList.1.ImageData.Data`). Empty
labels are normal.

### 1.3 Data tag payload (the `%%%%` block)

```
a4        '%%%%'      (four bytes each == 37; assert)
SPECIAL   ninfo       (big-endian)
SPECIAL   info[ninfo] (big-endian; the "encoded type" descriptor)
<data>                (primitive values, in file byte order = little-endian)
```
`info[0]` is the **encoded type**:
- **Simple (2–12):** one value of that type (`ninfo == 1`).
- **String (18):** then `>u4 stringSize`, then `stringSize` bytes.
- **Struct (15):** `info = [15, <struct def>]` (§2.3).
- **Array (20):** `info = [20, <element type(s)>, length]` (§2.4).

**Endianness split:** structure (labels, counts, `SPECIAL`, encoded-type ints, `%%%%`,
`ninfo`) is **always big-endian**; primitive `<data>` values are **little-endian** (per
`byteord`). Never read `%%%%`/counts/encoded-type as little-endian.

---

## 2. Type tables

### 2.1 Tag encoded-type codes (the tag-tree enum)

| Code | Name | Bytes | Notes |
|---|---|---|---|
| 2 | int16 | 2 | signed |
| 3 | int32 | 4 | signed |
| 4 | uint16 | 2 | (also "unicode") |
| 5 | uint32 | 4 | |
| 6 | float32 | 4 | |
| 7 | float64 | 8 | |
| 8 | bool | 1 | |
| 9 | int8 | 1 | signed |
| 10 | byte | 1 | |
| **11** | **int64** | 8 | **new in DM4 — signed** (see note) |
| 12 | uint64 | 8 | new in DM4 |
| 15 | struct | var | §2.3 |
| 18 | string | var | |
| 20 | array | var | §2.4 |

`_encodedTypeSizes` (ncempy, verbatim): `{0:0, 2:2, 3:4, 4:2, 5:4, 6:4, 7:8, 8:1, 9:1, 10:1, 11:8, 12:8}`.

**Code 11 note (verified discrepancy):** ncempy's `_TagType2NPDataTypes` maps code 11
to `np.uint64`; the NTU spec and HyperSpy treat it as **signed int64** (`q`). Byte size
is 8 either way; for value interpretation **implement code 11 = int64 (signed)**. It's
rare in tag metadata, so the risk is low, but do it correctly. ncempy's small-array
decode table also omits key 11 (a latent bug) — include it.

### 2.2 Image `DataType` codes (`ImageData.DataType` — a DIFFERENT enum)

Governs the pixel format of the data blob. **Not the same as §2.1.**

| Code | Type | Bytes/px | Notes |
|---|---|---|---|
| 0 | (null / not implemented) | — | |
| 1 | int16 | 2 | |
| 2 | float32 | 4 | |
| 3 | complex64 | 8 | |
| 5 | float32 (packed FFT half-complex) | 4 | HyperSpy only |
| 6 | uint8 | 1 | |
| 7 | int32 | 4 | |
| 8 | RGBA (BGRA uint8×4) | 4 | |
| 9 | int8 | 1 | |
| 10 | uint16 | 2 | |
| 11 | uint32 | 4 | |
| 12 | float64 | 8 | |
| 13 | complex128 | 16 | |
| 14 | bool | 1 | HyperSpy only |
| 23 | RGBA (BGRA uint8×4) | 4 | **thumbnails use this** |
| 27 | complex64 (packed FFT) | 8 | |
| 28 | complex128 (packed FFT) | 16 | |

`_DM2NPDataTypes` (ncempy, verbatim): `{1:int16, 2:float32, 3:complex64, 6:uint8, 7:int32, 9:int8, 10:uint16, 11:uint32, 12:float64, 13:complex128}`.

4D-STEM camera data is almost always **1 (int16), 6 (uint8), 7 (int32), 10 (uint16),
2 (float32)**. Implement the full table so RGBA thumbnails (23) and FFT types don't crash.

### 2.3 Struct (encoded type 15)
```
SPECIAL  structNameLength   (discard)
SPECIAL  nFields            (guard nFields > 100 as corruption)
repeat nFields: { SPECIAL fieldNameLength (discard); SPECIAL fieldType (a code 2..12) }
```
Struct **data** = nFields values read back-to-back, each per its `fieldType`, in file
byte order. Field names are not stored — fields are positional.

### 2.4 Array (encoded type 20)
```
SPECIAL  elementType   (simple code, OR 15 → struct def follows, OR 20 → nested array)
[ if elementType == 15: full struct definition here, BEFORE the length ]
SPECIAL  arrayLength
```
Element size = struct field-size sum, or `_encodedTypeSizes[elementType]`. Total =
`arrayLength × elementSize`.

**Deferred reads:** ncempy/HyperSpy do **not** eagerly read array bodies. Record
`{offset = current pos, size, elementType}` and `seek` forward. Only small arrays
(**< 1000 bytes**) are decoded inline (this is how `Units` strings become `scaleUnit`).
**The datacube is one deferred array** (§3).

---

## 3. Locating the datacube

### 3.1 Tag path
```
ImageList.<index>.ImageData
  ├─ Data          (encoded type 20 array — the raw pixel blob)
  ├─ DataType      (int → §2.2)
  ├─ Dimensions.{1,2,3,4}    (sizes, fastest-first)
  └─ Calibrations.Dimension.<i>.{Scale, Origin, Units}
```
Index 0 is often a thumbnail; real data at 1+.

### 3.2 Capturing the blob
On the `Data` array tag, don't read it — store `arraySize = arrayLength × itemSize`,
`arrayOffset = file position after the array header`, `arrayType`, then seek past
`arraySize`. **Memory-map the datacube from `arrayOffset`** using the dtype from
`DataType`; never load a multi-GB cube into RAM.

### 3.3 Dimension interpretation → [Ry, Rx, Qy, Qx]
DM dims are **fastest-first**: `Dimensions.1` = xSize (contiguous), `.2` = ySize,
`.3` = zSize, `.4` = zSize2. ncempy reshapes as `(zSize2, zSize, ySize, xSize)` then
drops singletons. Three real layouts (all handled by `read_dm.py`):
- **True 4D** (`zSize2 > 1`): `(zSize2, zSize, ySize, xSize)` → **[Ry=zSize2, Rx=zSize, Qy=ySize, Qx=xSize]**.
- **3D "TitanX"**: `(N_scan, Qy, Qx)`; scan shape from tags `4D STEM Tags.Scan shape X/Y`; py4DSTEM reshapes `(scan)→(Ry,Rx)` and applies a **`-2` pixel roll on axis 1** (TitanX artifact). If those tags are absent, Rx/Ry can't be recovered from data alone.
- **2D**: single pattern/image — not a datacube.

**Selection heuristic (replicate):** pick the first object whose `squeeze(shape).ndim > 2`
(skips a thumbnail at index 0 and any 2D survey image). `read_dm.py`:
`if dmFile.dataShape[dataset_index + thumbnail_count] > 2`.

### 3.4 Calibration extraction
Per-dimension `scale`/`scaleUnit`/`origin` are chained flat across objects. `getDataset`
slices `scale[jj : jj+dataShape][::-1]` with `jj = sum(dataShape[0:obj])` — note the
**`[::-1]` reversal** (tags stored fastest→slowest; return order slowest→fastest). In
`read_dm.py` the offset also adds `2 * thumbnail_count`. For a 4D object the four
calibrations map to Qx, Qy, Rx, Ry (fastest→slowest); py4DSTEM takes `pixelsize[0]` =
Q pixel size, `pixelsize[2]` = R pixel size.

**Reliably present:** per-dim `Scale`, `Origin`, `Units`; `ImageData.DataType`;
`Dimensions.*`. Origin is in pixels (`round(-1 * origin * scale, 4)`).

**Vendor/version-dependent (grep `allTags` by substring, don't assume path):**
- Accelerating voltage: `...Microscope Info.Voltage`.
- Camera length, exposure, detector pixel size, scan calibration: under
  `ImageTags`/`Microscope Info`/`Acquisition`/`Session Info` — not standardized.

**Calibration sanity (port from py4DSTEM):** treat Q-units of `nm`/`µm` as invalid
(fall back to pixels); convert `mrad`→Å⁻¹ via electron wavelength (needs voltage);
`1/nm`→Å⁻¹ by `/10`.

---

## 4. Parsing algorithm (pseudocode)

```
# HEADER (big-endian)
version = readU32BE()                        # 3 or 4
SPECIAL = (version == 4) ? u64 : u32
rootlen = readSPECIAL_BE()
byteord = readU32BE()                        # 1 => little-endian values
valueEndian = (byteord == 1) ? little : big

flatTags = {}                                # path -> value
imageObjects = []                            # {offset, byteCount, dataType, dims[], calibs[]}

walkGroup(prefix=""):
    is_sorted = readI8(); is_open = readI8()
    nTags = readSPECIAL_BE()
    for _ in 0..<nTags:
        tag = readI8()
        ltname = readU16BE()
        label = ltname > 0 ? readBytes(ltname) : ""
        path = prefix.isEmpty ? label : prefix + "." + label
        if version == 4: tagByteCount = readSPECIAL_BE()   # data tags AND subgroups
        switch tag {
          case 21: readDataTag(path)          # may seek by tagByteCount if unknown
          case 20: walkGroup(path)
          case 0:  return
        }

readDataTag(path):
    assert readBytes(4) == "%%%%"
    ninfo   = readSPECIAL_BE()
    encType = readSPECIAL_BE()
    switch encType {
      case 2...12: flatTags[path] = readValue(encType, valueEndian)
      case 18:     n = readU32BE(); flatTags[path] = readString(n)
      case 15:     fields = readStructDef(); flatTags[path] = readStructVals(fields, valueEndian)
      case 20:
        (elemType, structDef) = readArrayElemType()   # elemType may be 15/20
        length = readSPECIAL_BE()
        nbytes = length * sizeOf(elemType, structDef)
        offset = currentPos()
        if label == "Data": record {offset, nbytes, elemType} on current image object
        elif nbytes < 1000: flatTags[path] = decodeArray(...)   # Units strings, etc.
        seek(offset + nbytes)                          # skip blob; never read into RAM
    }

# after walk:
obj    = first imageObject with ndim(squeeze(dims)) > 2   # skip thumbnails/2D surveys
dtype  = imageDataTypeMap[obj.dataType]                   # §2.2
shape  = interpret(obj.dims)  -> (Ry, Rx, Qy, Qx)         # §3.3
cube   = memoryMap(file, offset: obj.offset, dtype: dtype, shape: shape)
calib  = { scale/units/origin per dim, reversed to axis order }   # §3.4
```

### Gotchas checklist
- **Endianness split:** structure = big-endian; primitive values = little-endian.
- **DM4 8-byte fields:** `rootlen`, `nTags`, per-tag/subgroup byte count, `ninfo`, encoded-type, struct lengths, array length are all `uint64` in DM4.
- **Per-tag byte count exists for BOTH data tags and subgroups in DM4.**
- Don't trust `is_sorted`; walk all `nTags`. Empty labels are normal.
- Struct fields are positional (names not stored inline).
- Deferred array reads: record offset + size and seek; only `Data` and <1KB arrays decoded. Memory-map the cube.
- Skip the index-0 thumbnail (DataType 23, 2D); account for it in the chained-calibration offset (`2 * thumbnail_count`).
- Calibration order reversal (`[::-1]`) between stored (fastest-first) and axis order.
- Code 11 = int64 signed (not uint64).
- Apply py4DSTEM's unit-sanity fallbacks.

---

## 5. Swift implementation notes

- **File access:** `Data(contentsOf: url, options: .mappedIfSafe)`; keep the mapping alive and slice the datacube sub-range without copying. Convert to the app's working representation (eventually HDF5) rather than holding the whole cube.
- **Cursor:** `struct ByteReader { let data: Data; var offset: Int }` with `readU32BE`, `readU64BE`, `readSPECIAL` (branch on DM version), `readI8`, `readU16BE`, `readBytes`. Use `withUnsafeBytes` + `loadUnaligned(fromByteOffset:as:)` and `UInt32(bigEndian:)` / `UInt64(bigEndian:)`. On Apple Silicon, little-endian values need no swap.
- **Endian helpers:** `readStructU64()` always big-endian; `readValue(encType, endian:)` swaps per `byteord` (no-op when `byteord == 1`).
- **Type maps:** `enum TagEncodedType: Int` (§2.1) and `enum ImageDataType: Int { var pixelSize: Int }` (§2.2). Map image DataType → a Metal-friendly element type (Int16/UInt16/Int8/UInt8/Int32/Float). Handle or explicitly reject RGBA/complex/FFT.
- **Model:** a flat `[String: TagValue]` (path-joined) plus `[ImageObject]` capturing `{ dataOffset, byteCount, dataType, dims, calibrations }`. Calibration extraction is then a substring search over the map (mirrors ncempy `allTags`).
- **Datacube handoff:** expose the mapped `Data` sub-range `[offset ..< offset+byteCount]` + `(Ry, Rx, Qy, Qx)` + dtype to the existing 4D pipeline. DM stores fastest-first C-order (Qx contiguous), so honoring the `(zSize2, zSize, ySize, xSize)` reshape yields `[Ry][Rx][Qy][Qx]` with no transpose.
- **Robustness:** use the DM4 per-tag byte count to `seek` past unimplemented tags/types; guard `nFields`/`nTags`/`arrayLength` against absurd values.
- **Port from py4DSTEM `read_dm.py`:** thumbnail skip, `ndim > 2` object selection, TitanX 3D→4D reshape (`Scan shape X/Y` + `-2` roll), and the Q-unit sanity/conversion logic.

### How it plugs into mac4DSTEM
The reader produces `(mapped data range, dtype, [Ry,Rx,Qy,Qx], calibration)`. Two options:
(1) convert to a working `.h5` on import (matches the "preprocessing" open issue, keeps
the rest of the app HDF5-only), or (2) feed the mapped cube directly into the existing
`FourDArray`/`MetalEngine` path (add a non-HDF5 source). Given the app currently expands
to float32 in `FourDArray.cubeBuffer`, a DM int16/uint16 cube converts cleanly there.
Calibration maps onto the existing `Calibration` model (Q/R pixel sizes + units).
