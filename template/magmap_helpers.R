# Functions sourced by magmap_eda.qmd. They accept a lazy duckplyr table, aggregate inside
# DuckDB and collect() only the small result. Most ggplot() calls stay in the report;
# plot_time_lines() is here because several sections draw the same figure.
#
# magmap's counts table only has rows where count > 0, so means and prevalences divide by
# the number of samples, never by the number of rows a feature has.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(duckplyr)
  library(RColorBrewer)
  library(ggplot2)
})

GTDB_TAXRANKS <- c("domain", "phylum", "class", "order", "family", "genus", "species")

# Colour-blind-safe qualitative palettes: Okabe & Ito (2008) without black and grey, and
# Paul Tol's "muted". Grey stays free for Other and Unassigned.
CB_PALETTES <- list(
  okabe_ito = c("#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7"),
  tol_muted = c("#332288", "#88CCEE", "#44AA99", "#117733", "#999933", "#DDCC77", "#CC6677",
                "#882255", "#AA4499")
)

SEASONS <- c("Winter", "Spring", "Summer", "Autumn")
SEASON_PAL <- setNames(CB_PALETTES$okabe_ito[c(5, 3, 1, 6)], SEASONS)
# Filled shapes, so fill carries the colour and the outline keeps light colours visible
SEASON_SHAPES <- setNames(c(21, 24, 22, 23), SEASONS)

# Meteorological seasons (winter = Dec-Feb)
season_of <- function(date) {
  month <- as.integer(format(date, "%m"))
  factor(SEASONS[c(1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 1)][month], levels = SEASONS)
}

# A magmap table (`name` without extension, e.g. "magmap.CDS.counts") as a lazy duckplyr
# table: the .parquet file if there is one, else .tsv.gz or .tsv. TSV works the same but is
# re-read on every query, so it is slower; prepare_input.R converts it once.
read_magmap <- function(name, dir) {
  files <- file.path(dir, paste0(name, c(".parquet", ".tsv.gz", ".tsv")))
  file <- files[file.exists(files)][1]
  if (is.na(file)) stop("No ", name, ".parquet, .tsv.gz or .tsv in ", dir)
  if (endsWith(file, ".parquet")) {
    read_parquet_duckdb(file, prudence = "stingy")
  } else {
    # Sample names like 001 must stay text
    read_csv_duckdb(file, prudence = "stingy",
                    options = list(delim = "\t", nullstr = "NA", types = list(sample = "VARCHAR")))
  }
}

# Raw KOfamScan output (exec_annotation -f detail-tsv) -> one row per ORF: orf, ko,
# ko_definition. Two header lines; '*' in the first column marks hits above the KO's
# threshold, and the best-scoring one is kept.
read_kofamscan_raw <- function(file) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbGetQuery(con, sprintf("
    SELECT orf, ko, ko_definition FROM (
      SELECT orf, ko, ko_definition,
        row_number() OVER (PARTITION BY orf ORDER BY TRY_CAST(score AS DOUBLE) DESC, ko) AS rn
      FROM read_csv(%s, delim = '\t', header = false, skip = 2, quote = '\"', all_varchar = true,
        columns = {'sig': 'VARCHAR', 'orf': 'VARCHAR', 'ko': 'VARCHAR', 'thrshld': 'VARCHAR',
                   'score': 'VARCHAR', 'evalue': 'VARCHAR', 'ko_definition': 'VARCHAR'})
      WHERE sig = '*'
    ) WHERE rn = 1 ORDER BY orf", DBI::dbQuoteString(con, file))) %>%
    as_tibble()
}

# Raw eggNOG-mapper output (*.emapper.annotations) -> one row per ORF: orf, ko,
# preferred_name, description, cog_category. Only the first KO of an ORF is kept, so its TPM
# isn't counted twice.
read_emapper_raw <- function(file) {
  # The "#query" header follows a variable number of "##" lines
  skip <- which(startsWith(readLines(file, n = 50), "#query"))[1] - 1
  if (is.na(skip)) stop("No '#query' header line in ", file)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbGetQuery(con, sprintf("
    SELECT \"#query\" AS orf,
      NULLIF(regexp_extract(KEGG_ko, 'ko:(K[0-9]+)', 1), '') AS ko,
      NULLIF(Preferred_name, '-') AS preferred_name,
      NULLIF(Description, '-') AS description,
      NULLIF(COG_category, '-') AS cog_category
    FROM read_csv(%s, delim = '\t', header = true, skip = %d, all_varchar = true, null_padding = true, quote = '')
    WHERE \"#query\" NOT LIKE '#%%'", DBI::dbQuoteString(con, file), skip)) %>%
    as_tibble()
}

# Function annotations in `dir`, one row per ORF, or NULL if there are none: the converted
# Parquet file if prepare_input.R made one, else the raw output read directly.
read_kofamscan <- function(dir) {
  pq <- file.path(dir, "kofamscan-uniq.parquet")
  if (file.exists(pq)) return(read_parquet_duckdb(pq, prudence = "stingy") %>% collect())
  raw <- grep("[.]parquet$", Sys.glob(file.path(dir, "*kofam*")), value = TRUE, invert = TRUE)
  if (length(raw)) read_kofamscan_raw(raw[1]) else NULL
}
read_emapper <- function(dir) {
  pq <- file.path(dir, "emapper.parquet")
  if (file.exists(pq)) return(read_parquet_duckdb(pq, prudence = "stingy") %>% collect())
  raw <- Sys.glob(file.path(dir, "*.emapper.annotations"))
  if (length(raw)) read_emapper_raw(raw[1]) else NULL
}

# genome_metadata -> one column per GTDB rank, prefixes stripped, empty ranks NA
parse_gtdb <- function(genome_metadata) {
  genome_metadata %>%
    separate(gtdb_taxonomy, GTDB_TAXRANKS, sep = ";", fill = "right") %>%
    mutate(across(all_of(GTDB_TAXRANKS), ~ na_if(sub("^[a-z]__", "", .), "")))
}

# Most resolved rank as a label: species, genus, else the lowest named rank with its prefix
lowest_taxon <- function(taxonomy, unassigned = "Unassigned") {
  taxonomy %>%
    mutate(lowest_taxon = coalesce(
      species, genus,
      paste0("f__", family), paste0("o__", order), paste0("c__", class), paste0("p__", phylum),
      unassigned
    ))
}

# Named colours for `levels` (in that order) plus Other and Unassigned. Build once per
# variable and reuse, so a taxon or group has the same colour in every figure.
# `palette` is a name in CB_PALETTES or an RColorBrewer palette.
assign_palette <- function(levels, palette = "tol_muted", other = "Other", unassigned = "Unassigned") {
  n <- length(levels)
  max_n <- if (palette %in% names(CB_PALETTES)) length(CB_PALETTES[[palette]]) else brewer.pal.info[palette, "maxcolors"]
  if (n > max_n) stop(sprintf("%d levels but palette %s has %d colours; show fewer levels", n, palette, max_n))
  colours <- if (palette %in% names(CB_PALETTES)) {
    CB_PALETTES[[palette]][seq_len(n)]
  } else {
    brewer.pal(max(n, 3), palette)[seq_len(n)]
  }
  setNames(c(colours, "grey70", "grey40"), c(levels, other, unassigned))
}

# One row per feature (accno, orf, ko, phylum, ...): sum, mean, SD and max of `value` over
# all `n_samples` samples, prevalence, and rank by sum. With a finite `n`, only the top `n`
# are collected, so a per-ORF table never reaches R in full.
feature_stats <- function(tbl, feature, value, n_samples, n = Inf) {
  feature_name <- rlang::as_label(rlang::enquo(feature))
  stats <- tbl %>%
    transmute(.feature = {{ feature }}, sample, .value = {{ value }}) %>%
    filter(!is.na(.feature)) %>%
    summarise(.persample = sum(.value, na.rm = TRUE), .by = c(.feature, sample)) %>%
    summarise(
      sum = sum(.persample, na.rm = TRUE), ss = sum(.persample * .persample, na.rm = TRUE),
      max = max(.persample, na.rm = TRUE), n_present = n(),
      .by = .feature
    ) %>%
    arrange(desc(sum))
  if (is.finite(n)) stats <- head(stats, n)
  stats %>%
    collect() %>%
    arrange(desc(sum)) %>%
    # SD from sums, so samples without a row count as zeros
    mutate(
      rank = row_number(), mean = sum / n_samples,
      sd = sqrt(pmax(ss - sum^2 / n_samples, 0) / (n_samples - 1)),
      prevalence = n_present / n_samples
    ) %>%
    select(-ss) %>%
    rename(!!feature_name := .feature)
}

# Per-sample values from feature_by_sample() -> mean and SD over the samples of each unit
# (`units`: sample, unit). SD is NA for a unit with one sample.
replicate_summary <- function(by_sample, units) {
  feature_cols <- setdiff(names(by_sample), c("sample", "value"))
  by_sample %>%
    inner_join(units %>% select(sample, unit), by = "sample") %>%
    summarise(mean = mean(value), sd = sd(value), n = n(), .by = all_of(c(feature_cols, "unit")))
}

# Replicate SD of each of `features`, averaged over units: how far replicates of one date
# differ, to set against the SD between dates from feature_stats()
replicate_sd <- function(tbl, feature, value, features, units) {
  feature_by_sample(tbl, {{ feature }}, {{ value }}, features, units$sample) %>%
    replicate_summary(units) %>%
    summarise(rep_sd = mean(sd, na.rm = TRUE), .by = -c(unit, mean, sd, n))
}

# Per-sample `value` of `features`, with zeros for every sample in `samples`
feature_by_sample <- function(tbl, feature, value, features, samples) {
  feature_name <- rlang::as_label(rlang::enquo(feature))
  tbl %>%
    transmute(.feature = {{ feature }}, sample, .value = {{ value }}) %>%
    filter(.feature %in% !!features) %>%
    summarise(value = sum(.value, na.rm = TRUE), .by = c(.feature, sample)) %>%
    collect() %>%
    complete(.feature = features, sample = samples, fill = list(value = 0)) %>%
    rename(!!feature_name := .feature)
}

# Per-sample `value` by `rank`, with taxa outside `top` as `other` and NA as `unassigned`
# (kept apart: small-but-classified and unclassified mean different things).
composition_data <- function(tbl, rank, value, top, other = "Other", unassigned = "Unassigned") {
  tbl %>%
    transmute(.rank = {{ rank }}, sample, .value = {{ value }}) %>%
    summarise(value = sum(.value, na.rm = TRUE), .by = c(sample, .rank)) %>%
    collect() %>%
    mutate(.display = case_when(is.na(.rank) ~ unassigned, .rank %in% top ~ .rank, TRUE ~ other)) %>%
    summarise(value = sum(value), .by = c(sample, .display)) %>%
    mutate(.display = factor(.display, levels = c(top, other, unassigned)))
}

# Mean `value` over `n_samples` of each `features` element (e.g. KOs), split by `by`
# (e.g. genus), with the same Other/Unassigned split as composition_data()
contribution_data <- function(tbl, feature, by, value, features, top, n_samples,
                              other = "Other", unassigned = "Unassigned") {
  feature_name <- rlang::as_label(rlang::enquo(feature))
  tbl %>%
    transmute(.feature = {{ feature }}, .by_value = {{ by }}, .value = {{ value }}) %>%
    filter(.feature %in% !!features) %>%
    summarise(value = sum(.value, na.rm = TRUE), .by = c(.feature, .by_value)) %>%
    collect() %>%
    mutate(.display = case_when(is.na(.by_value) ~ unassigned, .by_value %in% top ~ .by_value, TRUE ~ other)) %>%
    summarise(value = sum(value) / n_samples, .by = c(.feature, .display)) %>%
    mutate(.display = factor(.display, levels = c(top, other, unassigned))) %>%
    rename(!!feature_name := .feature)
}

# Replicate means over time, one panel per `label` with its own y axis. `df`: label, date,
# season, mean and sd (TPM); error bars are ± 1 SD between replicates.
plot_time_lines <- function(df, ncol = 2, y = "% of TPM") {
  ggplot(df, aes(x = date, y = mean / 1e4)) +
    geom_line(colour = "grey40", linewidth = 0.4) +
    geom_linerange(aes(ymin = pmax(mean - sd, 0) / 1e4, ymax = (mean + sd) / 1e4),
                   colour = "grey55", na.rm = TRUE) +
    geom_point(aes(fill = season, shape = season), size = 1.8, stroke = 0.3) +
    facet_wrap(~ label, ncol = ncol, scales = "free_y") +
    scale_fill_manual(values = SEASON_PAL, name = "Season", drop = FALSE) +
    scale_shape_manual(values = SEASON_SHAPES, name = "Season", drop = FALSE) +
    scale_x_date(date_breaks = "3 months", date_labels = "%b\n%Y") +
    labs(x = NULL, y = y) +
    theme(legend.position = "top", strip.text = element_text(size = 8))
}

# Cyclic colour scale for day of year, so late December and early January look alike.
# Get doy with as.integer(format(date, "%j")).
scale_colour_doy <- function(name = "Day of year", ...) {
  ggplot2::scale_colour_gradientn(
    colours = grDevices::hcl(h = seq(250, 610, length.out = 25), c = 70, l = 60),
    limits = c(1, 366), name = name, na.value = "grey50",
    breaks = c(1, 91, 182, 274), labels = c("Jan", "Apr", "Jul", "Oct"), ...
  )
}
