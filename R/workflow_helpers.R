# Helpers shared by analysis entry points and UBELIX jobs.

project_path <- function(...) {
  here::here(...)
}

ensure_directory <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(normalizePath(path, mustWork = TRUE))
}

chunk_arguments <- function(args = commandArgs(trailingOnly = TRUE),
                            default_chunk = 1L,
                            default_chunks = 1L) {
  chunk <- if (length(args) >= 1L) as.integer(args[[1]]) else default_chunk
  chunks <- if (length(args) >= 2L) as.integer(args[[2]]) else default_chunks

  if (is.na(chunk) || is.na(chunks) || chunk < 1L || chunks < 1L) {
    stop("Chunk number and total chunks must be positive integers.", call. = FALSE)
  }
  if (chunk > chunks) {
    stop("Chunk number cannot exceed total chunks.", call. = FALSE)
  }

  list(chunk = chunk, chunks = chunks)
}

split_work <- function(items, chunks) {
  if (!length(items)) {
    return(list())
  }
  chunks <- min(as.integer(chunks), length(items))
  rows_per_chunk <- ceiling(length(items) / chunks)
  split(items, ceiling(seq_along(items) / rows_per_chunk))
}

work_for_chunk <- function(items, chunk, chunks) {
  work <- split_work(items, chunks)
  if (chunk > length(work)) {
    return(items[0])
  }
  unname(work[[chunk]])
}

allocated_cores <- function(tasks = Inf) {
  slurm_cores <- suppressWarnings(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "")))
  detected <- if (!is.na(slurm_cores) && slurm_cores > 0L) {
    slurm_cores
  } else if (requireNamespace("parallelly", quietly = TRUE)) {
    parallelly::availableCores(omit = 0L)
  } else {
    parallel::detectCores(logical = FALSE)
  }

  task_limit <- if (is.finite(tasks)) as.integer(tasks) else .Machine$integer.max
  if (is.na(detected) || detected < 1L) detected <- 1L
  max(1L, min(as.integer(detected), task_limit))
}

run_parallel <- function(items, fn, ..., cores = allocated_cores(length(items)),
                         continue_on_error = TRUE) {
  if (!length(items)) {
    return(list())
  }

  runner <- function(item) {
    if (continue_on_error) {
      try(fn(item, ...), silent = FALSE)
    } else {
      fn(item, ...)
    }
  }

  cores <- min(as.integer(cores), length(items))
  result <- if (cores <= 1L || .Platform$OS.type == "windows") {
    lapply(items, runner)
  } else {
    parallel::mclapply(
      items,
      runner,
      mc.cores = cores,
      mc.preschedule = FALSE
    )
  }

  failures <- vapply(result, inherits, logical(1), what = "try-error")
  if (any(failures)) {
    stop(
      sum(failures), " of ", length(result),
      " parallel tasks failed; completed outputs were retained for restart.",
      call. = FALSE
    )
  }
  result
}

require_files <- function(paths, step = NULL) {
  missing <- paths[!file.exists(path.expand(paths))]
  if (length(missing)) {
    prefix <- if (is.null(step)) "Missing required input files" else {
      paste0("Cannot run ", step, "; missing required input files")
    }
    stop(prefix, ":\n- ", paste(missing, collapse = "\n- "), call. = FALSE)
  }
  invisible(paths)
}

write_rdata_atomic <- function(object, object_name, path) {
  ensure_directory(dirname(path))
  temporary <- tempfile(
    pattern = paste0(".", basename(path), "-"),
    tmpdir = dirname(path)
  )
  on.exit(unlink(temporary), add = TRUE)

  environment <- new.env(parent = emptyenv())
  assign(object_name, object, envir = environment)
  save(list = object_name, file = temporary, envir = environment)

  if (file.exists(path) && unlink(path) != 0L) {
    stop("Could not replace existing output: ", path, call. = FALSE)
  }
  if (!file.rename(temporary, path)) {
    stop("Could not move completed output into place: ", path, call. = FALSE)
  }
  invisible(path)
}

parse_index_spec <- function(spec = Sys.getenv("MCT_ILON", "")) {
  if (!nzchar(spec)) {
    return(NULL)
  }

  parts <- trimws(strsplit(spec, ",", fixed = TRUE)[[1]])
  indices <- unlist(lapply(parts, function(part) {
    bounds <- strsplit(part, "-", fixed = TRUE)[[1]]
    values <- suppressWarnings(as.integer(bounds))
    if (anyNA(values) || length(values) > 2L) {
      stop("Invalid MCT_ILON specification: ", spec, call. = FALSE)
    }
    if (length(values) == 1L) values else seq(values[[1]], values[[2]])
  }))

  sort(unique(indices))
}
