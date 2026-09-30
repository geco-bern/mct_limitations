# Analysis sequence

Run scripts from the project root. The retained workflow contains only the
global gridded calculations needed to derive annual maximum cumulative water
deficit (CWD) and its preceding maximum cumulative surplus, plus a separate
FLUXNET site-level exploration.

## 01 — Tidy climate inputs

1. `01_watch_prec.R` — configured daily precipitation (MSWEP by default)
2. `04_watch_temp.R` — configured daily temperature (ERA5-Land by default)
3. `05_alexi.R` — configured daily ET (ALEXI by default)

These scripts call the shared `map2tidy` adapter and write restartable
longitude-slice files with outer `lon`, `lat`, and nested `data` columns.

## 02 — FLUXNET site-level CWD, CWS, and PCWD

`02_site_level/01_fluxnet_cwd_pcwd.R` applies the `eval_rsofun_et` eligibility
rules and selects each site's longest sequence of at least 10 consecutive
complete GPP and LE years. It converts the uncorrected latent heat variable
(`le`, FLUXNET `LE_F_MDS`) and precipitation to daily water fluxes, simulates
snow, and calculates daily CWD/CWS without calendar resetting. Valid calibration
days are divided into equal-width CWD bins; the site PET scalar is the ratio of
median observed ET to median Priestley--Taylor PET, initially in the lowest-CWD
bin. Bins 2--5 are checked sequentially. If scaled PET underpredicts median ET
in bin *i*, the scalar is recalibrated by median matching across all data in
bins 1 through *i*. PCWD uses that final scaled PET and resets at the start of
the climatologically wettest month. Missing net radiation is KNN-imputed from
temperature and PPFD and explicitly flagged. Invalid non-positive atmospheric
pressure values are interpolated within site and flagged separately. Set
`MCT_MIN_SITE_YEARS` to change the default record-length threshold and
`MCT_CWD_BIN_COUNT` to change the default five bins.

The output `data/site_level/fluxnet_cwd_cws_pcwd.rds` contains daily series,
site summaries, CWD-bin calibration summaries, and monthly balances used to
choose PCWD reset dates.

`../vignettes/fluxnet_site_diagnostics.Rmd` provides network-wide summaries
and nested plot tabs for calibrated ET--PET, flux distributions by CWD bin, and
daily CWD/PCWD/CWS diagnostics within each site tab.

`02_site_level/02_select_cwd_models.R` compares three zero-offset annual CWD
hypotheses at each site: energy (`D = a P`), energy plus storage
(`D = min(a P, S0)`), and energy plus preceding recharge
(`D = min(a P, b R(t-1))`). The non-negative scales `a` and `b`, storage
capacity `S0`, and residual-error scale are fitted separately for each model
and site. Every pair is tested with a dual-null parametric-bootstrap
likelihood-ratio contrast, which
does not rely on a chi-squared reference for boundary or non-nested models.
Models decisively defeated in a pair are excluded and the least complex
undefeated model is selected. Leave-one-year-out RMSE and AICc are reported as
complementary diagnostics. The bootstrap is configured with
`MCT_MODEL_BOOTSTRAP_REPS`, `MCT_MODEL_BOOTSTRAP_ALPHA`,
`MCT_MODEL_BOOTSTRAP_SEED`, and `MCT_MODEL_BOOTSTRAP_CORES`.

The outputs are
`data/site_level/fluxnet_cwd_model_selection.rds` and a compact selected-model
CSV. `../vignettes/fluxnet_cwd_model_selection.Rmd` demonstrates network-wide
results and tabbed diagnostics for every site.

## 03 — Daily water balance

Run these scripts in order:

1. `01_convert_et_mm.R` converts the configured ET source to mm d-1.
2. `02_simulate_snow.R` partitions total precipitation into rain and snow,
   simulates snow storage and melt, and derives liquid water reaching the soil.
3. `03_calculate_balance.R` calculates daily liquid input minus ET for each
   grid cell.

## 04 — Annual CWD and preceding surplus

`04_annual_cwd/01_calculate_annual_cwd.R` reads the daily balance and writes
one temporary, restartable file per ALEXI longitude slice under
`data/df_cwd_annual/`. The nested annual table contains:

- `year`
- `date_max_cwd`
- `cwd_mm`
- `date_max_preceding_surplus`
- `preceding_surplus_year`
- `preceding_surplus_mm`
- `n_events`

The first observed year is prepended as spin-up. Daily deficit and surplus are
calculated by `cwd::cwd(do_surplus = TRUE)`; all padding is removed before
calendar-year maxima and preceding-surplus pairs are extracted. No
extreme-value distribution or return level is fitted.

## 10 — CWD–surplus relationship

`10_results/01_cwd_surplus_relationship.R` is the only retained results
script. It samples valid annual pairs across longitude slices, stores the
sample and a linear summary, and plots annual maximum CWD against its preceding
maximum surplus. Set `MCT_RESULTS_PER_SLICE` to control the maximum number of
observations retained from each longitude-slice file.

## Demonstration and controls

`vignettes/core_workflow_synthetic.Rmd` demonstrates the complete retained
workflow using synthetic nested tidy climate inputs, so it requires no external
data.

Chunked scripts accept `CHUNK TOTAL_CHUNKS`. `MCT_ILON` restricts a run to
specific longitude indices. Existing products are skipped, allowing safe
restart. Run `Rscript analysis/00_status.R` to compare current output counts
with the UBELIX job registry.
