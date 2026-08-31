#!/usr/bin/env bash

if [[ -f ~/.bash_profile ]]; then
  source ~/.bash_profile
fi
set -euo pipefail
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$project_root/data"

eudrs df_corr.rds
eudrs df_rl_fet.rds
eudrs df_rl_agg_fet.rds
eudrs df_cwdx_10_20_40.rds
eudrs df_cwdx_10_20_80.rds
eudrs df_whc_hires_lasthope.rds
eudrs df_whc.rds
eudrs df_cwd_lue0_2.rds
eudrs df_cwd_et0_3.rds
eudrs df_rivers.rds
eudrs df_mct_merged.rds
eudrs df_mask.rds
