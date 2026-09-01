# UBELIX Slurm jobs

Submit from the project root on UBELIX. `jobs.tsv` is the single registry of job
names, R entry points, array sizes, resources, output patterns, and expected
counts. `submit.sh` converts a registry row into an `sbatch` call;
`run_r_job.sh` is the shared batch entry point.

```sh
src/ubelix/submit.sh prepare_precipitation
src/ubelix/submit.sh prepare_et
src/ubelix/submit.sh calculate_balance
```

Available job names are printed when `submit.sh` is called without an argument.
The default allocation account is `gratis`; override it when required:

```sh
MCT_SLURM_ACCOUNT=my_account src/ubelix/submit.sh calculate_annual_cwd
```

Optional controls are:

- `MCT_SLURM_PARTITION`: add an explicit partition;
- `MCT_USE_WORKSPACE=1`: load the UBELIX Workspace module before R;
- `MCT_DEPENDENCY=afterok:JOBID`: submit only after a successful upstream job;
- `MCT_ILON=...`: restrict longitude indices inside the R entry point.
- `MCT_INPUT_CONFIG=...`: select an alternative climate-input namelist.

`submit_pipeline.sh` submits the core climate path with `afterok` dependencies:
configured precipitation, temperature, and ET; snow/rain partitioning; daily
water balance; and annual CWD. It ends at the temporary annual-CWD checkpoints.
The extreme-value jobs remain in `jobs.tsv` under
`04_optional_cwd_extremes`, but the pipeline does not submit them.

Array stdout and stderr are written to
`logs/ubelix/JOB__ET_PREC_%A_%a.{out,err}`. The same configured run ID appears
in checkpoint filenames. Completed per-longitude products are skipped, so an
interrupted array can be submitted again. To rerun only missing indices, derive
them with `analysis/09_diagnostics/01_check_files.R` or inspect
`Rscript analysis/00_status.R`, then set `MCT_ILON` for a targeted submission.

Resource requests in `jobs.tsv` are starting points migrated from the historical
jobs. Review UBELIX accounting data after representative runs and tune memory,
time, and the maximum simultaneous array tasks without changing the R scripts.
