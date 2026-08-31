#!/usr/bin/env bash

set -euo pipefail

source_dir=${MCT_MODIS_EVI_DIR:?Set MCT_MODIS_EVI_DIR to the directory containing yearly subdirectories}

for year in $(seq 2001 2015); do
  year_dir="$source_dir/$year"
  yearly="$source_dir/modis_vegetation__LPDAAC__v5__halfdegMAX_${year}.nc"
  cdo mergetime "$year_dir"/modis_vegetation__LPDAAC__v5__0.05deg__*_halfdeg.nc "$yearly"
done

combined="$source_dir/modis_vegetation__LPDAAC__v5__halfdegMAX.nc"
cdo mergetime "$source_dir"/modis_vegetation__LPDAAC__v5__halfdegMAX_????.nc "$combined"
mkdir -p "$source_dir/../halfdeg"
mv "$combined" "$source_dir/../halfdeg/"

# The historical Ferret gap-filling step remains a separate manual operation.
