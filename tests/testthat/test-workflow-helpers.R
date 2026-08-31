source(testthat::test_path("..", "..", "R", "workflow_helpers.R"))
source(testthat::test_path("..", "..", "R", "map_netcdf_to_tidy.R"))

test_that("work is split into stable contiguous chunks", {
  expect_equal(work_for_chunk(1:10, 1, 3), 1:4)
  expect_equal(work_for_chunk(1:10, 2, 3), 5:8)
  expect_equal(work_for_chunk(1:10, 3, 3), 9:10)
})

test_that("longitude specifications accept values and ranges", {
  expect_equal(parse_index_spec("5,2-4,5"), 2:5)
  expect_null(parse_index_spec(""))
  expect_error(parse_index_spec("x"), "Invalid MCT_ILON")
})

test_that("parallel task failures make the checkpoint fail", {
  expect_error(
    run_parallel(1:3, function(x) if (x == 2) stop("bad item") else x, cores = 1),
    "1 of 3 parallel tasks failed"
  )
})

test_that("atomic RData writes preserve the requested object name", {
  output <- tempfile(fileext = ".RData")
  on.exit(unlink(output), add = TRUE)

  write_rdata_atomic(data.frame(x = 1), "df", output)
  loaded <- new.env(parent = emptyenv())
  expect_equal(load(output, envir = loaded), "df")
  expect_equal(loaded$df$x, 1)

  write_rdata_atomic(data.frame(x = 2), "df", output)
  load(output, envir = loaded)
  expect_equal(loaded$df$x, 2)
})

test_that("map2tidy time output is normalised to the legacy contract", {
  input <- data.frame(
    lon = 7,
    lat = 47,
    data = I(list(data.frame(datetime = c("2020-01-01", "2020-01-02"), x = 1:2)))
  )
  output <- normalise_tidy_time(input)

  expect_named(output$data[[1]], c("time", "x"))
  expect_s3_class(output$data[[1]]$time, "Date")
})
