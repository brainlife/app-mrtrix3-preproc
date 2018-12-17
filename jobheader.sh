#!/bin/bash

##figure out amount of wall time we really need by parsing config.json with jq
if [ "$(jq .rpe -r config.json)" == "none" ]; then
    walltime=01:30:00
else
    walltime=24:00:00
fi

echo "#PBS -l nodes=1:ppn=8,vmem=24gb"
echo "#PBS -l walltime=$walltime"
