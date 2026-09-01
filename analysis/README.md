# Analysis sequence

Run scripts from the project root. The retained workflow contains only the
global gridded calculations needed to derive annual maximum cumulative water
deficit (CWD) and its preceding maximum cumulative surplus.

## 01 — Tidy climate inputs

1. `01_watch_prec.R` — configured daily precipitation (MSWEP by default)
2. `04_watch_temp.R` — configured daily temperature (ERA5-Land by default)
3. `05_alexi.R` — configured daily ET (ALEXI by default)

These scripts call the shared `map2tidy` adapter and write restartable
longitude-slice files with outer `lon`, `lat`, and nested `data` columns.

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
