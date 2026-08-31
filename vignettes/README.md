# Reports and supplementary analyses

These R Markdown files are focused reports, validation analyses, and figure
work. They are not the execution order for the computational pipeline; that is
defined under `analysis/` and documented in the repository README.

Important reports include `rsip.Rmd`, `eval_et.Rmd`,
`rsofun_rsip_mct.Rmd`, `rsip_tga.Rmd`, and `create_suppl_info.Rmd`. All active
reports knit with the project root as their working directory so their existing
relative data and function paths remain valid.

`archive/workflow_legacy.Rmd` preserves the original monolithic workflow for
provenance. Its executable work was separated into numbered analysis stages;
new computation should not be added to the archived notebook.

