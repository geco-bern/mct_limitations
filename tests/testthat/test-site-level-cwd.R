source(testthat::test_path("..", "..", "R", "calculate_annual_cwd.R"))
source(testthat::test_path("..", "..", "R", "site_level_cwd.R"))

test_that("analysis-site selection retains eligible long records", {
  site_info <- tibble::tribble(
    ~sitename, ~koeppen_code, ~igbp_land_use, ~lon, ~lat, ~elv,
    "keep-a", "Cfb", "ENF", 7, 47, 500,
    "keep-b", "Csa", "GRA", 8, 46, 400,
    "too-short", "Cfb", "ENF", 6, 48, 600,
    "crop", "Cfb", "CRO", 9, 45, 300,
    "MX-Tes", "Cfb", "ENF", 10, 44, 200
  )
  site_filter <- tibble::tribble(
    ~sitename, ~drop_gpp, ~drop_le, ~nyears_gpp, ~nyears_le,
    ~year_start_gpp, ~year_end_gpp, ~year_start_le, ~year_end_le,
    "keep-a", FALSE, FALSE, 13, 12, 2000, 2012, 2003, 2014,
    "keep-b", FALSE, FALSE, 20, 14, 1999, 2018, 2002, 2015,
    "too-short", FALSE, FALSE, 9, 9, 2001, 2009, 2001, 2009,
    "crop", FALSE, FALSE, 20, 20, 2000, 2019, 2000, 2019,
    "MX-Tes", FALSE, FALSE, 20, 20, 2000, 2019, 2000, 2019
  )

  output <- select_fluxnet_analysis_sites(
    site_info,
    site_filter,
    minimum_years = 10
  )

  expect_equal(output$sitename, c("keep-a", "keep-b"))
  expect_equal(output$year_start, c(2003, 2002))
  expect_equal(output$year_end, c(2012, 2015))
  expect_equal(output$nyears_overlap, c(10, 14))
})

test_that("net-radiation KNN preserves observations and fills targets", {
  input <- tibble::tibble(
    temp = c(0, 10, 20, 0.1, 19.9),
    ppfd = c(0, 1, 2, 0.01, 1.99),
    netrad = c(10, 20, 30, NA, NA)
  )

  output <- impute_netrad_knn(
    input,
    donor_count = 3,
    neighbors = 1,
    seed = 1
  )

  expect_equal(output$netrad[1:3], c(10, 20, 30))
  expect_equal(output$netrad[4:5], c(10, 30))
  expect_equal(
    output$netrad_source,
    c(rep("observed", 3), rep("knn_imputed", 2))
  )
})

test_that("invalid atmospheric pressure is interpolated within site", {
  input <- tibble::tibble(
    sitename = rep("test", 5),
    date = seq(as.Date("2001-01-01"), by = "day", length.out = 5),
    patm = c(100000, -9999, 100200, NA, 100400)
  )

  output <- repair_site_pressure(input)

  expect_equal(output$patm, seq(100000, 100400, by = 100))
  expect_equal(
    output$patm_source,
    c("observed", "linear_interpolated", "observed", "linear_interpolated", "observed")
  )
})

test_that("PET scalar median-matches the lowest CWD bin", {
  cwd_mm <- 1:100
  pet_pt_mm <- rep(c(2, 4), 50)
  et_obs_mm <- pet_pt_mm * ifelse(cwd_mm <= 20, 1.5, 1)
  input <- tibble::tibble(
    cwd_mm = cwd_mm,
    pet_pt_mm = pet_pt_mm,
    et_obs_mm = et_obs_mm,
    le_qc = 1
  )

  output <- calibrate_site_pet_scalar(
    input,
    cwd_bin_count = 5
  )

  expect_equal(output$summary$pet_scalar, 1.5)
  expect_equal(output$summary$cwd_bins_requested, 5)
  expect_equal(output$summary$cwd_bins_actual, 5)
  expect_equal(output$summary$n_pet_calibration, 20)
  expect_equal(output$summary$pet_calibration_max_cwd_bin, 1)
  expect_equal(output$summary$n_pet_scalar_refits, 0)
  expect_equal(output$summary$pet_calibration_median_bias_mm, 0)
  expect_equal(output$bin_summary$median_bias_mm[[1]], 0)
  expect_equal(sum(output$calibration_data), 20)
})

test_that("PET scalar expands sequentially across underpredicted CWD bins", {
  cwd_mm <- 1:100
  pet_pt_mm <- rep(2, 100)
  bin_multiplier <- rep(c(1, 1.5, 2, 1.2, 1.4), each = 20)
  input <- tibble::tibble(
    cwd_mm = cwd_mm,
    pet_pt_mm = pet_pt_mm,
    et_obs_mm = pet_pt_mm * bin_multiplier,
    le_qc = 1
  )

  output <- calibrate_site_pet_scalar(input, cwd_bin_count = 5)

  expect_equal(output$summary$pet_scalar, 1.5)
  expect_equal(output$summary$pet_calibration_max_cwd_bin, 3)
  expect_equal(output$summary$n_pet_calibration_bins, 3)
  expect_equal(output$summary$n_pet_scalar_refits, 2)
  expect_equal(output$summary$n_pet_calibration, 60)
  expect_equal(output$summary$pet_calibration_median_bias_mm, 0)
  expect_equal(output$bin_summary$pet_scalar_refit, c(FALSE, TRUE, TRUE, FALSE, FALSE))
  expect_equal(sum(output$calibration_data), 60)
})

test_that("PET scalar can expand to calibration on every CWD bin", {
  cwd_mm <- 1:100
  pet_pt_mm <- rep(2, 100)
  bin_multiplier <- rep(seq(1, 1.8, by = 0.2), each = 20)
  input <- tibble::tibble(
    cwd_mm = cwd_mm,
    pet_pt_mm = pet_pt_mm,
    et_obs_mm = pet_pt_mm * bin_multiplier,
    le_qc = 1
  )

  output <- calibrate_site_pet_scalar(input, cwd_bin_count = 5)

  expect_equal(output$summary$pet_scalar, 1.4)
  expect_equal(output$summary$pet_calibration_max_cwd_bin, 5)
  expect_equal(output$summary$n_pet_calibration_bins, 5)
  expect_equal(output$summary$n_pet_scalar_refits, 4)
  expect_equal(output$summary$n_pet_calibration, 100)
  expect_equal(output$summary$pet_calibration_median_bias_mm, 0)
})

test_that("CWD bins are equal-width and their count is configurable", {
  expect_equal(cwd_interval_bins(0:10, bin_count = 5), c(
    1L, 1L, 1L, 2L, 2L, 3L, 3L, 4L, 4L, 5L, 5L
  ))
  expect_equal(cwd_interval_bins(rep(0, 4), bin_count = 5), rep(1L, 4))
  expect_error(cwd_interval_bins(0:10, bin_count = 0), "positive integer")
})

test_that("PCWD resets in the wettest balance month", {
  dates <- seq(as.Date("2001-01-01"), as.Date("2002-12-31"), by = "day")
  dates <- dates[format(dates, "%m-%d") != "02-29"]
  input <- tibble::tibble(
    date = dates,
    potential_water_balance_mm = ifelse(lubridate::month(dates) == 11, 2, -1)
  )

  reset <- pcwd_reset_timing(input)

  expect_equal(reset$wettest_month, 11)
  expect_equal(reset$reset_month, 11)
  expect_equal(reset$reset_doy, 305)
  pcwd <- calculate_pcwd(input, reset$reset_doy)
  expect_equal(
    pcwd[lubridate::month(dates) == 11 & lubridate::mday(dates) == 1],
    c(0, 0)
  )
  expect_equal(
    pcwd[lubridate::month(dates) == 1 & lubridate::mday(dates) == 1],
    c(32, 32)
  )
})

test_that("site CWD uses spin-up, has no calendar reset, and removes padding", {
  input <- tibble::tibble(
    date = seq(as.Date("2001-01-01"), by = "day", length.out = 730),
    water_balance_mm = -1
  )

  output <- calculate_daily_cwd_cws(input)

  expect_equal(nrow(output), nrow(input))
  expect_equal(output$date, input$date)
  expect_equal(output$cwd_mm[c(1, 365, 366, 730)], c(366, 730, 731, 1095))
  expect_false(any(output$.cwd_spinup))
  expect_false(any(output$.cwd_tail_guard))
})

test_that("annual site metrics retain preceding surplus events", {
  input <- tibble::tibble(
    sitename = "test",
    date = as.Date(c(
      "2001-01-01", "2001-02-01", "2001-03-01", "2001-04-01",
      "2002-01-01", "2002-02-01", "2002-03-01", "2002-04-01",
      "2003-01-01", "2003-02-01", "2003-03-01", "2003-04-01"
    )),
    cwd_mm = c(0, 2, 5, 1, 0, 3, 8, 2, 0, 4, 10, 3),
    pcwd_mm = c(0, 3, 7, 1, 0, 5, 9, 2, 0, 6, 12, 3),
    cws_event = rep(1:3, each = 4),
    cws_mm = c(1, 4, 2, 0, 2, 6, 1, 0, 3, 9, 2, 0)
  )

  annual <- calculate_site_annual_metrics(input)
  correlations <- calculate_site_correlations(annual)

  expect_equal(annual$annual_max_cwd_mm, c(5, 8, 10))
  expect_equal(annual$annual_max_pcwd_mm, c(7, 9, 12))
  expect_equal(annual$preceding_cws_mm, c(4, 6, 9))
  expect_equal(correlations$n_years_cwd_pcwd, 3)
  expect_equal(correlations$n_years_cwd_preceding_cws, 3)
})

test_that("FLUXNET flux units and snow partition feed daily CWD", {
  dates <- seq(as.Date("2001-01-01"), by = "day", length.out = 365)
  input <- tibble::tibble(
    sitename = "test",
    date = dates,
    year = 2001L,
    temp = rep(c(-2, 5), length.out = 365),
    patm = 101325,
    patm_source = "observed",
    rain = 1 / 86400,
    snow = 0,
    le = 50,
    le_qc = 1,
    netrad = 100,
    netrad_source = "observed",
    ppfd = 0.0005
  )

  balance <- prepare_fluxnet_water_balance(input)
  output <- calculate_daily_cwd_cws(balance)

  expect_equal(balance$precipitation_mm, rep(1, 365))
  expect_equal(balance$rain_mm[input$temp < 0], rep(0, sum(input$temp < 0)))
  expect_equal(balance$snow_mm[input$temp < 0], rep(1, sum(input$temp < 0)))
  expect_equal(nrow(output), 365)
  expect_true(all(output$cwd_mm >= 0))
  expect_true(all(output$cws_mm >= 0))
})
