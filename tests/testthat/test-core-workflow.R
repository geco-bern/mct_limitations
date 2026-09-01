project_file <- function(...) {
  testthat::test_path("..", "..", ...)
}

test_that("the core registry ends in annual CWD", {
  jobs <- utils::read.delim(
    project_file("src", "ubelix", "jobs.tsv"),
    sep = "\t",
    quote = "",
    comment.char = "",
    stringsAsFactors = FALSE
  )

  annual_job <- jobs[jobs$job == "calculate_annual_cwd", ]
  expect_equal(nrow(annual_job), 1L)
  expect_equal(annual_job$stage, "04_annual_cwd")
  expect_match(annual_job$output_pattern, "data/df_cwd_annual/")

  extreme_jobs <- jobs[grepl("extreme|return_levels", jobs$job), ]
  expect_true(nrow(extreme_jobs) > 0L)
  expect_true(all(extreme_jobs$stage == "04_optional_cwd_extremes"))
})

test_that("the core submitter omits extreme-value fitting", {
  pipeline <- readLines(
    project_file("src", "ubelix", "submit_pipeline.sh"),
    warn = FALSE
  )

  expect_true(any(grepl("submit_job calculate_annual_cwd", pipeline, fixed = TRUE)))
  expect_false(any(grepl("submit_job fit_extremes", pipeline, fixed = TRUE)))
  expect_false(any(grepl("submit_job extract_return_levels", pipeline, fixed = TRUE)))
})

test_that("the annual adapter delegates daily calculations to cwd", {
  implementation <- readLines(
    project_file("R", "calculate_annual_cwd.R"),
    warn = FALSE
  )
  wrapper <- readLines(
    project_file("R", "get_annual_cwd_byilon.R"),
    warn = FALSE
  )
  description <- read.dcf(project_file("DESCRIPTION"))

  expect_true(any(grepl("cwd::cwd(", implementation, fixed = TRUE)))
  expect_false(any(grepl("calculate_cumulative_surplus <-", implementation)))
  expect_false(any(grepl('source("R/mct2.R")', wrapper, fixed = TRUE)))
  expect_match(
    description[[1, "Imports"]],
    "(^|,|\\n)\\s*cwd\\s*(\\([^)]*\\))?(,|$)"
  )
})
