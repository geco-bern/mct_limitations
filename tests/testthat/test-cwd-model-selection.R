source(testthat::test_path("..", "..", "R", "cwd_model_selection.R"))

synthetic_annual <- function(cwd, pcwd, recharge, site = "test") {
  tibble::tibble(
    sitename = site,
    year = seq_along(cwd) + 1999L,
    annual_max_cwd_mm = cwd,
    annual_max_pcwd_mm = pcwd,
    preceding_cws_mm = recharge
  )
}

test_that("predictions implement the three explicit zero-offset models", {
  pcwd <- c(30, 90, 100)
  recharge <- c(100, 40, 80)

  expect_equal(
    predict_cwd_model("energy", pcwd, recharge, energy_scale_a = 2),
    2 * pcwd
  )
  expect_equal(
    predict_cwd_model(
      "energy_storage", pcwd, recharge,
      energy_scale_a = 2, s0_mm = 120
    ),
    pmin(2 * pcwd, 120)
  )
  expect_equal(
    predict_cwd_model(
      "energy_recharge", pcwd, recharge,
      energy_scale_a = 2, recharge_scale_b = 3
    ),
    pmin(2 * pcwd, 3 * recharge)
  )
  expect_error(
    predict_cwd_model("storage", pcwd, recharge, energy_scale_a = 2),
    "Unknown CWD model"
  )
})

test_that("zero-offset fits recover a non-negative scale", {
  predictor <- c(10, 20, 40, 80)
  fit <- fit_zero_offset_relation(1.5 * predictor, predictor)

  expect_equal(fit$scale, 1.5)
  expect_equal(fit$rss, 0, tolerance = 1e-20)

  decreasing <- fit_zero_offset_relation(rev(predictor), predictor)
  expect_gt(decreasing$scale, 0)
  negative <- fit_zero_offset_relation(-predictor, predictor)
  expect_equal(negative$scale, 0)
})

test_that("storage fits recover a and S0 on the response scale", {
  pcwd <- rep(c(10, 30, 50, 70, 90), 4)
  observed <- pmin(1.5 * pcwd, 75)
  fit <- fit_storage_limiter(observed, pcwd)

  expect_equal(fit$energy_scale_a, 1.5, tolerance = 1e-5)
  expect_equal(fit$s0_mm, 75, tolerance = 1e-5)
  expect_true(fit$storage_active)

  inactive <- fit_storage_limiter(1.5 * pcwd, pcwd)
  expect_identical(inactive$s0_mm, Inf)
  expect_false(inactive$storage_active)
})

test_that("dual-limiter fits recover separate a and b", {
  pcwd <- rep(c(20, 50, 100, 150, 200), 6)
  recharge <- rep(c(200, 20, 80, 40, 180, 60), 5)
  observed <- pmin(1.4 * pcwd, 0.8 * recharge)
  fit <- fit_energy_recharge_limiter(observed, pcwd, recharge)

  expect_equal(fit$energy_scale_a, 1.4, tolerance = 1e-5)
  expect_equal(fit$recharge_scale_b, 0.8, tolerance = 1e-5)
  expect_equal(fit$rss, 0, tolerance = 1e-12)
  expect_true(fit$energy_active)
  expect_true(fit$recharge_active)
})

test_that("leave-one-year-out fits do not use held-out CWD", {
  data <- synthetic_annual(
    cwd = c(10, 20, 30, 100),
    pcwd = c(10, 20, 30, 40),
    recharge = rep(200, 4)
  )
  cv <- cross_validate_cwd_candidates(data) |>
    dplyr::filter(.data$model_id == "energy") |>
    dplyr::arrange(.data$year)

  expect_equal(nrow(cv), 4)
  expect_false(any(cv$predicted_cwd_mm == cv$observed_cwd_mm))
  expect_true(all(is.finite(cv$training_energy_scale_a)))
  expect_true(all(is.na(cv$training_recharge_scale_b)))
})

test_that("dual-null bootstrap returns all three pairwise comparisons", {
  pcwd <- rep(c(20, 40, 80, 120, 160), 4)
  data <- synthetic_annual(
    cwd = pmin(1.4 * pcwd, 90) + rep(c(-2, 1, 0, 2), 5),
    pcwd = pcwd,
    recharge = rep(300, length(pcwd))
  )
  set.seed(42)
  tests <- parametric_bootstrap_lr_tests(data, n_boot = 39, alpha = 0.05)

  expect_equal(tests$pair_id, cwd_model_pairs()$pair_id)
  expect_true(all(tests$successful_bootstrap_a == 39))
  expect_true(all(tests$successful_bootstrap_b == 39))
  expect_true(all(tests$p_against_a > 0 & tests$p_against_a <= 1))
  expect_true(all(tests$p_against_b > 0 & tests$p_against_b <= 1))
  expect_true(all(tests$decision_code %in% c(
    "favours_a", "favours_b", "both_rejected", "indistinguishable"
  )))
})

test_that("the parsimonious energy model is retained when adequate", {
  pcwd <- seq(20, 160, length.out = 24)
  data <- synthetic_annual(
    cwd = 1.5 * pcwd + rep(c(-3, 2, -1, 2), 6),
    pcwd = pcwd,
    recharge = rep(500, length(pcwd))
  )
  result <- select_cwd_models_by_site(
    data,
    n_boot = 99,
    alpha = 0.05,
    seed = 123
  )

  expect_equal(result$site_selection$selected_model_id, "energy")
  expect_equal(result$site_selection$selected_energy_scale_a, 1.5, tolerance = 0.02)
  expect_equal(nrow(result$pairwise_tests), 3)
})

test_that("a recurrent storage cap can defeat the energy model", {
  pcwd <- rep(c(20, 40, 60, 100, 140, 180), 5)
  data <- synthetic_annual(
    cwd = pmin(1.5 * pcwd, 95) + rep(c(-2, 1, 0, 2, -1), 6),
    pcwd = pcwd,
    recharge = rep(c(240, 500, 900, 330, 700), 6)
  )
  result <- select_cwd_models_by_site(
    data,
    n_boot = 99,
    alpha = 0.05,
    seed = 456
  )

  expect_equal(result$site_selection$selected_model_id, "energy_storage")
  expect_equal(result$site_selection$selected_s0_mm, 95, tolerance = 3)
  expect_true(result$site_selection$selected_s0_identifiable)
})

test_that("a recurrent recharge cap can defeat the other candidates", {
  pcwd <- rep(c(40, 100, 160, 220, 130, 190), 5)
  recharge <- rep(c(200, 45, 150, 70, 95, 180), 5)
  data <- synthetic_annual(
    cwd = pmin(1.3 * pcwd, 0.75 * recharge) +
      rep(c(-2, 1, 0, 2, -1), 6),
    pcwd = pcwd,
    recharge = recharge
  )
  result <- select_cwd_models_by_site(
    data,
    n_boot = 99,
    alpha = 0.05,
    seed = 789
  )

  expect_equal(result$site_selection$selected_model_id, "energy_recharge")
  expect_equal(result$site_selection$selected_energy_scale_a, 1.3, tolerance = 0.1)
  expect_equal(result$site_selection$selected_recharge_scale_b, 0.75, tolerance = 0.1)
  expect_equal(result$site_selection$selected_decisive_losses, 0)
})
