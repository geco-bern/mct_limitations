#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source_dir=${MCT_MODIS_EVI_DIR:?Set MCT_MODIS_EVI_DIR to the MODIS EVI input directory}
grid_file="$project_root/data-raw/grid/gridfile_halfdeg.txt"

for year in $(seq 2001 2015); do
  year_dir="$source_dir/$year"
  for month in $(seq -f "%02g" 1 12); do
    input="$year_dir/modis_vegetation__LPDAAC__v5__0.05deg__${year}${month}.nc"
    output="$year_dir/modis_vegetation__LPDAAC__v5__0.5deg__${year}${month}.nc"
    cdo "remapbil,$grid_file" "$input" "$output"
  done

  yearly="$source_dir/modis_vegetation__LPDAAC__v5__0.5deg__${year}.nc"
  cdo mergetime "$year_dir"/modis_vegetation__LPDAAC__v5__0.5deg__*.nc "$yearly"
done

cdo mergetime "$source_dir"/modis_vegetation__LPDAAC__v5__0.5deg__20??.nc \
  "$source_dir/modis_vegetation__LPDAAC__v5__0.5deg.nc"

# The historical Ferret gap-filling step remains a separate manual operation.
