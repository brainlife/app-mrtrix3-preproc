#!/bin/bash

set -x
set -e

#some mrtrix3 commands don't honor -nthreads option (https://github.com/MRtrix3/mrtrix3/issues/1479
echo "OMP_NUM_THREADS=$OMP_NUM_THREADS"
[ -z "$OMP_NUM_THREADS" ] && export OMP_NUM_THREADS=8

#*add* cudalib path to LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CUDA91PATH/lib64

## assign output space of final data if acpc not called
out=proc

## diffusion file that changes name based on steps performed
difm=dwi
mask=b0_dwi_brain_mask

## create / remove old tmp folders / previous run files explicitly
rm -rf ./tmp ./eddyqc cor1.b cor2.b corr.b
mkdir -p ./tmp

common="-nthreads $OMP_NUM_THREADS -quiet -force"

##
## import .json
##

## raw inputs
DIFF=`jq -r '.diff' config.json`
BVAL=`jq -r '.bval' config.json`
BVEC=`jq -r '.bvec' config.json`

ANAT=`jq -r '.anat' config.json`

## optional reverse phase encoded (rpe) inputs
RDIF=`jq -r '.rdif' config.json` ## optional
RBVL=`jq -r '.rbvl' config.json` ## optional
RBVC=`jq -r '.rbvc' config.json` ## optional

ROUND_BVALS=`jq -r '.round_bvals' config.json`

## acquisition direction: RL, PA, IS
ACQD=`jq -r '.acqd' config.json`

## switches for potentially optional steps
DO_DENOISE=`jq -r '.denoise' config.json`
DO_DEGIBBS=`jq -r '.degibbs' config.json`
DO_EDDY=`jq -r '.eddy' config.json`
DO_BIAS=`jq -r '.bias' config.json`
DO_RICN=`jq -r '.ricn' config.json`
DO_NORM=`jq -r '.norm' config.json`
DO_ACPC=`jq -r '.acpc' config.json`
NEW_RES=`jq -r '.reslice' config.json`
NORM=`jq -r '.nval' config.json`
PRCT=`jq -r '.prct' config.json`

## switch and advanced options for bias correction
BIAS_METHOD=`jq -r '.bias_method' config.json`
ANTSB=`jq -r '.antsb' config.json`
ANTSC=`jq -r '.antsc' config.json`
ANTSS=`jq -r '.antss' config.json`

## fill in arguments common to all dwifslpreproc calls
common_fslpreproc="-eddy_mask ${mask}.mif -eddyqc_all ./eddyqc -scratch ./tmp -nthreads $OMP_NUM_THREADS -force"

## add advanced options to eddy call
eddy_data_is_shelled=`jq -r '.eddy_data_is_shelled' config.json`
eddy_slm=`jq -r '.eddy_slm' config.json`
eddy_niter=`jq -r '.eddy_niter' config.json`
eddy_repol=`jq -r '.eddy_repol' config.json`
eddy_mporder=`jq -r '.eddy_mporder' config.json`

eddy_options=" " ## must contain at least 1 space according to mrtrix doc
[ "$eddy_repol" == "true" ] && eddy_options="$eddy_options --repol"
[ "$eddy_data_is_shelled" == "true" ] && eddy_options="$eddy_options --data_is_shelled"
eddy_options="$eddy_options --slm=$eddy_slm"
eddy_options="$eddy_options --niter=$eddy_niter"
[ "$eddy_mporder" != "0" ] && eddy_options="$eddy_options --mporder=$eddy_mporder"

# Provide a file containing slice groupings for eddy's slice-to-volume registration (for dwifslpreproc)
jq -rj '.eddy_slspec' config.json > slspec.txt
if [ -s slspec.txt ]; then
    common_fslpreproc="$common_fslpreproc -eddy_slspec slspec.txt"
fi

## add add advanced options for topup call
topup_lambda=`jq -r '.topup_lambda' config.json`
topup_options=" "
[ "$topup_lambda" != "0.005,0.001,0.0001,0.000015,0.000005,0.0000005,0.00000005,0.0000000005,0.00000000001" ] && topup_options="$topup_options --lambda=$topup_lambda"

## set switch to relsice to a new isotropic voxel size
if [ -z $NEW_RES ]; then
    DO_RESLICE="false"
else
    DO_RESLICE="true"
fi

##
## Begin processing
##

## create local copy of anat (TODO - wouldn't symlink work?)
cp $ANAT t1_acpc.nii.gz
chmod +w t1_acpc.nii.gz #to be able to rerun
ANAT=t1_acpc

echo "Converting input files to mrtrix format..."

if [ "$ROUND_BVALS" == "true" ]; then
    ./round.py $BVAL > bval.round
    BVAL=bval.round
fi

## convert input diffusion data into mrtrix format
mrconvert -fslgrad $BVEC $BVAL $DIFF raw1.mif --export_grad_mrtrix raw1.b $common

## if the second input exists
if [ -e $RDIF ]; then

    if [ "$ROUND_BVALS" == "true" ]; then
        ./round.py $RBVL > rbvl.round
        RBVL=rbvl.round
    fi

    ## convert it to mrtrix format
    mrconvert -fslgrad $RBVC $RBVL $RDIF raw2.mif --export_grad_mrtrix raw2.b $common
fi

## determine the type of acquisition for dwipreproc eddy options
if [ $RDIF == "null" ];
then 

    ## if no second sequence, override to the only option
    RPE="none"

else
    
    ## grab the size of each sequence
    nb0F=`mrinfo -size raw1.mif | grep -oE '[^[:space:]]+$'`
    nb0R=`mrinfo -size raw2.mif | grep -oE '[^[:space:]]+$'`

    echo "Forward phase encoded dwi volume has $nb0F volumes."
    echo "Reverse phase encoded dwi volume has $nb0R volumes."
    
    ## check the size of the inputs
    if [ $nb0F -eq $nb0R ];
    then
	## if they match, it's "all"
	RPE="all"
	## just because the # of volumes match doesn't mean they're valid
    else
	## if they don't, it's "pairs"
	RPE="pairs"

	## if the last dim is even
	if [ $(($nb0R%2)) == 0 ];
	then
	    ## pass the file - no assurance it's valid volumes, just a valid number of them
	    echo "The RPE file has an even number of volumes. No change was made."
	else
	    ## drop any volumes w/ a sufficiently high bval to be a direction - often makes an odd sequence even
	    echo "The RPE file has an odd number of volumes. Only the b0 volumes were extracted."
	    #dwiextract -bzero raw2.mif raw2.mif $common
	    dwiextract -bzero raw2.mif rpe_${difm}.mif $common
	    ob0=`mrinfo -size raw2.mif | grep -oE '[^[:space:]]+$'`
	    echo "This should be an even number: $ob0"
	    ## this doesn't stop or exit if it's still odd...
	fi

    fi
    
fi

echo "RPE assigned as: $RPE"

if [ $RPE == "all" ]; then

    ## merge them
    mrcat raw1.mif raw2.mif raw.mif $common
    cat raw1.b raw2.b > raw.b
    
    echo "creating dwimask (dwi2mask) from merged data ..."
    dwi2mask raw.mif ${mask}.mif $common

    ## check and correct gradient orientation and create corrected image
    echo "Identifying correct gradient orientation..."
    dwigradcheck raw.mif -grad raw.b -mask ${mask}.mif -export_grad_mrtrix corr.b -scratch ./tmp $common
    mrconvert raw.mif -grad corr.b ${difm}.mif $common

else
    echo "creating dwimask (dwi2mask) from raw1.mif ..."
    dwi2mask raw1.mif ${mask}.mif $common

    ## check and correct gradient orientation and create corrected image
    echo "Identifying correct gradient orientation..."
    dwigradcheck raw1.mif -grad raw1.b -mask ${mask}.mif -export_grad_mrtrix cor1.b -scratch ./tmp $common
    mrconvert raw1.mif -grad cor1.b ${difm}.mif $common

    ## this fails if only a single volume (?) - also, it doesn't appear to be used
    # if [ -e raw2.mif ]; then
    #     dwi2mask raw2.mif rpe_${mask}.mif $common
    #     ## no dwigradcheck, b/c this is necessarily b0s with this logic
    # fi
    
fi

## perform PCA denoising
if [ $DO_DENOISE == "true" ] || [ $DO_RICN == "true" ]; then

    echo "Performing PCA denoising (dwidenoise)..."
    dwidenoise -extent 5,5,5 -noise fpe_noise.mif -estimator Exp2 ${difm}.mif ${difm}_denoise.mif $common

    ## if the second volume exists, denoise as well and average the noise volumes together    
    if [ -e rpe_${difm}.mif ]; then
        dwidenoise -extent 5,5,5 -noise rpe_noise.mif -estimator Exp2 rpe_${difm}.mif rpe_${difm}_denoise.mif $common
        mrcalc fpe_noise.mif rpe_noise.mif -add 2 -divide noise.mif $common
    else
        cp fpe_noise.mif noise.mif
    fi

    ## if denoise is true, use the denoised volume on the next steps
    ## otherwise it just makes the noise for the rician
    if [ $DO_DENOISE == "true" ]; then
        difm=${difm}_denoise
    fi

fi

## if scanner artifact is found
if [ $DO_DEGIBBS == "true" ]; then

    echo "Performing Gibbs ringing correction (mrdegibbs)..."
    mrdegibbs -nshifts 20 -minW 1 -maxW 3 ${difm}.mif ${difm}_degibbs.mif $common

    if [ -e rpe_${difm}.mif && $RPE == "all" ]; then
        mrdegibbs -nshifts 20 -minW 1 -maxW 3 rpe_${difm}.mif rpe_${difm}_degibbs.mif $common
    else
	## if it's just a b0, silently move over b/c it appears to not be a valid call
	cp rpe_${difm}.mif rpe_${difm}_degibbs.mif $common
    fi

    difm=${difm}_degibbs
    
fi

## perform eddy correction with FSL
if [ $DO_EDDY == "true" ]; then
    echo "Performing Eddy correction (dwifslpreproc)... rpe:$RPE"
    
    if [ $RPE == "none" ]; then
	    dwifslpreproc ${difm}.mif ${difm}_eddy.mif -rpe_none -pe_dir ${ACQD} -eddy_options "$eddy_options" $common_fslpreproc
        difm=${difm}_eddy
    fi

    if [ $RPE == "pairs" ]; then
        ## pull and merge the b0s
        dwiextract -bzero ${difm}.mif fpe_b0.mif $common
        dwiextract -bzero rpe_${difm}.mif rpe_b0.mif $common ## maybe redundant?
        mrcat fpe_b0.mif rpe_b0.mif b0_pairs.mif -axis 3 $common

        ## call to dwifslpreproc w/ new options
        dwifslpreproc ${difm}.mif ${difm}_eddy.mif -rpe_pair -se_epi b0_pairs.mif -pe_dir ${ACQD} -align_seepi -topup_options "$topup_options" -eddy_options "$eddy_options" $common_fslpreproc
        difm=${difm}_eddy
    fi

    if [ $RPE == "all" ]; then
        dwifslpreproc ${difm}.mif ${difm}_eddy.mif -rpe_all -pe_dir ${ACQD} -topup_options "$topup_options" -eddy_options "$eddy_options" $common_fslpreproc
        difm=${difm}_eddy
    fi

fi

## rebuild mask after eddy motion - necessary?
dwi2mask ${difm}.mif ${mask}.mif $common

## compute bias correction with ANTs on dwi data
if [ $DO_BIAS == "true" ]; then
    
    if [ $BIAS_METHOD == "ants" ]; then
        echo "Performing bias correction with ANTs (dwibiascorrect ants)..."
        dwibiascorrect ants -ants.b $ANTSB -ants.c $ANTSC -ants.s $ANTSS -mask ${mask}.mif ${difm}.mif ${difm}_bias.mif -scratch ./tmp $common
    fi

    if [ $BIAS_METHOD == "fsl" ]; then
        echo "Performing bias correction with FSL (dwibiascorrect fsl)..."
        dwibiascorrect fsl -mask ${mask}.mif ${difm}.mif ${difm}_bias.mif -scratch ./tmp $common   
    fi

    difm=${difm}_bias

fi

## perform Rician background noise removal
## - I don't think this has changed, but if a field map is present there is a more direct way to apply this correction (see mrtrix3 mrdenoise doc online)
if [ $DO_RICN == "true" ]; then

    echo "Performing Rician background noise removal..."

    mrinfo ${difm}.mif -export_grad_mrtrix tmp.b $common
    mrcalc noise.mif -finite noise.mif 0 -if lowbnoisemap.mif $common
    mrcalc ${difm}.mif 2 -pow lowbnoisemap.mif 2 -pow -sub -abs -sqrt - $common | mrcalc - -finite - 0 -if tmp.mif $common
    difm=${difm}_ricn
    mrconvert tmp.mif -grad tmp.b ${difm}.mif $common
    rm -f tmp.mif tmp.b

fi

## perform intensity normalization of dwi data
if [ $DO_NORM == "true" ]; then

    echo "Performing intensity normalization (dwinormalise)..."
    
    ## compute dwi mask for processing
    #dwi2mask ${difm}.mif ${mask}.mif $common

    ## create fa wm mask of input subject
    dwi2tensor -mask ${mask}.mif ${difm}.mif - $common | tensor2metric - -fa - $common | mrthreshold -abs 0.5 - wm.mif $common

    ## dilate / erode fa wm mask for smoother volume
    #maskfilter -npass 3 wm_raw.mif dilate - | maskfilter -connectivity - connect - | maskfilter -npass 3 - erode wm.mif
    ## this looks far too blocky to be useful
    
    ## normalize the 50th percentile intensity of generous FA white matter mask to 1000
    dwinormalise individual ${difm}.mif wm.mif ${difm}_norm.mif -intensity $NORM -percentile $PRCT $common
    difm=${difm}_norm
    
fi

echo "Creating dwi space b0 reference images..."

## create b0 and mask image in dwi space on forward direction only
dwiextract ${difm}.mif - -bzero $common | mrmath - mean b0_dwi.mif -axis 3 $common

## compute dwi mask for processing
dwi2mask ${difm}.mif ${mask}.mif $common

## convert to nifti for alignment to anatomy later on
mrconvert b0_dwi.mif b0_dwi.nii.gz $common
mrconvert ${mask}.mif ${mask}.nii.gz $common

## apply mask to image
fslmaths b0_dwi.nii.gz -mas ${mask}.nii.gz b0_dwi_brain.nii.gz

## align diffusion data to T1 acpc anatomy
if [ $DO_ACPC == "true" ]; then

    echo "Running brain extraction on anatomy (bet)..."
    bet ${ANAT}.nii.gz ${ANAT}_brain -R -B -m

    ## compute BBR registration corrected diffusion data to AC-PC anatomy
    echo "Aligning dwi data with AC-PC anatomy (epi_reg)..."
    epi_reg --epi=b0_dwi_brain.nii.gz --t1=${ANAT}.nii.gz --t1brain=${ANAT}_brain.nii.gz --out=dwi2acpc
   
    ## apply the transform w/in mrtrix, correcting gradients
    transformconvert dwi2acpc.mat b0_dwi_brain.nii.gz ${ANAT}_brain.nii.gz flirt_import dwi2acpc_mrtrix.mat $common
    mrtransform -linear dwi2acpc_mrtrix.mat ${difm}.mif ${difm}_acpc.mif $common
    difm=${difm}_acpc

    ## assign output space label
    out=acpc
    
fi

if [ $DO_RESLICE == "true" ]; then

    echo "Reslicing diffusion data to requested isotropic voxel size..."

    ## sed to turn possible decimal into p
    VAL=`echo $NEW_RES | sed s/\\\./p/g`

    echo "Reslicing diffusion data to the requested isotropic voxel size of $VAL mm^3..."
    mrgrid ${difm}.mif regrid -voxel $NEW_RES ${difm}_${VAL}mm.mif $common
    difm=${difm}_${VAL}mm

    ## this makes sense for a majority of uses, but if a different resolution
    ## than the ac-pc is requested, this gets really weird. It prevents partial upsampling / supersampling.
    #
    # ## reslice the image to ac-pc dimensions after selecting final voxel size
    # if [ $DO_ACPC == "true" ]; then
    #	ADIM=`mrinfo ${ANAT}_brain.nii.gz -size | sed "s/ /,/g"`
    #	mrresize -size $ADIM ${difm}.mif ${difm}.mif
    # fi

else
    
    ## append current voxel size in mm to the end of file, rename
    VAL=`mrinfo -spacing dwi.mif | awk {'print $1'} | sed s/\\\./p/g`
    cp ${difm}.mif ${difm}_${VAL}mm.mif
    difm=${difm}_${VAL}mm
    
fi

echo "Creating $out space b0 reference images..."

## create final b0 / mask
dwiextract ${difm}.mif - -bzero $common | mrmath - mean b0_${out}.mif -axis 3 $common
dwi2mask ${difm}.mif b0_${out}_brain_mask.mif $common

## create output space b0s
mrconvert b0_${out}.mif b0_${out}.nii.gz $common
mrconvert b0_${out}_brain_mask.mif b0_${out}_brain_mask.nii.gz $common
fslmaths b0_${out}.nii.gz -mas b0_${out}_brain_mask.nii.gz b0_${out}_brain.nii.gz

echo "Creating preprocessed dwi files in $out space..."

## convert to nifti / fsl output for storage
mkdir -p output
mrconvert ${difm}.mif output/dwi.nii.gz -export_grad_fsl output/dwi.bvecs output/dwi.bvals -export_grad_mrtrix ${difm}.b -json_export ${difm}.json $common

## export a lightly structured text file (json?) of shell count / lmax
echo "Writing text file of basic sequence information..."

## parse the number of shells / determine if a b0 is found
if [ ! -f b0_dwi.mif ]; then
    echo "No b-zero volumes present"
    nshell=`mrinfo -shell_bvalues -bvalue_scaling false ${difm}.mif | wc -w`
    shell=$nshell
    b0s=0
    lmaxs=`dirstat ${difm}.b | grep lmax | awk '{print $8}' | sed "s|:||g"`
else
    nshell=`mrinfo -shell_bvalues -bvalue_scaling false ${difm}.mif | wc -w`
    shell=$(($nshell-1)) ## at least 1 b0 found
    b0s=`mrinfo -shell_sizes ${difm}.mif | awk '{print $1}'`
    lmaxs='0 '`dirstat ${difm}.b | grep lmax | awk '{print $8}' | sed "s|:||g"`
fi

## add file name to summary.txt
echo ${difm} > summary.txt

if [ $shell -gt 1 ]; then
    echo multi-shell: $shell total shells >> summary.txt
else
    echo single-shell: $shell total shell >> summary.txt
fi

## print the number of b0s
echo Number of b0s: $b0s >> summary.txt 
echo shell / count / lmax >> summary.txt

## echo basic shell count summaries
mrinfo -shell_bvalues -bvalue_scaling false ${difm}.mif >> summary.txt
mrinfo -shell_sizes ${difm}.mif >> summary.txt

## echo max lmax per shell
echo $lmaxs >> summary.txt

cat summary.txt

echo "Cleaning up working directory..."
rm -f *.mif
rm -f *.b
rm -f *fast*.nii.gz
rm -f *init.mat
rm -f dwi2acpc.nii.gz
rm -rf ./tmp

