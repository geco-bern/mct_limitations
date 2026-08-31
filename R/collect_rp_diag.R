collect_rp_diag_nSIF <- function(ichunk){
  
  ## construct output file name
  dirn <- "data/df_rp_diag/"
  filn <- paste0("df_rp_diag_nSIF_ichunk_", ichunk, "_30.rds")
  path <- paste0(dirn, filn)
  
  if (file.exists(path)){
    df_rp_diag <- readRDS(path)
  } else {
    rlang::inform(paste("File does not exist:", path))
    df_rp_diag <- tibble()
  }
  
  return(df_rp_diag)
}

collect_rp_diag_fet <- function(ichunk){
  
  ## construct output file name
  dirn <- "data/df_rp_diag/"
  filn <- paste0("df_rp_diag_fet_ichunk_", ichunk, "_30.rds")
  path <- paste0(dirn, filn)
  
  if (file.exists(path)){
    df_rp_diag <- readRDS(path)
  } else {
    rlang::inform(paste("File does not exist:", path))
    df_rp_diag <- tibble()
  }
  
  return(df_rp_diag)
}
