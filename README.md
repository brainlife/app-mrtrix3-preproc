[![Abcdspec-compliant](https://img.shields.io/badge/ABCD_Spec-v1.1-green.svg)](https://github.com/brain-life/abcd-spec)
[![Run on Brainlife.io](https://img.shields.io/badge/Brainlife-bl.app.68-blue.svg)](https://doi.org/10.25663/brainlife.app.68)

# app-mrtrix3-preproc
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
