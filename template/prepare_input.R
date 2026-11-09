#!/usr/bin/env Rscript

# Optional. The report reads .tsv.gz tables and raw KOfamScan/eggNOG-mapper output directly,
# but every render re-reads them. This converts them once to Parquet, which is faster:
#   magmap.*.tsv.gz                -> magmap.*.parquet
#   KOfamScan detail-tsv (*kofam*) -> kofamscan-uniq.parquet
#   *.emapper.annotations          -> emapper.parquet
# Existing Parquet files are left alone; the original files are not touched.
#
# Usage, from the folder root: Rscript template/prepare_input.R input_data

script_dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)))
source(file.path(script_dir, "magmap_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
dir <- if (length(args)) args[1] else "input_data"

for (tsv in Sys.glob(file.path(dir, "magmap.*.tsv.gz"))) {
  out <- sub("[.]tsv[.]gz$", ".parquet", tsv)
  if (file.exists(out)) next
  compute_parquet(read_magmap(sub("[.]tsv[.]gz$", "", basename(tsv)), dir), out)
  message("wrote ", out)
}

out <- file.path(dir, "kofamscan-uniq.parquet")
if (!file.exists(out)) {
  kofam <- read_kofamscan(dir)
  if (!is.null(kofam)) { compute_parquet(kofam, out); message("wrote ", out) }
}

out <- file.path(dir, "emapper.parquet")
if (!file.exists(out)) {
  emapper <- read_emapper(dir)
  if (!is.null(emapper)) { compute_parquet(emapper, out); message("wrote ", out) }
}
