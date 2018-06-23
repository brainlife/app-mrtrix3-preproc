#!/bin/bash

## -se_epi for optional topup? should be done automatically w/ reverse dirs...?
## add option to just perform motion correction

export LD_LIBRARY_PATH=/usr/local/cuda-8.0/lib64:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/usr/lib/nvidia-390:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/usr/lib/nvidia-390/extra:$LD_LIBRARY_PATH

## define number of threads to use
NCORE=8

## raw inputs
DIFF=`jq -r '.diff' config.json`
BVAL=`jq -r '.bval' config.json`
BVEC=`jq -r '.bvec' config.json`

ANAT=`jq -r '.anat' config.json`

RDIF=`jq -r '.rdif' config.json` ## optional
RBVL=`jq -r '.rbvl' config.json` ## optional
RBVC=`jq -r '.rbvc' config.json` ## optional

## acquisition direction: RL, PA, IS
ACQD=`jq -r '.acqd' config.json`

## switches for potentially optional steps
DO_DENOISE=`jq -r '.denoise' config.json`
DO_DEGIBBS=`jq -r '.degibbs' config.json`
DO_EDDY=`jq -r '.eddy' config.json`
DO_BIAS=`jq -r '.bias' config.json`
DO_NORM=`jq -r '.norm' config.json`
DO_ACPC=`jq -r '.acpc' config.json`
NEW_RES=`jq -r '.reslice' config.json`
NORM=`jq -r '.nval' config.json`

if [ -z $NEW_RES ]; then
    DO_RESLICE="false"
else
    DO_RESLICE="true"
fi

## read in eddy options
RPE=`jq -r '.rpe' config.json` ## optional

## if no second sequence, override to only option
if [ -z $RDIF ]; then
    RPE="none"
fi

## assign output space of final data if acpc not called
out=proc

## diffusion file that changes name based on steps performed
difm=dwi
mask=b0_dwi_brain_mask

## create local copy of anat
cp $ANAT ./t1_acpc.nii.gz
ANAT=t1_acpc

## create temp folders explicitly
mkdir ./tmp

echo "Converting input files to mrtrix format..."

## convert input diffusion data into mrtrix format
mrconvert -fslgrad $BVEC $BVAL $DIFF raw1.mif --export_grad_mrtrix raw1.b -nthreads $NCORE -quiet

## if the second input exists
if [ -e $RDIF ]; then

    ## convert it to mrtrix format
    mrconvert -fslgrad $RBVC $RBVL $RDIF raw2.mif --export_grad_mrtrix raw2.b -nthreads $NCORE -quiet
    
fi

echo "Identifying correct gradient orientation..."

if [ $RPE == "all" ]; then

    ## merge them
    mrcat raw1.mif raw2.mif raw.mif -nthreads $NCORE -quiet

    echo "Creating processing mask..."

    ## create mask
    dwi2mask raw.mif ${mask}.mif -force -nthreads $NCORE -quiet

    ## check and correct gradient orientation and create corrected image
    dwigradcheck raw.mif -grad raw1.b -mask ${mask}.mif -export_grad_mrtrix corr.b -force -tempdir ./tmp -nthreads $NCORE -quiet
    mrconvert raw.mif -grad corr.b ${difm}.mif -nthreads $NCORE -quiet

else

    echo "Creating processing mask..."

    ## create mask
    dwi2mask raw1.mif ${mask}.mif -force -nthreads $NCORE -quiet

    ## check and correct gradient orientation and create corrected image
    dwigradcheck raw1.mif -grad raw1.b -mask ${mask}.mif -export_grad_mrtrix corr.b -force -tempdir ./tmp -nthreads $NCORE -quiet
    mrconvert raw1.mif -grad corr.b ${difm}.mif -nthreads $NCORE -quiet

    if [ -e raw2.mif ]; then
	dwi2mask raw2.mif rpe_${mask}.mif -force -nthreads $NCORE -quiet
	dwigradcheck raw2.mif -grad raw2.b -mask rpe_${mask}.mif -export_grad_mrtrix cor2.b -force -tempdir ./tmp -nthreads $NCORE -quiet
	mrconvert raw2.mif -grad cor2.b rpe_${difm}.mif -nthreads $NCORE -quiet
    fi
    
fi

## perform PCA denoising
if [ $DO_DENOISE == "true" ]; then

    echo "Performing PCA denoising..."
    dwidenoise ${difm}.mif ${difm}_denoise.mif -nthreads $NCORE -quiet
    
    if [ -e rpe_${difm}.mif ]; then
	dwidenoise rpe_${difm}.mif rpe_${difm}_denoise.mif -nthreads $NCORE -quiet
    fi

    difm=${difm}_denoise
    
fi

## if scanner artifact is found
if [ $DO_DEGIBBS == "true" ]; then

    echo "Performing Gibbs ringing correction..."
    mrdegibbs ${difm}.mif ${difm}_degibbs.mif -nthreads $NCORE -quiet

    if [ -e rpe_${difm}.mif ]; then
	mrdegibbs rpe_${difm}.mif rpe_${difm}_degibbs.mif -nthreads $NCORE -quiet
    fi

    difm=${difm}_degibbs
    
fi
   
## perform eddy correction with FSL
if [ $DO_EDDY == "true" ]; then

    if [ $RPE == "none" ]; then
	    
	echo "Performing FSL eddy correction..."
	dwipreproc -rpe_none -pe_dir $ACQD ${difm}.mif ${difm}_eddy.mif -tempdir ./tmp -nthreads $NCORE -quiet
	difm=${difm}_eddy
	
    fi

    if [ $RPE == "pairs" ]; then
      
	echo "Performing FSL topup and eddy correction ..."
	dwipreproc -rpe_pair -pe_dir $ACQD ${difm}.mif -se_epi rpe_${difm}.mif ${difm}_eddy.mif -tempdir ./tmp -nthreads $NCORE -quiet
	difm=${difm}_eddy
	
    fi

    if [ $RPE == "all" ]; then
	
	echo "Performing FSL eddy correction for merged input DWI sequences..."
	dwipreproc -rpe_all -pe_dir $ACQD ${difm}.mif ${difm}_eddy.mif -tempdir ./tmp -nthreads $NCORE -quiet
	difm=${difm}_eddy
	
    fi

    
    if [ $RPE == "header" ]; then
    
	echo "Performing FSL eddy correction for merged input DWI sequences..."
	dwipreproc -rpe_header ${difm}.mif ${difm}_eddy.mif -tempdir ./tmp -nthreads $NCORE -quiet
	difm=${difm}_eddy
	
    fi

fi

echo "Creating dwi space b0 reference images..."

## create b0 and mask image in dwi space on forward direction only
dwiextract ${difm}.mif - -bzero -nthreads $NCORE -quiet | mrmath - mean b0_dwi.mif -axis 3 -nthreads $NCORE -quiet
dwi2mask ${difm}.mif ${mask}.mif -force -nthreads $NCORE -quiet

## convert to nifti for alignment to anatomy later on
mrconvert b0_dwi.mif -stride 1,2,3,4 b0_dwi.nii.gz -nthreads $NCORE -quiet
mrconvert ${mask}.mif -stride 1,2,3,4 ${mask}.nii.gz -nthreads $NCORE -quiet

## apply mask to image
fslmaths b0_dwi.nii.gz -mas ${mask}.nii.gz b0_dwi_brain.nii.gz

## compute bias correction with ANTs on dwi data
if [ $DO_BIAS == "true" ]; then
    
    echo "Performing bias correction with ANTs..."
    dwibiascorrect -mask ${mask}.mif -ants ${difm}.mif ${difm}_bias.mif -tempdir ./tmp -nthreads $NCORE -quiet
    difm=${difm}_bias
    
fi

## perform intensity normalization of dwi data
if [ $DO_NORM == "true" ]; then

    echo "Performing intensity normalization..."

    ## create fa wm mask of input subject
    dwi2tensor -mask ${mask}.mif -nthreads $NCORE -quiet ${difm}.mif - | tensor2metric -nthreads $NCORE -quiet - -fa - | mrthreshold -nthreads $NCORE -quiet -abs 0.5 - wm.mif 

    ## dilate / erode fa wm mask for smoother volume
    #maskfilter -npass 3 wm_raw.mif dilate - | maskfilter -connectivity - connect - | maskfilter -npass 3 - erode wm.mif
    ## this looks far too blocky to be useful
    
    ## normalize intensity of generous FA white matter mask to 1000
    dwinormalise -intensity $NORM ${difm}.mif wm.mif ${difm}_norm.mif -nthreads $NCORE -quiet
    difm=${difm}_norm
    
fi

if [ $DO_ACPC == "true" ]; then

    echo "Running brain extraction on anatomy..."

    ## create t1 mask
    bet ${ANAT}.nii.gz ${ANAT}_brain -R -B -m

    echo "Aligning dwi data with AC-PC anatomy..."

    ## compute BBR registration corrected diffusion data to AC-PC anatomy
    epi_reg --epi=b0_dwi_brain.nii.gz --t1=${ANAT}.nii.gz --t1brain=${ANAT}_brain.nii.gz --out=dwi2acpc

    ## apply the transform w/in mrtrix, correcting gradients
    mrtransform -linear dwi2acpc.mat ${difm}.mif ${difm}_acpc.mif -nthreads $NCORE -quiet
    difm=${difm}_acpc

    ## assign output space label
    out=acpc
    
fi

if [ $DO_RESLICE == "true" ]; then

    echo "Reslicing diffusion data to requested isotropic voxel size..."

    ## sed to turn possible decimal into p
    VAL=`echo $NEW_RES | sed s/\\\./p/g`

    mrresize ${difm}.mif -voxel $NEW_RES ${difm}_${VAL}mm.mif -nthreads $NCORE -quiet
    difm=${difm}_${VAL}mm

else

    ## append voxel size in mm to the end of file, rename
    VAL=`mrinfo -vox dwi.mif | awk {'print $1'} | sed s/\\\./p/g`
    echo VAL: $VAL
    mv ${difm}.mif ${difm}_${VAL}mm.mif
    difm=${difm}_${VAL}mm
    
fi

echo "Creating $out space b0 reference images..."

## create final b0 / mask
dwiextract ${difm}.mif - -bzero -nthreads $NCORE -quiet | mrmath - mean b0_${out}.mif -axis 3 -nthreads $NCORE -quiet
dwi2mask ${difm}.mif b0_${out}_brain_mask.mif -nthreads $NCORE -quiet

## create output space b0s
mrconvert b0_${out}.mif -stride 1,2,3,4 b0_${out}.nii.gz -nthreads $NCORE -quiet
mrconvert b0_${out}_brain_mask.mif -stride 1,2,3,4 b0_${out}_brain_mask.nii.gz -nthreads $NCORE -quiet
fslmaths b0_${out}.nii.gz -mas b0_${out}_brain_mask.nii.gz b0_${out}_brain.nii.gz

echo "Creating preprocessed dwi files in $out space..."

## convert to nifti / fsl output for storage
mrconvert ${difm}.mif -stride 1,2,3,4 dwi.nii.gz -export_grad_fsl dwi.bvecs dwi.bvals -export_grad_mrtrix ${difm}.b -json_export ${difm}.json -nthreads $NCORE -quiet

## export a lightly structured text file (json?) of shell count / lmax
echo "Writing text file of basic sequence information..."

## parse single or multishell counts
nshell=`mrinfo -shells ${difm}.mif | wc -w`
shell=$(($nshell-1)) ## assumes at least 1 b0

## add file name to summary.txt
echo ${difm} > summary.txt

if [ $shell -gt 1 ]; then
    echo multi-shell: $shell total shells >> summary.txt
else
    echo single-shell: $shell total shell >> summary.txt
fi

## compute # of b0s
b0s=`mrinfo -shellcounts ${difm}.mif | awk '{print $1}'`
echo Number of b0s: $b0s >> summary.txt 

echo >> summary.txt
echo shell / count / lmax >> summary.txt

## echo basic shell count summaries
mrinfo -shells ${difm}.mif >> summary.txt
mrinfo -shellcounts ${difm}.mif >> summary.txt

## echo max lmax per shell
lmaxs=`dirstat ${difm}.b | grep lmax | awk '{print $8}' | sed "s|:||g"`
echo $lmaxs >> summary.txt

## print into log
cat summary.txt

echo "Cleaning up working directory..."

## cleanup
find . -maxdepth 1 -mindepth 1 -type f -name "*.mif" ! -name "${difm}.mif" -delete
find . -maxdepth 1 -mindepth 1 -type f -name "*.b" ! -name "${difm}.b" -delete
rm -f *fast*.nii.gz
rm -f *init.mat
rm -f dwi2acpc.nii.gz
rm -rf ./tmp

