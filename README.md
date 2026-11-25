
> **This branch, `1.8`, is the brainlife.io App mrtrix3 preprocess** ([doi:10.25663/bl.app.68](https://doi.org/10.25663/bl.app.68)).
<h1 align="center">MRtrix3 preprocess</h1>

<p align="center">
  Analysis-ready diffusion MRI from raw DWI: denoising, Gibbs ringing removal, topup/eddy, bias correction and alignment to the T1w, with MRtrix3, FSL and ANTs.
</p>

<p align="center">
  <a href="https://doi.org/10.25663/bl.app.68"><img src="https://img.shields.io/badge/brainlife.io-run%20this%20App-2b6cb0" alt="Run on brainlife.io"></a>
  <a href="https://doi.org/10.25663/bl.app.68"><img src="https://img.shields.io/badge/DOI-10.25663%2Fbl.app.68-blue" alt="DOI"></a>
  <a href="https://github.com/brainlife/abcd-spec"><img src="https://img.shields.io/badge/ABCD%20spec-v1.1-green" alt="ABCD spec v1.1"></a>
  <a href="https://www.mrtrix.org/"><img src="https://img.shields.io/badge/MRtrix3-3.0.2-orange" alt="MRtrix3 3.0.2"></a>
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT license">
</p>

## At a glance

<!-- brainlife-app:begin (generated from the App manifest; edit the manifest, not this block) -->

> **Preprocesses raw DWI with MRtrix3 3.0.2 following the DESIGNER-style order (PCA denoising, Gibbs ringing removal, FSL topup/eddy, bias correction, Rician noise removal, optional normalisation) and aligns it to a T1w image with epi_reg.**

Converts the DWI (and optional reverse phase-encoded DWI) to MRtrix format, optionally checks gradient orientation, runs dwidenoise, mrdegibbs, dwifslpreproc (eddy, with topup when reverse phase-encoded data are given), dwibiascorrect (ANTs or FSL), Rician noise removal and dwinormalise as selected, then aligns the data and gradients to the brain-extracted T1w with FSL epi_reg and optionally reslices to an isotropic voxel size. Use it to turn converted raw DWI into analysis-ready data for tensor, NODDI or tractography Apps. Needs a raw (not preprocessed) DWI and a T1w of the same subject, ideally ACPC aligned; topup with both phase-encoding directions can take many hours.

| | |
|---|---|
| **Inputs** | `neuro/anat/t1w` · `neuro/dwi` · `neuro/dwi` (optional) |
| **Outputs** | `neuro/dwi` · `raw` |
| **Container** | `brainlife/mrtrix3:3.0.2` |
| **Resources** | 8 CPUs · 19 h walltime |
| **Run it** | [doi.org/10.25663/bl.app.68](https://doi.org/10.25663/bl.app.68) |

#### Inputs

| Input | Datatype | Required | Description |
|---|---|---|---|
| `anat` | `neuro/anat/t1w` | yes | the t1w image to align the input dwi image |
| `dwi` | `neuro/dwi` (!preprocessed) | yes | The dwi image to preprocess |
| `reverse` | `neuro/dwi` (!preprocessed) | no | optional reverse encoding data set |

#### Outputs

| Output | Datatype | Description |
|---|---|---|
| `output` | `neuro/dwi` | Preprocessed DWI aligned to the T1w (anatomical) space, with rotated bvecs and bvals. |
| `eddyqc` | `raw` | QC output from eddy. Please see quad/qc.pdf file for summary |

<details>
<summary><b>Parameters</b> (24)</summary>

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

</details>

<!-- brainlife-app:end -->

## How it works

The App runs the recommended preprocessing steps for diffusion-weighted MRI (dMRI) with the tools and scripts distributed in MRtrix3, in the recommended order; several pipelines use these steps, notably the published DESIGNER pipeline. Every step can be turned off and its defaults changed, but this should not be necessary for most data.

1. **Conversion and checks.** The DWI (and the optional reverse phase-encoded DWI) are converted to MRtrix format; bvals can be rounded to the nearest 50 (`round_bvals`), and the gradient orientation can be checked with `dwigradcheck`.
2. **PCA denoising** with `dwidenoise` (`denoise`).
3. **Gibbs ringing removal** with `mrdegibbs` (`degibbs`).
4. **Motion, eddy-current and susceptibility correction** with `dwifslpreproc` (FSL eddy, plus topup when reverse phase-encoded data are given) (`eddy`). The eddy options (`eddy_slm`, `eddy_niter`, `eddy_repol`, `eddy_mporder`, `eddy_slspec`, `eddy_data_is_shelled`) and topup's `topup_lambda` are exposed.
5. **Bias field correction** with `dwibiascorrect`, using ANTs N4 (default) or FSL FAST (`bias`, `bias_method`, `antsb`, `antsc`, `antss`).
6. **Rician background noise removal** (`ricn`).
7. **Intensity normalisation** of the white matter mode to `nval` with `dwinormalise` (`norm`, off by default).
8. **Alignment to the anatomy**: the data and gradients are aligned to the brain-extracted T1w with FSL `epi_reg` (boundary-based registration) (`acpc`), and optionally resliced to an isotropic voxel size (`reslice`, in mm).

## Running the App

### On brainlife.io

Open the App at [doi.org/10.25663/bl.app.68](https://doi.org/10.25663/bl.app.68) and choose:

- a raw (not yet preprocessed) `neuro/dwi` dataset, converted from DICOM;
- optionally, a reverse phase-encoded `neuro/dwi` dataset;
- the T1-weighted image of the same subject, in the space the DWI will be aligned to (ideally AC-PC aligned, but this is not required).

Set `acqd` to the phase encoding direction of the DWI and press **Execute**. The preprocessed DWI is archived to your project as a `neuro/dwi` dataset tagged `preprocessed`, ready for tensor/kurtosis, NODDI or tractography Apps, together with the eddy QC output. With topup on both phase-encoding directions a run can take many hours.

### Locally

You need [Singularity/Apptainer](https://apptainer.org/). `main` runs `mrtrix3_preproc.sh` inside the `brainlife/mrtrix3:3.0.2` container (which provides MRtrix3, FSL and ANTs) and downloads a `jq` binary at start-up. Without Singularity you need [MRtrix3](https://www.mrtrix.org/), [FSL](https://fsl.fmrib.ox.ac.uk/fsl/fslwiki) and [ANTs](http://stnava.github.io/ANTs/).

1. Clone this repository and check out the App's branch: `git checkout 1.8`.
2. Create `config.json` with the paths to your inputs and the options you want (see `config.json.sample` for the full list):

   ```json
   {
       "anat": "/input/anat/t1.nii.gz",
       "diff": "/input/dwi/dwi.nii.gz",
       "bvec": "/input/dwi/dwi.bvecs",
       "bval": "/input/dwi/dwi.bvals",
       "rdif": "/input/rev/dwi.nii.gz",
       "rbvc": "/input/rev/dwi.bvecs",
       "rbvl": "/input/rev/dwi.bvals",
       "acqd": "AP",
       "dwigradcheck": true,
       "denoise": true,
       "degibbs": true,
       "eddy": true,
       "bias": true,
       "bias_method": "ants",
       "ricn": true,
       "norm": false,
       "nval": 1000,
       "acpc": true,
       "reslice": "1",
       "eddy_data_is_shelled": true,
       "eddy_slm": "linear",
       "eddy_niter": 5,
       "eddy_repol": true,
       "eddy_mporder": 0
   }
   ```

   Leave out `rdif`, `rbvc` and `rbvl` if you have no reverse phase-encoded data.

3. Run the App:

   ```bash
   ./main
   ```

### Sample data

Download sample datasets from brainlife.io with the [brainlife CLI](https://github.com/brainlife/cli):

```bash
npm install -g brainlife
bl login
mkdir input
bl dataset download 5a0e604116e499548135de87 && mv 5a0e604116e499548135de87 input/anat
bl dataset download 5a0dcb1216e499548135dd27 && mv 5a0dcb1216e499548135dd27 input/dwi
```

## Outputs

All output files are written under the current working directory:

```text
output/
├── dwi.nii.gz     preprocessed DWI, aligned to the T1w
├── dwi.bvals
└── dwi.bvecs      gradient directions rotated into T1w space
eddyqc/            eddy QC output (see quad/qc.pdf for a summary)
summary.txt        number of shells and b0s, shell sizes and maximum lmax per shell
```

## Troubleshooting

- **`dwipreproc: [ERROR] Unable to determine matching reversed phase-encode direction volume for DWI volume 1`**: set `round_bvals` to round the bvals to the nearest 50.
- **Gradient check fails**: with low data quality or low resolution `dwigradcheck` can fail; set `dwigradcheck` to `false`.
- **Slice-to-volume motion correction** (`eddy_mporder` > 0) is only available with the CUDA version of eddy and needs an `eddy_slspec` slice-timing file.

## Citing

> [!TIP]
> If you use this App in your work, please cite the App, the software it builds on and brainlife.io (below). GitHub's **Cite this repository** button gives the App citation in APA and BibTeX.

- Tournier J-D, Smith R, Raffelt D, Tabbara R, Dhollander T, Pietsch M, et al., Connelly A. MRtrix3: a fast, flexible and open software framework for medical image processing and visualisation. *NeuroImage* 202:116137 (2019). [doi:10.1016/j.neuroimage.2019.116137](https://doi.org/10.1016/j.neuroimage.2019.116137)
- Ades-Aron B, Veraart J, Kochunov P, McGuire S, Sherman P, Kellner E, et al., Fieremans E. Evaluation of the accuracy and precision of the diffusion parameter EStImation with Gibbs and NoisE removal pipeline. *NeuroImage* 183:532–543 (2018). [doi:10.1016/j.neuroimage.2018.07.066](https://doi.org/10.1016/j.neuroimage.2018.07.066)
- mrtrix3 preprocess. brainlife.io App. [doi:10.25663/bl.app.68](https://doi.org/10.25663/bl.app.68)
- Avesani P. et al. The open diffusion data derivatives. Sci Data 6, 69 (2019). [doi:10.1038/s41597-019-0073-y](https://doi.org/10.1038/s41597-019-0073-y)
- Jenkinson et al. FSL. *NeuroImage* 62:782-790 (2012). [doi:10.1016/j.neuroimage.2011.09.015](https://doi.org/10.1016/j.neuroimage.2011.09.015)
- Avants et al. A reproducible evaluation of ANTs similarity metric performance in brain image registration. *NeuroImage* 54:2033-2044 (2011). [doi:10.1016/j.neuroimage.2010.09.025](https://doi.org/10.1016/j.neuroimage.2010.09.025)
- Zhang et al. NODDI: Practical in vivo neurite orientation dispersion and density imaging of the human brain. *NeuroImage* 61:1000-1016 (2012). [doi:10.1016/j.neuroimage.2012.03.072](https://doi.org/10.1016/j.neuroimage.2012.03.072)
- Hayashi S, Caron BA, Heinsfeld AS, et al. brainlife.io: a decentralized and open-source cloud platform to support neuroscience research. *Nature Methods* 21:809–813 (2024). [doi:10.1038/s41592-024-02237-2](https://doi.org/10.1038/s41592-024-02237-2)

## Authors

- [Brent McPherson](https://github.com/bcmcpher)

**Contributors:** Soichi Hayashi

## Funding

[![Wellcome-226486/Z/22/Z](https://img.shields.io/badge/Wellcome-226486%2FZ%2F22%2FZ-purple.svg)](https://wellcome.org/)
[![NIH-NINDS-U24NS140384](https://img.shields.io/badge/NIH_NINDS-U24NS140384-green.svg)](https://reporter.nih.gov/project-details/11261037)
[![NIH-NINDS-UM1NS132207](https://img.shields.io/badge/NIH_NINDS-UM1NS132207-green.svg)](https://reporter.nih.gov/project-details/11411328)
[![NIH-NIBIB-R01EB029272](https://img.shields.io/badge/NIH_NIBIB-R01EB029272-green.svg)](https://reporter.nih.gov/project-details/10262925)
[![NIH-NIBIB-R01EB030896](https://img.shields.io/badge/NIH_NIBIB-R01EB030896-green.svg)](https://reporter.nih.gov/project-details/10428625)
[![NIH-NIMH-R01MH126699](https://img.shields.io/badge/NIH_NIMH-R01MH126699-green.svg)](https://reporter.nih.gov/project-details/10460628)
[![NIH-NIDCD-R01DC020088](https://img.shields.io/badge/NIH_NIDCD-R01DC020088-green.svg)](https://reporter.nih.gov/project-details/11140284)
[![NSF-BCS-1734853](https://img.shields.io/badge/NSF_BCS-1734853-blue.svg)](https://www.nsf.gov/awardsearch/showAward?AWD_ID=1734853)
[![NSF-BCS-2203524](https://img.shields.io/badge/NSF_BCS-2203524-blue.svg)](https://www.nsf.gov/awardsearch/showAward?AWD_ID=2203524)
[![NSF-IIS-1636893](https://img.shields.io/badge/NSF_IIS-1636893-blue.svg)](https://www.nsf.gov/awardsearch/showAward?AWD_ID=1636893)
[![NSF-OAC-2148729](https://img.shields.io/badge/NSF_OAC-2148729-blue.svg)](https://www.nsf.gov/awardsearch/showAward?AWD_ID=2148729)
[![NSF-IIS-1912270](https://img.shields.io/badge/NSF_IIS-1912270-blue.svg)](https://www.nsf.gov/awardsearch/showAward?AWD_ID=1912270)
[![NSF-IIS-2148700](https://img.shields.io/badge/NSF_IIS-2148700-blue.svg)](https://www.nsf.gov/awardsearch/showAward?AWD_ID=2148700)
[![NSF-OAC-1916518](https://img.shields.io/badge/NSF_OAC-1916518-blue.svg)](https://www.nsf.gov/awardsearch/showAward?AWD_ID=1916518)

<sub>brainlife.io is publicly funded, and acknowledging that support helps keep it running. This App was developed with support from Wellcome, the U.S. National Institutes of Health (including the BRAIN Initiative BRAIN CONNECTS program: The Axonal Projectome EXchange, U24NS140384, and the Center for Mesoscale Connectomics, UM1NS132207) and the U.S. National Science Foundation.</sub>

## License

MIT, Copyright (c) 2020 Brent McPherson, brainlife.io, Indiana University and The University of Texas at Austin. MRtrix3, FSL and ANTs are distributed under their own licenses.
