[![Abcdspec-compliant](https://img.shields.io/badge/ABCD_Spec-v1.1-green.svg)](https://github.com/brain-life/abcd-spec)
[![Run on Brainlife.io](https://img.shields.io/badge/Brainlife-bl.app.68-blue.svg)](https://doi.org/10.25663/brainlife.app.68)

# app-mrtrix3-preproc

<!-- brainlife-app:begin (generated from the App manifest; edit the manifest, not this block) -->

**Preprocesses raw DWI with MRtrix3 3.0.2 following the DESIGNER-style order (PCA denoising, Gibbs ringing removal, FSL topup/eddy, bias correction, Rician noise removal, optional normalisation) and aligns it to a T1w image with epi_reg.**

Converts the DWI (and optional reverse phase-encoded DWI) to MRtrix format, optionally checks gradient orientation, runs dwidenoise, mrdegibbs, dwifslpreproc (eddy, with topup when reverse phase-encoded data are given), dwibiascorrect (ANTs or FSL), Rician noise removal and dwinormalise as selected, then aligns the data and gradients to the brain-extracted T1w with FSL epi_reg and optionally reslices to an isotropic voxel size. Use it to turn converted raw DWI into analysis-ready data for tensor, NODDI or tractography Apps. Needs a raw (not preprocessed) DWI and a T1w of the same subject, ideally ACPC aligned; topup with both phase-encoding directions can take many hours.

Run it on brainlife.io: [https://doi.org/10.25663/bl.app.68](https://doi.org/10.25663/bl.app.68)

| Input | Datatype | Required | Description |
|---|---|---|---|
| `anat` | `neuro/anat/t1w` | yes | the t1w image to align the input dwi image |
| `dwi` | `neuro/dwi` (!preprocessed) | yes | The dwi image to preprocess |
| `reverse` | `neuro/dwi` (!preprocessed) | no | optional reverse encoding data set |

| Output | Datatype | Description |
|---|---|---|
| `output` | `neuro/dwi` | Preprocessed DWI aligned to the T1w (anatomical) space, with rotated bvecs and bvals. |
| `eddyqc` | `raw` | QC output from eddy. Please see quad/qc.pdf file for summary |

| Parameter | Type | Default | Description |
|---|---|---|---|
| `acqd` | enum | `AP` | provide the encoding direction used for the dwi data for the preprocessing steps below Options: `PA`, `RL`, `IS`, `AP`, `LR`, `SI`. |
| `dwigradcheck` | boolean | `true` | Check dwi gradient orientation. The default value is 'true', but sometimes with low data quality or low voxel resolution, this process may fail. If that's the case, you may want to set this value as 'false'. |
| `denoise` | boolean | `true` | Perform PCA denoising on the input data |
| `degibbs` | boolean | `true` | Perform correction on Gibbs ringing artifact |
| `eddy` | boolean | `true` | Perform motion and eddy current correction with FSL |
| `bias` | boolean | `true` | Perform bias correction with ANTs N4 |
| `ricn` | boolean | `true` | Remove Rician background noise |
| `norm` | boolean | `false` | Perform mode value intensity normalization in white matter |
| `nval` | number | `1000` | The value to which the mode value intensity normalization will normalize the white matter intensity. |
| `acpc` | boolean | `true` | Align dwi data and gradients to anatomical (t1w) input using BBR in FSL |
| `reslice` | string |  | The final isotropic voxel dimension in mm of the processed dwi data |
| `eddy_data_is_shelled` | boolean | `true` | Do not check that data is shelled |
| `eddy_slm` | enum | `linear` | "Second level model" that specifies the mathematical form for how the diffusion gradients cause eddy currents. For high quality data with 60 directions, or more, sampled on the whole sphere we have not found any advantage of performing second level modelling. Hence our recommendation for such data is to use none, and that is also the default. If the data has quite few directions and/or is has not been sampled on the whole sphere it can be advantageous to specify --slm=linear. Options: `none`, `linear`, `quadratic`. |
| `eddy_niter` | number | `5` | eddy does not check for convergence. Instead it runs a fixed number of iterations given by --niter. This is not unusual for registration algorithms where each iteration is expensive (i.e. takes long time). Instead we run it for a fixed number of iterations, 5 as default. If, on visual inspection, one finds residual movement or EC-induced distortions it is possible that eddy has not fully converged. In that case we primarily recommend that one uses --fwhm=10,0,0,0,0, as described above, to speed up convergence. Only if that fails do we recommend increasing the number of iterations. |
| `eddy_repol` | boolean | `true` | Remove any slices deemed as outliers and replace them with predictions made by the Gaussian Process. Exactly what constitutes an outlier is affected by the parameters --ol_nstd, --ol_nvox, --ol_type, --ol_pos and --ol_sqr. If the defaults are used for all those parameters an outlier is defined as a slice whose average intensity is at least four standard deviations lower than the expected intensity, where the expectation is given by the Gaussian Process prediction. The default is to not do outlier replacement since we don't want to risk people using it "unawares". However, our experience and tests indicate that it is always a good idea to use --repol. |
| `eddy_mporder` | number | `0` | If one wants to do slice-to-vol motion correction --mporder should be set to an integer value greater than 0 and less than the number of excitations in a volume. (The timing of acquisition of each slice must be known in order to perform slice-to-volume correction. This is provided to eddy via eddy_slspec option). Only when --mporder > 0 will any of the parameters prefixed by --s2v_ be considered. The larger the value of --mporder, the more degrees of freedom for modelling movement. If --mporder is set to N-1, where N is the number of excitations in a volume, the location of each slice/MB-group is individually estimated. We don't recommend going that high and in our tests we have used values of N/4 -- N/2. The underlying temporal model of movement is a DCT basis-set of order N. Slice-to-vol motion correction is computationally very expensive so it is only implemented for the CUDA version. |
| `eddy_slspec` | string |  | Specifies a text-file that describes how the slices/MB-groups were acquired. This information is necessary for eddy to know how a temporally continuous movement translates into location of individual slices/MB-groups. Let us say a given acquisition has N slices and that m is the MB-factor (also known as Simultaneous Multi-Slice (SMS)). Then the file pointed to be --slspec will have N/m rows and m columns. Let us for example assume that we have a data-set which has been acquired with an MB-factor of 3, 15 slices and interleaved slice order. The file would then be 0 5 10 2 7 12 4 9 14 1 6 11 3 8 13 where the first row "0 5 10" specifies that the first, sixth and 11th slice are acquired first and together, followed by the third, eighth and 13th slice etc. For single-band data and for multi-band data with an odd number of excitations/MB-groups it is trivial to work out the --slspec file using the logic of the example. For an even number of excitations/MB-groups it is considerably more difficult and we recommend using a DICOM->niftii converter that writes the exact slice timings into a .JSON file. This can then be used to create the --slspec file. |
| `dilate_mask` | boolean | `false` | Apply dilate maskfilter on b0 whole brain mask |
| `round_bvals` | boolean | `false` | If you are seeing this error message "dwipreproc: [ERROR] Unable to determine matching reversed phase-encode direction volume for DWI volume 1". You might be able to work around it by rounding your bvals to the nearest 50s. |
| `topup_lambda` | string | `0.005,0.001,0.0001,0.000015,0.000005,0.0000005,0.00000005,0.0000000005,0.00000000001` | Replace lambda value in topup |
| `bias_method` | enum | `ants` | Select bias correction algorithm. Options: `ants`, `fsl`. |
| `antsb` | string | `[150,3]` | Advanced option for ANTs N4 bias field removal. |
| `antsc` | string | `[200x200,1e-6]` | Advanced option for ANTs N4 bias field removal. |
| `antss` | string | `2` | Advanced option for ANTs N4 bias field removal. |

Runtime: container `brainlife/mrtrix3:3.0.2`; 8 CPUs; 19 h walltime.

Please cite:
- Tournier J.D. et al. MRtrix3: A fast, flexible and open software framework for medical image processing and visualisation. NeuroImage 202:116137 (2019). [doi:10.1016/j.neuroimage.2019.116137](https://doi.org/10.1016/j.neuroimage.2019.116137)
- Avesani P. et al. The open diffusion data derivatives. Sci Data 6, 69 (2019). [doi:10.1038/s41597-019-0073-y](https://doi.org/10.1038/s41597-019-0073-y)
- Ades-Aron B. et al. Evaluation of the accuracy and precision of the diffusion parameter EStImation with Gibbs and NoisE removal pipeline. NeuroImage 183:532-543 (2018). [doi:10.1016/j.neuroimage.2018.07.066](https://doi.org/10.1016/j.neuroimage.2018.07.066)

<!-- brainlife-app:end -->

This runs the recommended preprocessing steps for diffusion weighted magnetic resonance imaging (dMRI) data. It uses all tools and scripts distributed in MRTrix3 in the recommended order. Several applications use these preprocessing steps, specifically the previously published DESIGNER pipeline. All steps are can be turnded off / default values modified, but this should not be necessary for the majority of use cases.

The inputs are dMRI files after conversion from dicom and the anatomical scan in the final space the dMRI data will be aligned to (ideally AC-PC aligned, but this is not a strict requirement).

The resulting scan should be an adequately processed dMRI registered to the antomical space ready for further analysis (tensor / kurtosis, NODDI, tractography, etc.).

### Authors
- [Brent McPherson](bcmcpher@iu.edu)

### Contributors
- [Soichi Hayashi](hayashis@iu.edu)

### Funding Acknowledgement
brainlife.io is publicly funded and for the sustainability of the project it is helpful to Acknowledge the use of the platform. We kindly ask that you acknowledge the funding below in your publications and code reusing this code.

[![NSF-BCS-1734853](https://img.shields.io/badge/NSF_BCS-1734853-blue.svg)](https://nsf.gov/awardsearch/showAward?AWD_ID=1734853)
[![NSF-BCS-1636893](https://img.shields.io/badge/NSF_BCS-1636893-blue.svg)](https://nsf.gov/awardsearch/showAward?AWD_ID=1636893)
[![NSF-ACI-1916518](https://img.shields.io/badge/NSF_ACI-1916518-blue.svg)](https://nsf.gov/awardsearch/showAward?AWD_ID=1916518)
[![NSF-IIS-1912270](https://img.shields.io/badge/NSF_IIS-1912270-blue.svg)](https://nsf.gov/awardsearch/showAward?AWD_ID=1912270)
[![NIH-NIBIB-R01EB029272](https://img.shields.io/badge/NIH_NIBIB-R01EB029272-green.svg)](https://grantome.com/grant/NIH/R01-EB029272-01)
[![NIH-NIBIB-2T32MH103213-06](https://img.shields.io/badge/NIH_NIBIB-2T32MH103213-06-green.svg)](https://grantome.com/grant/NIH/T32-MH103213-06)

### Citations
We kindly ask that you cite the following articles when publishing papers and code using this code. 

1. Tournier, J. D., Smith, R., Raffelt, D., Tabbara, R., Dhollander, T., Pietsch, M., ... & Connelly, A. (2019). MRtrix3: A fast, flexible and open software framework for medical image processing and visualisation. NeuroImage, 202, 116137. [https://doi.org/10.1016/j.neuroimage.2019.116137](https://doi.org/10.1016/j.neuroimage.2019.116137)

2. Avesani, P., McPherson, B., Hayashi, S. et al. The open diffusion data derivatives, brain data upcycling via integrated publishing of derivatives and reproducible open cloud services. Sci Data 6, 69 (2019). [https://doi.org/10.1038/s41597-019-0073-y](https://doi.org/10.1038/s41597-019-0073-y)

3. Ades-Aron, B., Veraart, J., Kochunov, P., McGuire, S., Sherman, P., Kellner, E., ... & Fieremans, E. (2018). Evaluation of the accuracy and precision of the diffusion parameter EStImation with Gibbs and NoisE removal pipeline. NeuroImage, 183, 532-543.[https://doi.org/10.1016/j.neuroimage.2018.07.066](https://doi.org/10.1016/j.neuroimage.2018.07.066)

#### MIT Copyright (c) 2020 Brent McPherson, brainlife.io, Indiana University, and The University of Texas at Austin

## Running the App 

### On Brainlife.io

You can submit this App online at [https://doi.org/10.25663/bl.app.1](https://doi.org/10.25663/bl.app.1) via the "Execute" tab.

### Running Locally (on your machine)

1. git clone this repo.
2. Inside the cloned directory, create `config.json` with something like the following content with paths to your input files.

```json
{
	"anat": "./input/t1.nii.gz",
	"dwi": "./input/dwi.nii.gz",
	"bvecs": "./input/dwi.bvecs",
	"bvals": "./input/dwi.bvals",
}
```

3. Launch the App by executing `main`

```bash
./main
```

### Sample Datasets

If you don't have your own input file, you can download sample datasets from Brainlife.io, or you can use [Brainlife CLI](https://github.com/brain-life/cli).

```
npm install -g brainlife
bl login
mkdir input
bl dataset download 5a0e604116e499548135de87 && mv 5a0e604116e499548135de87 input/anat
bl dataset download 5a0dcb1216e499548135dd27 && mv 5a0dcb1216e499548135dd27 input/dwi
```

## Output

All output files will be generated under the current working directory (pwd). The main output of this App is a file called `track.tck`. This file contains following object.

```
  Tracks file: "tracks.tck"
    DW_scheme:            dwi.b
    SIFT_mu:              0.19794122804040393
    act:                  5tt.mif
    backtrack:            1
    count:                500000
    crop_at_gmwmi:        1
    downsample_factor:    3
    fod_power:            0.25
    init_threshold:       0.100000001
    lmax:                 8
    max_angle:            45
    max_num_seeds:        variable
    max_num_tracks:       variable
    max_seed_attempts:    1000
    max_trials:           1000
    method:               iFOD2
    mrtrix_version:       3.0.0
    output_step_size:     1
    rk4:                  0
    samples_per_step:     4
    sh_precomputed:       1
    source:               wmt_fod.mif
    step_size:            1
    stop_on_all_include:  0
    threshold:            0.100000001
    timestamp:            1518584698.6087715626
    total_count:          500000
    unidirectional:       0

```

#### Product.json

The secondary output of this app is `product.json`. This file allows web interfaces, DB and API calls on the results of the processing. 

### Dependencies

This App only requires [singularity](https://www.sylabs.io/singularity/) to run. If you don't have singularity, you will need to install following dependencies.  

  - MRTrix3: https://www.mrtrix.org/
  - FSL: https://fsl.fmrib.ox.ac.uk/fsl/fslwiki
  - ANTs: http://stnava.github.io/ANTs/

#### MIT Copyright (c) 2020 Brent McPherson, brainlife.io, Indiana University, and The University of Texas at Austin 
