## function to extract info by file
extract_whc_byfil <- function(ifil, batch_size = 10000L){
  
  ## Process bounded batches to avoid the old row-by-row bottleneck without
  ## materialising every nested soil profile at once.
  extract_whc_batch <- function(df){
    df %>% 
      tidyr::unnest(data_soiltext_top) %>%
      dplyr::select(lon, lat, fc_top = fc, pwp_top = pwp, whc_top = whc, data_soiltext_sub) %>%
      tidyr::unnest(data_soiltext_sub) %>% 
      dplyr::select(lon, lat, fc_top, pwp_top, whc_top, fc_sub = fc, pwp_sub = pwp, whc_sub = whc)
  }
  load(ifil) # should load 'df_whc'
  df_whc <- df_whc %>% 
    ungroup()
  batches <- split(
    seq_len(nrow(df_whc)),
    ceiling(seq_len(nrow(df_whc)) / batch_size)
  )
  df <- purrr::map_dfr(
    batches,
    ~dplyr::slice(df_whc, .x) %>% extract_whc_batch()
  )
  
  ## old version:
  # df <- df_whc %>% 
  #   dplyr::ungroup() %>% 
  #   tidyr::unnest(data_soiltext_top) %>%
  #   dplyr::select(lon, lat, fc_top = fc, pwp_top = pwp, whc_top = whc, data_soiltext_sub) %>%
  #   tidyr::unnest(data_soiltext_sub) %>% 
  #   dplyr::select(lon, lat, fc_top, pwp_top, whc_top, fc_sub = fc, pwp_sub = pwp, whc_sub = whc)
  
  return(df)
}
