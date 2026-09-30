#!/usr/bin/env Rscript

source("R/workflow_helpers.R")
source("R/calculate_annual_cwd.R")
source("R/site_level_cwd.R")

driver_path <- path.expand(Sys.getenv(
  "MCT_FLUXNET_DRIVER",
  "~/data_2/FluxDataKit/v3.4/zenodo_upload/rsofun_driver_data_v3.4.2.rds"
))
input_dir <- dirname(driver_path)
site_info_path <- Sys.getenv(
  "MCT_FLUXNET_SITE_INFO",
  file.path(input_dir, "fdk_site_info.csv")
)
site_filter_path <- Sys.getenv(
  "MCT_FLUXNET_SITE_FILTER",
  file.path(input_dir, "fdk_site_fullyearsequence.csv")
)
output_dir <- Sys.getenv("MCT_SITE_OUTPUT_DIR", "data/site_level")
output_rds <- file.path(output_dir, "fluxnet_cwd_cws_pcwd.rds")
output_summary <- file.path(output_dir, "fluxnet_site_summary.csv")
minimum_years_text <- Sys.getenv("MCT_MIN_SITE_YEARS", "10")
minimum_years <- suppressWarnings(as.integer(minimum_years_text))
if (is.na(minimum_years) ||
    minimum_years < 1L ||
    as.character(minimum_years) != minimum_years_text) {
  stop("MCT_MIN_SITE_YEARS must be one positive integer.", call. = FALSE)
}
cwd_bin_count_text <- Sys.getenv("MCT_CWD_BIN_COUNT", "5")
cwd_bin_count <- suppressWarnings(as.integer(cwd_bin_count_text))
if (is.na(cwd_bin_count) ||
    cwd_bin_count < 1L ||
    as.character(cwd_bin_count) != cwd_bin_count_text) {
  stop("MCT_CWD_BIN_COUNT must be one positive integer.", call. = FALSE)
}

require_files(
  c(driver_path, site_info_path, site_filter_path),
  "FLUXNET site-level analysis"
)
ensure_directory(output_dir)

message("Reading FLUXNET driver: ", driver_path)
driver <- readRDS(driver_path)
site_info <- utils::read.csv(site_info_path, stringsAsFactors = FALSE)
site_filter <- utils::read.csv(site_filter_path, stringsAsFactors = FALSE)

result <- run_fluxnet_site_analysis(
  driver,
  site_info,
  site_filter,
  minimum_years = minimum_years,
  cwd_bin_count = cwd_bin_count
)
result$provenance <- list(
  driver_path = normalizePath(driver_path),
  site_info_path = normalizePath(site_info_path),
  site_filter_path = normalizePath(site_filter_path),
  site_selection = paste(
    "all sites passing the ecosystem and data-quality exclusions in",
    paste0(
      "https://github.com/geco-bern/eval_rsofun_et/blob/main/",
      "analysis/00_prepare_forcing_fluxnet.R"
    ),
    "with at least the requested number of overlapping complete GPP/LE years"
  ),
  minimum_overlapping_years = minimum_years,
  latent_heat_variable = "rsofun driver le (uncorrected FLUXNET LE_F_MDS)",
  cwd_method = "https://geco-bern.github.io/cwd/articles/cwd_example.html",
  pcwd_method = "https://geco-bern.github.io/cwd/articles/potential_cwd.html",
  pressure_repair = "non-positive values linearly interpolated within site",
  netrad_imputation = "5-nearest-neighbour regression from temperature and PPFD",
  le_qc_min_for_pet_calibration = 0.8,
  pet_scalar_calibration = paste(
    "initial median matching in the lowest of", cwd_bin_count,
    "equal-width CWD bins, followed by sequential pooled-median refitting",
    "through bin i whenever median observed ET exceeds median scaled PET in bin i"
  ),
  cwd_bin_count = cwd_bin_count,
  pcwd_reset = paste(
    "first day of the climatologically wettest month by mean",
    "potential water balance; one-year spin-up"
  ),
  cwd_reset = "none; one-year spin-up only"
)

write_rds_atomic(result, output_rds)
utils::write.csv(result$site_summary, output_summary, row.names = FALSE)
message(
  "Wrote ", nrow(result$daily), " daily rows for ",
  nrow(result$site_summary), " sites to ", output_rds
)
message("Wrote site diagnostics to ", output_summary)
