# magmap EDA workshop

A first exploratory report on an [nf-core/magmap](https://nf-co.re/magmap) run, written in
Quarto and R, built and changed with Claude Code.

The report covers the data overview, taxonomic composition, NMDS, top MAGs, top genes, top
functions and P/N marker genes. The workshop plan is in [seminar_guide.md](seminar_guide.md).

## Before the workshop

Install:

1. [VS Code](https://code.visualstudio.com/) with the extensions *Claude Code* (Anthropic),
   *Quarto*, *R* and *Remote - SSH*.
2. Claude Code: `curl -fsSL https://claude.ai/install.sh | bash`, then run `claude` once and
   log in.
3. [R](https://cran.r-project.org/), [RStudio](https://posit.co/download/rstudio-desktop/),
   [Quarto](https://quarto.org/docs/get-started/), and the R packages:
   ```r
   install.packages(c("tidyverse", "duckplyr", "vegan", "knitr", "grateful", "RColorBrewer"))
   ```
4. A UTF-8 locale: `echo $LANG` should print something like `en_US.UTF-8`. Without it,
   `grateful` fails on names with accents.

Then clone the repo:

```bash
git clone https://github.com/danilodileo/magmap-eda-workshop.git
cd magmap-eda-workshop
```

## What's in the repo

```
AGENTS.md            rules for Claude Code and other AI agents working in this folder
CLAUDE.md            one line, @AGENTS.md: Claude Code reads CLAUDE.md, not AGENTS.md
seminar_guide.md     the workshop guide
template/
  magmap_eda.qmd     the report
  _pn_genes.qmd      P and N marker genes section, included by the report
  magmap_helpers.R   functions the report uses
  prepare_input.R    optional: Parquet copies of the tables, for faster renders
  _quarto.yml        sends the rendered report to output/
```

**There are no data in the repo.** `input_data/` and `output/` are in `.gitignore`. The data
are unpublished, so keep them out of any commit.

## Running the report on your own run

1. Create `input_data/` in the repo folder.
2. Put these files in it:
   - from the run's `summary_tables/`: `magmap.CDS.counts`, `magmap.genome_metadata` and
     `magmap.prokka-annotations`, as `.parquet` or `.tsv.gz`
   - optional: KOfamScan output (`exec_annotation -f detail-tsv`) or eggNOG-mapper
     `*.emapper.annotations`, made on this run's Prokka proteins
   - optional: `P_N_marker_genes.tsv`; without it the marker section is skipped
   - `sample_table.tsv`: one row per sample, tab-separated, with at least `sample` (exactly as
     in the counts), `filter_fraction` and `date` (`YYYY-MM-DD`)

   Or ask Claude Code: *"Get my magmap run into input_data/. The summary tables are in …, the
   sample table is …"*. It follows the procedure in `AGENTS.md`.
3. Check the `constants` chunk at the top of `template/magmap_eda.qmd`:
   - `FRACTION`: the filter fractions to keep
   - `GROUP`: the column that groups the samples
   - `USE_KO`: `TRUE` once you have KOfamScan or eggNOG-mapper output for this run
4. Render:
   ```bash
   quarto render template/magmap_eda.qmd
   ```
   The report is written to `output/magmap_eda.html`.

With large runs, make Parquet copies once, so tables aren't re-read on every render:

```bash
Rscript template/prepare_input.R input_data
```

## How the report handles the data

- Samples with the same date are replicates. Figures show the mean of each date's replicates
  (± 1 SD). Tables give the mean over dates, with the SD between dates and between replicates.
- Abundance is % of TPM, the share of the CDS transcripts in a sample that map to the genome
  catalogue. It is not a share of the whole community.
- Seasons are meteorological (winter = December–February).

## Data safety

Prompts and the files Claude Code reads are sent to Anthropic's servers. Follow your group's
and your university's rules for unpublished data.
