#!/usr/bin/env bash
#SBATCH --account=gratis
#SBATCH --job-name=mct
#SBATCH --time=01:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G

set -euo pipefail

script_path=${1:?Missing R script path}
argument_mode=${2:?Missing argument mode}
total_chunks=${3:-1}
extra_args=${4:--}
task_id=${SLURM_ARRAY_TASK_ID:-1}
project_root=${SLURM_SUBMIT_DIR:?Submit jobs from the project root}

cd "$project_root"
if [[ ! -f mct.Rproj ]]; then
  echo "Submit this job from the mct_limitations project root." >&2
  exit 2
fi

if [[ ${MCT_USE_WORKSPACE:-0} == 1 ]]; then
  module load Workspace
fi
module load R

case "$argument_mode" in
  chunk_count)
    if [[ "$extra_args" == "-" ]]; then
      srun --ntasks=1 Rscript --vanilla "$script_path" "$task_id" "$total_chunks"
    else
      srun --ntasks=1 Rscript --vanilla "$script_path" "$task_id" "$total_chunks" "$extra_args"
    fi
    ;;
  chunk_value)
    srun --ntasks=1 Rscript --vanilla "$script_path" "$task_id" "$extra_args"
    ;;
  none)
    srun --ntasks=1 Rscript --vanilla "$script_path"
    ;;
  *)
    echo "Unknown argument mode: $argument_mode" >&2
    exit 2
    ;;
esac
