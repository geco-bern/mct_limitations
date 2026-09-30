cwd_model_definitions <- function() {
  tibble::tribble(
    ~model_id, ~model_label, ~model_formula, ~mechanism_count,
    ~fitted_parameter_count,
    "energy", "Energy limited", "D(t) = a * P(t)", 1L, 1L,
    "energy_storage", "Energy + storage limited",
    "D(t) = min(a * P(t), S0)", 2L, 2L,
    "energy_recharge", "Energy + recharge limited",
    "D(t) = min(a * P(t), b * R(t-1))", 2L, 2L
  )
}

cwd_model_pairs <- function() {
  tibble::tribble(
    ~pair_id, ~model_a_id, ~model_b_id, ~pair_label, ~comparison_type,
    "energy__energy_storage", "energy", "energy_storage",
    "Energy vs storage cap", "Boundary-nested",
    "energy__energy_recharge", "energy", "energy_recharge",
    "Energy vs recharge cap", "Boundary-nested",
    "energy_recharge__energy_storage", "energy_recharge", "energy_storage",
    "Recharge cap vs storage cap", "Non-nested"
  )
}

assert_cwd_model_data <- function(data) {
  required <- c(
    "sitename", "year", "annual_max_cwd_mm", "annual_max_pcwd_mm",
    "preceding_cws_mm"
  )
  missing <- setdiff(required, names(data))
  if (length(missing)) {
    stop(
      "Annual CWD model data are missing: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  if (anyDuplicated(data[c("sitename", "year")])) {
    stop("Annual CWD model data contain duplicate site-years.", call. = FALSE)
  }
  invisible(data)
}

predict_cwd_model <- function(model_id,
                              pcwd_mm,
                              preceding_cws_mm,
                              energy_scale_a,
                              recharge_scale_b = NA_real_,
                              s0_mm = NA_real_) {
  definitions <- cwd_model_definitions()
  if (length(model_id) != 1L || !(model_id %in% definitions$model_id)) {
    stop("Unknown CWD model: ", paste(model_id, collapse = ", "), call. = FALSE)
  }
  if (length(pcwd_mm) != length(preceding_cws_mm)) {
    stop("PCWD and preceding CWS must have the same length.", call. = FALSE)
  }
  if (length(energy_scale_a) != 1L || is.na(energy_scale_a) ||
      energy_scale_a < 0) {
    stop("A non-negative energy scale a is required.", call. = FALSE)
  }
  energy_term <- if (is.infinite(energy_scale_a)) {
    rep(Inf, length(pcwd_mm))
  } else {
    energy_scale_a * pcwd_mm
  }

  if (model_id == "energy") {
    if (!is.finite(energy_scale_a)) {
      stop("The energy model requires a finite scale a.", call. = FALSE)
    }
    return(energy_term)
  }
  if (model_id == "energy_storage") {
    if (!is.finite(energy_scale_a) || length(s0_mm) != 1L ||
        is.na(s0_mm) || s0_mm < 0) {
      stop("The storage model requires finite a and non-negative S0.", call. = FALSE)
    }
    return(pmin(energy_term, s0_mm))
  }
  if (length(recharge_scale_b) != 1L || is.na(recharge_scale_b) ||
      recharge_scale_b < 0) {
    stop("A non-negative recharge scale b is required.", call. = FALSE)
  }
  recharge_term <- if (is.infinite(recharge_scale_b)) {
    rep(Inf, length(preceding_cws_mm))
  } else {
    recharge_scale_b * preceding_cws_mm
  }
  pmin(energy_term, recharge_term)
}

fit_zero_offset_relation <- function(observed_cwd_mm, predictor_mm) {
  if (!length(observed_cwd_mm) ||
      length(observed_cwd_mm) != length(predictor_mm) ||
      any(!is.finite(observed_cwd_mm)) ||
      any(!is.finite(predictor_mm)) ||
      any(predictor_mm < 0)) {
    stop("Zero-offset fitting requires paired finite non-negative values.", call. = FALSE)
  }
  denominator <- sum(predictor_mm^2)
  tolerance <- sqrt(.Machine$double.eps) * max(1, denominator)
  scale <- if (denominator <= tolerance) {
    0
  } else {
    max(0, sum(observed_cwd_mm * predictor_mm) / denominator)
  }
  prediction <- scale * predictor_mm
  list(
    scale = scale,
    prediction = prediction,
    residual = observed_cwd_mm - prediction,
    rss = sum((observed_cwd_mm - prediction)^2),
    predictor_has_variation = denominator > tolerance
  )
}

profile_interval_candidates <- function(objective, breaks) {
  breaks <- sort(unique(breaks[is.finite(breaks) & breaks >= 0]))
  candidates <- breaks
  if (length(breaks) > 1L) {
    for (index in seq_len(length(breaks) - 1L)) {
      lower <- breaks[[index]]
      upper <- breaks[[index + 1L]]
      if (upper > lower) {
        optimized <- stats::optimize(
          objective,
          interval = c(lower, upper),
          tol = max(1e-8, (upper - lower) * 1e-9)
        )
        candidates <- c(candidates, optimized$minimum)
      }
    }
  }
  sort(unique(candidates))
}

fit_storage_limiter <- function(observed_cwd_mm, pcwd_mm) {
  if (length(observed_cwd_mm) != length(pcwd_mm) ||
      any(!is.finite(observed_cwd_mm)) ||
      any(!is.finite(pcwd_mm)) || any(pcwd_mm < 0)) {
    stop("Storage-limiter fitting requires paired finite non-negative values.", call. = FALSE)
  }
  energy_fit <- fit_zero_offset_relation(observed_cwd_mm, pcwd_mm)
  objective <- function(pcwd_cap_mm) {
    fit_zero_offset_relation(
      observed_cwd_mm,
      pmin(pcwd_mm, pcwd_cap_mm)
    )$rss
  }
  candidates <- profile_interval_candidates(objective, c(0, pcwd_mm))
  candidate_rss <- vapply(candidates, objective, numeric(1))
  best_rss <- min(candidate_rss)
  tolerance <- sqrt(.Machine$double.eps) * max(1, best_rss, energy_fit$rss)

  if (energy_fit$rss <= best_rss + tolerance) {
    return(list(
      energy_scale_a = energy_fit$scale,
      s0_mm = Inf,
      prediction = energy_fit$prediction,
      rss = energy_fit$rss,
      storage_active = FALSE,
      s0_identifiable = FALSE
    ))
  }
  pcwd_cap_mm <- min(candidates[candidate_rss <= best_rss + tolerance])
  capped_fit <- fit_zero_offset_relation(
    observed_cwd_mm,
    pmin(pcwd_mm, pcwd_cap_mm)
  )
  s0_mm <- capped_fit$scale * pcwd_cap_mm
  list(
    energy_scale_a = capped_fit$scale,
    s0_mm = s0_mm,
    prediction = pmin(capped_fit$scale * pcwd_mm, s0_mm),
    rss = capped_fit$rss,
    storage_active = TRUE,
    s0_identifiable = capped_fit$scale > 0 &&
      capped_fit$predictor_has_variation
  )
}

fit_energy_recharge_limiter <- function(observed_cwd_mm,
                                        pcwd_mm,
                                        preceding_cws_mm) {
  if (length(observed_cwd_mm) != length(pcwd_mm) ||
      length(observed_cwd_mm) != length(preceding_cws_mm) ||
      any(!is.finite(c(observed_cwd_mm, pcwd_mm, preceding_cws_mm))) ||
      any(pcwd_mm < 0) || any(preceding_cws_mm < 0)) {
    stop("Dual-limiter fitting requires paired finite non-negative values.", call. = FALSE)
  }
  energy_fit <- fit_zero_offset_relation(observed_cwd_mm, pcwd_mm)
  recharge_fit <- fit_zero_offset_relation(observed_cwd_mm, preceding_cws_mm)
  positive_recharge <- preceding_cws_mm > 0
  ratios <- pcwd_mm[positive_recharge] / preceding_cws_mm[positive_recharge]
  finite_ratios <- sort(unique(ratios[is.finite(ratios) & ratios >= 0]))

  objective <- function(scale_ratio) {
    if (scale_ratio <= 0) {
      return(recharge_fit$rss)
    }
    predictor <- pmin(pcwd_mm, scale_ratio * preceding_cws_mm)
    fit_zero_offset_relation(observed_cwd_mm, predictor)$rss
  }
  candidates <- profile_interval_candidates(objective, c(0, finite_ratios))
  candidate_rss <- if (length(candidates)) {
    vapply(candidates, objective, numeric(1))
  } else {
    numeric()
  }
  interior_best <- if (length(candidate_rss)) min(candidate_rss) else Inf
  best_rss <- min(energy_fit$rss, recharge_fit$rss, interior_best)
  tolerance <- sqrt(.Machine$double.eps) *
    max(1, energy_fit$rss, recharge_fit$rss, best_rss)

  # Prefer a boundary representation when the additional limiter makes no
  # likelihood improvement. Infinite opposite scales denote inactive limits.
  if (energy_fit$rss <= best_rss + tolerance) {
    return(list(
      energy_scale_a = energy_fit$scale,
      recharge_scale_b = Inf,
      prediction = energy_fit$prediction,
      rss = energy_fit$rss,
      energy_active = TRUE,
      recharge_active = FALSE,
      energy_scale_identifiable = TRUE,
      recharge_scale_identifiable = FALSE
    ))
  }
  if (recharge_fit$rss <= best_rss + tolerance) {
    return(list(
      energy_scale_a = Inf,
      recharge_scale_b = recharge_fit$scale,
      prediction = recharge_fit$prediction,
      rss = recharge_fit$rss,
      energy_active = FALSE,
      recharge_active = TRUE,
      energy_scale_identifiable = FALSE,
      recharge_scale_identifiable = TRUE
    ))
  }

  scale_ratio <- min(candidates[candidate_rss <= best_rss + tolerance])
  limited_predictor <- pmin(pcwd_mm, scale_ratio * preceding_cws_mm)
  profiled_fit <- fit_zero_offset_relation(observed_cwd_mm, limited_predictor)
  energy_scale_a <- profiled_fit$scale
  recharge_scale_b <- energy_scale_a * scale_ratio
  prediction <- pmin(
    energy_scale_a * pcwd_mm,
    recharge_scale_b * preceding_cws_mm
  )
  list(
    energy_scale_a = energy_scale_a,
    recharge_scale_b = recharge_scale_b,
    prediction = prediction,
    rss = sum((observed_cwd_mm - prediction)^2),
    energy_active = any(
      energy_scale_a * pcwd_mm <=
        recharge_scale_b * preceding_cws_mm + sqrt(.Machine$double.eps)
    ),
    recharge_active = any(
      recharge_scale_b * preceding_cws_mm <=
        energy_scale_a * pcwd_mm + sqrt(.Machine$double.eps)
    ),
    energy_scale_identifiable = energy_scale_a > 0,
    recharge_scale_identifiable = recharge_scale_b > 0
  )
}

fit_cwd_candidate <- function(data, model_id) {
  assert_cwd_model_data(data)
  definitions <- cwd_model_definitions()
  definition <- definitions[definitions$model_id == model_id, , drop = FALSE]
  if (!nrow(definition)) {
    stop("Unknown CWD model: ", model_id, call. = FALSE)
  }
  observed <- data$annual_max_cwd_mm
  pcwd <- data$annual_max_pcwd_mm
  recharge <- data$preceding_cws_mm
  if (any(!is.finite(c(observed, pcwd, recharge))) ||
      any(c(pcwd, recharge) < 0)) {
    stop("CWD model fitting requires complete non-negative annual predictors.", call. = FALSE)
  }

  if (model_id == "energy") {
    raw_fit <- fit_zero_offset_relation(observed, pcwd)
    energy_scale_a <- raw_fit$scale
    recharge_scale_b <- NA_real_
    s0_mm <- NA_real_
    storage_active <- FALSE
    recharge_active <- FALSE
    s0_identifiable <- FALSE
    energy_scale_identifiable <- raw_fit$predictor_has_variation
    recharge_scale_identifiable <- FALSE
  } else if (model_id == "energy_storage") {
    raw_fit <- fit_storage_limiter(observed, pcwd)
    energy_scale_a <- raw_fit$energy_scale_a
    recharge_scale_b <- NA_real_
    s0_mm <- raw_fit$s0_mm
    storage_active <- raw_fit$storage_active
    recharge_active <- FALSE
    s0_identifiable <- raw_fit$s0_identifiable
    energy_scale_identifiable <- is.finite(energy_scale_a) && energy_scale_a > 0
    recharge_scale_identifiable <- FALSE
  } else {
    raw_fit <- fit_energy_recharge_limiter(observed, pcwd, recharge)
    energy_scale_a <- raw_fit$energy_scale_a
    recharge_scale_b <- raw_fit$recharge_scale_b
    s0_mm <- NA_real_
    storage_active <- FALSE
    recharge_active <- raw_fit$recharge_active
    s0_identifiable <- FALSE
    energy_scale_identifiable <- raw_fit$energy_scale_identifiable
    recharge_scale_identifiable <- raw_fit$recharge_scale_identifiable
  }
  prediction <- predict_cwd_model(
    model_id,
    pcwd,
    recharge,
    energy_scale_a = energy_scale_a,
    recharge_scale_b = recharge_scale_b,
    s0_mm = s0_mm
  )
  residual <- observed - prediction
  rss <- sum(residual^2)
  n <- length(observed)
  sigma2_ml <- max(rss / n, .Machine$double.eps)
  log_likelihood <- -0.5 * n * (log(2 * pi * sigma2_ml) + 1)
  likelihood_parameters <- definition$fitted_parameter_count[[1]] + 1L
  aic <- -2 * log_likelihood + 2 * likelihood_parameters
  aicc <- if (n > likelihood_parameters + 1L) {
    aic + 2 * likelihood_parameters * (likelihood_parameters + 1) /
      (n - likelihood_parameters - 1)
  } else {
    Inf
  }

  list(
    model_id = model_id,
    energy_scale_a = energy_scale_a,
    recharge_scale_b = recharge_scale_b,
    s0_mm = s0_mm,
    error_sigma_ml_mm = sqrt(sigma2_ml),
    storage_active = storage_active,
    recharge_active = recharge_active,
    s0_identifiable = s0_identifiable,
    energy_scale_identifiable = energy_scale_identifiable,
    recharge_scale_identifiable = recharge_scale_identifiable,
    prediction = prediction,
    residual = residual,
    rss = rss,
    rmse = sqrt(mean(residual^2)),
    mae = mean(abs(residual)),
    log_likelihood = log_likelihood,
    aic = aic,
    aicc = aicc,
    n = n
  )
}

cross_validate_cwd_candidates <- function(data) {
  assert_cwd_model_data(data)
  definitions <- cwd_model_definitions()
  if (nrow(data) < 3L) {
    stop("At least three complete years are required for cross-validation.", call. = FALSE)
  }
  rows <- vector("list", nrow(data) * nrow(definitions))
  output_index <- 0L
  for (held_out in seq_len(nrow(data))) {
    training <- data[-held_out, , drop = FALSE]
    test <- data[held_out, , drop = FALSE]
    for (model_id in definitions$model_id) {
      fitted <- fit_cwd_candidate(training, model_id)
      prediction <- predict_cwd_model(
        model_id,
        test$annual_max_pcwd_mm,
        test$preceding_cws_mm,
        energy_scale_a = fitted$energy_scale_a,
        recharge_scale_b = fitted$recharge_scale_b,
        s0_mm = fitted$s0_mm
      )
      output_index <- output_index + 1L
      residual <- test$annual_max_cwd_mm - prediction
      rows[[output_index]] <- tibble::tibble(
        sitename = test$sitename,
        year = test$year,
        model_id = model_id,
        observed_cwd_mm = test$annual_max_cwd_mm,
        predicted_cwd_mm = prediction,
        residual_mm = residual,
        absolute_error_mm = abs(residual),
        squared_error_mm2 = residual^2,
        training_energy_scale_a = fitted$energy_scale_a,
        training_recharge_scale_b = fitted$recharge_scale_b,
        training_s0_mm = fitted$s0_mm,
        training_error_sigma_ml_mm = fitted$error_sigma_ml_mm,
        training_storage_active = fitted$storage_active,
        training_recharge_active = fitted$recharge_active
      )
    }
  }
  dplyr::bind_rows(rows)
}

validate_bootstrap_arguments <- function(n_boot, alpha) {
  if (length(n_boot) != 1L || !is.finite(n_boot) ||
      n_boot < 1 || n_boot != as.integer(n_boot)) {
    stop("n_boot must be one positive integer.", call. = FALSE)
  }
  if (length(alpha) != 1L || !is.finite(alpha) || alpha <= 0 || alpha >= 0.5) {
    stop("alpha must be one number strictly between 0 and 0.5.", call. = FALSE)
  }
  invisible(TRUE)
}

simulate_lr_contrasts <- function(data,
                                  generating_fit,
                                  model_a_id,
                                  model_b_id,
                                  n_boot) {
  contrasts <- rep(NA_real_, n_boot)
  for (replicate_id in seq_len(n_boot)) {
    simulated <- data
    simulated$annual_max_cwd_mm <- generating_fit$prediction +
      stats::rnorm(nrow(data), sd = generating_fit$error_sigma_ml_mm)
    contrasts[[replicate_id]] <- tryCatch({
      fit_a <- fit_cwd_candidate(simulated, model_a_id)
      fit_b <- fit_cwd_candidate(simulated, model_b_id)
      2 * (fit_b$log_likelihood - fit_a$log_likelihood)
    }, error = function(error) NA_real_)
  }
  contrasts[is.finite(contrasts)]
}

parametric_bootstrap_lr_pair <- function(data,
                                         model_a_id,
                                         model_b_id,
                                         n_boot = 999L,
                                         alpha = 0.05) {
  assert_cwd_model_data(data)
  validate_bootstrap_arguments(n_boot, alpha)
  pair <- cwd_model_pairs() |>
    dplyr::filter(
      .data$model_a_id == .env$model_a_id,
      .data$model_b_id == .env$model_b_id
    )
  if (nrow(pair) != 1L) {
    stop("The requested model pair is not part of the comparison set.", call. = FALSE)
  }
  definitions <- cwd_model_definitions()
  fit_a <- fit_cwd_candidate(data, model_a_id)
  fit_b <- fit_cwd_candidate(data, model_b_id)
  observed_lr <- 2 * (fit_b$log_likelihood - fit_a$log_likelihood)
  lr_under_a <- simulate_lr_contrasts(data, fit_a, model_a_id, model_b_id, n_boot)
  lr_under_b <- simulate_lr_contrasts(data, fit_b, model_a_id, model_b_id, n_boot)
  if (!length(lr_under_a) || !length(lr_under_b)) {
    stop("All parametric-bootstrap refits failed for a model pair.", call. = FALSE)
  }

  p_against_a <- (1 + sum(lr_under_a >= observed_lr)) /
    (length(lr_under_a) + 1)
  p_against_b <- (1 + sum(lr_under_b <= observed_lr)) /
    (length(lr_under_b) + 1)
  reject_a <- p_against_a < alpha
  reject_b <- p_against_b < alpha
  decision_code <- if (reject_a && !reject_b) {
    "favours_b"
  } else if (reject_b && !reject_a) {
    "favours_a"
  } else if (reject_a && reject_b) {
    "both_rejected"
  } else {
    "indistinguishable"
  }
  preferred_model_id <- if (decision_code == "favours_a") {
    model_a_id
  } else if (decision_code == "favours_b") {
    model_b_id
  } else {
    NA_character_
  }
  label_a <- definitions$model_label[match(model_a_id, definitions$model_id)]
  label_b <- definitions$model_label[match(model_b_id, definitions$model_id)]
  decision_label <- switch(
    decision_code,
    favours_a = paste("Favours", label_a),
    favours_b = paste("Favours", label_b),
    both_rejected = "Both generating models rejected",
    indistinguishable = "No supported distinction"
  )
  quantile_a <- stats::quantile(lr_under_a, c(0.025, 0.5, 0.975), names = FALSE)
  quantile_b <- stats::quantile(lr_under_b, c(0.025, 0.5, 0.975), names = FALSE)

  tibble::tibble(
    sitename = unique(data$sitename),
    pair_id = pair$pair_id,
    pair_label = pair$pair_label,
    comparison_type = pair$comparison_type,
    model_a_id = model_a_id,
    model_a_label = label_a,
    model_b_id = model_b_id,
    model_b_label = label_b,
    log_likelihood_a = fit_a$log_likelihood,
    log_likelihood_b = fit_b$log_likelihood,
    observed_lr_b_minus_a = observed_lr,
    higher_likelihood_model_id = if (observed_lr >= 0) model_b_id else model_a_id,
    directional_p_value = if (observed_lr >= 0) p_against_a else p_against_b,
    p_against_a = p_against_a,
    p_against_b = p_against_b,
    reject_a = reject_a,
    reject_b = reject_b,
    decision_code = decision_code,
    decision_label = decision_label,
    preferred_model_id = preferred_model_id,
    lr_a_q025 = quantile_a[[1]],
    lr_a_median = quantile_a[[2]],
    lr_a_q975 = quantile_a[[3]],
    lr_b_q025 = quantile_b[[1]],
    lr_b_median = quantile_b[[2]],
    lr_b_q975 = quantile_b[[3]],
    successful_bootstrap_a = length(lr_under_a),
    successful_bootstrap_b = length(lr_under_b),
    requested_bootstrap_replicates = as.integer(n_boot),
    alpha = alpha
  )
}

parametric_bootstrap_lr_tests <- function(data,
                                          n_boot = 999L,
                                          alpha = 0.05) {
  pairs <- cwd_model_pairs()
  dplyr::bind_rows(lapply(seq_len(nrow(pairs)), function(index) {
    parametric_bootstrap_lr_pair(
      data,
      pairs$model_a_id[[index]],
      pairs$model_b_id[[index]],
      n_boot,
      alpha
    )
  }))
}

summarise_cwd_candidate_selection <- function(cv_predictions,
                                              full_fits,
                                              pairwise_tests) {
  definitions <- cwd_model_definitions()
  site_names <- unique(cv_predictions$sitename)
  if (length(site_names) != 1L ||
      !identical(site_names, unique(pairwise_tests$sitename))) {
    stop("Candidate selection requires exactly one site.", call. = FALSE)
  }
  performance <- cv_predictions |>
    dplyr::group_by(.data$model_id) |>
    dplyr::summarise(
      n_years = dplyr::n(),
      cv_mse_mm2 = mean(.data$squared_error_mm2),
      cv_rmse_mm = sqrt(mean(.data$squared_error_mm2)),
      cv_mae_mm = mean(.data$absolute_error_mm),
      .groups = "drop"
    )
  best_model_id <- performance$model_id[[which.min(performance$cv_mse_mm2)]]
  full_summary <- dplyr::bind_rows(lapply(full_fits, function(fitted) {
    tibble::tibble(
      model_id = fitted$model_id,
      full_energy_scale_a = fitted$energy_scale_a,
      full_recharge_scale_b = fitted$recharge_scale_b,
      full_s0_mm = fitted$s0_mm,
      full_error_sigma_ml_mm = fitted$error_sigma_ml_mm,
      full_storage_active = fitted$storage_active,
      full_recharge_active = fitted$recharge_active,
      full_s0_identifiable = fitted$s0_identifiable,
      full_energy_scale_identifiable = fitted$energy_scale_identifiable,
      full_recharge_scale_identifiable = fitted$recharge_scale_identifiable,
      full_rmse_mm = fitted$rmse,
      full_mae_mm = fitted$mae,
      full_log_likelihood = fitted$log_likelihood,
      aic = fitted$aic,
      aicc = fitted$aicc
    )
  }))
  decisive <- pairwise_tests |>
    dplyr::filter(!is.na(.data$preferred_model_id)) |>
    dplyr::mutate(
      defeated_model_id = dplyr::if_else(
        .data$preferred_model_id == .data$model_a_id,
        .data$model_b_id,
        .data$model_a_id
      )
    )
  defeated <- unique(decisive$defeated_model_id)
  performance <- performance |>
    dplyr::left_join(full_summary, by = "model_id") |>
    dplyr::left_join(definitions, by = "model_id") |>
    dplyr::mutate(
      delta_cv_rmse_mm = .data$cv_rmse_mm - min(.data$cv_rmse_mm),
      delta_aicc = .data$aicc - min(.data$aicc),
      empirically_best = .data$model_id == best_model_id,
      decisive_wins = unname(vapply(.data$model_id, function(id) {
        sum(decisive$preferred_model_id == id)
      }, integer(1))),
      decisive_losses = unname(vapply(.data$model_id, function(id) {
        sum(decisive$defeated_model_id == id)
      }, integer(1))),
      bootstrap_undefeated = !(.data$model_id %in% defeated)
    )
  eligible <- performance |>
    dplyr::filter(.data$bootstrap_undefeated) |>
    dplyr::arrange(
      .data$mechanism_count,
      .data$fitted_parameter_count,
      .data$aicc,
      .data$model_id
    )
  if (!nrow(eligible)) {
    stop("No candidate remained after pairwise bootstrap comparisons.", call. = FALSE)
  }
  selected_model_id <- eligible$model_id[[1]]
  performance <- performance |>
    dplyr::mutate(
      selected = .data$model_id == selected_model_id,
      sitename = site_names,
      .before = 1L
    ) |>
    dplyr::arrange(
      dplyr::desc(.data$selected),
      .data$mechanism_count,
      .data$fitted_parameter_count,
      .data$cv_rmse_mm
    )
  list(
    performance = performance,
    selected_model_id = selected_model_id,
    best_model_id = best_model_id
  )
}

select_cwd_models_by_site <- function(annual,
                                      n_boot = 999L,
                                      alpha = 0.05,
                                      seed = 20260930L,
                                      cores = 1L) {
  assert_cwd_model_data(annual)
  validate_bootstrap_arguments(n_boot, alpha)
  if (length(seed) != 1L || !is.finite(seed)) {
    stop("seed must be one finite number.", call. = FALSE)
  }
  if (length(cores) != 1L || !is.finite(cores) ||
      cores < 1 || cores != as.integer(cores)) {
    stop("cores must be one positive integer.", call. = FALSE)
  }
  complete <- annual |>
    dplyr::filter(
      is.finite(.data$annual_max_cwd_mm),
      is.finite(.data$annual_max_pcwd_mm),
      is.finite(.data$preceding_cws_mm),
      .data$annual_max_pcwd_mm >= 0,
      .data$preceding_cws_mm >= 0
    ) |>
    dplyr::arrange(.data$sitename, .data$year)
  omitted <- dplyr::anti_join(
    annual[c("sitename", "year")],
    complete[c("sitename", "year")],
    by = c("sitename", "year")
  )
  site_groups <- split(complete, complete$sitename)
  fit_site <- function(site_index) {
    set.seed(as.integer(seed) + site_index - 1L)
    site_data <- site_groups[[site_index]]
    if (nrow(site_data) < 3L) {
      stop(
        "Site ", unique(site_data$sitename),
        " has fewer than three complete years.",
        call. = FALSE
      )
    }
    definitions <- cwd_model_definitions()
    full_fits <- setNames(
      lapply(definitions$model_id, function(model_id) {
        fit_cwd_candidate(site_data, model_id)
      }),
      definitions$model_id
    )
    cv_predictions <- cross_validate_cwd_candidates(site_data)
    pairwise_tests <- parametric_bootstrap_lr_tests(
      site_data,
      n_boot = n_boot,
      alpha = alpha
    )
    selection <- summarise_cwd_candidate_selection(
      cv_predictions,
      full_fits,
      pairwise_tests
    )
    full_predictions <- dplyr::bind_rows(lapply(full_fits, function(fitted) {
      tibble::tibble(
        sitename = site_data$sitename,
        year = site_data$year,
        model_id = fitted$model_id,
        observed_cwd_mm = site_data$annual_max_cwd_mm,
        predicted_cwd_mm = fitted$prediction,
        residual_mm = fitted$residual,
        full_energy_scale_a = fitted$energy_scale_a,
        full_recharge_scale_b = fitted$recharge_scale_b,
        full_s0_mm = fitted$s0_mm,
        full_error_sigma_ml_mm = fitted$error_sigma_ml_mm,
        full_storage_active = fitted$storage_active,
        full_recharge_active = fitted$recharge_active
      )
    }))
    list(
      performance = selection$performance,
      pairwise_tests = pairwise_tests,
      cv_predictions = cv_predictions,
      full_predictions = full_predictions,
      selected_model_id = selection$selected_model_id,
      best_model_id = selection$best_model_id
    )
  }
  site_indices <- seq_along(site_groups)
  site_results <- if (cores > 1L && .Platform$OS.type != "windows") {
    parallel::mclapply(
      site_indices,
      fit_site,
      mc.cores = as.integer(cores),
      mc.set.seed = FALSE
    )
  } else {
    lapply(site_indices, fit_site)
  }

  performance <- dplyr::bind_rows(lapply(site_results, `[[`, "performance"))
  pairwise_tests <- dplyr::bind_rows(lapply(site_results, `[[`, "pairwise_tests"))
  cv_predictions <- dplyr::bind_rows(lapply(site_results, `[[`, "cv_predictions"))
  full_predictions <- dplyr::bind_rows(lapply(site_results, `[[`, "full_predictions"))
  pair_counts <- pairwise_tests |>
    dplyr::group_by(.data$sitename) |>
    dplyr::summarise(
      n_decisive_pairs = sum(!is.na(.data$preferred_model_id)),
      n_indistinguishable_pairs = sum(.data$decision_code == "indistinguishable"),
      n_both_rejected_pairs = sum(.data$decision_code == "both_rejected"),
      .groups = "drop"
    )
  site_selection <- performance |>
    dplyr::filter(.data$selected) |>
    dplyr::transmute(
      sitename = .data$sitename,
      n_years = .data$n_years,
      selected_model_id = .data$model_id,
      selected_model_label = .data$model_label,
      selected_model_formula = .data$model_formula,
      selected_mechanism_count = .data$mechanism_count,
      selected_parameter_count = .data$fitted_parameter_count,
      selected_cv_rmse_mm = .data$cv_rmse_mm,
      selected_cv_mae_mm = .data$cv_mae_mm,
      selected_energy_scale_a = .data$full_energy_scale_a,
      selected_recharge_scale_b = .data$full_recharge_scale_b,
      selected_s0_mm = .data$full_s0_mm,
      selected_error_sigma_ml_mm = .data$full_error_sigma_ml_mm,
      selected_storage_active = .data$full_storage_active,
      selected_recharge_active = .data$full_recharge_active,
      selected_s0_identifiable = .data$full_s0_identifiable,
      selected_energy_scale_identifiable = .data$full_energy_scale_identifiable,
      selected_recharge_scale_identifiable = .data$full_recharge_scale_identifiable,
      selected_aicc = .data$aicc,
      selected_decisive_wins = .data$decisive_wins,
      selected_decisive_losses = .data$decisive_losses
    )
  best_models <- performance |>
    dplyr::filter(.data$empirically_best) |>
    dplyr::select(
      "sitename",
      empirically_best_model_id = "model_id",
      empirically_best_model_label = "model_label",
      best_cv_rmse_mm = "cv_rmse_mm"
    )
  site_selection <- site_selection |>
    dplyr::left_join(best_models, by = "sitename") |>
    dplyr::left_join(pair_counts, by = "sitename") |>
    dplyr::mutate(
      selected_is_empirically_best =
        .data$selected_model_id == .data$empirically_best_model_id
    ) |>
    dplyr::arrange(.data$sitename)
  selected_predictions <- full_predictions |>
    dplyr::inner_join(
      site_selection |>
        dplyr::select("sitename", "selected_model_id"),
      by = "sitename"
    ) |>
    dplyr::filter(.data$model_id == .data$selected_model_id) |>
    dplyr::select(-"selected_model_id")

  list(
    model_definitions = cwd_model_definitions(),
    model_pairs = cwd_model_pairs(),
    site_selection = site_selection,
    model_performance = performance,
    pairwise_tests = pairwise_tests,
    cv_predictions = cv_predictions,
    full_predictions = full_predictions,
    selected_predictions = selected_predictions,
    omitted_site_years = omitted,
    bootstrap_replicates = as.integer(n_boot),
    bootstrap_alpha = alpha,
    bootstrap_seed = as.integer(seed),
    bootstrap_cores = as.integer(cores)
  )
}
