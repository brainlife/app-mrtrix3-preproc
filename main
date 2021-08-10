#!/bin/bash
#PBS -l nodes=1:ppn=8,walltime=19:00:00
#PBS -N bl_mrtrix3_preproc
#PBS -l vmem=29gb

set -x
set -e

# in case cuda version fails
export SINGULARITYENV_OMP_NUM_THREADS=$OMP_NUM_THREADS

# pass cuda91 path to singularity
export SINGULARITYENV_CUDA91PATH=$CUDA91PATH

time singularity exec -e --nv docker://brainlife/mrtrix3:3.0.2 ./mrtrix3_preproc.sh

