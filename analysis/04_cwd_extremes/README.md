# Optional extreme-value analysis (not part of the core workflow)

The scripts in this directory are retained for provenance and optional
experiments. They fit Gumbel/GEV distributions to annual CWD maxima and derive
return levels, but the core analysis no longer submits or requires them.

The core workflow ends with
`analysis/04_annual_cwd/01_calculate_annual_cwd.R`, which writes the annual CWD
values and their paired preceding cumulative-surplus maxima without fitting an
extreme-value distribution.
