// Stage TB1 sitting 2's WS2 sidecar fixture.
//
// Writes a load specification recording a 200x200 scan crop onto a copied
// sidecar. WS2 is 128x128 in scan, so LoadView(source:specification:) throws
// and AppState arms gates.sidecarRestoreFailure = .doesNotFit -- which is what
// Track B row F1.26 and TB1StallProbeTests.testOpeningWS2BesideItsSidecar-
// Completes both need. No local cube is >= 200x200 in scan, so this fixture
// cannot be produced by driving the app; it is synthesised deliberately.
#include <hdf5.h>
#include <stdio.h>
#include <string.h>

static int put_string(hid_t obj, const char *name, const char *value) {
    hid_t type = H5Tcopy(H5T_C_S1);
    H5Tset_size(type, H5T_VARIABLE);
    H5Tset_cset(type, H5T_CSET_UTF8);
    H5Tset_strpad(type, H5T_STR_NULLTERM);
    hid_t space = H5Screate(H5S_SCALAR);
    if (H5Aexists(obj, name) > 0) H5Adelete(obj, name);
    hid_t attr = H5Acreate2(obj, name, type, space, H5P_DEFAULT, H5P_DEFAULT);
    if (attr < 0) { fprintf(stderr, "create %s failed\n", name); return -1; }
    const char *buf[1] = { value };
    herr_t rc = H5Awrite(attr, type, buf);
    H5Aclose(attr); H5Sclose(space); H5Tclose(type);
    if (rc < 0) { fprintf(stderr, "write %s failed\n", name); return -1; }
    printf("  wrote %s = %s\n", name, value);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: stage_ws2 <sidecar.h5>\n"); return 2; }
    hid_t f = H5Fopen(argv[1], H5F_ACC_RDWR, H5P_DEFAULT);
    if (f < 0) { fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
    hid_t g = H5Gopen2(f, "/braggvectors_root", H5P_DEFAULT);
    if (g < 0) { fprintf(stderr, "no /braggvectors_root\n"); H5Fclose(f); return 1; }
    int rc = 0;
    rc |= put_string(g, "mac4dstem_load_specification",
        "{\"scanCrop\":{\"yOffset\":0,\"xOffset\":0,\"height\":200,\"width\":200},\"detectorBin\":1}");
    // A reduced specification raises the minimum reader from 5 to 6
    // (BraggVectorEMDWriter.minimumReaderSchema). Left at 5 the file would be
    // internally inconsistent with what the app itself would have written.
    rc |= put_string(g, "mac4dstem_min_reader_schema", "6");
    H5Gclose(g); H5Fclose(f);
    return rc ? 1 : 0;
}
