get_annual_cwd_byilon <- function(ilon_hires, config = read_input_config()) {
  source("R/calculate_annual_cwd.R")

  output_path <- climate_output_path(
    paste0(
      "data/df_cwd_annual/df_cwd_annual_ilon_",
      ilon_hires,
      ".rds"
    ),
    config
  )
  ensure_directory(dirname(output_path))

  if (file.exists(output_path)) {
    rlang::inform(paste("File exists already:", output_path))
    return(0)
  }

  balance_path <- climate_output_path(
    paste0("data/df_bal/df_bal_ilon_", ilon_hires, ".rds"),
    config
  )
  require_files(balance_path, step = "annual CWD calculation")

  analysis_years <- seq.int(
    config$analysis_period$start_year,
    config$analysis_period$end_year
  )
  coordinate_digits <- source_coordinate_digits(
    config$et$source,
    "longitude"
  )
  select_analysis_period <- function(daily_balance) {
    if (!is.data.frame(daily_balance) ||
        !all(c("time", "bal") %in% names(daily_balance))) {
      return(tibble::tibble(time = as.Date(character()), bal = numeric()))
    }
    dplyr::filter(
      daily_balance,
      lubridate::year(time) >= config$analysis_period$start_year,
      lubridate::year(time) <= config$analysis_period$end_year
    )
  }

  output <- readRDS(balance_path) |>
    dplyr::mutate(
      lon = round(lon, digits = coordinate_digits),
      lat = round(lat, digits = coordinate_digits),
      data = purrr::map(
        data,
        select_analysis_period
      ),
      cwd_result = purrr::map(
        data,
        ~calculate_annual_cwd(
          .x,
          varname_wbal = "bal",
          varname_date = "time",
          years = analysis_years,
          thresh_drop = 0.0,
          return_cumulative_surplus = FALSE
        )
      ),
      annual_cwd = purrr::map(cwd_result, "annual_cwd"),
      cwd_status = purrr::map_chr(cwd_result, "status")
    ) |>
    dplyr::select(-data, -cwd_result)

  attr(output, "climate_inputs") <- list(
    precipitation = config$precipitation$id,
    precipitation_form = config$precipitation$form,
    temperature = config$temperature$id,
    evapotranspiration = config$et$id,
    daily_balance = paste(
      config$precipitation$id,
      "rain plus simulated snowmelt reaching the soil minus",
      config$et$id,
      "ET"
    )
  )
  attr(output, "annual_cwd_definition") <- paste(
    "Calendar-year maximum of actual daily CWD after spin-up rows are",
    "removed, paired with the latest preceding maximum of the actual",
    "cumulative-surplus time series; no extreme-value distribution is fitted."
  )
  attr(output, "cumulative_surplus_definition") <- paste(
    "Positive daily balances accumulate until the surplus is exhausted or",
    "the date of an annual maximum CWD is reached, following the cwd package",
    "cumulative-surplus vignette."
  )
  attr(output, "cwd_spinup_definition") <- paste(
    "The first observed calendar year is copied and prepended to the daily",
    "balance before CWD and cumulative-surplus calculation. Padded daily",
    "rows are removed before annual CWD maxima and preceding-surplus maxima",
    "are extracted."
  )
  attr(output, "cwd_package") <- paste0(
    "cwd ", as.character(utils::packageVersion("cwd")),
    " via cwd::cwd(do_surplus = TRUE)"
  )

  rlang::inform(paste("Writing file:", output_path))
  write_rds_atomic(output, output_path)
  0
}
