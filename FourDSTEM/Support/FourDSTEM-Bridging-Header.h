//
//  FourDSTEM-Bridging-Header.h
//  Role: Exposes the HDF5 C library to Swift.
//
//  Anything #imported here becomes callable from every Swift file in the
//  app target. We only need the HDF5 umbrella header. The header is found via
//  the "Header Search Paths" build setting that points at your Homebrew
//  HDF5 install (see the setup guide).
//
//  NOTE FOR SWIFT: Many HDF5 "constants" (H5F_ACC_RDONLY, H5P_DEFAULT,
//  H5T_NATIVE_FLOAT, ...) are C macros that DO NOT import cleanly into Swift.
//  We redefine the simple ones in H5Reader.swift, and we use the underlying
//  global variables (e.g. H5T_NATIVE_FLOAT_g) after calling H5open(). This is
//  a well-known HDF5+Swift gotcha — see comments in H5Reader.swift.
//

#ifndef FourDSTEM_Bridging_Header_h
#define FourDSTEM_Bridging_Header_h

#import <hdf5.h>

#endif /* FourDSTEM_Bridging_Header_h */
