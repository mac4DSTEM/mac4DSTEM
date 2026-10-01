#!/bin/zsh
# Lane R2 graphene arms (2026-10-01), one lock for the whole sequence. Predictions G1-G3 are in $SP/R/report.md, written before this ran.
SP=${SP:?set SP to the session scratchpad (the lane dir is $SP/R)}
REPO=/Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM
CUBE=/Volumes/PL_SSD_2TB/4D_STEM_Datacubes/twisted_bilayer_graphene.hdf5
PY=$HOME/miniconda3/envs/py4dstem/bin/python
G=$SP/R/gr
until mkdir "$SP/heavy.lock" 2>/dev/null; do sleep 15; done
trap 'rmdir "$SP/heavy.lock"' EXIT
echo "lock acquired $(date)"
cd $REPO
for NM in 1 0.05; do
  $PY tools/parallax-ptycho-real-probe/reference_ptycho.py $CUBE --out $G/py-dm-m600-nm$NM --defocus -600 --rotation-deg 0 --transpose 0 --method dm --norm-min $NM > $G/py-dm-m600-nm$NM.log 2>&1; echo "py dm nm$NM EXIT=$?"
done
COMMON=(--kv 80 --q 0.025 --r 5.0 --repeat 1 --defocus -600)
PROBE_DIR=$SP/R/probe tools/parallax-ptycho-real-probe/run.sh $CUBE ptycho dmap $COMMON --norm-min 1 --constrain-amplitude 1 --out $G/app-dm-nm1-c1 > $G/arm-r2a.log 2>&1; echo "arm r2a EXIT=$?"
PROBE_DIR=$SP/R/probe tools/parallax-ptycho-real-probe/run.sh $CUBE ptycho dmap $COMMON --norm-min 1 --constrain-amplitude 0 --out $G/app-dm-nm1-c0 > $G/arm-r2b.log 2>&1; echo "arm r2b EXIT=$?"
PROBE_DIR=$SP/R/probe tools/parallax-ptycho-real-probe/run.sh $CUBE ptycho dmap $COMMON --norm-min 0.05 --constrain-amplitude 1 --out $G/app-dm-nm0.05-c1 > $G/arm-r2c.log 2>&1; echo "arm r2c EXIT=$?"
PROBE_DIR=$SP/R/probe tools/parallax-ptycho-real-probe/run.sh $CUBE ptycho gd $COMMON --constrain-amplitude 1 --out $G/app-gd-c1 > $G/arm-r2d.log 2>&1; echo "arm r2d EXIT=$?"
echo "done $(date)"
