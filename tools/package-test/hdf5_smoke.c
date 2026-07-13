#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef int (*H5openFn)(void);
typedef int (*H5getLibversionFn)(unsigned *, unsigned *, unsigned *);
typedef int64_t (*H5FopenFn)(const char *, unsigned, int64_t);
typedef int (*H5FcloseFn)(int64_t);

static void *required(void *handle, const char *name) {
    void *symbol = dlsym(handle, name);
    if (!symbol) {
        fprintf(stderr, "missing %s: %s\n", name, dlerror());
        exit(1);
    }
    return symbol;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: hdf5_smoke LIBHDF5 FIXTURE\n");
        return 2;
    }
    void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror());
        return 1;
    }
    H5openFn h5open = (H5openFn)required(handle, "H5open");
    H5getLibversionFn version =
        (H5getLibversionFn)required(handle, "H5get_libversion");
    H5FopenFn fileOpen = (H5FopenFn)required(handle, "H5Fopen");
    H5FcloseFn fileClose = (H5FcloseFn)required(handle, "H5Fclose");

    unsigned major = 0, minor = 0, patch = 0;
    if (h5open() < 0 || version(&major, &minor, &patch) < 0) return 1;
    int64_t file = fileOpen(argv[2], 0, 0);
    if (file < 0 || fileClose(file) < 0) return 1;
    printf("PASS: bundled HDF5 %u.%u.%u opened fixture\n", major, minor, patch);
    dlclose(handle);
    return 0;
}
