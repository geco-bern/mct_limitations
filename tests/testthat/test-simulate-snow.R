source(testthat::test_path("..", "..", "R", "simulate_snow2.R"))

test_that("total precipitation is partitioned before snowmelt", {
  input <- data.frame(
    temp = c(rep(-2, 365), 2, 2),
    prec = c(rep(0, 364), 10, 0, 0)
  )

  result <- simulate_snow(input, precipitation_form = "total")

  expect_equal(result$liquid_to_soil[[365]], 0)
  expect_equal(result$snow_pool[[365]], 20)
  expect_equal(result$liquid_to_soil[[366]], 1)
  expect_equal(result$snow_pool[[367]], 18)
})

test_that("separate rain and snow retains the existing behavior", {
  input <- data.frame(
    temp = rep(2, 367),
    prec = c(rep(0, 365), 3, 0),
    snow = c(rep(0, 365), 0, 2)
  )

  result <- simulate_snow(input, precipitation_form = "separate")

  expect_equal(result$liquid_to_soil[[366]], 3)
  expect_equal(result$snow_pool[[366]], 0)
  expect_equal(result$liquid_to_soil[[367]], 0)
  expect_equal(result$snow_pool[[367]], 2)
})
