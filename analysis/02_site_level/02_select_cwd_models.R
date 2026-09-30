#!/usr/bin/env Rscript

source("R/workflow_helpers.R")
source("R/cwd_model_selection.R")

input_path <- Sys.getenv(
  "MCT_SITE_CWD_INPUT",
  "data/site_level/fluxnet_cwd_cws_pcwd.rds"
)
output_dir <- Sys.getenv("MCT_SITE_OUTPUT_DIR", "data/site_level")
output_rds <- file.path(output_dir, "fluxnet_cwd_model_selection.rds")
output_summary <- file.path(output_dir, "fluxnet_cwd_model_selection.csv")
bootstrap_replicates_text <- Sys.getenv("MCT_MODEL_BOOTSTRAP_REPS", "999")
bootstrap_replicates <- suppressWarnings(as.integer(bootstrap_replicates_text))
bootstrap_alpha_text <- Sys.getenv("MCT_MODEL_BOOTSTRAP_ALPHA", "0.05")
bootstrap_alpha <- suppressWarnings(as.numeric(bootstrap_alpha_text))
bootstrap_seed_text <- Sys.getenv("MCT_MODEL_BOOTSTRAP_SEED", "20260930")
bootstrap_seed <- suppressWarnings(as.integer(bootstrap_seed_text))
bootstrap_cores_text <- Sys.getenv("MCT_MODEL_BOOTSTRAP_CORES", "4")
bootstrap_cores <- suppressWarnings(as.integer(bootstrap_cores_text))
if (is.na(bootstrap_replicates) || bootstrap_replicates < 1L) {
  stop("MCT_MODEL_BOOTSTRAP_REPS must be one positive integer.", call. = FALSE)
}
if (is.na(bootstrap_alpha) || !is.finite(bootstrap_alpha) ||
    bootstrap_alpha <= 0 || bootstrap_alpha >= 0.5) {
  stop("MCT_MODEL_BOOTSTRAP_ALPHA must be between 0 and 0.5.", call. = FALSE)
}
if (is.na(bootstrap_seed)) {
  stop("MCT_MODEL_BOOTSTRAP_SEED must be an integer.", call. = FALSE)
}
if (is.na(bootstrap_cores) || bootstrap_cores < 1L) {
  stop("MCT_MODEL_BOOTSTRAP_CORES must be one positive integer.", call. = FALSE)
}

require_files(input_path, "FLUXNET CWD model selection")
ensure_directory(output_dir)

message("Reading annual FLUXNET water-balance metrics: ", input_path)
site_analysis <- readRDS(input_path)
if (is.null(site_analysis$annual)) {
  stop("The site-level checkpoint does not contain annual metrics.", call. = FALSE)
}

result <- select_cwd_models_by_site(
  site_analysis$annual,
  n_boot = bootstrap_replicates,
  alpha = bootstrap_alpha,
  seed = bootstrap_seed,
  cores = bootstrap_cores
)
result$annual <- site_analysis$annual
result$site_metadata <- site_analysis$site_summary
result$provenance <- list(
  input_path = normalizePath(input_path),
  response = "annual maximum observed-ET CWD",
  energy_limit = "annual maximum site-calibrated PCWD",
  recharge_limit = paste(
    "maximum of the latest CWS event whose peak is on or before",
    "the date of annual maximum CWD"
  ),
  model_means = paste(
    "A: a*PCWD; B: min(a*PCWD, S0);",
    "C: min(a*PCWD, b*preceding_CWS); no additive intercept"
  ),
  storage_parameter = paste(
    "S0 is a cap on predicted CWD and is fitted jointly with energy scale a by",
    "Gaussian maximum likelihood (minimum RSS)"
  ),
  residual_error = paste(
    "independent zero-mean Gaussian residual error with a separate maximum-",
    "likelihood standard deviation fitted for each site and candidate model"
  ),
  validation = paste(
    "leave-one-year-out cross-validation with a, b, S0, and residual error",
    "parameters re-estimated as applicable within each training fold"
  ),
  pairwise_inference = paste(
    "dual-null parametric-bootstrap likelihood-ratio contrasts for all three",
    "model pairs, with", bootstrap_replicates, "replicates per generating",
    "model and alpha =", bootstrap_alpha
  ),
  selection_rule = paste(
    "exclude models decisively defeated in any pairwise bootstrap comparison;",
    "among undefeated models select by mechanism count, fitted-parameter",
    "count, then AICc"
  ),
  bootstrap_seed = bootstrap_seed,
  bootstrap_cores = bootstrap_cores,
  predictive_diagnostic = paste(
    "leave-one-year-out cross-validation with all coefficients re-estimated",
    "inside each fold; reported as a diagnostic, not the selection gate"
  )
)

write_rds_atomic(result, output_rds)
utils::write.csv(result$site_selection, output_summary, row.names = FALSE)
message(
  "Wrote model selection for ", nrow(result$site_selection),
  " sites to ", output_rds
)
message("Wrote selected-model summary to ", output_summary)
