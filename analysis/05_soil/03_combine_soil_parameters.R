#!/usr/bin/env Rscript

library(dplyr)
library(tidyr)
library(purrr)
library(magrittr)

source("R/workflow_helpers.R")
source("R/extract_whc_byfil.R")

dir <- "data/df_whc_hires_chunks/"
filelist <- list.files(
  dir,
  pattern = "^df_whc_hires_ilon_.*[.]RData$",
  full.names = TRUE
)
if (!length(filelist)) {
  stop("No soil-parameter chunks found in ", dir, call. = FALSE)
}

df_whc <- run_parallel(filelist, extract_whc_byfil) %>% bind_rows()
path <- "~/data/mct_data/df_whc_hires_lasthope.rds"
write_rds_atomic(df_whc, path.expand(path))
message("Wrote ", path)
