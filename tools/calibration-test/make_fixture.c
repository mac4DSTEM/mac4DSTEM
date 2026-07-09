/* Builds two tiny py4DSTEM-style EMD fixtures using the repo's libhdf5.dylib.
 * attrs.h5:    calibration values as HDF5 attributes (emdfile Metadata.to_h5
 *              layout), QR_flip as an int8-based enum {FALSE,TRUE} — exactly
 *              the type h5py writes for a Python bool.
 * datasets.h5: calibration values as scalar datasets (legacy/regression form).
 */
#include <stdint.h>
#include <stdio.h>
#include <stddef.h>

typedef int64_t hid_t;
typedef uint64_t hsize_t;
typedef int herr_t;

extern hid_t H5T_NATIVE_DOUBLE_g, H5T_NATIVE_FLOAT_g, H5T_NATIVE_INT8_g, H5T_C_S1_g;

herr_t H5open(void);
hid_t  H5Fcreate(const char*, unsigned, hid_t, hid_t);
herr_t H5Fclose(hid_t);
hid_t  H5Screate(int);
hid_t  H5Screate_simple(int, const hsize_t*, const hsize_t*);
herr_t H5Sclose(hid_t);
hid_t  H5Gcreate2(hid_t, const char*, hid_t, hid_t, hid_t);
herr_t H5Gclose(hid_t);
hid_t  H5Dcreate2(hid_t, const char*, hid_t, hid_t, hid_t, hid_t, hid_t);
herr_t H5Dwrite(hid_t, hid_t, hid_t, hid_t, hid_t, const void*);
herr_t H5Dclose(hid_t);
hid_t  H5Acreate2(hid_t, const char*, hid_t, hid_t, hid_t, hid_t);
herr_t H5Awrite(hid_t, hid_t, const void*);
herr_t H5Aclose(hid_t);
hid_t  H5Tcopy(hid_t);
herr_t H5Tset_size(hid_t, size_t);
herr_t H5Tset_cset(hid_t, int);
hid_t  H5Tenum_create(hid_t);
herr_t H5Tenum_insert(hid_t, const char*, const void*);
herr_t H5Tclose(hid_t);

#define H5F_ACC_TRUNC 2u
#define H5P_DEFAULT 0
#define H5S_SCALAR 0
#define H5T_CSET_UTF8 1
#define H5T_VARIABLE ((size_t)-1)

static hid_t g_file;

static hid_t open_fixture(const char *path) {
    g_file = -1;
    hid_t cal = -1;
    hid_t f = H5Fcreate(path, H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    if (f < 0) return -1;
    g_file = f;
    hid_t root = H5Gcreate2(f, "test_root", H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    hid_t dcg = H5Gcreate2(root, "datacube", H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    hsize_t dims[4] = {2, 2, 4, 4};
    hid_t sp = H5Screate_simple(4, dims, NULL);
    float cube[2*2*4*4];
    for (int i = 0; i < 2*2*4*4; i++) cube[i] = (float)i;
    hid_t ds = H5Dcreate2(dcg, "data", H5T_NATIVE_FLOAT_g, sp,
                          H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    H5Dwrite(ds, H5T_NATIVE_FLOAT_g, 0, 0, H5P_DEFAULT, cube);
    H5Dclose(ds); H5Sclose(sp); H5Gclose(dcg);
    hid_t mb = H5Gcreate2(root, "metadatabundle", H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    cal = H5Gcreate2(mb, "calibration", H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    H5Gclose(mb); H5Gclose(root);
    return cal;
}

static void write_double_attr(hid_t loc, const char *name, double v) {
    hid_t sp = H5Screate(H5S_SCALAR);
    hid_t a = H5Acreate2(loc, name, H5T_NATIVE_DOUBLE_g, sp, H5P_DEFAULT, H5P_DEFAULT);
    H5Awrite(a, H5T_NATIVE_DOUBLE_g, &v);
    H5Aclose(a); H5Sclose(sp);
}

static void write_vlen_str_attr(hid_t loc, const char *name, const char *v) {
    hid_t t = H5Tcopy(H5T_C_S1_g);
    H5Tset_size(t, H5T_VARIABLE);
    H5Tset_cset(t, H5T_CSET_UTF8);
    hid_t sp = H5Screate(H5S_SCALAR);
    hid_t a = H5Acreate2(loc, name, t, sp, H5P_DEFAULT, H5P_DEFAULT);
    H5Awrite(a, t, &v);
    H5Aclose(a); H5Sclose(sp); H5Tclose(t);
}

static void write_bool_enum_attr(hid_t loc, const char *name, int truth) {
    hid_t t = H5Tenum_create(H5T_NATIVE_INT8_g);
    int8_t f0 = 0, t1 = 1;
    H5Tenum_insert(t, "FALSE", &f0);
    H5Tenum_insert(t, "TRUE", &t1);
    hid_t sp = H5Screate(H5S_SCALAR);
    hid_t a = H5Acreate2(loc, name, t, sp, H5P_DEFAULT, H5P_DEFAULT);
    int8_t v = truth ? 1 : 0;
    H5Awrite(a, t, &v);
    H5Aclose(a); H5Sclose(sp); H5Tclose(t);
}

static void write_double_dset(hid_t loc, const char *name, double v) {
    hid_t sp = H5Screate(H5S_SCALAR);
    hid_t d = H5Dcreate2(loc, name, H5T_NATIVE_DOUBLE_g, sp,
                         H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    H5Dwrite(d, H5T_NATIVE_DOUBLE_g, 0, 0, H5P_DEFAULT, &v);
    H5Dclose(d); H5Sclose(sp);
}

static void write_vlen_str_dset(hid_t loc, const char *name, const char *v) {
    hid_t t = H5Tcopy(H5T_C_S1_g);
    H5Tset_size(t, H5T_VARIABLE);
    H5Tset_cset(t, H5T_CSET_UTF8);
    hid_t sp = H5Screate(H5S_SCALAR);
    hid_t d = H5Dcreate2(loc, name, t, sp, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    H5Dwrite(d, t, 0, 0, H5P_DEFAULT, &v);
    H5Dclose(d); H5Sclose(sp); H5Tclose(t);
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s attrs.h5 datasets.h5\n", argv[0]); return 2; }
    H5open();

    hid_t cal = open_fixture(argv[1]);
    if (cal < 0) { fprintf(stderr, "attrs fixture failed\n"); return 1; }
    write_double_attr(cal, "Q_pixel_size", 0.0125);
    write_vlen_str_attr(cal, "Q_pixel_units", "A^-1");
    write_double_attr(cal, "R_pixel_size", 2.5);
    write_vlen_str_attr(cal, "R_pixel_units", "A");
    write_bool_enum_attr(cal, "QR_flip", 1);
    write_double_attr(cal, "qx0_mean", 31.5);
    write_double_attr(cal, "qy0_mean", 32.25);
    write_double_attr(cal, "a", 1.02);
    write_double_attr(cal, "b", 0.98);
    write_double_attr(cal, "theta", 0.35);
    H5Gclose(cal); H5Fclose(g_file);

    cal = open_fixture(argv[2]);
    if (cal < 0) { fprintf(stderr, "datasets fixture failed\n"); return 1; }
    write_double_dset(cal, "Q_pixel_size", 0.0125);
    write_vlen_str_dset(cal, "Q_pixel_units", "A^-1");
    write_double_dset(cal, "R_pixel_size", 2.5);
    write_vlen_str_dset(cal, "R_pixel_units", "A");
    write_double_dset(cal, "QR_flip", 1.0);
    write_double_dset(cal, "qx0_mean", 31.5);
    write_double_dset(cal, "qy0_mean", 32.25);
    write_double_dset(cal, "a", 1.02);
    write_double_dset(cal, "b", 0.98);
    write_double_dset(cal, "theta", 0.35);
    H5Gclose(cal); H5Fclose(g_file);

    printf("fixtures written\n");
    return 0;
}
