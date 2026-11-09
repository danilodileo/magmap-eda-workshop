# AGENTS.md

Rules for Claude Code and any other AI agent working in this folder: a first exploratory
analysis of an nf-core/magmap run, made by PhD students and discussed with the PI.

## Communication style

The people using this folder are often new to R and the command line. Be direct and concise.

- Answer the question, then stop. No preamble, no recap of the question, no restating the
  plan before doing it.
- Plain words, short sentences, one idea per sentence. Match the length of the answer to the
  question.
- State what is true, what changed, and what to do next. No enthusiasm, no hedging.

## Code comments

- Default to no comment. Comment only to say *why*: a non-obvious constraint, a property of
  the data, a workaround.
- Never narrate the code or the change ("loop over samples", "fixed X"). A comment must make
  sense to someone reading the file for the first time.
- Keep each comment to the one fact the reader needs at that line, in the fewest words.

## Folder structure

```
AGENTS.md            this file
CLAUDE.md            one line, @AGENTS.md: Claude Code reads CLAUDE.md, not AGENTS.md
seminar_guide.md     the seminar guide (for people, not for agents)
input_data/          the tables of one magmap run (read-only)
template/
  magmap_eda.qmd     the report
  magmap_helpers.R   functions the report sources
  prepare_input.R    optional: converts the tables in input_data/ to Parquet, for faster renders
  _quarto.yml        sends the rendered report to output/
output/              rendered reports
```

- Never edit, rename or delete anything in `input_data/`. The only files written there are
  the Parquet copies `prepare_input.R` makes.
- No `setwd()` and no absolute paths. The report reads `../input_data/` relative to itself.
- Put new analyses in `template/magmap_eda.qmd` (or a new `.qmd` next to it); reusable
  functions in `template/magmap_helpers.R`. Reuse what is there before writing new code.

## The data

`input_data/` holds the `summary_tables` of one magmap run, plus function annotations made
outside magmap and a sample table. Each magmap table can be `.parquet` (runs with
`--save_parquet`) or `.tsv.gz`; the report uses Parquet when it is there, else the TSV.

| File | Columns |
|---|---|
| `magmap.CDS.counts.{parquet,tsv.gz}` | `accno, orf, chr, start, end, strand, length, sample, count, tpm` |
| `magmap.genome_metadata.{parquet,tsv.gz}` | `accno, gtdb_taxonomy, checkm_completeness, checkm_contamination, genome_size, …` |
| `magmap.prokka-annotations.{parquet,tsv.gz}` | `orf, ftype, length, gene, ec_number, cog, product` |
| KOfamScan `-f detail-tsv` output (name contains `kofam`), or `kofamscan-uniq.parquet` | read as `orf, ko, ko_definition`: best significant hit, one row per ORF |
| `*.emapper.annotations`, or `emapper.parquet` | read as `orf, ko, preferred_name, description, cog_category`: first KO, one row per ORF |
| `sample_table.tsv` | `sample` plus the student's own columns, e.g. `treatment`, `site`, `date` |

Facts that are easy to get wrong:

- The counts table has rows only where `count > 0`. A missing sample–ORF pair is a zero.
  Means and prevalences over samples divide by the total number of samples, never by the
  number of rows.
- `tpm` sums to 10^6 per sample over all ORFs of the feature type. % of TPM is `tpm / 1e4`.
  A MAG's share is the sum of its ORFs' TPM.
- `gtdb_taxonomy` is `d__…;p__…;…;s__…`. Strip the prefixes and turn empty ranks into `NA`.
  Keep genomes without a classification and show them as `Unassigned`; never drop them.
- Below the top taxa, keep `Other` (classified but small) apart from `Unassigned` (not
  classified at that rank). They mean different things: diversity vs. database coverage.
- magmap produces no KOs. They come from KOfamScan or eggNOG-mapper. Check that their ORF ids
  match `orf` in the counts table, and report the share of TPM that has a KO.
- An ORF's abundance mixes how abundant its organism is with how much the gene is expressed.
  Read top genes together with the KO level.
- magmap also writes counts for other features (`magmap.rRNA.counts.*` etc.). Use CDS unless
  the question is about those.

## Getting a new run into input_data/

1. Copy the run's `summary_tables/` files (`magmap.*.parquet` if there are any, else
   `magmap.*.tsv.gz`), the KOfamScan output (`exec_annotation -f detail-tsv`) and/or the
   eggNOG-mapper `*.emapper.annotations`, and `sample_table.tsv` into `input_data/`.
   Ask the student where the files are; don't guess paths.
2. If the report is slow to render, offer `Rscript template/prepare_input.R input_data`: it
   writes Parquet copies once, so tables aren't re-read from TSV on every render.
3. Check that every `sample` in the counts table is in `sample_table.tsv` and the other way
   round. Report mismatches and odd values (dates that don't parse, `3-0,2` vs `3-0.2`).
4. Ask which column of `sample_table.tsv` groups the samples, and set `GROUP` in the
   `constants` chunk of the report.

## Reading the tables in R

Read magmap tables with `read_magmap()` from `magmap_helpers.R`. It opens the Parquet file, or
the TSV if there is none, as a lazy `duckplyr` table, so the data stay on disk until a result
is needed:

```r
counts <- read_magmap("magmap.CDS.counts", "../input_data")
```

It uses `prudence = "stingy"`, which makes `duckplyr` stop with an error instead of silently
loading the whole table into R. Keep the table lazy and `collect()` only small summaries.
Function annotations: `read_kofamscan()` and `read_emapper()`, which return one row per ORF.

- Use `.by`, not `group_by()`: `summarise(x = sum(y, na.rm = TRUE), .by = c(sample, taxon))`.
- Give `sum()`, `mean()` and `max()` `na.rm = TRUE`.
- Not translated (duckplyr 1.2): `as.character()`, `case_when()`, `ifelse()` (`if_else()`
  works), `separate()`, `pivot_wider()`, `pivot_longer()`, `factor()`, and `{{ }}` inside
  `filter()`. Aggregate first, `collect()` the small result, then use them locally; for
  `{{ }}`, `transmute()` to a fixed column name before filtering.
- With `library(duckplyr)` loaded, `left_join()` on in-memory tibbles does not keep row
  order. Sort with `arrange()` after the last join, right before a table is shown.
- Never `collect()` the full counts table. Rank and cut (`arrange()` + `head()`) inside DuckDB.

## Reports

- Section skeleton: Summary, Introduction, Materials and Methods, Results, Discussion,
  References. Packages are cited with `grateful::cite_packages()`.
- Every figure and table has a `#| label:` and a caption that states the unit (TPM, % of
  TPM, counts) and what was averaged over.
- Numbers in the text come from inline R, never typed by hand.
- Same variable, same colours in every figure: build a palette once with `assign_palette()`
  and reuse it.
- Write what the data show. Leave Summary, Discussion and the biological interpretation to
  the student; write them only when asked.
- Render with `quarto render template/magmap_eda.qmd`; `template/_quarto.yml` sends the HTML
  to `output/`. Before saying a task is done, render and report any error or unexpected warning.

## Safety

- The data are unpublished: don't upload them anywhere or paste them into web services.
- Don't push to a remote, and don't install packages, without asking first.
