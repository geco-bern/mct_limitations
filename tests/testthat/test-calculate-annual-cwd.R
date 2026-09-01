library(dplyr)

source(testthat::test_path("..", "..", "R", "calculate_annual_cwd.R"))

test_that("the first observed year is prepended as a spin-up cycle", {
  balance <- tibble::tibble(
    time = as.Date("2003-01-01") + 0:39,
    bal = seq_len(40)
  )

  extended <- prepend_first_year_spinup(balance)

  expect_equal(nrow(extended), 80L)
  expect_equal(extended$bal, rep(balance$bal, 2L))
  expect_true(all(extended$.cwd_spinup[1:40]))
  expect_false(any(extended$.cwd_spinup[41:80]))
  expect_equal(extended$time[41:80], balance$time)
  expect_equal(max(extended$time[1:40]), min(balance$time) - 1L)
})

test_that("tail guards let cwd close events and are disposable", {
  balance <- tibble::tibble(
    time = as.Date("2003-01-01") + 0:39,
    bal = 1
  )

  guarded <- balance |>
    prepend_first_year_spinup() |>
    append_cwd_tail_guard()

  expect_equal(sum(guarded$.cwd_tail_guard), 3L)
  expect_true(all(tail(guarded$.cwd_tail_guard, 3L)))
  expect_true(min(tail(guarded$time, 3L)) > max(balance$time))
  expect_no_error(
    cwd::cwd(guarded, "bal", "time", do_surplus = TRUE)
  )
})

test_that("a gridcell with no daily deficit has zero annual CWD", {
  balance <- tibble::tibble(
    time = seq(as.Date("2003-01-01"), as.Date("2003-12-31"), by = "day"),
    bal = 1
  )

  result <- calculate_annual_cwd(balance, years = 2003:2004)

  expect_equal(result$status, "no_deficit")
  expect_equal(result$annual_cwd$cwd_mm, c(0, NA))
  expect_equal(result$annual_cwd$n_events, c(0L, 0L))
  expect_true(all(is.na(result$annual_cwd$preceding_surplus_mm)))
  expect_equal(nrow(result$cumulative_surplus), 365L)
  expect_equal(head(result$cumulative_surplus$surplus, 1), 366)
  expect_equal(tail(result$cumulative_surplus$surplus, 1), 730)
  expect_false(any(grepl("^\\.cwd_", names(result$cumulative_surplus))))
})

test_that("spin-up state carries into first-year deficit and surplus", {
  deficit_balance <- tibble::tibble(
    time = as.Date("2003-01-01") + 0:39,
    bal = c(rep(1, 10), rep(0, 20), rep(-1, 10))
  )
  deficit_result <- calculate_annual_cwd(deficit_balance, years = 2003L)
  expect_equal(deficit_result$annual_cwd$cwd_mm, 10)
  expect_equal(
    deficit_result$annual_cwd$date_max_cwd,
    as.Date("2003-02-09")
  )

  surplus_balance <- tibble::tibble(
    time = as.Date("2003-01-01") + 0:39,
    bal = c(rep(-1, 10), rep(0, 20), rep(1.1, 10))
  )
  result <- calculate_annual_cwd(surplus_balance, years = 2003L)

  expect_equal(result$annual_cwd$cwd_mm, 10)
  expect_equal(result$annual_cwd$date_max_cwd, as.Date("2003-01-10"))
  expect_equal(result$annual_cwd$preceding_surplus_mm, 10)
  expect_equal(
    result$annual_cwd$date_max_preceding_surplus,
    as.Date("2003-01-01")
  )
  expect_equal(result$cumulative_surplus$time, surplus_balance$time)
  expect_equal(head(result$cumulative_surplus$surplus, 1), 10)
  expect_true(all(result$cumulative_surplus$time >= as.Date("2003-01-01")))
})

test_that("missing daily balance is represented explicitly", {
  balance <- tibble::tibble(time = as.Date(character()), bal = numeric())

  result <- calculate_annual_cwd(balance, years = 2003:2005)

  expect_equal(result$status, "insufficient_daily_balance")
  expect_equal(result$annual_cwd$year, 2003:2005)
  expect_true(all(is.na(result$annual_cwd$cwd_mm)))
  expect_equal(nrow(result$cumulative_surplus), 0L)
})

test_that("daily deficit and surplus values come from cwd::cwd", {
  balance <- tibble::tibble(
    time = as.Date("2003-01-01") + 0:39,
    bal = c(rep(-1, 10), rep(0, 20), rep(1.1, 10))
  )
  cwd_input <- balance |>
    prepend_first_year_spinup() |>
    append_cwd_tail_guard()
  package_output <- cwd::cwd(
    cwd_input,
    varname_wbal = "bal",
    varname_date = "time",
    thresh_drop = 0,
    do_surplus = TRUE
  )
  package_actual <- actual_cwd_rows(package_output$df)

  result <- calculate_annual_cwd(balance, years = 2003L)

  expect_equal(
    result$cumulative_surplus$surplus,
    package_actual$surplus
  )
  expect_equal(
    result$annual_cwd$cwd_mm,
    max(package_actual$deficit)
  )
})

test_that("annual CWD is paired with the latest preceding surplus maximum", {
  annual <- tibble::tibble(
    year = 2003:2004,
    date_max_cwd = as.Date(c("2003-06-01", "2004-07-01")),
    cwd_mm = c(50, 80),
    n_events = c(2L, 1L)
  )
  surplus_events <- tibble::tibble(
    date_max_surplus = as.Date(c("2003-02-01", "2004-01-01", "2004-08-01")),
    max_surplus = c(100, 200, 300)
  )

  paired <- associate_preceding_surplus(annual, surplus_events)

  expect_equal(paired$preceding_surplus_mm, c(100, 200))
  expect_equal(
    paired$date_max_preceding_surplus,
    as.Date(c("2003-02-01", "2004-01-01"))
  )
  expect_equal(paired$preceding_surplus_year, c(2003L, 2004L))
})

test_that("annual CWD is calculated without a fitted model", {
  balance <- tibble::tibble(
    time = seq(as.Date("2003-01-01"), as.Date("2003-12-31"), by = "day"),
    bal = rep(c(-2, -3, 10, 1, 1), length.out = 365)
  )

  result <- calculate_annual_cwd(balance, years = 2003L)

  expect_named(
    result,
    c("annual_cwd", "cumulative_surplus", "status")
  )
  expect_equal(result$status, "ok")
  expect_equal(result$annual_cwd$cwd_mm, 5)
  expect_named(
    result$annual_cwd,
    c(
      "year", "date_max_cwd", "cwd_mm", "date_max_preceding_surplus",
      "preceding_surplus_year", "preceding_surplus_mm", "n_events"
    )
  )
  expect_false(any(c("mod", "df_return", "return_level") %in% names(result)))

  compact <- calculate_annual_cwd(
    balance,
    years = 2003L,
    return_cumulative_surplus = FALSE
  )
  expect_null(compact$cumulative_surplus)
  expect_equal(compact$annual_cwd, result$annual_cwd)
})
