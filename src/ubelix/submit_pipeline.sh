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
temperature_id=$(submit_job prepare_temperature)
configured_et_id=$(submit_job prepare_et)

et_id=$(submit_job convert_et_mm "${configured_et_id}:${temperature_id}")
snow_id=$(submit_job simulate_snow "${precipitation_id}:${temperature_id}")
balance_id=$(submit_job calculate_balance "${et_id}:${snow_id}")
annual_cwd_id=$(submit_job calculate_annual_cwd "$balance_id")
result_id=$(submit_job cwd_surplus_relationship "$annual_cwd_id")

echo "Submitted full workflow through CWD-surplus result job ${result_id}."
