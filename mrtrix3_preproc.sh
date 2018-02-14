#!/bin/bash

## add option to just perform motion correction

## define number of threads to use
NCORE=8

## raw inputs
DIFF=`jq -r '.diff' config.json`
BVAL=`jq -r '.bval' config.json`
BVEC=`jq -r '.bvec' config.json`
ANAT=`jq -r '.anat' config.json`

## acquisition direction: RL, PA, IS
ACQD=`jq -r '.acqd' config.json`

## switches for potentially optional steps
DO_BIAS=`jq -r '.bias' config.json`
DO_DENOISE=`jq -r '.denoise' config.json`
DO_DEGIBBS=`jq -r '.degibbs' config.json`
DO_INORM=`jq -r '.inorm' config.json`
DO_EDDY=`jq -r '.eddy' config.json`
DO_RESLICE=`jq -r '.reslice' config.json`

## diffusion file that changes name based on steps performed
difm=dwi

## create local copy of anat
cp $ANAT ./t1.nii.gz
ANAT=t1.nii.gz

## create temp folders explicitly
mkdir ./tmp

## convert input diffusion data into mrtrix format
mrconvert -fslgrad $BVEC $BVAL $DIFF ${difm}.mif --export_grad_mrtrix ${difm}.b -nthreads $NCORE -quiet

echo "Creating processing files..."

## create mask
dwi2mask ${difm}.mif mask.mif -nthreads $NCORE -quiet

echo "Identifying correct gradient orientation..."

## check and correct gradient orientation
dwigradcheck ${difm}.mif -grad ${difm}.b -mask mask.mif -export_grad_mrtrix ${difm}_corr.b -force -tempdir ./tmp -nthreads $NCORE -quiet

## create corrected image
mrconvert ${difm}.mif -grad ${difm}_corr.b ${difm}_corr.mif -nthreads $NCORE -quiet
difm=${difm}_corr

## perform PCA denoising
if [ $DO_DENOISE == "true" ]; then

    echo "Performing PCA denoising..."
    dwidenoise ${difm}.mif ${difm}_denoise.mif -nthreads $NCORE -quiet
    difm=${difm}_denoise
    
fi

## if scanner artifact is found
if [ $DO_DEGIBBS == "true" ]; then

    echo "Performong Gibbs ringing correction..."
    mrdegibbs ${difm}.mif ${difm}_degibbs.mif -nthreads $NCORE -quiet
    difm=${difm}_degibbs
    
fi
   
## perform eddy correction with FSL
if [ $DO_EDDY == "true" ]; then

    echo "Performing FSL eddy correction..."
    dwipreproc -rpe_none -pe_dir $ACQD ${difm}.mif ${difm}_eddy.mif -export_grad_mrtrix ${difm}_eddy.b -tempdir ./tmp -nthreads $NCORE -quiet
    difm=${difm}_eddy

fi

## compute bias correction with ANTs on dwi data
if [ $DO_BIAS == "true" ]; then
    
    echo "Performing bias correction with ANTs..."
    dwibiascorrect -mask mask.mif -ants ${difm}.mif ${difm}_bias.mif -tempdir ./tmp -nthreads $NCORE -quiet
    difm=${difm}_bias
    
fi

## perform intensity normalization of dwi data
if [ $DO_INORM == "true" ]; then

    echo "Performing intensity normalization..."
    dwinormalise -intensity 1000 ${difm}.mif mask.mif ${difm}_norm.mif -nthreads $NCORE -quiet
    difm=${difm}_norm
    
fi

## create b0 and mask image in dwi space
dwiextract ${difm}.mif - -bzero -nthreads $NCORE | mrmath - mean b0_dwi.mif -axis 3 -nthreads $NCORE -quiet
dwi2mask ${difm}.mif mask_dwi.mif -force -nthreads $NCORE -quiet

## convert to nifti for alignment
mrconvert b0_dwi.mif -stride 1,2,3,4 b0_dwi.nii.gz -nthreads $NCORE -quiet
mrconvert mask_dwi.mif -stride 1,2,3,4 mask_dwi.nii.gz -nthreads $NCORE -quiet

## apply mask to image
fslmaths b0_dwi.nii.gz -mas mask_dwi.nii.gz b0_dwi_brain.nii.gz

echo "Running brain extraction on anatomy..."

## create t1 mask
bet $ANAT ${ANAT}_brain -R -B -m

echo "Aligning dwi data with AC-PC anatomy..."

## compute BBR registration corrected diffusion data to AC-PC anatomy
epi_reg --epi=b0_dwi_brain.nii.gz --t1=$ANAT --t1brain=${ANAT}_brain.nii.gz --out=dwi2acpc

## apply the transform w/in mrtrix, correcting gradients
mrtransform -linear dwi2acpc.mat ${difm}_acpc.mif -nthreads $NCORE -quiet
difm=${difm}_acpc

if [ $DO_RESLICE -ne 0 ]; then

    echo "Reslicing diffusion data to requested voxel size..."
    mrresize ${difm}.mif -voxel $DO_RESLICE ${difm}_${DO_RESLICE}mm.mif -nthreads $NCORE -quiet
    difm=${difm}_${DO_RESLICE}mm

fi

## create acpc b0 / mask
#dwiextract ${difm}.mif - -bzero -nthreads $NCORE | mrmath - mean b0_acpc.mif -axis 3 -nthreads $NCORE -quiet
#dwi2mask ${difm}.mif mask_acpc.mif -nthreads $NCORE -quiet

echo "Creating output files..."

## convert to nifti / fsl output for storage
mrconvert ${difm}.mif -stride 1,2,3,4 ${difm}.nii.gz -export_grad_fsl ${difm}.bvals ${difm}.bvecs -nthreads $NCORE -quiet
#mrconvert b0_acpc.mif -stride 1,2,3,4 meanb0_acpc.nii.gz -nthreads $NCORE -quiet
#mrconvert mask_acpc.mif -stride 1,2,3,4 mask_acpc.nii.gz -nthreads $NCORE -quiet

echo "Cleaning up working directory..."

## cleanup
#rm -f *.mif
#rm -f *.b
#rm -f *fast*.nii.gz
#rm -f *init.mat
#rm -f dwi2acpc.nii.gz
#rm -rf ./tmp

