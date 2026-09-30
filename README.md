# MCT Limitations

*Benjamin D. Stocker*

This repository contains site-level and global workflows for cumulative water
deficit (CWD), cumulative water surplus (CWS), and potential cumulative water
deficit (PCWD). The repository name refers to the Mass Curve Technique used by
[Gao et al. (2014)](https://doi.org/10.1002/2014GL061668). The code is licensed
under GPL-3.

The active analysis does not fit extreme-value distributions, derive return
levels or return periods, convert CWD to rooting depth, or analyse SIF and
evaporative-fraction thresholds.

## Repository layout

- `analysis/` contains the executable global work steps.
- `config/` contains the climate-input namelist.
- `R/` contains reusable functions.
- `data-raw/` contains small grid definitions kept with the project.
- `data/`, `fig/`, and `logs/` contain generated outputs and are ignored by
  Git.
- `vignettes/` contains synthetic and FLUXNET demonstrations plus the UBELIX
  submission guide.
- `src/ubelix/` contains the Slurm job registry and submission scripts.
- `tests/` contains focused workflow tests.

## Software setup

Use R 4.2 or newer and run commands from the directory containing
`mct.Rproj`. Dependencies are recorded in `DESCRIPTION`. A typical setup is:

```r
install.packages(c("remotes", "renv"))
renv::init()
renv::snapshot()
```

The core workflow uses the GitHub packages `cwd`, `map2tidy`, and `rgeco`,
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
| `02_site_level` | Derive daily FLUXNET CWD/CWS/PCWD and select parsimonious annual CWD models | `data/site_level/fluxnet_cwd_cws_pcwd.rds`, `data/site_level/fluxnet_cwd_model_selection.rds` |
| `03_water_balance` | Convert ET, partition and melt snow, and calculate daily liquid input minus ET | `data/df_bal/df_bal_ilon_*.rds` |
| `04_annual_cwd` | Calculate annual maximum CWD and preceding maximum surplus for every grid cell | `data/df_cwd_annual/df_cwd_annual_ilon_*.rds` |
| `10_results` | Plot annual maximum CWD against preceding maximum surplus | `fig/cwd_vs_preceding_surplus.*` |

See `analysis/README.md` for the script order.

## FLUXNET site-level analysis

Run the site-level workflow with:

```sh
Rscript analysis/02_site_level/01_fluxnet_cwd_pcwd.R
```

By default it reads
`~/data_2/FluxDataKit/v3.4/zenodo_upload/rsofun_driver_data_v3.4.2.rds`
and the two FluxDataKit site tables beside it. It applies the ecosystem and
data-quality exclusions used to construct `sites_train` in `eval_rsofun_et`.
It then includes each eligible site's longest sequence of at least 10
consecutive complete GPP and LE years. Set `MCT_MIN_SITE_YEARS` to a positive
integer to change that threshold.

The uncorrected latent heat variable (`le`, FLUXNET `LE_F_MDS`) in the rsofun
driver is converted from W m-2 to ET in mm d-1. Total precipitation is converted
from mm s-1 to mm d-1, partitioned into rain and snow, and passed through
`cwd::simulate_snow()`. Daily CWD and CWS are then calculated with
`cwd::cwd(do_surplus = TRUE)` without calendar resetting. Non-positive source
pressure values are treated as invalid and linearly interpolated within site.

Before each CWD/CWS or PCWD call, a copy of the site's first year is prepended
as spin-up. The copied year is removed from the returned daily series after
`cwd::cwd()` has run, as are the disposable tail-guard rows.

Priestley-Taylor PET is calculated with `cwd::pet()`. Missing net radiation is
filled by five-nearest-neighbour prediction from temperature and PPFD, following
the FluxDataKit processing approach; each daily value retains an `observed` or
`knn_imputed` source flag. For each site, valid days are divided into five
equal-width CWD bins. The initial PET scalar is the ratio of median observed ET
to median Priestley--Taylor PET in the lowest-CWD bin. Bins 2--5 are then
inspected sequentially. Whenever median observed ET exceeds median scaled PET in
bin *i*, the scalar is recalibrated by median matching over all observations in
bins 1 through *i*. Thus calibration can expand to the full site record when no
water-limitation signal is apparent. Set `MCT_CWD_BIN_COUNT` to a positive
integer to change the number of bins. Calibration uses days with LE QC at least
0.8, positive PT-PET, and non-negative observed ET. Negative PT-PET values
arising from negative daily net radiation are retained, as in the referenced
`cwd` implementation, but are not used to calibrate the site scalar.

PCWD uses the fitted site PET. Its annual reset is the first day of the site's
climatologically wettest potential-water-balance month. CWD has no calendar
reset. The RDS checkpoint contains the daily and annual data, per-site
correlations, site diagnostics, CWD-bin summaries, and monthly balances. A
compact site summary is also written to
`data/site_level/fluxnet_site_summary.csv`.

`vignettes/fluxnet_site_diagnostics.Rmd` displays the calibrated ET--PET
relationships, PET/scaled-PET/ET distributions by CWD bin, and full-record
daily CWD/PCWD/CWS series in nested plot tabs within one tab per site, alongside
network-wide PET-scalar and annual-correlation overviews.

The follow-on model comparison is run with:

```sh
Rscript analysis/02_site_level/02_select_cwd_models.R
```

For each site, it compares three zero-offset annual models: energy
(`D = a P`), energy plus storage (`D = min(a P, S0)`), and energy plus
preceding recharge (`D = min(a P, b R(t-1))`). The scales `a` and `b`, storage
capacity `S0`, and residual-error scale are fitted separately for each model
and site. Every pair is evaluated with
a dual-null parametric-bootstrap likelihood-ratio contrast. This supplies an
empirical reference distribution for the boundary-nested storage comparison
and both non-nested comparisons. Models decisively defeated in any pair are
excluded; the least complex undefeated model is selected. Leave-one-year-out
predictions and AICc remain complementary diagnostics. Set
`MCT_MODEL_BOOTSTRAP_REPS`, `MCT_MODEL_BOOTSTRAP_ALPHA`,
`MCT_MODEL_BOOTSTRAP_SEED`, or `MCT_MODEL_BOOTSTRAP_CORES` to change the
bootstrap defaults. `vignettes/fluxnet_cwd_model_selection.Rmd` documents the
method and provides network-wide evidence maps plus tabbed diagnostics for
every site.

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
