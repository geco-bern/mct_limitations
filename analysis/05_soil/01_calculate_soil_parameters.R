#!/usr/bin/env Rscript

library(dplyr)
library(purrr)
library(tidyr)
library(magrittr)

source("R/workflow_helpers.R")
source("R/calc_soilparams_byilon.R")

args <- chunk_arguments()
path <- paste0(
  "data/df_whc_hires_chunks/df_whc_hires_ilon_",
  args$chunk,
  ".rds"
)

if (!file.exists(path)) {
  require_files("data/df_hwsd_hires.rds", "soil-parameter calculation")
  df_hwsd <- readRDS("data/df_hwsd_hires.rds")

  df_hwsd <- df_hwsd %>%
    mutate(
      lon = round(lon, digits = 3),
      lat = round(lat, digits = 3),
      ilon = as.integer(round((lon + 179.975) / 0.05 + 1))
    )

  ilon <- parse_index_spec()
  if (is.null(ilon)) ilon <- seq_len(7200L)
  ilon <- work_for_chunk(ilon, args$chunk, args$chunks)

  df_cells <- df_hwsd %>%
    ungroup() %>%
    dplyr::filter(ilon %in% !!ilon) %>%
    group_by(lon, lat) %>%
    group_split(.keep = TRUE)

  calculate_cell <- function(df) {
    out <- calc_soilparams_byilon(df)
    bind_cols(df %>% dplyr::select(lon, lat) %>% dplyr::slice(1), out)
  }

  df_whc <- run_parallel(df_cells, calculate_cell) %>% bind_rows()
  write_rds_atomic(df_whc, path.expand(path))
  message("Wrote ", path)
} else {
  message("File exists already: ", path)
}
