# Calculate annual maximum cumulative water deficit and its preceding
# cumulative water surplus with cwd::cwd(). This file only adapts package
# output to the workflow-specific spin-up and annual output definitions.

prepend_first_year_spinup <- function(df, varname_date = "time") {
  if (!nrow(df)) {
    df$.cwd_spinup <- logical()
    return(df)
  }

  df <- df[order(df[[varname_date]]), , drop = FALSE]
  first_year <- min(lubridate::year(df[[varname_date]]))
  first_year_data <- df[
    lubridate::year(df[[varname_date]]) == first_year,
    ,
    drop = FALSE
  ]
  n_spinup <- nrow(first_year_data)
  first_actual_date <- min(df[[varname_date]])

  spinup <- first_year_data
  spinup[[varname_date]] <- seq(
    from = first_actual_date - n_spinup,
    by = "day",
    length.out = n_spinup
  )
  spinup$.cwd_spinup <- TRUE
  df$.cwd_spinup <- FALSE

  dplyr::bind_rows(spinup, df)
}

append_cwd_tail_guard <- function(df,
                                  varname_wbal = "bal",
                                  varname_date = "time") {
  if (!nrow(df)) {
    df$.cwd_tail_guard <- logical()
    return(df)
  }

  # cwd::cwd(do_surplus = TRUE) requires at least one deficit event and a
  # terminating row after the final surplus event. These disposable rows first
  # close any active deficit, then close any active surplus and create a
  # synthetic deficit event, followed by the package's required final guard.
  guard_scale <- sum(abs(df[[varname_wbal]])) + 1
  if (!is.finite(guard_scale) || 2 * guard_scale > .Machine$double.xmax) {
    stop(
      "Daily balance is too large to construct a CWD tail guard.",
      call. = FALSE
    )
  }

  guard <- df[rep(nrow(df), 3L), , drop = FALSE]
  guard_year <- max(lubridate::year(df[[varname_date]])) + 2L
  guard[[varname_date]] <- as.Date(paste0(guard_year, "-01-01")) + 0:2
  guard[[varname_wbal]] <- c(guard_scale, -2 * guard_scale, 0)
  guard$.cwd_spinup <- FALSE
  guard$.cwd_tail_guard <- TRUE
  df$.cwd_tail_guard <- FALSE

  dplyr::bind_rows(df, guard)
}

actual_cwd_rows <- function(df) {
  df |>
    dplyr::filter(!.cwd_spinup, !.cwd_tail_guard)
}

annual_cwd_from_cwd <- function(out_cwd, years, varname_date) {
  daily <- actual_cwd_rows(out_cwd$df)
  annual <- tibble::tibble(year = sort(unique(as.integer(years))))

  if (!nrow(daily)) {
    return(annual |>
      dplyr::mutate(
        date_max_cwd = as.Date(NA),
        cwd_mm = NA_real_,
        n_events = 0L
      ))
  }

  daily <- daily |>
    dplyr::mutate(year = lubridate::year(.data[[varname_date]]))
  annual_values <- lapply(split(daily, daily$year), function(year_data) {
    idx_local <- which.max(year_data$deficit)
    cwd_mm <- year_data$deficit[[idx_local]]
    has_cwd <- is.finite(cwd_mm) && cwd_mm > 0
    tibble::tibble(
      year = year_data$year[[1]],
      date_max_cwd = if (has_cwd) {
        year_data[[varname_date]][idx_local]
      } else {
        year_data[[varname_date]][NA_integer_]
      },
      cwd_mm = cwd_mm,
      n_events = dplyr::n_distinct(stats::na.omit(year_data$iinst))
    )
  }) |>
    dplyr::bind_rows()

  annual |>
    dplyr::left_join(annual_values, by = "year") |>
    dplyr::mutate(n_events = dplyr::coalesce(n_events, 0L)) |>
    dplyr::select(year, date_max_cwd, cwd_mm, n_events)
}

surplus_events_from_daily <- function(df, varname_date = "time") {
  if (!nrow(df)) {
    return(tibble::tibble(
      max_surplus = numeric(),
      date_max_surplus = df[[varname_date]][integer()]
    ))
  }

  df |>
    dplyr::filter(!is.na(iinst_surplus), surplus > 0) |>
    dplyr::group_by(iinst_surplus) |>
    dplyr::slice_max(surplus, n = 1L, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::transmute(
      max_surplus = surplus,
      date_max_surplus = .data[[varname_date]]
    )
}

associate_preceding_surplus <- function(annual_cwd, surplus_events) {
  n <- nrow(annual_cwd)
  preceding_event <- rep(NA_integer_, n)

  if (nrow(surplus_events)) {
    surplus_dates <- as.numeric(surplus_events$date_max_surplus)
    cwd_dates <- as.numeric(annual_cwd$date_max_cwd)
    preceding_event <- vapply(cwd_dates, function(cwd_date) {
      if (is.na(cwd_date)) return(NA_integer_)
      candidates <- which(surplus_dates <= cwd_date)
      if (!length(candidates)) return(NA_integer_)
      candidates[[which.max(surplus_dates[candidates])]]
    }, integer(1))
  }

  date_max_preceding_surplus <- annual_cwd$date_max_cwd
  date_max_preceding_surplus[] <- NA
  preceding_surplus_mm <- rep(NA_real_, n)
  matched <- !is.na(preceding_event)
  if (any(matched)) {
    date_max_preceding_surplus[matched] <-
      surplus_events$date_max_surplus[preceding_event[matched]]
    preceding_surplus_mm[matched] <-
      surplus_events$max_surplus[preceding_event[matched]]
  }

  annual_cwd |>
    dplyr::mutate(
      date_max_preceding_surplus = date_max_preceding_surplus,
      preceding_surplus_year = lubridate::year(date_max_preceding_surplus),
      preceding_surplus_mm = preceding_surplus_mm
    ) |>
    dplyr::select(
      year,
      date_max_cwd,
      cwd_mm,
      date_max_preceding_surplus,
      preceding_surplus_year,
      preceding_surplus_mm,
      n_events
    )
}

calculate_annual_cwd <- function(df,
                                 varname_wbal = "bal",
                                 varname_date = "time",
                                 years = NULL,
                                 thresh_drop = 0.0,
                                 return_cumulative_surplus = TRUE) {
  required <- c(varname_wbal, varname_date)
  missing <- setdiff(required, names(df))
  if (length(missing)) {
    stop(
      "Daily balance is missing: ", paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  if (!requireNamespace("cwd", quietly = TRUE)) {
    stop("Package 'cwd' is required for annual CWD calculation.", call. = FALSE)
  }

  valid <- is.finite(df[[varname_wbal]]) & !is.na(df[[varname_date]])
  df <- df[valid, , drop = FALSE]
  observed_years <- sort(unique(lubridate::year(df[[varname_date]])))
  if (is.null(years)) years <- observed_years
  years <- sort(unique(as.integer(years)))

  empty_annual <- tibble::tibble(
    year = years,
    date_max_cwd = as.Date(NA),
    cwd_mm = NA_real_,
    n_events = 0L
  )
  empty_surplus <- tibble::tibble(
    !!varname_date := df[[varname_date]],
    iinst_surplus = rep(NA_real_, nrow(df)),
    dday_surplus = rep(NA_real_, nrow(df)),
    surplus = rep(NA_real_, nrow(df))
  )
  result <- function(annual_cwd, cumulative_surplus, status) {
    list(
      annual_cwd = annual_cwd,
      cumulative_surplus = if (return_cumulative_surplus) {
        cumulative_surplus
      } else {
        NULL
      },
      status = status
    )
  }

  if (nrow(df) < 30L) {
    return(result(
      associate_preceding_surplus(empty_annual, tibble::tibble()),
      empty_surplus,
      "insufficient_daily_balance"
    ))
  }

  cwd_input <- df |>
    prepend_first_year_spinup(varname_date) |>
    append_cwd_tail_guard(varname_wbal, varname_date)
  out_cwd <- cwd::cwd(
    cwd_input,
    varname_wbal = varname_wbal,
    varname_date = varname_date,
    thresh_drop = thresh_drop,
    do_surplus = TRUE
  )

  daily_actual <- actual_cwd_rows(out_cwd$df)
  annual_cwd <- annual_cwd_from_cwd(out_cwd, years, varname_date)
  cumulative_surplus <- daily_actual |>
    dplyr::select(
      dplyr::all_of(varname_date),
      iinst_surplus,
      dday_surplus,
      surplus
    )
  surplus_events <- surplus_events_from_daily(
    cumulative_surplus,
    varname_date
  )
  annual_cwd <- associate_preceding_surplus(annual_cwd, surplus_events)

  status <- if (!any(df[[varname_wbal]] < 0)) {
    "no_deficit"
  } else if (!any(annual_cwd$cwd_mm > 0, na.rm = TRUE)) {
    "no_cwd_events"
  } else {
    "ok"
  }

  result(annual_cwd, cumulative_surplus, status)
}
