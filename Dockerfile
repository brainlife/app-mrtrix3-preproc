FROM neurodebian:nd90-non-free 

MAINTAINER Brent McPherson <bcmcpher@iu.edu> 

apt-get update

## install ants / fsl / other requirements
apt-get install -y jq ants fsl-5.0-core fsl-5.0-eddy-non-free fsl-first-data fsl-mni152-templates

## run distributed script to set up fsl
. /etc/fsl/fsl.sh

## install mrtrix3 requirements
apt-get install git g++ python python-numpy libeigen3-dev zlib1g-dev libqt4-opengl-dev libgl1-mesa-dev libfftw3-dev libtiff5-dev

## install and compile mrtrix
git clone git clone https://github.com/MRtrix3/mrtrix3.git
cd mrtrix3
./configure && ./build
./set_path

## manually add to path
#export PATH="$(pwd)/bin:$PATH"

