#!/bin/bash

tag=3.0_RC3
docker run --rm -it -v `pwd`:/output brainlife/mrtrix3:$tag
