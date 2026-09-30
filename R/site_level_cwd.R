assert_has_columns <- function(df, required, label) {
  missing <- setdiff(required, names(df))
  if (length(missing)) {
    stop(
      label, " is missing: ", paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
}

select_fluxnet_analysis_sites <- function(site_info,
                                          site_filter,
                                          minimum_years = 10L) {
  assert_has_columns(
    site_info,
    c("sitename", "koeppen_code", "igbp_land_use"),
    "FLUXNET site information"
  )
  assert_has_columns(
    site_filter,
    c(
      "sitename", "drop_gpp", "drop_le",
      "nyears_gpp", "nyears_le",
      "year_start_gpp", "year_end_gpp",
      "year_start_le", "year_end_le"
    ),
    "FLUXNET full-year filter"
  )
  if (length(minimum_years) != 1L ||
      !is.finite(minimum_years) ||
      minimum_years < 1 ||
      minimum_years != as.integer(minimum_years)) {
    stop("Minimum site years must be one positive integer.", call. = FALSE)
  }
  minimum_years <- as.integer(minimum_years)

  sites <- site_info |>
    dplyr::filter(
      !(.data$sitename %in% c("MX-Tes", "US-KS3")),
      !(.data$igbp_land_use %in% c("CRO", "WET"))
    ) |>
    dplyr::left_join(site_filter, by = "sitename") |>
    dplyr::filter(
      !.data$drop_gpp & !.data$drop_le,
      .data$nyears_gpp >= 1,
      .data$nyears_le >= 1
    ) |>
    dplyr::mutate(
      year_start = pmax(.data$year_start_gpp, .data$year_start_le),
      year_end = pmin(.data$year_end_gpp, .data$year_end_le),
      nyears_overlap = .data$year_end - .data$year_start + 1L
    ) |>
    dplyr::filter(
      is.finite(.data$nyears_overlap),
      .data$nyears_overlap >= minimum_years
    ) |>
    dplyr::arrange(.data$sitename)

  if (!nrow(sites)) {
    stop("No FLUXNET sites meet the minimum overlapping-year criterion.", call. = FALSE)
  }
  sites
}

select_fluxnet_driver <- function(driver, sites) {
  assert_has_columns(driver, c("sitename", "forcing"), "FLUXNET driver")
  assert_has_columns(
    sites,
    c("sitename", "year_start", "year_end"),
    "Analysis-site table"
  )
  missing_sites <- setdiff(sites$sitename, driver$sitename)
  if (length(missing_sites)) {
    stop(
      "Analysis sites missing from driver: ",
      paste(missing_sites, collapse = ", "),
      call. = FALSE
    )
  }

  daily <- driver |>
    dplyr::filter(.data$sitename %in% sites$sitename) |>
    dplyr::select(sitename, forcing) |>
    tidyr::unnest(cols = tidyselect::all_of("forcing")) |>
    dplyr::inner_join(
      sites |>
        dplyr::select(sitename, year_start, year_end),
      by = "sitename"
    ) |>
    dplyr::mutate(year = lubridate::year(.data$date)) |>
    dplyr::filter(
      .data$year >= .data$year_start,
      .data$year <= .data$year_end
    ) |>
    dplyr::select(-year_start, -year_end) |>
    dplyr::arrange(.data$sitename, .data$date)

  assert_has_columns(
    daily,
    c(
      "date", "temp", "patm", "rain", "snow", "netrad", "ppfd",
      "le", "le_qc"
    ),
    "Selected FLUXNET forcing"
  )

  duplicated_dates <- duplicated(daily[c("sitename", "date")])
  if (any(duplicated_dates)) {
    stop("Selected FLUXNET forcing contains duplicate site dates.", call. = FALSE)
  }
  year_counts <- daily |>
    dplyr::count(.data$sitename, .data$year, name = "n_days")
  incomplete <- year_counts |>
    dplyr::filter(.data$n_days != 365L)
  if (nrow(incomplete)) {
    stop(
      "Selected FLUXNET forcing does not contain 365 rows for every site-year.",
      call. = FALSE
    )
  }

  daily
}

repair_site_pressure <- function(df) {
  assert_has_columns(df, c("sitename", "date", "patm"), "Pressure input")

  repair_one_site <- function(site_df) {
    valid <- is.finite(site_df$patm) & site_df$patm > 0
    site_df$patm_source <- ifelse(valid, "observed", "linear_interpolated")
    if (all(valid)) return(site_df)
    if (sum(valid) < 2L) {
      stop(
        "Fewer than two valid pressure values are available at ",
        unique(site_df$sitename), ".",
        call. = FALSE
      )
    }

    date_number <- as.numeric(site_df$date)
    site_df$patm[!valid] <- stats::approx(
      x = date_number[valid],
      y = site_df$patm[valid],
      xout = date_number[!valid],
      method = "linear",
      rule = 2
    )$y
    site_df
  }

  split(df, df$sitename) |>
    lapply(repair_one_site) |>
    dplyr::bind_rows() |>
    dplyr::arrange(.data$sitename, .data$date)
}

impute_netrad_knn <- function(df,
                              donor_count = 10000L,
                              neighbors = 5L,
                              seed = 123L) {
  assert_has_columns(
    df,
    c("netrad", "temp", "ppfd"),
    "Net-radiation input"
  )
  if (!requireNamespace("FNN", quietly = TRUE)) {
    stop("Package 'FNN' is required for net-radiation imputation.", call. = FALSE)
  }

  observed <- is.finite(df$netrad)
  predictable <- is.finite(df$temp) & is.finite(df$ppfd)
  target <- which(!observed & predictable)
  donors <- which(observed & predictable)

  df$netrad_source <- ifelse(observed, "observed", "missing")
  if (!length(target)) return(df)
  if (!length(donors)) {
    stop("No observed net-radiation donor values are available.", call. = FALSE)
  }

  donor_count <- min(as.integer(donor_count), length(donors))
  neighbors <- min(as.integer(neighbors), donor_count)
  if (donor_count < 1L || neighbors < 1L) {
    stop("Net-radiation donor count and neighbors must be positive.", call. = FALSE)
  }

  had_random_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_random_seed) {
    previous_random_seed <- get(".Random.seed", envir = .GlobalEnv)
  }
  on.exit({
    if (had_random_seed) {
      assign(".Random.seed", previous_random_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(seed)
  donors <- sample(donors, size = donor_count, replace = FALSE)
  donor_x <- as.matrix(df[donors, c("temp", "ppfd")])
  target_x <- as.matrix(df[target, c("temp", "ppfd")])
  center <- colMeans(donor_x)
  scale <- apply(donor_x, 2L, stats::sd)
  scale[!is.finite(scale) | scale == 0] <- 1
  donor_x <- sweep(sweep(donor_x, 2L, center, "-"), 2L, scale, "/")
  target_x <- sweep(sweep(target_x, 2L, center, "-"), 2L, scale, "/")

  nearest <- FNN::get.knnx(donor_x, target_x, k = neighbors)$nn.index
  if (neighbors == 1L) nearest <- matrix(nearest, ncol = 1L)
  donor_values <- matrix(
    df$netrad[donors[as.vector(nearest)]],
    nrow = nrow(nearest),
    ncol = ncol(nearest)
  )
  df$netrad[target] <- rowMeans(donor_values)
  df$netrad_source[target] <- "knn_imputed"

  df
}

le_to_et_mm_day <- function(le, temp, patm) {
  1000 * 86400 * le /
    (cwd::calc_enthalpy_vap(temp) * cwd::calc_density_h2o(temp, patm))
}

prepare_fluxnet_water_balance <- function(df) {
  assert_has_columns(
    df,
    c("date", "temp", "patm", "rain", "snow", "le"),
    "Site forcing"
  )
  if (nrow(df) < 365L) {
    stop("At least one complete site-year is required.", call. = FALSE)
  }

  required_values <- c("temp", "patm", "rain", "snow", "le")
  if (any(!vapply(df[required_values], function(x) all(is.finite(x)), logical(1)))) {
    stop("Site forcing contains non-finite water-balance inputs.", call. = FALSE)
  }

  df |>
    dplyr::mutate(
      precipitation_mm = 86400 * (.data$rain + .data$snow),
      rain_mm = ifelse(.data$temp < 0, 0, .data$precipitation_mm),
      snow_mm = ifelse(.data$temp < 0, .data$precipitation_mm, 0),
      et_obs_mm = le_to_et_mm_day(.data$le, .data$temp, .data$patm)
    ) |>
    cwd::simulate_snow(
      varnam_temp = "temp",
      varnam_prec = "rain_mm",
      varnam_snow = "snow_mm"
    ) |>
    dplyr::rename(
      liquid_to_soil_mm = liquid_to_soil,
      snow_pool_mm = snow_pool
    ) |>
    dplyr::mutate(
      water_balance_mm = .data$liquid_to_soil_mm - .data$et_obs_mm
    )
}

calculate_daily_cwd_cws <- function(df) {
  assert_has_columns(
    df,
    c("date", "water_balance_mm"),
    "Daily water balance"
  )

  cwd_input <- df |>
    prepend_first_year_spinup(varname_date = "date") |>
    append_cwd_tail_guard(
      varname_wbal = "water_balance_mm",
      varname_date = "date"
    )
  out <- cwd::cwd(
    cwd_input,
    varname_wbal = "water_balance_mm",
    varname_date = "date",
    thresh_drop = 0,
    doy_reset = NA_integer_,
    do_surplus = TRUE
  )

  actual_cwd_rows(out$df) |>
    dplyr::rename(
      cwd_event = iinst,
      cwd_event_day = dday,
      cwd_mm = deficit,
      cws_event = iinst_surplus,
      cws_event_day = dday_surplus,
      cws_mm = surplus
    )
}

cwd_interval_bins <- function(cwd_mm, bin_count = 5L) {
  if (length(bin_count) != 1L ||
      !is.finite(bin_count) ||
      bin_count < 1L ||
      bin_count != as.integer(bin_count)) {
    stop("CWD bin count must be one positive integer.", call. = FALSE)
  }
  bin_count <- as.integer(bin_count)
  bins <- rep(NA_integer_, length(cwd_mm))
  valid <- is.finite(cwd_mm)
  if (!any(valid)) return(bins)

  cwd_range <- range(cwd_mm[valid])
  if (diff(cwd_range) == 0) {
    bins[valid] <- 1L
  } else {
    breaks <- seq(cwd_range[[1]], cwd_range[[2]], length.out = bin_count + 1L)
    bins[valid] <- as.integer(cut(
      cwd_mm[valid],
      breaks = breaks,
      include.lowest = TRUE,
      labels = FALSE
    ))
  }
  bins
}

calibrate_site_pet_scalar <- function(df,
                                      cwd_bin_count = 5L,
                                      le_qc_min = 0.8) {
  assert_has_columns(
    df,
    c("cwd_mm", "pet_pt_mm", "et_obs_mm", "le_qc"),
    "PET calibration data"
  )

  valid <- is.finite(df$cwd_mm) &
    is.finite(df$pet_pt_mm) &
    is.finite(df$et_obs_mm) &
    is.finite(df$le_qc) &
    df$pet_pt_mm > 0 &
    df$et_obs_mm >= 0 &
    df$le_qc >= le_qc_min
  if (sum(valid) < 2L) {
    stop("Too few valid observations to calibrate site PET.", call. = FALSE)
  }

  cwd_bin <- rep(NA_integer_, nrow(df))
  cwd_bin[valid] <- cwd_interval_bins(
    df$cwd_mm[valid],
    bin_count = cwd_bin_count
  )
  calibration_frame <- df |>
    dplyr::mutate(cwd_bin = cwd_bin) |>
    dplyr::filter(!is.na(.data$cwd_bin))
  binned <- calibration_frame |>
    dplyr::group_by(.data$cwd_bin) |>
    dplyr::summarise(
      cwd_min_mm = min(.data$cwd_mm),
      cwd_max_mm = max(.data$cwd_mm),
      median_cwd_mm = stats::median(.data$cwd_mm),
      median_et_obs_mm = stats::median(.data$et_obs_mm),
      median_pet_pt_mm = stats::median(.data$pet_pt_mm),
      n = dplyr::n(),
      .groups = "drop"
    )

  bin_levels <- sort(binned$cwd_bin)
  lowest_bin <- bin_levels[[1]]
  pooled_calibration <- function(max_bin) {
    pooled <- calibration_frame |>
      dplyr::filter(.data$cwd_bin <= max_bin)
    list(
      cwd_min_mm = min(pooled$cwd_mm),
      cwd_max_mm = max(pooled$cwd_mm),
      median_cwd_mm = stats::median(pooled$cwd_mm),
      median_et_obs_mm = stats::median(pooled$et_obs_mm),
      median_pet_pt_mm = stats::median(pooled$pet_pt_mm),
      n = nrow(pooled)
    )
  }
  calculate_scalar <- function(calibration) {
    scalar <- calibration$median_et_obs_mm / calibration$median_pet_pt_mm
    if (!is.finite(scalar) || scalar <= 0) {
      stop(
        "The calibrated site PET scalar is not positive and finite.",
        call. = FALSE
      )
    }
    scalar
  }

  calibration_max_bin <- lowest_bin
  calibration <- pooled_calibration(calibration_max_bin)
  scalar <- calculate_scalar(calibration)
  binned <- binned |>
    dplyr::mutate(
      pet_scalar_before_bin = NA_real_,
      median_pet_site_before_refit_mm = NA_real_,
      pet_scalar_refit = FALSE,
      pet_scalar_after_bin = NA_real_
    )
  initial_index <- which(binned$cwd_bin == lowest_bin)
  binned$pet_scalar_before_bin[initial_index] <- scalar
  binned$median_pet_site_before_refit_mm[initial_index] <-
    scalar * binned$median_pet_pt_mm[initial_index]
  binned$pet_scalar_after_bin[initial_index] <- scalar

  if (length(bin_levels) > 1L) {
    for (cwd_bin_i in bin_levels[-1L]) {
      bin_index <- which(binned$cwd_bin == cwd_bin_i)
      median_scaled_pet <- scalar * binned$median_pet_pt_mm[bin_index]
      binned$pet_scalar_before_bin[bin_index] <- scalar
      binned$median_pet_site_before_refit_mm[bin_index] <- median_scaled_pet

      if (binned$median_et_obs_mm[bin_index] > median_scaled_pet) {
        calibration_max_bin <- cwd_bin_i
        calibration <- pooled_calibration(calibration_max_bin)
        scalar <- calculate_scalar(calibration)
        binned$pet_scalar_refit[bin_index] <- TRUE
      }
      binned$pet_scalar_after_bin[bin_index] <- scalar
    }
  }

  calibration_data <- valid & cwd_bin <= calibration_max_bin
  binned <- binned |>
    dplyr::mutate(
      median_pet_site_mm = scalar * .data$median_pet_pt_mm,
      median_bias_mm = .data$median_pet_site_mm - .data$median_et_obs_mm
    )

  list(
    cwd_bin = cwd_bin,
    calibration_data = calibration_data,
    bin_summary = binned,
    summary = tibble::tibble(
      pet_scalar = scalar,
      pet_calibration_method =
        "sequential_pooled_median_matching_across_cwd_intervals",
      cwd_bins_requested = as.integer(cwd_bin_count),
      cwd_bins_actual = nrow(binned),
      pet_calibration_initial_cwd_bin = lowest_bin,
      pet_calibration_max_cwd_bin = calibration_max_bin,
      n_pet_calibration_bins = sum(bin_levels <= calibration_max_bin),
      n_pet_scalar_refits = sum(binned$pet_scalar_refit),
      pet_calibration_cwd_min_mm = calibration$cwd_min_mm,
      pet_calibration_cwd_max_mm = calibration$cwd_max_mm,
      pet_calibration_median_cwd_mm = calibration$median_cwd_mm,
      pet_calibration_median_et_obs_mm = calibration$median_et_obs_mm,
      pet_calibration_median_pet_pt_mm = calibration$median_pet_pt_mm,
      pet_calibration_median_bias_mm =
        scalar * calibration$median_pet_pt_mm -
        calibration$median_et_obs_mm,
      n_pet_calibration = calibration$n,
      le_qc_min = le_qc_min
    )
  )
}

pcwd_reset_timing <- function(df) {
  assert_has_columns(
    df,
    c("date", "potential_water_balance_mm"),
    "Potential water balance"
  )

  monthly <- df |>
    dplyr::mutate(
      year = lubridate::year(.data$date),
      month = lubridate::month(.data$date)
    ) |>
    dplyr::group_by(.data$year, .data$month) |>
    dplyr::summarise(
      potential_water_balance_mm = sum(.data$potential_water_balance_mm),
      .groups = "drop"
    ) |>
    dplyr::group_by(.data$month) |>
    dplyr::summarise(
      potential_water_balance_mm = mean(.data$potential_water_balance_mm),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(.data$potential_water_balance_mm), .data$month)

  wettest_month <- monthly$month[[1]]
  reset_month <- wettest_month
  reset_doy <- lubridate::yday(as.Date(sprintf("2001-%02d-01", reset_month)))
  list(
    wettest_month = wettest_month,
    reset_month = reset_month,
    reset_doy = reset_doy,
    monthly = monthly
  )
}

calculate_pcwd <- function(df, reset_doy) {
  # FluxDataKit omits 29 February. Map month/day to a non-leap reference year
  # so a fixed `doy_reset` always represents the same calendar day.
  pcwd_input <- df |>
    prepend_first_year_spinup(varname_date = "date") |>
    append_cwd_tail_guard(
      varname_wbal = "potential_water_balance_mm",
      varname_date = "date"
    ) |>
    dplyr::mutate(
      .pcwd_date = as.Date(sprintf(
        "2001-%02d-%02d",
        lubridate::month(.data$date),
        lubridate::mday(.data$date)
      ))
    )
  # cwd ends the current deficit event *after* processing doy_reset, so pass
  # the preceding day to make the requested calendar day the first day of the
  # new PCWD accumulation.
  reset_trigger_doy <- if (reset_doy == 1L) 365L else reset_doy - 1L
  out <- cwd::cwd(
    pcwd_input,
    varname_wbal = "potential_water_balance_mm",
    varname_date = ".pcwd_date",
    thresh_drop = 0,
    doy_reset = reset_trigger_doy
  )
  actual_cwd_rows(out$df)$deficit
}

analyse_fluxnet_site <- function(df,
                                 cwd_bin_count = 5L,
                                 le_qc_min = 0.8) {
  sitename <- unique(df$sitename)
  if (length(sitename) != 1L) {
    stop("Site analysis requires exactly one sitename.", call. = FALSE)
  }

  daily <- df |>
    prepare_fluxnet_water_balance() |>
    calculate_daily_cwd_cws() |>
    dplyr::mutate(
      pet_pt_mm = 86400 * cwd::pet(.data$netrad, .data$temp, .data$patm)
    )
  if (any(!is.finite(daily$pet_pt_mm))) {
    stop("PET could not be calculated for every day at ", sitename, ".", call. = FALSE)
  }

  pet_calibration <- calibrate_site_pet_scalar(
    daily,
    cwd_bin_count = cwd_bin_count,
    le_qc_min = le_qc_min
  )
  calibration_summary <- pet_calibration$summary
  daily <- daily |>
    dplyr::mutate(
      cwd_bin = pet_calibration$cwd_bin,
      pet_calibration_data = pet_calibration$calibration_data,
      pet_site_mm = calibration_summary$pet_scalar[[1]] * .data$pet_pt_mm,
      potential_water_balance_mm = .data$liquid_to_soil_mm - .data$pet_site_mm
    )
  reset <- pcwd_reset_timing(daily)
  daily$pcwd_mm <- calculate_pcwd(daily, reset$reset_doy)

  site_summary <- calibration_summary |>
    dplyr::mutate(
      sitename = sitename,
      date_start = min(daily$date),
      date_end = max(daily$date),
      n_days = nrow(daily),
      latent_heat_variable = "le",
      patm_repaired_days = sum(daily$patm_source == "linear_interpolated"),
      netrad_observed_fraction = mean(daily$netrad_source == "observed"),
      netrad_imputed_days = sum(daily$netrad_source == "knn_imputed"),
      pcwd_wettest_month = reset$wettest_month,
      pcwd_reset_month = reset$reset_month,
      pcwd_reset_doy = reset$reset_doy
    ) |>
    dplyr::select(sitename, dplyr::everything())

  list(
    daily = daily |>
      dplyr::select(
        sitename,
        date,
        year,
        temp,
        patm,
        patm_source,
        le,
        le_qc,
        netrad,
        netrad_source,
        ppfd,
        precipitation_mm,
        rain_mm,
        snow_mm,
        snow_pool_mm,
        liquid_to_soil_mm,
        et_obs_mm,
        water_balance_mm,
        cwd_event,
        cwd_event_day,
        cwd_mm,
        cws_event,
        cws_event_day,
        cws_mm,
        pet_pt_mm,
        cwd_bin,
        pet_calibration_data,
        pet_site_mm,
        potential_water_balance_mm,
        pcwd_mm
    ),
    summary = site_summary,
    cwd_bin_summary = pet_calibration$bin_summary |>
      dplyr::mutate(sitename = sitename, .before = 1L),
    pcwd_monthly_balance = reset$monthly |>
      dplyr::mutate(sitename = sitename, .before = 1L)
  )
}

calculate_site_annual_metrics <- function(daily) {
  assert_has_columns(
    daily,
    c("sitename", "date", "cwd_mm", "pcwd_mm", "cws_mm", "cws_event"),
    "Site daily series"
  )

  calculate_one_site <- function(site_daily) {
    annual <- site_daily |>
      dplyr::mutate(year = lubridate::year(.data$date)) |>
      dplyr::group_by(.data$year) |>
      dplyr::slice_max(.data$cwd_mm, n = 1L, with_ties = FALSE) |>
      dplyr::ungroup() |>
      dplyr::transmute(
        sitename = .data$sitename,
        year = .data$year,
        date_max_cwd = .data$date,
        annual_max_cwd_mm = .data$cwd_mm
      ) |>
      dplyr::left_join(
        site_daily |>
          dplyr::mutate(year = lubridate::year(.data$date)) |>
          dplyr::group_by(.data$year) |>
          dplyr::summarise(
            annual_max_pcwd_mm = max(.data$pcwd_mm),
            .groups = "drop"
          ),
        by = "year"
      )

    surplus_peaks <- site_daily |>
      dplyr::filter(is.finite(.data$cws_event), .data$cws_mm > 0) |>
      dplyr::group_by(.data$cws_event) |>
      dplyr::slice_max(.data$cws_mm, n = 1L, with_ties = FALSE) |>
      dplyr::ungroup() |>
      dplyr::arrange(.data$date) |>
      dplyr::transmute(
        date_max_preceding_cws = .data$date,
        preceding_cws_mm = .data$cws_mm
      )

    peak_index <- findInterval(
      as.numeric(annual$date_max_cwd),
      as.numeric(surplus_peaks$date_max_preceding_cws)
    )
    annual$date_max_preceding_cws <- as.Date(NA)
    annual$preceding_cws_mm <- NA_real_
    has_peak <- peak_index > 0L
    annual$date_max_preceding_cws[has_peak] <-
      surplus_peaks$date_max_preceding_cws[peak_index[has_peak]]
    annual$preceding_cws_mm[has_peak] <-
      surplus_peaks$preceding_cws_mm[peak_index[has_peak]]
    annual
  }

  split(daily, daily$sitename) |>
    lapply(calculate_one_site) |>
    dplyr::bind_rows() |>
    dplyr::arrange(.data$sitename, .data$year)
}

calculate_site_correlations <- function(annual) {
  assert_has_columns(
    annual,
    c(
      "sitename", "annual_max_cwd_mm", "annual_max_pcwd_mm",
      "preceding_cws_mm"
    ),
    "Annual site metrics"
  )

  safe_correlation <- function(x, y) {
    keep <- is.finite(x) & is.finite(y)
    if (sum(keep) < 3L || stats::sd(x[keep]) == 0 || stats::sd(y[keep]) == 0) {
      return(NA_real_)
    }
    stats::cor(x[keep], y[keep])
  }

  annual |>
    dplyr::group_by(.data$sitename) |>
    dplyr::summarise(
      n_years_cwd_pcwd = sum(
        is.finite(.data$annual_max_cwd_mm) &
          is.finite(.data$annual_max_pcwd_mm)
      ),
      correlation_cwd_pcwd = safe_correlation(
        .data$annual_max_cwd_mm,
        .data$annual_max_pcwd_mm
      ),
      n_years_cwd_preceding_cws = sum(
        is.finite(.data$annual_max_cwd_mm) & is.finite(.data$preceding_cws_mm)
      ),
      correlation_cwd_preceding_cws = safe_correlation(
        .data$annual_max_cwd_mm,
        .data$preceding_cws_mm
      ),
      .groups = "drop"
    )
}

run_fluxnet_site_analysis <- function(driver,
                                      site_info,
                                      site_filter,
                                      minimum_years = 10L,
                                      netrad_seed = 123L,
                                      netrad_donor_count = 10000L,
                                      netrad_neighbors = 5L,
                                      cwd_bin_count = 5L,
                                      le_qc_min = 0.8) {
  sites <- select_fluxnet_analysis_sites(
    site_info,
    site_filter,
    minimum_years = minimum_years
  )
  daily_input <- select_fluxnet_driver(driver, sites) |>
    repair_site_pressure() |>
    impute_netrad_knn(
      donor_count = netrad_donor_count,
      neighbors = netrad_neighbors,
      seed = netrad_seed
    )

  results <- split(daily_input, daily_input$sitename) |>
    lapply(
      analyse_fluxnet_site,
      cwd_bin_count = cwd_bin_count,
      le_qc_min = le_qc_min
    )
  daily <- dplyr::bind_rows(lapply(results, `[[`, "daily"))
  annual <- calculate_site_annual_metrics(daily)

  list(
    sites = sites,
    site_summary = dplyr::bind_rows(lapply(results, `[[`, "summary")) |>
      dplyr::left_join(
        sites |>
          dplyr::select(
            sitename,
            lon,
            lat,
            elv,
            koeppen_code,
            igbp_land_use,
            year_start,
            year_end,
            nyears_overlap
          ),
        by = "sitename"
      ),
    daily = daily,
    annual = annual,
    site_correlations = calculate_site_correlations(annual),
    cwd_bin_summaries = dplyr::bind_rows(
      lapply(results, `[[`, "cwd_bin_summary")
    ),
    pcwd_monthly_balance = dplyr::bind_rows(
      lapply(results, `[[`, "pcwd_monthly_balance")
    )
  )
}
