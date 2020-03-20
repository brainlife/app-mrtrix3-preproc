#!/bin/bash

## add option to just perform motion correction
## make extent an argument?

#--nv from singularity should take care of this
#cuda/nvidia drivers comes from the host. it needs to be mounted by singularity
#export LD_LIBRARY_PATH=/usr/local/cuda-10.0/lib64:$LD_LIBRARY_PATH
#export LD_LIBRARY_PATH=/usr/lib/nvidia-410:$LD_LIBRARY_PATH

#needed for bridges
#export LD_LIBRARY_PATH=/opt/packages/cuda/8.0/lib64:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/pylon5/tr4s8pp/shayashi/cuda-8.0/lib64:$LD_LIBRARY_PATH

#TODO - we are using eddy_cuda which is compiled with cuda8.. As of right now, cuda8 is the latest version supported by fsl
#https://fsl.fmrib.ox.ac.uk/fsldownloads/patches/eddy-patch-fsl-5.0.11/centos6/

#we also need /usr/lib/x86_64-linux-gnu/libcuda.so.1 from the machine that this app runs on
#we used to copy it into this app, but let's let singularity bind it
#bind path = /usr/lib/x86_64-linux-gnu/libcuda.so.1
#export LD_LIBRARY_PATH=`pwd`/nvidia-410:$LD_LIBRARY_PATH

## show commands running
set -x
set -e

#some mrtrix3 commands don't honer -nthreads option (https://github.com/MRtrix3/mrtrix3/issues/1479
echo "OMP_NUM_THREADS=$OMP_NUM_THREADS"
[ -z "$OMP_NUM_THREADS" ] && export OMP_NUM_THREADS=8

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

#construct eddy_options from config.json
eddy_data_is_shelled=`jq -r '.eddy_data_is_shelled' config.json`
eddy_slm=`jq -r '.eddy_slm' config.json`
eddy_niter=`jq -r '.eddy_niter' config.json`
eddy_repol=`jq -r '.eddy_repol' config.json`
eddy_mporder=`jq -r '.eddy_mporder' config.json`

eddy_options=" " #must contain at least 1 space according to mrtrix doc
[ "$eddy_repol" == "true" ] && eddy_options="$eddy_options --repol"
[ "$eddy_data_is_shelled" == "true" ] && eddy_options="$eddy_options --data_is_shelled"
eddy_options="$eddy_options --slm=$eddy_slm"
eddy_options="$eddy_options --niter=$eddy_niter"
[ "$eddy_mporder" != "0" ] && eddy_options="$eddy_options --mporder=$eddy_mporder"

jq -rj '.eddy_slspec' config.json > slspec.txt
if [ -s slspec.txt ]; then
    eddy_options="$eddy_options --slspec=slspec.txt"
fi

## set switch to relsice to a new isotropic voxel size
if [ -z $NEW_RES ]; then
    DO_RESLICE="false"
else
    DO_RESLICE="true"
fi

# ## read in eddy options
# RPE=`jq -r '.rpe' config.json` ## optional

# ## if no second sequence, override to only option
# if [ -z $RDIF ]; then
#     RPE="none"
# else
#     nb0=`mrinfo -size rpe_${difm}.mif | grep -oE '[^[:space:]]+$'`
#     nb0=`mrinfo -size rpe_${difm}.mif | grep -oE '[^[:space:]]+$'`
#     if [ $(($nb0%2)) == 0 ];
#     ## check the size of the inputs
#     ## - if they match, it's "all"
#     ## - if they don't, it's "pairs"
# fi

## assign output space of final data if acpc not called
out=proc

## diffusion file that changes name based on steps performed
difm=dwi
mask=b0_dwi_brain_mask

## create local copy of anat
cp $ANAT ./t1_acpc.nii.gz
ANAT=t1_acpc

## create temp folders explicitly
rm -rf ./tmp ./eddyqc cor1.b cor2.b corr.b
mkdir -p ./tmp

common="-nthreads $OMP_NUM_THREADS -quiet -force"

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

## echo "RDIF: $RDIF"

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
	    dwiextract -bzero raw2.mif raw2.mif $common
	    ob0=`mrinfo -size raw2.mif | grep -oE '[^[:space:]]+$'`
	    echo "This should be an even number: $ob0"
	    ## this doesn't stop or exit if it's still odd...
	fi

    fi
    
fi

echo "RPE assigned as: $RPE"

echo "Identifying correct gradient orientation..."

if [ $RPE == "all" ]; then

    ## merge them
    mrcat raw1.mif raw2.mif raw.mif $common
    cat raw1.b raw2.b > raw.b
    
    echo "Creating processing mask..."

    ## create mask from merged data
    dwi2mask raw.mif ${mask}.mif $common

    ## check and correct gradient orientation and create corrected image
    dwigradcheck raw.mif -grad raw.b -mask ${mask}.mif -export_grad_mrtrix corr.b -tempdir ./tmp $common
    mrconvert raw.mif -grad corr.b ${difm}.mif $common

else

    echo "Creating processing mask..."

    ## create mask
    dwi2mask raw1.mif ${mask}.mif $common

    ## check and correct gradient orientation and create corrected image
    dwigradcheck raw1.mif -grad raw1.b -mask ${mask}.mif -export_grad_mrtrix cor1.b -tempdir ./tmp $common
    mrconvert raw1.mif -grad cor1.b ${difm}.mif $common

    if [ -e raw2.mif ]; then
	dwi2mask raw2.mif rpe_${mask}.mif $common
	cp raw2.b cor2.b	
	mrconvert raw2.mif -grad cor2.b rpe_${difm}.mif $common
	## no dwigradcheck, b/c this is necessarily b0s with this logic
    fi
    
fi

## perform PCA denoising
if [ $DO_DENOISE == "true" ] || [ $DO_RICN == "true" ]; then

    if [ $DO_RICN == "true" ] && [ $DO_DENOISE != "true" ]; then
	echo "Rician denoising requires PCA denoising be performed. The deniose == 'False' option will be overridden."
    fi    

    echo "Performing PCA denoising..."
    dwidenoise -extent 5,5,5 -noise fpe_noise.mif ${difm}.mif ${difm}_denoise.mif $common
    
    if [ -e rpe_${difm}.mif ]; then
        dwidenoise -extent 5,5,5 -noise rpe_noise.mif rpe_${difm}.mif rpe_${difm}_denoise.mif $common
    fi

    difm=${difm}_denoise

    ## if the second input exists average the noise volumes (best practice?), else just use the first one
    if [ -e rpe_noise.mif ]; then
	mrcalc fpe_noise.mif rpe_noise.mif -add 2 -divide noise.mif $common
    else
	cp fpe_noise.mif noise.mif
    fi
    
fi

## if scanner artifact is found
if [ $DO_DEGIBBS == "true" ]; then

    echo "Performing Gibbs ringing correction..."
    mrdegibbs -nshifts 20 -minW 1 -maxW 3 ${difm}.mif ${difm}_degibbs.mif $common

    if [ -e rpe_${difm}.mif ]; then
        mrdegibbs -nshifts 20 -minW 1 -maxW 3 rpe_${difm}.mif rpe_${difm}_degibbs.mif $common
    fi

    difm=${difm}_degibbs
    
fi

## perform eddy correction with FSL
if [ $DO_EDDY == "true" ]; then

    common_preproc="-eddyqc_all ./eddyqc -tempdir ./tmp"

    if [ $RPE == "none" ]; then
        echo "Performing FSL eddy correction... (dwipreproc uses eddy_cuda which uses cuda8)"
        dwipreproc -eddy_options "$eddy_options" -rpe_none -pe_dir $ACQD ${difm}.mif ${difm}_eddy.mif $common_preproc $common
        difm=${difm}_eddy
    fi

    if [ $RPE == "pairs" ]; then
        echo "Performing FSL topup and eddy correction ... (dwipreproc uses eddy_cuda which uses cuda8)"
        dwipreproc -eddy_options "$eddy_options" -rpe_pair -pe_dir $ACQD ${difm}.mif -se_epi rpe_${difm}.mif ${difm}_eddy.mif $common_preproc $common
        difm=${difm}_eddy
    fi

    if [ $RPE == "all" ]; then
        echo "Performing FSL eddy correction for merged input DWI sequences... (dwipreproc uses eddy_cuda which uses cuda8)"
        dwipreproc -eddy_options "$eddy_options" -rpe_all -pe_dir $ACQD ${difm}.mif ${difm}_eddy.mif $common_preproc $common
        difm=${difm}_eddy
    fi
    
    # #TODO - get rid of this by implementing autodetect
    # if [ $RPE == "header" ]; then
    #     echo "Performing FSL eddy correction for merged input DWI sequences... (dwipreproc uses eddy_cuda which uses cuda8)"
    #     dwipreproc -eddy_options "$eddy_options" -rpe_header ${difm}.mif ${difm}_eddy.mif $common_preproc $common
    # 	difm=${difm}_eddy
    # fi

fi

## compute bias correction with ANTs on dwi data
if [ $DO_BIAS == "true" ]; then
    
    echo "Performing bias correction with ANTs..."
    dwibiascorrect -ants ${difm}.mif ${difm}_bias.mif -tempdir ./tmp $common
    difm=${difm}_bias
    
fi

## perform Rician background noise removal
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

    echo "Performing intensity normalization..."
    
    ## compute dwi mask for processing
    dwi2mask ${difm}.mif ${mask}.mif $common

    ## create fa wm mask of input subject
    dwi2tensor -mask ${mask}.mif ${difm}.mif - $common | tensor2metric - -fa - $common | mrthreshold -abs 0.5 - wm.mif $common

    ## dilate / erode fa wm mask for smoother volume
    #maskfilter -npass 3 wm_raw.mif dilate - | maskfilter -connectivity - connect - | maskfilter -npass 3 - erode wm.mif
    ## this looks far too blocky to be useful
    
    ## normalize intensity of generous FA white matter mask to 1000
    dwinormalise -intensity $NORM ${difm}.mif wm.mif ${difm}_norm.mif $common
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

    echo "Running brain extraction on anatomy..."

    ## create t1 mask
    bet ${ANAT}.nii.gz ${ANAT}_brain -R -B -m

    echo "Aligning dwi data with AC-PC anatomy..."

    ## compute BBR registration corrected diffusion data to AC-PC anatomy
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
    mrresize ${difm}.mif -voxel $NEW_RES ${difm}_${VAL}mm.mif $common
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

