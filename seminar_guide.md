# From magmap output to a first report with Claude Code — seminar guide

**Goal:** by the end of the session everyone can put the tables of a magmap run in a folder,
have Claude Code produce a first exploratory report (composition, NMDS, top MAGs, top genes,
top functions, P/N marker genes) and bring it to a discussion with the PI or with each other.

## The folder

```
magmap-eda-workshop/
├── README.md            install, clone, run the report
├── seminar_guide.md     this guide
├── AGENTS.md            rules for Claude or any other AI agent working in the folder
├── CLAUDE.md            one line, @AGENTS.md: Claude Code reads CLAUDE.md, not AGENTS.md
├── .gitignore           keeps input_data/ and output/ out of git
├── input_data/          the tables of one magmap run (not in the repo: you add them)
├── template/
│   ├── magmap_eda.qmd   the report
│   ├── _pn_genes.qmd    P and N marker genes section, included by the report
│   ├── magmap_helpers.R functions the report uses
│   ├── prepare_input.R  optional: makes Parquet copies of the tables, for faster renders
│   └── _quarto.yml      sends the rendered report to output/
└── output/
    └── magmap_eda.html  the rendered report (not in the repo)
```

Everyone clones the repo and works on their own copy, one copy per magmap run. The repo has
no data: the data are unpublished, so `input_data/` and `output/` stay on your computer.

**Parquet or TSV?** magmap writes its tables as `.tsv.gz`, and also as `.parquet` when run with
`--save_parquet`. The report reads either: Parquet if it finds it, otherwise the `.tsv.gz`.
KOfamScan and eggNOG-mapper output can be used as it comes out of the tools. Parquet is only
faster: a compressed, column-based format that R reads without loading the whole table. With
big runs, `Rscript template/prepare_input.R input_data` makes Parquet copies once.

## Suggested schedule (≈ 3 h)

| Time | Part |
|---|---|
| 0:00 | 1. Three tools, one folder: VS Code, Claude Code, RStudio |
| 0:30 | 2. AGENTS.md: our rules for Claude |
| 1:00 | 3. Hands-on: the report on the practice data |
| 1:40 | break |
| 1:50 | 4. Hands-on: your own run |
| 2:20 | 5. Reading the report: what to bring to the PI |
| 2:50 | 6. Good practice |

---

## Part 1 — Three tools, one folder

All three tools open **the same folder**. Each does what it is best at:

| Tool | Use it for |
|---|---|
| **Claude Code** (panel in VS Code, or `claude` in a terminal) | writing and changing code, getting data in, explaining code |
| **VS Code** | reading Claude's changes as diffs before accepting them, browsing files, Remote-SSH to the cluster |
| **RStudio** | running chunks one by one, looking at the data, rendering the report |

- Claude Code also runs in RStudio's **Terminal** tab (`claude`). People who prefer to stay in
  RStudio can do everything there; VS Code adds the side-by-side diffs.
- **Save in RStudio before asking Claude to edit the same file.** RStudio reloads files
  changed on disk, but unsaved edits would conflict with Claude's.
- **One Claude session per folder.** Two sessions working in the same folder overwrite each
  other's changes.
- In RStudio, set the working directory to `template/` (Session → Set Working Directory →
  To Source File Location) before running chunks; the *Render* button does this by itself.

### Install (send this the day before)

The same steps are in the README.

1. VS Code with the extensions *Claude Code* (Anthropic), *Quarto*, *R*, *Remote - SSH*.
2. Claude Code: `curl -fsSL https://claude.ai/install.sh | bash`, then run `claude` once and log in.
3. R, RStudio, Quarto, and the R packages:
   ```r
   install.packages(c("tidyverse", "duckplyr", "vegan", "knitr", "grateful", "RColorBrewer"))
   ```
4. A UTF-8 locale (`echo $LANG` → `en_US.UTF-8`); without it `grateful` fails on names
   with accents.
5. Accept the GitHub invitation to the repo and clone it:
   `git clone https://github.com/danilodileo/magmap-eda-workshop.git`

### Claude Code: what to show

- The panel takes the open file and the selected lines as context; `@file` adds others.
- Every edit is a **diff** to accept or reject.
- **Plan mode** (mode menu in the panel, Shift+Tab in the terminal): Claude reads and proposes,
  changes nothing. Use it before anything bigger than a small fix.
- **Rewind** (`Esc Esc` or `/rewind`) goes back to before a prompt, in code and conversation.
- `/clear` for a new task, `/context` to see what fills the context, `/memory` to open the
  memory files.

## Part 2 — AGENTS.md: our rules for Claude

`AGENTS.md` is read at the start of every session (through the one-line `CLAUDE.md`; other
agents such as Codex or Copilot read `AGENTS.md` directly). It is modelled on the project
`CLAUDE.md` in Daniel Lundin's
[dltemplates](https://github.com/erikrikarddaniel/dltemplates). Go through it section by
section:

| Section | What it does |
|---|---|
| Communication style | short, direct answers for people new to R |
| Code comments | comments only for *why*, never narrating the code |
| Folder structure | what goes where; `input_data/` is read-only; no `setwd()` |
| The data | column names of every table, and the facts that are easy to get wrong |
| Getting a new run into input_data/ | the procedure Claude follows for your own data |
| Reading the tables in R | Parquet if present, else `.tsv.gz`; `duckplyr` rules so large tables never load into memory |
| Reports | captions with units, numbers from inline R, interpretation left to you |
| Safety | unpublished data stay here; ask before pushing or installing |

What makes these rules work:

- **Facts Claude can't guess, written once.** The counts table has no zero rows, TPM sums to
  10^6 per sample, GTDB ranks have prefixes, magmap produces no KOs. Without these lines Claude
  writes code that runs and gives wrong means.
- **Short.** Every line should change what Claude does. Delete lines it already follows.
- **Treat it as code.** When Claude makes the same mistake twice, add a line. Ask Claude to do
  it: *"You assumed X; that was wrong because Y. Add a line to AGENTS.md."*

Where other instructions go:

| What | Where |
|---|---|
| Rules for everyone in the group | `AGENTS.md` (agree on changes, keep one shared version) |
| Notes about one run (odd samples, decisions taken) | the Introduction or Materials and Methods of the report, where the PI also reads them |
| Your personal preferences, all projects | `~/.claude/CLAUDE.md` (e.g. "answer in Italian", "explain R as to a beginner") |

## Part 3 — Hands-on: the report on the practice data

1. Open the cloned folder in VS Code and start Claude Code in it. Download the practice run's
   tables from the server into `input_data/`, and save there the sample key
   (`sample_table.tsv`) you received by email.
2. *"Explain what this folder does and how the data go from input_data/ to the figures. Don't
   change anything."*
3. *"Render the report."* Claude runs `quarto render template/magmap_eda.qmd`; the result is
   `output/magmap_eda.html`. Open it.
4. **Check one number by hand.** In RStudio, compute the mean % of TPM of the top MAG
   yourself:
   1. For each sample, sum the TPM of the MAG's ORFs.
   2. For each date, average the samples (the replicates).
   3. Average over all dates, counting dates where the MAG has no reads as 0.
   4. Divide by 10^4.

   Compare with the table. Then ask Claude why the mean divides by the number of dates and
   not by the number of rows.
5. **Change something in Plan mode,** e.g. *"show the top 30 instead of 50 and add the class
   to the MAG labels"* or *"add a line plot of the top 10 families over time"*. Read the plan,
   accept, read the diff in VS Code, render in RStudio.

### What the report contains

| Section | Content |
|---|---|
| Data overview | number of samples and dates, replicates per date; reads counted per sample over time; samples missing from `sample_table.tsv` |
| Taxonomic composition | phylum barplot, one bar per date (mean of the replicates) on a time axis |
| NMDS | family-level Bray-Curtis on all replicates; date means joined in time order; shape and colour by season; replicate vs between-date dissimilarity |
| Top MAGs | table (top 50): taxonomy, completeness, contamination, mean, SD between dates, SD between replicates, max, prevalence, cumulative %; one time-series panel per MAG for the top 10 |
| Top genes | table of top ORFs with genome, taxon, gene name, product; one time-series panel per ORF for the top 10 |
| Top functions (Prokka gene names) | table of top gene names (all ORFs with the name summed); time series for the top 10; bars split by the genus expressing each |
| Top functions (KOs) | the same for KOs, when `USE_KO` is `TRUE` and KOfamScan or eggNOG-mapper output is in `input_data/` |
| P and N marker genes | Pho regulon genes in the MAGs that express them most, as % of each MAG's own TPM; nitrogen processes over time, split by the MAGs that carry them. Needs `P_N_marker_genes.tsv` |

Why these figures:

- **Replicates averaged per date, ± 1 SD as error bars:** the replicates of one date are much
  closer to each other than to other dates (the NMDS section gives the numbers), so the date
  mean is the value to follow over time. The error bars show where the replicates disagree.
- **One panel per feature, each with its own y axis:** a shared scale flattens the less
  abundant features; separate panels show their peaks and timing.
- **Real time axis:** bars and points sit at their sampling date, so gaps in sampling stay
  visible.
- **NMDS with replicates and date means:** the small points show how tight the replicates
  are; the line through the date means shows the seasonal trajectory.
- **Colour-blind-safe palettes, season shown by shape as well as colour:** readable for
  everyone and in black and white.
- **Genes labelled *gene | taxon (ORF)*:** organism and function are read together.
- **Function bars split by genus:** for a function the question is *who* expresses it, one
  lineage or many (functional redundancy).

## Part 4 — Hands-on: your own run

1. Clone the repo again into a new folder and create `input_data/` in it.
2. Ask Claude: *"Get my magmap run into input_data/. The summary tables are in
   `<path>/results/summary_tables`, KOfamScan output in `<path>`, the sample table is
   `<path>`."* Claude follows "Getting a new run into input_data/" in AGENTS.md: copies the
   files, checks that samples match, and asks which column groups the samples. TSV files work
   as they are.
3. Check the `constants` chunk at the top of `template/magmap_eda.qmd`: `FRACTION` (filter
   fractions to keep), `GROUP` (the column that groups the samples), `USE_KO` (`TRUE` once you
   have KOs for this run).
4. *"Render the report."*

The sample table is tab-separated, one row per sample. It needs `sample` (exactly as in the
counts table), `filter_fraction` and `date` (`YYYY-MM-DD`). Samples with the same date are
treated as replicates.

## Part 5 — Reading the report: what to bring to the PI

Write Summary, Results text and Discussion **yourselves**, in pairs, then compare.

- **Data overview:** any sample with few reads counted? Compare with the reads sequenced
  (NGI delivery report): a low share means the genome catalogue misses much of that sample's
  community. Samples without metadata?
- **Composition / NMDS:** seasonal pattern? Are replicates tight compared with the distance
  between dates? Do dates with few reads counted sit apart?
- **Top MAGs:** what share do the top 10 take? Persistent (high prevalence, steady) or
  blooming (high max, low mean)? Any dominant MAG with low completeness or no taxonomy? Two
  MAGs with near-identical curves may be the same organism, with reads split between them.
- **Top genes:** housekeeping genes (ribosomal proteins, chaperones, EF-Tu) or process genes
  (photosynthesis, rhodopsin, transporters)? All from the top MAGs? ORF abundance mixes
  organism abundance and expression, so check against the function sections.
- **Top functions:** what share of the TPM has a gene name or a KO at all (printed above the
  table)? Is each top function carried by one lineage or many? Prokka gene names are weak
  function labels: a photosynthesis gene in a non-photosynthetic genus is a reason to check
  the annotation, not a finding.
- **P and N markers:** when does each Pho regulon gene peak, and in which MAGs? Which
  nitrogen processes are expressed, when, and by whom?

## Part 6 — Good practice

- **Data:** prompts and files Claude reads go to Anthropic's servers. Follow the group's and
  LNU's rules for unpublished data. Never commit `input_data/` or `output/`.
- **Verify, don't trust:** read the diff, render, check one number by hand. Code can run and
  be wrong.
- **The report is the record**, not the chat: what matters goes in the `.qmd`.
- **Interpretation is yours.** Use Claude to write code and find patterns; the biological
  story is for you and the PI.
- **New task, new context:** `/clear` between unrelated tasks.

## Prompt library

- *Explain what this folder does. Don't change anything.*
- *Get my magmap run into input_data/. Files are in …*
- *Render the report and tell me if anything failed.*
- *Explain the `replicates` chunk line by line, as to someone who knows R but not duckplyr.*
- *Give me a one-liner I can run in RStudio to check the mean % of TPM of the top MAG.*
- *[Plan mode] I want to test whether community composition differs between seasons, using
  dates, not replicates, as the units. Propose the approach before writing code.*
- *Look at the figures as an outside reviewer would. What would you question?*
- *You assumed X; that was wrong because Y. Add a line to AGENTS.md.*
