source(testthat::test_path("..", "..", "R", "input_config.R"))

default_config_path <- testthat::test_path(
  "..", "..", "config", "input_sources.R"
)

test_that("default climate inputs produce a stable run identifier", {
  config <- read_input_config(default_config_path)

  expected_id <- "et-alexi__prec-mswep-v3.16-past__temp-era5-land"
  expect_equal(climate_run_id(config), expected_id)
  expect_equal(
    climate_output_path("data/result.rds", config),
    paste0("data/result__", expected_id, ".rds")
  )
  expect_equal(
    climate_output_path(
      paste0("data/result__", expected_id, ".rds"),
      config
    ),
    paste0("data/result__", expected_id, ".rds")
  )
})

test_that("default precipitation uses MSWEP total precipitation", {
  config <- read_input_config(default_config_path)

  expect_equal(config$precipitation$form, "total")
  expect_null(config$precipitation$snow)
  expect_equal(config$precipitation$rain$variable, "precipitation")
  expect_equal(config$temperature$id, "era5-land")
})

test_that("configured grids drive longitude lookup", {
  config <- read_input_config(default_config_path)

  expect_length(
    source_grid_values(config$et$source, "longitude"),
    config$et$source$grid$longitude_count
  )
  expect_equal(
    nearest_source_index(
      1L,
      config$et$source,
      config$precipitation$rain
    ),
    1L
  )
})

test_that("snow simulation inputs must share a grid", {
  config <- dget(default_config_path)
  config$temperature$source$grid$longitude_step <- 1
  path <- tempfile(fileext = ".R")
  on.exit(unlink(path), add = TRUE)
  dput(config, path)

  expect_error(read_input_config(path), "must use the same grid")
})

test_that("separate precipitation requires a snowfall source", {
  config <- dget(default_config_path)
  config$precipitation$form <- "separate"
  path <- tempfile(fileext = ".R")
  on.exit(unlink(path), add = TRUE)
  dput(config, path)

  expect_error(read_input_config(path), "precipitation[$]snow")
})

test_that("precipitation form is validated", {
  config <- dget(default_config_path)
  config$precipitation$form <- "mixed"
  path <- tempfile(fileext = ".R")
  on.exit(unlink(path), add = TRUE)
  dput(config, path)

  expect_error(read_input_config(path), "either 'separate' or 'total'")
})

test_that("input identifiers are safe for filenames", {
  expect_equal(normalise_input_id("ERA5 Land", "id"), "era5-land")
  expect_error(normalise_input_id("***", "id"), "filename-safe")
})

test_that("configured ET unit conversions preserve the analysis contract", {
  config <- read_input_config(default_config_path)
  expect_equal(
    et_to_w_m2(1, config$et$source),
    1e6 / 86400
  )

  source <- config$et$source
  source$conversion <- "identity_mm_day"
  source$scale <- 1
  source$offset <- 0
  expect_equal(et_to_w_m2(1, source), 2.45e6 / 86400)
})
