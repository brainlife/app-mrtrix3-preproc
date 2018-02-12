#!/bin/bash

## version
tag=1.0

## build and push online
docker build -t brainlife/mrtrix3:$tag . && docker push brainlife/mrtrix3:$tag
