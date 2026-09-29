#!/bin/zsh
SP=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/b119bc6d-fd92-4a13-b081-be12f91a813f/scratchpad
R=/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/References
T=$R/training_dataset
entries=(
 "fixture|fixture"
 "WS2|$T/polycrystal_2D_WS2.h5"
 "SiSiGe_exp|$T/downsample_Si_SiGe_exp.h5"
 "Particle_1|$T/Particle_1_Stack_1_45x90_ss30nm_0p09s_spot8_alpha=0p48_bin2_cl-600mm_300kV_bin8.h5"
 "simAu_poly|$T/sim_Au_data_all_binned.h5|/4DSTEM_simulation/4DSTEM_polyAu/data"
 "simAu_nano|$T/sim_Au_data_all_binned.h5|/4DSTEM_simulation/4DSTEM_AuNanoplatelet/data"
 "bullseye_polyAu|$T/calibrationData_bullseyeProbe.h5|/4DSTEM_experiment/data/datacubes/polyAu_4DSTEM/data"
 "bullseye_sim|$T/calibrationData_bullseyeProbe.h5|/4DSTEM_experiment/data/datacubes/simulation_4DSTEM/data"
 "SiSiGe_cal|$T/Si-SiGe_calibrated.h5"
 "Au_ref|$T/Au_ref_ROI15_preprocessed_unfiltered_bin_4_20241214.h5"
 "AlMgSi_060|$T/Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5"
 "thronsenA|$R/thronsen-datasetA/datasetA_stride3.h5"
 "demo_cube|$R/demo-dataset/AlMgSi_demo.h5"
)
cd $SP/s14/run
for e in $entries; do
  lab=${e%%|*}
  until mkdir $SP/heavy.lock 2>/dev/null; do sleep 20; done
  S14_OUT=$SP/s14/out MAC4DSTEM_HDF5_PATH=$SP/s14/run/libhdf5.dylib ./s14probe "$e" > $SP/s14/logs/grid_$lab.log 2>&1
  echo $? > $SP/s14/logs/grid_$lab.exit
  rmdir $SP/heavy.lock
done
echo done > $SP/s14/logs/grid.done
