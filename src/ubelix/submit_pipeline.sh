#!/usr/bin/env bash

set -euo pipefail

submit_job() {
  local job=$1
  local dependency=${2:-}
  if [[ -n "$dependency" ]]; then
    MCT_DEPENDENCY="afterok:${dependency}" src/ubelix/submit.sh "$job"
  else
    src/ubelix/submit.sh "$job"
  fi
}

precipitation_id=$(submit_job prepare_precipitation)
precipitation_form=$(Rscript -e 'source("R/input_config.R"); cat(read_input_config()$precipitation$form)')
if [[ "$precipitation_form" == "separate" ]]; then
  snowfall_id=$(submit_job prepare_snowfall)
else
  snowfall_id=""
fi
temperature_id=$(submit_job prepare_temperature)
configured_et_id=$(submit_job prepare_et)

et_id=$(submit_job convert_et_mm "${configured_et_id}:${temperature_id}")
snow_dependencies="${precipitation_id}:${temperature_id}"
if [[ -n "$snowfall_id" ]]; then
  snow_dependencies="${snow_dependencies}:${snowfall_id}"
fi
snow_id=$(submit_job simulate_snow "$snow_dependencies")
balance_id=$(submit_job calculate_balance "${et_id}:${snow_id}")
annual_cwd_id=$(submit_job calculate_annual_cwd "$balance_id")

echo "Submitted core workflow through annual CWD job ${annual_cwd_id}."
