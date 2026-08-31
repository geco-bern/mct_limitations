#!/usr/bin/env Rscript

library(dplyr)
library(purrr)
library(tidyr)
library(magrittr)
library(rlang)

source("R/workflow_helpers.R")
source("R/collect_cwdx_byilon.R")

ilon <- seq_len(7200L)
message("Collecting ", length(ilon), " longitude bands.")
df <- run_parallel(
  ilon,
  collect_cwdx_byilon,
  continue_on_error = FALSE
) %>% bind_rows()

path <- "data/df_cwdx_10_20_40.rds"
write_rds_atomic(df, path.expand(path))
message("Wrote ", path)
