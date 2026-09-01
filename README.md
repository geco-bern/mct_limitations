# MCT Limitations

*Benjamin D. Stocker*

This repository contains the global gridded workflow for deriving annual
maximum cumulative water deficit (CWD) and the maximum cumulative water surplus
that precedes each annual CWD maximum. The repository name refers to the Mass
Curve Technique used by [Gao et al. (2014)](https://doi.org/10.1002/2014GL061668).
The code is licensed under GPL-3.

The active analysis no longer fits extreme-value distributions, derives return
levels or return periods, converts CWD to rooting depth, evaluates sites, or
analyses SIF- and evaporative-fraction thresholds.

## Repository layout

- `analysis/` contains the executable global work steps.
- `config/` contains the climate-input namelist.
- `R/` contains reusable functions.
- `data-raw/` contains small grid definitions kept with the project.
- `data/`, `fig/`, and `logs/` contain generated outputs and are ignored by
  Git.
- `vignettes/` contains a synthetic workflow demonstration and the UBELIX
  submission guide.
- `src/ubelix/` contains the Slurm job registry and submission scripts.
- `tests/` contains focused workflow tests.

## Software setup

Use R 4.1 or newer and run commands from the directory containing
`mct.Rproj`. Dependencies are recorded in `DESCRIPTION`. A typical setup is:

```r
install.packages(c("remotes", "renv"))
renv::init()
renv::snapshot()
```

The core workflow uses the GitHub packages `cwd`, `map2tidy`, and `rbeni`,
all declared under `Remotes` in `DESCRIPTION`.

## Climate inputs

Edit `config/input_sources.R` to select datasets, source paths, variables,
transformations, and regular grids. The default configuration uses:

- MSWEP V3.16 Past daily total precipitation;
- ERA5-Land daily 2 m temperature, regridded to the MSWEP grid;
- ALEXI daily evapotranspiration.

MSWEP total precipitation is partitioned into rain and snow using ERA5-Land
temperature. A degree-day snow model supplies rain plus snowmelt reaching the
soil. The daily water balance is this liquid input minus ALEXI ET.

The selected source identifiers form a run tag such as
`et-alexi__prec-mswep-v3.16-past__temp-era5-land`. Climate-dependent
checkpoints and figures include this tag, allowing runs with different inputs
to coexist.

Use `MCT_INPUT_CONFIG` to select another namelist without editing code:

```sh
MCT_INPUT_CONFIG=config/input_sources_alternative.R \
  Rscript analysis/03_water_balance/01_convert_et_mm.R 1 100
```

## Retained work steps

| Stage | Purpose | Main checkpoint |
|---|---|---|
| `01_tidy_inputs` | Convert configured NetCDF inputs to nested tidy longitude slices with `map2tidy` | configured tidy-cache `.rds` files |
| `03_water_balance` | Convert ET, partition and melt snow, and calculate daily liquid input minus ET | `data/df_bal/df_bal_ilon_*.rds` |
| `04_annual_cwd` | Calculate annual maximum CWD and preceding maximum surplus for every grid cell | `data/df_cwd_annual/df_cwd_annual_ilon_*.rds` |
| `10_results` | Plot annual maximum CWD against preceding maximum surplus | `fig/cwd_vs_preceding_surplus.*` |

See `analysis/README.md` for the script order.

## Running locally

Chunked scripts accept `CHUNK TOTAL_CHUNKS`. For example:

```sh
Rscript analysis/03_water_balance/01_convert_et_mm.R 3 100
```

`MCT_ILON` can restrict a run to selected longitude indices:

```sh
MCT_ILON=3961-3970,5000 \
  Rscript analysis/04_annual_cwd/01_calculate_annual_cwd.R
```

Existing checkpoint files are skipped, so interrupted work can be restarted
with the same command. Check progress with:

```sh
Rscript analysis/00_status.R
```

## UBELIX

`src/ubelix/jobs.tsv` is the job registry. The full pipeline submits
precipitation, temperature, ET, snow simulation, daily balance, annual CWD, and
the final CWD-surplus result with Slurm `afterok` dependencies:

```sh
src/ubelix/submit.sh prepare_et
src/ubelix/submit.sh calculate_balance
src/ubelix/submit.sh calculate_annual_cwd
src/ubelix/submit_pipeline.sh
```

The relationship plot can also be submitted separately after annual outputs
exist:

```sh
src/ubelix/submit.sh cwd_surplus_relationship
```

## Annual output definition

Each annual longitude-slice file contains one row per ALEXI grid cell and a
nested `annual_cwd` table with:

- `year`
- `date_max_cwd`
- `cwd_mm`
- `date_max_preceding_surplus`
- `preceding_surplus_year`
- `preceding_surplus_mm`
- `n_events`

The first observed calendar year is copied and prepended as spin-up. Daily
deficit and surplus are calculated by
[`cwd::cwd(do_surplus = TRUE)`](https://geco-bern.github.io/cwd/reference/cwd.html).
Spin-up and disposable tail-guard rows are removed before calendar-year CWD
maxima and preceding-surplus maxima are extracted. No probability distribution
is fitted.

## Synthetic demonstration

`vignettes/core_workflow_synthetic.Rmd` creates synthetic nested tidy
precipitation, temperature, and ET tables that mimic the output contract of the
first `map2tidy` step. It then demonstrates ET conversion, rain/snow
partitioning, snowmelt, daily balance, annual CWD/surplus extraction, annual
time series, and the final CWD–surplus relationship.

`vignettes/ubelix_workflow.Rmd` gives the corresponding operational instructions
for submitting individual stages or the full dependency-linked workflow on
UBELIX.
