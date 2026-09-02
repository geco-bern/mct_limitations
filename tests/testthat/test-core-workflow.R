project_file <- function(...) {
  testthat::test_path("..", "..", ...)
}

test_that("the job registry contains only the retained global workflow", {
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

  expect_setequal(
    unique(jobs$stage),
    c("01_tidy_inputs", "03_water_balance", "04_annual_cwd", "10_results")
  )
  expect_false(any(grepl(
    "sif|fluxnet|sj02|soil|root|extreme|return|diagnostic",
    paste(jobs$stage, jobs$job, jobs$script),
    ignore.case = TRUE
  )))
  expect_true(all(file.exists(project_file(jobs$script))))
  expect_false("prepare_snowfall" %in% jobs$job)

  result_job <- jobs[jobs$job == "cwd_surplus_relationship", ]
  expect_equal(nrow(result_job), 1L)
  expect_equal(result_job$stage, "10_results")
})

test_that("the core submitter omits extreme-value fitting", {
  pipeline <- readLines(
    project_file("src", "ubelix", "submit_pipeline.sh"),
    warn = FALSE
  )

  expect_true(any(grepl("submit_job calculate_annual_cwd", pipeline, fixed = TRUE)))
  expect_true(any(grepl("submit_job cwd_surplus_relationship", pipeline, fixed = TRUE)))
  expect_false(any(grepl("submit_job fit_extremes", pipeline, fixed = TRUE)))
  expect_false(any(grepl("submit_job extract_return_levels", pipeline, fixed = TRUE)))
})

test_that("only the retained workflow vignettes remain", {
  vignette_files <- list.files(
    project_file("vignettes"),
    pattern = "[.]Rmd$",
    recursive = TRUE
  )

  expect_setequal(
    vignette_files,
    c("core_workflow_synthetic.Rmd", "ubelix_workflow.Rmd")
  )
})

test_that("R contains only helpers used by the retained workflow", {
  retained <- c(
    "calculate_annual_cwd.R",
    "convert_et.R",
    "get_annual_cwd_byilon.R",
    "get_bal.R",
    "get_bal_byilon.R",
    "get_et_mm_byilon.R",
    "input_config.R",
    "map_netcdf_to_tidy.R",
    "simulate_snow.R",
    "simulate_snow_byilon.R",
    "workflow_helpers.R"
  )

  expect_setequal(
    list.files(project_file("R"), pattern = "[.]R$"),
    retained
  )
})

test_that("the annual adapter delegates daily calculations to cwd", {
  implementation <- readLines(
    project_file("R", "calculate_annual_cwd.R"),
    warn = FALSE
  )
  description <- read.dcf(project_file("DESCRIPTION"))

  expect_true(any(grepl("cwd::cwd(", implementation, fixed = TRUE)))
  expect_false(any(grepl("calculate_cumulative_surplus <-", implementation)))
  expect_match(
    description[[1, "Imports"]],
    "(^|,|\\n)\\s*cwd\\s*(\\([^)]*\\))?(,|$)"
  )
})

test_that("the workflow depends on rgeco rather than rbeni", {
  description <- read.dcf(project_file("DESCRIPTION"))
  imports <- description[[1, "Imports"]]
  remotes <- description[[1, "Remotes"]]

  expect_match(imports, "(^|,|\\n)\\s*rgeco\\s*(,|$)")
  expect_false(grepl("(^|,|\\n)\\s*rbeni\\s*(,|$)", imports))
  expect_match(remotes, "geco-bern/rgeco")
  expect_false(grepl("rbeni", remotes, fixed = TRUE))

  workflow_files <- c(
    list.files(project_file("R"), full.names = TRUE, pattern = "[.]R$"),
    list.files(
      project_file("analysis"),
      full.names = TRUE,
      recursive = TRUE,
      pattern = "[.]R$"
    )
  )
  implementation <- unlist(lapply(workflow_files, readLines, warn = FALSE))

  expect_false(any(grepl("rbeni::", implementation, fixed = TRUE)))
  expect_true(any(grepl("rgeco::extract_nc", implementation, fixed = TRUE)))
  expect_true(any(grepl("rgeco::calc_patm", implementation, fixed = TRUE)))
})
