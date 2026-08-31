#!/usr/bin/env Rscript

# Extract global input datasets
# Extracted from vignettes/archive/workflow_legacy.Rmd.
source("analysis/_common.R")

library(sf)
library(raster)
library(rasterVis)
nc <- read_nc_onefile("~/data/alexi_tir/netcdf/EDAY_CERES_2006200.nc")

## crop and write smaller file
rasta <- raster("~/data/alexi_tir/netcdf/EDAY_CERES_2006200.nc")
lonmin <- 0
lonmax <- 180
latmin <- 50
latmax <- 80
rasta2 <- crop(rasta, extent(lonmin, lonmax, latmin, latmax))
raster::writeRaster(rasta2, filename = "./data/maptest.nc", format = "CDF", overwrite = TRUE )
plot_map3("./data/maptest.nc", lonmin = lonmin, lonmax = lonmax, latmin = latmin, latmax = latmax)

if (siteset=="global"){
  
  ## Submit the `alexi` and `alexi_lores` jobs on UBELIX, or run the
  ## corresponding scripts under analysis/01_tidy_inputs locally.
  
} else {
  ##------------------------------------------------------------------------
  ## Extract point data and construct single nested time series data frame
  ##------------------------------------------------------------------------
  filn <- paste0("data/df_alexi_", siteset,".Rdata")
  filn_csv <- str_replace(filn, "RData", "csv")
  if (!file.exists(filn)){
    if (!file.exists(filn_csv)){
      df_alexi <- get_data_mct_global(
        df_grid,
        dir_et   = "~/data/alexi_tir/netcdf/", fil_et_pattern = "EDAY_CERES_",
        get_watch = FALSE, get_landeval = FALSE, get_alexi = TRUE
      )
      save(df_alexi, file = filn)
      df_alexi |>
        tidyr::unnest(df) |>
        write_csv(path = filn_csv)
    } else {
      df_alexi <- read_csv(file = filn_csv) |>
        group_by(idx, lon, lat) |>
        tidyr::nest() |>
        dplyr::mutate(data = purrr::map(data, ~as_tibble(.))) |>
        dplyr::rename(df = data)
    }
  } else {
    load(filn)
    df_alexi |>
      tidyr::unnest(df) |>
      write_csv(path = filn_csv)
  } 
}

##------------------------------------------------------------------------
## WATCH
##------------------------------------------------------------------------
filn <- paste0("data/df_watch_", siteset,".RData")
filn_csv <- str_replace(filn, "RData", "csv")
if (!file.exists(filn)){
  if (!file.exists(filn_csv)){
    df_watch <- get_data_mct_global(
      df_grid,
      dir_prec = "~/data/watch_wfdei/Rainf_daily/", fil_prec_pattern = "Rainf_daily_WFDEI_CRU",
      dir_snow = "~/data/watch_wfdei/Snowf_daily/", fil_snow_pattern = "Snowf_daily_WFDEI_CRU",
      dir_temp = "~/data/watch_wfdei/Tair_daily/",  fil_temp_pattern = "Tair_daily_WFDEI",
      get_watch = TRUE, get_landeval = FALSE, get_alexi = FALSE,
      year_start_watch = 2003, year_end_watch = 2018
    )
    save(df_watch, file = filn)
    df_watch |>
      tidyr::unnest(data) |>
      write_csv(path = filn_csv)
  } else {
    df_watch <- read_csv(file = filn_csv) |>
      group_by(sitename) |>
      tidyr::nest() |>
      dplyr::mutate(data = purrr::map(data, ~as_tibble(.))) |>
      dplyr::rename(df = data)
  }
} else {
  load(filn)
  df_watch |>
    tidyr::unnest(data) |>
    write_csv(path = filn_csv)
}

library(sf)
library(raster)
library(rasterVis)
nc <- read_nc_onefile("~/data/alexi_tir/netcdf/EDAY_CERES_2006200.nc")

## crop and write smaller file
rasta <- raster("~/data/glass/data_netcdf/2001/GLASS07B01.V41.A2001166.2018264.nc")
lonmin <- 0
lonmax <- 180
latmin <- 50
latmax <- 80
rasta2 <- crop(rasta, extent(lonmin, lonmax, latmin, latmax))
raster::writeRaster(rasta2, filename = "./data/maptest.nc", format = "CDF", overwrite = TRUE )
plot_map3("./data/maptest.nc", lonmin = lonmin, lonmax = lonmax, latmin = latmin, latmax = latmax)
