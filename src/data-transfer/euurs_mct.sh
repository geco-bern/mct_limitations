#!/usr/bin/env bash

if [[ -f ~/.bash_profile ]]; then
  source ~/.bash_profile
fi
set -euo pipefail
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$project_root/data"

euurs df_corr.rds
euurs gg_fig1a.rds
euurs gg_fig1b.rds
euurs gg_fig1_legend.rds
euurs gg_rsip_10.rds
euurs gg_rsip_25.rds
euurs gg_rsip_50.rds
euurs gg_rsip_75.rds
euurs gg_rsip_90.rds
euurs gg_sj02_10.rds
euurs gg_sj02_25.rds
euurs gg_sj02_50.rds
euurs gg_sj02_75.rds
euurs gg_sj02_90.rds
euurs gg_sif_50.rds
euurs gg_ef_50.rds
euurs df_rl_fet.rds
euurs df_rl_agg_fet.rds
euurs df_cwdx_10_20_40.rds
euurs df_cwdx_10_20_80.rds
euurs df_whc_hires_lasthope.rds
euurs df_whc.rds
euurs df_cwd_lue0_2.rds
euurs df_cwd_et0_3.rds
euurs df_rivers.rds
euurs df_sj02_biome_wwf_NEW.rds
euurs siteinfo_sj02.rds
euurs df_zroot_sj02.rds
euurs df_mct_merged.rds
euurs df_mask.rds
euurs df_zroot80.rds
euurs cwdx10_tenthdeg.nc
euurs cwdx20_tenthdeg.nc
euurs cwdx40_tenthdeg.nc
euurs cwdx80_tenthdeg.nc
euurs cwdx100_tenthdeg.nc
euurs cwdx200_tenthdeg.nc
euurs gg_fig1c.rds
