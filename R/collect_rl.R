collect_rl_nSIF <- function(ichunk){
  
  ## construct output file name
  dirn <- "data/df_rl/"
  filn <- paste0("df_rl_nSIF_ichunk_", ichunk, "_30.rds")
  path <- paste0(dirn, filn)
  
  if (file.exists(path)){
    df <- readRDS(path)
  } else {
    rlang::inform(paste("File does not exist:", path))
    df <- tibble()
  }
  
  return(df)
}

collect_rl_fet <- function(ichunk){
  
  ## construct output file name
  dirn <- "data/df_rl/"
  filn <- paste0("df_rl_fet_ichunk_", ichunk, "_30.rds")
  path <- paste0(dirn, filn)
  
  if (file.exists(path)){
    df <- readRDS(path)
  } else {
    rlang::inform(paste("File does not exist:", path))
    df <- tibble()
  }
  
  return(df)
}
