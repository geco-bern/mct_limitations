suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(magrittr))

source(testthat::test_path("..", "..", "R", "get_bal.R"))
source(testthat::test_path("..", "..", "R", "get_et_mm_byilon.R"))
source(testthat::test_path("..", "..", "R", "convert_et.R"))

test_that("daily balance interpolation and endpoint trimming are preserved", {
  input <- tibble::tibble(
    time = as.Date("2020-01-01") + 0:4,
    et_mm = c(NA, 2, NA, 4, NA),
    liquid_to_soil = c(1, 1, NA, 1, 1)
  )

  output <- get_bal(
    input,
    varnam_bal = "bal",
    varnam_et = "et_mm",
    varnam_prec = "liquid_to_soil"
  )

  expect_equal(output$time, as.Date("2020-01-01") + 1:3)
  expect_equal(output$bal, c(-1, -3, -3))
})

test_that("rgeco extraction is adapted to the elevation table contract", {
  filename <- tempfile(fileext = ".nc")
  on.exit(unlink(filename), add = TRUE)

  longitude <- ncdf4::ncdim_def("lon", "degrees_east", c(0, 1))
  latitude <- ncdf4::ncdim_def("lat", "degrees_north", c(10, 11))
  elevation <- ncdf4::ncvar_def(
    "elevation",
    "m",
    list(longitude, latitude),
    missval = -9999
  )
  nc <- ncdf4::nc_create(filename, elevation)
  ncdf4::ncvar_put(nc, elevation, matrix(c(1, 2, 3, 4), nrow = 2))
  ncdf4::nc_close(nc)

  points <- tibble::tibble(lon = c(0, 1), lat = c(10, 11))
  output <- suppressWarnings(extract_elevation(filename, points))

  expect_named(output, c("lon", "lat", "elv"))
  expect_equal(output$elv, c(1, 4))
})

test_that("ET conversion remains numerically stable with rgeco pressure", {
  output <- convert_et(
    et_e = c(1e6, 2e6, NA),
    tc = c(20, 0, 15),
    elv = c(100, 1500, 0)
  )

  expect_equal(output, c(0.2789602, 0.3577301, NA), tolerance = 1e-6)
})
