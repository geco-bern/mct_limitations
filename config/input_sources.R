# Climate-input namelist.
#
# Edit IDs, paths, variable names, transformations, and regular grids here;
# analysis scripts should not need source-specific edits. Values are transformed
# as `value * scale + offset`. ET conversion can be "latent_energy_to_mm" or
# "identity_mm_day". ET, precipitation, and temperature IDs are embedded in
# output names. Total precipitation is partitioned into rain and snow using the
# configured temperature source during snow simulation.

list(
  analysis_period = list(
    start_year = 2003L,
    end_year = 2017L
  ),

  et = list(
    id = "alexi",
    source = list(
      netcdf_dir = "~/data/alexi_tir/netcdf",
      netcdf_pattern = "^EDAY_CERES_.*[.]nc$",
      recursive = FALSE,
      tidy_dir = "~/data/alexi_tir/data_tidy",
      tidy_prefix = "EDAY_CERES_",
      variable = "et",
      longitude_name = "lon",
      latitude_name = "lat",
      time_name = "time",
      conversion = "latent_energy_to_mm",
      scale = 1e6,
      offset = 0,
      grid = list(
        longitude_start = -179.975,
        longitude_step = 0.05,
        longitude_count = 7200L,
        latitude_start = -89.975,
        latitude_step = 0.05,
        latitude_count = 3600L
      )
    )
  ),

  precipitation = list(
    id = "mswep-v3.16-past",
    # MSWEP is total precipitation in mm d-1; snow is diagnosed from temperature.
    form = "total",
    rain = list(
      netcdf_dir = "~/data/mswep_v316/Past/Daily",
      netcdf_pattern = "^[0-9]{7}[.]nc$",
      recursive = FALSE,
      tidy_dir = "~/data/mswep_v316/data_tidy_past_daily",
      tidy_prefix = "MSWEP_V316_Past_Daily",
      variable = "precipitation",
      longitude_name = "lon",
      latitude_name = "lat",
      time_name = "time",
      scale = 1,
      offset = 0,
      grid = list(
        longitude_start = -179.95,
        longitude_step = 0.1,
        longitude_count = 3600L,
        latitude_start = -89.95,
        latitude_step = 0.1,
        latitude_count = 1800L
      )
    )
  ),

  temperature = list(
    id = "era5-land",
    source = list(
      # Daily-mean 2 m temperature, bilinearly regridded to MSWEP cell centres.
      netcdf_dir = "~/data/era5_land/daily_2m_temperature_mswep_grid",
      netcdf_pattern = "^era5_land_t2m_daily_.*[.]nc$",
      recursive = FALSE,
      tidy_dir = "~/data/era5_land/data_tidy_daily_mswep_grid",
      tidy_prefix = "ERA5_Land_t2m_Daily",
      variable = "t2m",
      longitude_name = "longitude",
      latitude_name = "latitude",
      time_name = "valid_time",
      scale = 1,
      offset = -273.15,
      grid = list(
        longitude_start = -179.95,
        longitude_step = 0.1,
        longitude_count = 3600L,
        latitude_start = -89.95,
        latitude_step = 0.1,
        latitude_count = 1800L
      )
    )
  ),

  elevation_file = "~/data/etopo/ETOPO1_Bed_g_gef_0.05deg_STANDARD.nc"
)
