#!/usr/bin/env Rscript

# Show the relationship between annual maximum CWD and its preceding maximum
# cumulative surplus. No return levels, site evaluations, or ancillary
# predictors enter this results step.

library(dplyr)
library(ggplot2)
library(purrr)
library(tidyr)

source("R/workflow_helpers.R")
source("R/input_config.R")

config <- read_input_config()
input_pattern <- climate_output_path(
  "data/df_cwd_annual/df_cwd_annual_ilon_*.rds",
  config
)
input_files <- sort(Sys.glob(input_pattern))
require_files(input_files, step = "CWD-surplus relationship analysis")

max_per_slice <- suppressWarnings(as.integer(Sys.getenv(
  "MCT_RESULTS_PER_SLICE",
  "25"
)))
if (is.na(max_per_slice) || max_per_slice < 1L) {
  stop("MCT_RESULTS_PER_SLICE must be a positive integer.", call. = FALSE)
}

extract_relationship_sample <- function(path) {
  values <- readRDS(path) |>
    dplyr::select(lon, lat, annual_cwd) |>
    tidyr::unnest(annual_cwd) |>
    dplyr::filter(
      is.finite(cwd_mm),
      is.finite(preceding_surplus_mm),
      cwd_mm > 0,
      preceding_surplus_mm > 0
    ) |>
    dplyr::arrange(lat, year)

  if (nrow(values) <= max_per_slice) return(values)
  indices <- unique(as.integer(round(seq(
    1,
    nrow(values),
    length.out = max_per_slice
  ))))
  dplyr::slice(values, indices)
}

relationship <- purrr::map_dfr(
  input_files,
  extract_relationship_sample
)
if (nrow(relationship) < 2L) {
  stop(
    "Fewer than two paired annual CWD-surplus observations are available.",
    call. = FALSE
  )
}

fit <- stats::lm(cwd_mm ~ preceding_surplus_mm, data = relationship)
relationship_summary <- tibble::tibble(
  n = nrow(relationship),
  correlation = stats::cor(
    relationship$cwd_mm,
    relationship$preceding_surplus_mm
  ),
  intercept = unname(stats::coef(fit)[[1]]),
  slope = unname(stats::coef(fit)[[2]])
)

data_path <- climate_output_path(
  "data/cwd_surplus_relationship_sample.rds",
  config
)
ensure_directory(dirname(data_path))
write_rds_atomic(
  list(data = relationship, summary = relationship_summary),
  data_path
)

relationship_plot <- ggplot(
  relationship,
  aes(x = preceding_surplus_mm, y = cwd_mm)
) +
  geom_bin_2d(bins = 60) +
  geom_smooth(
    method = "lm",
    formula = y ~ x,
    color = "black",
    linewidth = 0.7,
    se = FALSE
  ) +
  scale_fill_viridis_c(trans = "log10", name = "Count") +
  labs(
    x = "Preceding maximum cumulative surplus (mm)",
    y = "Annual maximum cumulative water deficit (mm)",
    title = "Annual maximum CWD and preceding maximum surplus",
    subtitle = paste(
      format(nrow(relationship), big.mark = ","),
      "observations sampled across longitude slices"
    )
  ) +
  theme_minimal(base_size = 11)

figure_png <- climate_output_path(
  "fig/cwd_vs_preceding_surplus.png",
  config
)
figure_pdf <- climate_output_path(
  "fig/cwd_vs_preceding_surplus.pdf",
  config
)
ensure_directory(dirname(figure_png))
ggsave(figure_png, relationship_plot, width = 7, height = 5, dpi = 300)
ggsave(figure_pdf, relationship_plot, width = 7, height = 5)

print(relationship_summary)
message("Wrote ", data_path)
message("Wrote ", figure_png)
message("Wrote ", figure_pdf)
