#!/usr/bin/env Rscript

# Prepare masks and spatial metadata
# Extracted from vignettes/archive/workflow_legacy.Rmd.
source("analysis/_common.R")

siteset <- "sj02"
# siteset <- "global"
# siteset <- "fluxnet2015"
# siteset <- "rsip"

df_vegmask <- nc_to_df("~/data/modis_monthly-evi/zmaw_data/modis_landcover__LPDAAC__v5.1__0.05deg__2011.nc", 
                       varnam = "urban_and_builtup") |> 
  mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |> 
  dplyr::select(-time) |> 
  left_join(
    nc_to_df("~/data/modis_monthly-evi/zmaw_data/modis_landcover__LPDAAC__v5.1__0.05deg__2011.nc", 
                       varnam = "snowandice") |> 
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |> 
      dplyr::select(-time),
    by = c("lon", "lat")
  ) |> 
  left_join(
    nc_to_df("~/data/modis_monthly-evi/zmaw_data/modis_landcover__LPDAAC__v5.1__0.05deg__2011.nc", 
                       varnam = "barren_sparsely_vegetated") |> 
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |> 
      dplyr::select(-time),
    by = c("lon", "lat")
  ) |> 
  left_join(
    nc_to_df("~/data/modis_monthly-evi/zmaw_data/modis_landcover__LPDAAC__v5.1__0.05deg__2011.nc", 
                       varnam = "water") |> 
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |> 
      dplyr::select(-time),
    by = c("lon", "lat")
  ) |> 
  # mutate(nonveg = (urban_and_builtup + snowandice + water + barren_sparsely_vegetated)/100) |> 
  mutate(nonveg = (urban_and_builtup + snowandice + water)/100) |> 
  mutate(vegmask = ifelse(nonveg > 0.99, NA, 1))

save(df_vegmask, file = "data/df_vegmask.RData")

df_vegmask_tenthdeg <- nc_to_df("~/data/modis_monthly-evi/zmaw_data/modis_landcover__LPDAAC__v5.1__0.1deg__2011.nc", 
                       varnam = "urban_and_builtup") |> 
  mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |> 
  dplyr::select(-time) |> 
  left_join(
    nc_to_df("~/data/modis_monthly-evi/zmaw_data/modis_landcover__LPDAAC__v5.1__0.1deg__2011.nc", 
                       varnam = "snowandice") |> 
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |> 
      dplyr::select(-time),
    by = c("lon", "lat")
  ) |> 
  left_join(
    nc_to_df("~/data/modis_monthly-evi/zmaw_data/modis_landcover__LPDAAC__v5.1__0.1deg__2011.nc", 
                       varnam = "barren_sparsely_vegetated") |> 
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |> 
      dplyr::select(-time),
    by = c("lon", "lat")
  ) |> 
  left_join(
    nc_to_df("~/data/modis_monthly-evi/zmaw_data/modis_landcover__LPDAAC__v5.1__0.1deg__2011.nc", 
                       varnam = "water") |> 
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |> 
      dplyr::select(-time),
    by = c("lon", "lat")
  ) |> 
  # mutate(nonveg = (urban_and_builtup + snowandice + water + barren_sparsely_vegetated)/100) |> 
  mutate(nonveg = (urban_and_builtup + snowandice + water)/100) |> 
  mutate(vegmask = ifelse(nonveg > 0.99, NA, 1))

save(df_vegmask_tenthdeg, file = "data/df_vegmask_tenthdeg.RData")

if (siteset=="sj02"){
  ##----------------------------------------------
  ## Schenk & Jackson sites
  ##----------------------------------------------
  siteinfo <- read_csv("~/data/rootingdepth/root_profiles_schenkjackson02/data/root_profiles_D50D95.csv") |>
    dplyr::filter(Wetland == "N" & Anthropogenic == "N" & Schenk_Jackson_2002 == "YES") |> 
    dplyr::rename(sitename = ID, lat = Latitude, lon = Longitude) |> 
    dplyr::mutate(elv = ifelse(elv==-999, NA, elv)) |> 
    dplyr::filter(lon!=-999 & lat!=-999) |> 
    dplyr::select(sitename, lon, lat, elv)

  df_grid_allsiteid <- siteinfo |> 
    dplyr::select(sitename, lon, lat, elv) |> 
    dplyr::rename(idx = sitename)

  df_grid <- df_grid_allsiteid |>
    dplyr::select(lon, lat) |>
    distinct() |>
    mutate(idx = 1:n()) |>
    mutate(idx = paste0("i", idx))

} else if (siteset == "fluxnet2015"){
  ##----------------------------------------------
  ## FLUXNET 2015 Tier 1 sites
  ##----------------------------------------------
  siteinfo <- ingestr::siteinfo_fluxnet2015 |> 
    rename(sitename = mysitename) |> 
    filter(!(classid %in% c("CRO", "WET"))) |> 
    #filter(year_start<=2007) |>    # xxx USE ONLY FOR LANDEVAL xxx
    mutate(date_start = lubridate::ymd(paste0(year_start, "-01-01"))) |> 
    mutate(date_end = lubridate::ymd(paste0(year_end, "-12-31")))

  df_grid <- siteinfo |> 
    dplyr::select(sitename, lon, lat, elv) |> 
    dplyr::rename(idx = sitename)

} else if (siteset == "global"){
  ##----------------------------------------------
  ## Global simulations at 0.5 degrees
  ##----------------------------------------------
  ## use WFDEI land mask and read its elevation
  df <- nc_to_df("~/data/watch_wfdei/WFDEI-elevation.nc", dropna = TRUE) |> 
    mutate(sitename = paste0("i", 1:n())) |> 
    rename(elv = myvar) |> 
    dplyr::select(sitename, lon, lat, elv)
}

df_elv <- nc_to_df(
  "~/data/etopo/ETOPO1_Bed_g_gef.tif_halfdeg.nc",
  varnam = "ETOPO1_Bed_g_geotiff"
  )

library(ingestr)

if (siteset != "global"){
  ##----------------------------------------------
  ## Site-scale set
  ##----------------------------------------------
  siteinfo <- siteinfo |> 
    left_join(
      ingest(
        siteinfo |> 
          dplyr::select(sitename, lon, lat, elv) |> 
          distinct(),
        source = "etopo1",
        dir = "~/data/etopo/"
        ) |> 
        unnest(data) |> 
        rename(elv_etopo = elv),
      by = "sitename"
    )

  ## Show a comparison
  modobs_elv <- siteinfo |> 
    analyse_modobs2("elv", "elv_etopo")
  modobs_elv$gg

  ## Replace missing
  siteinfo <- siteinfo |> 
    mutate(source_elv = ifelse(is.na(elv), "etopo1", "orig_data")) |> 
    mutate(elv = ifelse(is.na(elv), elv_etopo, elv)) |> 
    dplyr::select(-elv_etopo)
}

## first get subsoil parameters
df_hwsd <- rbeni::nc_to_df("~/data/soil/hwsd/hwsd_wieder/data/S_SAND.nc4", "S_SAND") |> 
  mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |>
  rename( S_SAND = myvar ) |>
  tidyr::drop_na() |> 
  
  left_join(
    rbeni::nc_to_df("~/data/soil/hwsd/hwsd_wieder/data/S_CLAY.nc4", "S_CLAY") |>
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |>
      rename( S_CLAY = myvar ),
    by = c("lon", "lat")
  ) |>
  left_join(
    rbeni::nc_to_df("~/data/soil/hwsd/hwsd_wieder/data/S_OC.nc4", "S_OC") |>
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |>
      rename( S_OC = myvar ),
    by = c("lon", "lat")
  ) |>
  left_join(
    rbeni::nc_to_df("~/data/soil/hwsd/hwsd_wieder/data/S_GRAVEL.nc4", "S_GRAVEL") |>
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |>
      rename( S_GRAVEL = myvar ),
    by = c("lon", "lat")
  ) |>

  ## get topsoil parameters
  left_join(
    rbeni::nc_to_df("~/data/soil/hwsd/hwsd_wieder/data/T_SAND.nc4", "T_SAND") |>
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |>
      rename( T_SAND = myvar ),
    by = c("lon", "lat")
  ) |>
  left_join(
    rbeni::nc_to_df("~/data/soil/hwsd/hwsd_wieder/data/T_CLAY.nc4", "T_CLAY") |>
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |>
      rename( T_CLAY = myvar ),
    by = c("lon", "lat")
  ) |>
  left_join(
    rbeni::nc_to_df("~/data/soil/hwsd/hwsd_wieder/data/T_OC.nc4", "T_OC") |>
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |>
      rename( T_OC = myvar ),
    by = c("lon", "lat")
  ) |>
  left_join(
    rbeni::nc_to_df("~/data/soil/hwsd/hwsd_wieder/data/T_GRAVEL.nc4", "T_GRAVEL") |>
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |>
      rename( T_GRAVEL = myvar ),
    by = c("lon", "lat")
  ) |> 

  left_join(
    rbeni::nc_to_df("~/data/soil/hwsd/hwsd_wieder/data/ROOTS.nc4", "ROOTS") |>
      mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) |>
      rename( ROOTS = myvar ),
    by = c("lon", "lat")
  ) |> 
  mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3)) 

save(df_hwsd, file = "data/df_hwsd_hires.RData")

## something is going wrong
df_test <- nc_to_df(
  "~/data/soil/hwsd/hwsd_wieder/data/T_OC.nc4", "T_OC",  
  lon = (seq(7200) - 1) * 0.05 - 179.975,
  lat = (seq(3600) - 1) * 0.05 - 89.975
  )
  # mutate(lon = round(lon, digits = 3), lat = round(lat, digits = 3))
all_lon <- (seq(7200) - 1) * 0.05 - 179.975
all_lon[1:3] %in% (df_test$lon[1:3] |> unique())
all_lon[1:3]
(df_test$lon[1:3] |> unique())

## load if it's not in the workspace yet
load("data/df_hwsd_hires.RData")

nc <- df_to_grid(df_hwsd, varnam = "T_SAND", lonnam = "lon", latnam = "lat")
write_nc2(nc, varnams = "T_SAND", lon = df_hwsd$lon |> unique() |> sort(), lat = df_hwsd$lat |> unique() |> sort(), path = "data/T_SAND.nc", make_zdim = FALSE)

system("cdo remapbil,data-raw/grid/gridfile_halfdeg.txt data/T_SAND.nc data/T_SAND_halfdeg.nc")

nc_halfdeg <- read_nc_onefile("data/T_SAND_halfdeg.nc", varnam = "T_SAND")
gg <- plot_map3(
  nc_halfdeg, 
  varnam = "T_SAND", 
  breaks = seq(0, 100, by = 10), 
  latmin = -60, latmax = 75,
  spacing = "constant",
  colorscale = viridis::magma,
  combine = FALSE
  )
gg$ggmap <- gg$ggmap + labs(title = "Sand fraction", subtitle = "Topsoil, percent")
cowplot::plot_grid(gg$ggmap, gg$gglegend, ncol = 2, rel_widths = c(1, 0.2))
ggsave("fig/map_T_SAND.pdf", width = 10, height = 6)

if (siteset != "global"){
  ##----------------------------------------------
  ## Site-scale set
  ##----------------------------------------------
  ## Collect HWSD data from database
  filn <- paste0("data/df_hwsd_", siteset, ".RData")
  if (!file.exists(filn)){
    df_hwsd <- ingest(
      siteinfo,
      source = "hwsd",
      settings = list(fil = "~/data/hwsd/HWSD_RASTER/hwsd.bil")
      )
    save(df_hwsd, file = filn)
  } else {
    load(filn)
  }

  ## Calculate FC, PWP, and WHC from texture data.
  filn <- paste0("data/df_whc_", siteset, ".RData")
  if (!file.exists(filn)){
    df_whc <- df_hwsd |> 
      mutate(data = purrr::map(data, ~slice(., 1))) |> 
      mutate(
        data_soiltext_top = purrr::map(data, ~dplyr::select(
          ., fclay = T_CLAY, fgravel = T_GRAVEL, forg = T_OC, fsand = T_SAND, roots = ROOTS, imperm = IL)),
        data_soiltext_sub = purrr::map(data, ~dplyr::select(
          ., fclay = S_CLAY, fgravel = S_GRAVEL, forg = S_OC, fsand = S_SAND, roots = ROOTS, imperm = IL))
        ) |> 
      dplyr::select(-data) |> 
      mutate(data_soiltext_top = purrr::map(data_soiltext_top, ~calc_soilparams(., method = "balland")),
             data_soiltext_sub = purrr::map(data_soiltext_sub, ~calc_soilparams(., method = "balland")))

    save(df_whc, file = filn)
  } else {
    load(filn)
  }

}

## add to meta data table
siteinfo <- siteinfo |> 
  left_join(df_whc, by = "sitename")

load("data/df_hwsd_hires.RData")

if (siteset!="global"){
 
df_whc <- df_hwsd |> 
  group_by(lon, lat) |> 
  nest() |> 
  mutate(
    data_soiltext_top = purrr::map(data, ~dplyr::select(
      ., fclay = T_CLAY, fgravel = T_GRAVEL, forg = T_OC, fsand = T_SAND, roots = ROOTS)),
    data_soiltext_sub = purrr::map(data, ~dplyr::select(
      ., fclay = S_CLAY, fgravel = S_GRAVEL, forg = S_OC, fsand = S_SAND, roots = ROOTS))
    ) |> 
  dplyr::select(-data) |> 
  mutate(data_soiltext_top = purrr::map(data_soiltext_top, ~calc_soilparams(., method = "balland")),
         data_soiltext_sub = purrr::map(data_soiltext_sub, ~calc_soilparams(., method = "balland")))
}

if (siteset != "global"){
  ##----------------------------------------------
  ## Site-scale set
  ##----------------------------------------------
  ## Collect HWSD data from database
  filn <- paste0("data/df_wtd_fan_", siteset, ".RData")
  if (!file.exists(filn)){
    df_wtd <- siteinfo |> 
      dplyr::select(sitename, lon, lat) |> 
      ingest_wtd_fan()
    save(df_wtd, file = filn)
  } else {
    load(filn)
  }

}

## add to meta data table
siteinfo <- siteinfo |> 
  left_join(df_wtd |> 
              dplyr::select(sitename, wtd), 
            by = "sitename"
            )

library(rgdal)

# read in the polygons
# shape <- readOGR("~/data/biomes/olson2001_teow/wwf_terr_ecos.shp")
shape <- readOGR("~/data/biomes/wwf_ecoregions/official/wwf_terr_ecos.shp")

# create empty raster
rasta <- raster(nrows=3600, ncols=7200, xmx=180, ymn=-90, ymx=90, crs=CRS("+init=EPSG:4326"))

# convert polygons to 1x1 raster
rasta_biome <- rasterize(shape, rasta, background=NA, field="BIOME")
#plot(rasta_biome)

# remove no data values
rasta_biome[rasta_biome %in% c(98, 99)] <- NA

# convert raster to factor
rasta_biome <- as.factor(rasta_biome)

# save to files
saveRDS( rasta_biome, "~/data/biomes/wwf_ecoregions/official/wwf_terr_ecos_raster.rds")

writeRaster( rasta_biome, "~/data/biomes/wwf_ecoregions/official/wwf_terr_ecos_raster.nc", 
             overwrite=TRUE, format="CDF", varname="biome", varunit="category", 
             longname="WWF ecoregions biome", xname="lon", yname="lat"
             )

if (siteset != "global"){
  ##----------------------------------------------
  ## Site-scale set
  ##----------------------------------------------
  ## WWF biome (Ecoregions dataset)
  filn <- paste0("data/df_biome_wwf_", siteset, ".RData")
  if (!file.exists(filn)){
    
    df_wwf <- ingest(
      dplyr::select(siteinfo, sitename, lon, lat),
      source = "wwf",
      dir = "~/data/biomes/wwf_ecoregions/official/",
      settings = list(layer = "wwf_terr_ecos")
      ) |> 
      mutate(data = purrr::map(data, ~slice(., 1)))
    
    save(df_wwf, file = filn)
  } else {
    load(filn)
  }
}

## add to meta data table
siteinfo <- siteinfo |> 
  left_join(df_wwf |> 
              mutate(data = purrr::map(data, ~dplyr::select(., biome_id = BIOME, biome_name = BIOME_NAME))) |>
              tidyr::unnest(data), 
            by = "sitename"
            )

filn <- paste0("data/siteinfo_", siteset, ".RData")
save(siteinfo, file = filn)

load(filn)
# filn <- paste0("data/siteinfo_", siteset, ".csv")
# siteinfo |> 
#   tidyr::unnest(c(data_soiltext_top, data_soiltext_sub)) |> 
#   write_csv(path = filn)
