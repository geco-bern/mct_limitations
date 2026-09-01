#!/usr/bin/env Rscript

# Core endpoint: calculate annual CWD and preceding cumulative-surplus maxima
# without distribution fitting.

library(dplyr)
library(purrr)
library(lubridate)
library(rlang)

source("R/workflow_helpers.R")
source("R/input_config.R")
source("R/get_annual_cwd_byilon.R")

args <- chunk_arguments()
config <- read_input_config()
ilon <- parse_index_spec()
if (is.null(ilon)) ilon <- seq_len(config$et$source$grid$longitude_count)
ilon <- work_for_chunk(ilon, args$chunk, args$chunks)

message(
  "Calculating annual CWD for longitude indices: ",
  paste(ilon, collapse = ", ")
)
df_out <- run_parallel(ilon, get_annual_cwd_byilon, config = config)
