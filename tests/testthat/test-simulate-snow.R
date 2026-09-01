source(testthat::test_path("..", "..", "R", "simulate_snow.R"))

test_that("total precipitation is partitioned before snowmelt", {
  input <- data.frame(
    temp = c(rep(-2, 365), 2, 2),
    prec = c(rep(0, 364), 10, 0, 0)
  )

  result <- simulate_snow(input)

  expect_equal(result$liquid_to_soil[[365]], 0)
  expect_equal(result$snow_pool[[365]], 20)
  expect_equal(result$liquid_to_soil[[366]], 1)
  expect_equal(result$snow_pool[[367]], 18)
})
