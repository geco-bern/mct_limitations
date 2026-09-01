# UBELIX Slurm jobs

Submit from the project root on UBELIX. `jobs.tsv` is the single registry of job
names, R entry points, array sizes, resources, output patterns, and expected
counts. `submit.sh` converts a registry row into an `sbatch` call;
`run_r_job.sh` is the shared batch entry point.

```sh
src/ubelix/submit.sh prepare_precipitation
src/ubelix/submit.sh prepare_et
src/ubelix/submit.sh calculate_balance
src/ubelix/submit.sh calculate_annual_cwd
src/ubelix/submit.sh cwd_surplus_relationship
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

`submit_pipeline.sh` submits the full climate path with `afterok` dependencies:
configured precipitation, temperature, and ET; snow/rain partitioning; daily
water balance; annual CWD; and the final CWD-surplus relationship result. The
result can also be submitted separately after the annual checkpoints are
complete.

Array stdout and stderr are written to
`logs/ubelix/JOB__ET_PREC_%A_%a.{out,err}`. The same configured run ID appears
in checkpoint filenames. Completed per-longitude products are skipped, so an
interrupted array can be submitted again. Inspect
`Rscript analysis/00_status.R`, then set `MCT_ILON` for a targeted submission
of missing longitude indices.

Resource requests in `jobs.tsv` are starting points migrated from the historical
jobs. Review UBELIX accounting data after representative runs and tune memory,
time, and the maximum simultaneous array tasks without changing the R scripts.
