# CLAUDE.md — BS & Dementia Project

## Project overview
Danish nationwide register-based cohort study.
Study 1: Bariatric surgery (BS) and risk of dementia.
Study 2: Bariatric surgery in Type 1 Diabetes — glycemic and hospital outcomes.
Data: Statistics Denmark (DST) server, project 708421. Registers accessed via
dstDataPrep::load_database() (parquet-registers folder) and arrow::open_dataset()
(parquet-external folder). DBSO (bariatric surgery registry) is a SAS file from
SunDK, converted to parquet in parquet-external/databasesvaerovervaegt/.

## Directory structure
```
R/
  prepare_dbso.R              # one-time: SAS -> parquet for DBSO
  build_cohorts.R             # BS cohort + GP comparator + obesity comparator
  extract_outcomes_covariates.R   # LPR/LMDB/DBSO outcome and covariate extraction
  extract_ses.R               # socioeconomic variables (UDDA, FAIK, AKM)
  data_management_dementia.R  # merge, exclusions, final analysis dataset
  variables_dictionary.txt    # register variable reference
  functions_guide.txt         # function inventory
  README_EXTRACTION.md        # extraction pipeline overview
doc/
  study1_methods_plan.txt     # analysis plan, figures, tables, open issues
  TODO.txt                    # open issues (CRITICAL / CONFIRM / MINOR)
datasets/                     # gitignored: processed .rds outputs
```

## Code style
- R only. Primary packages: dplyr, arrow, lubridate, dstDataPrep, haven, heaven.
- Inline comments on every substantive line; explain WHY, not WHAT.
- No emoji in code or comments.
- Variable names: snake_case. Column names after load_database(): always apply
  rename_with(tolower) immediately.
- Patient identifiers: always called `pnr` in code (DST raw name varies: v_cpr,
  CPR, PNR — all renamed to pnr after tolower).
- ICD codes in registers have a leading "D" prefix (e.g., "DF00", "DG30").
  Strip with substr(code, 2, 4) for 3-char or substr(code, 2, 5) for 4-char
  comparison. Never compare against codes with the D prefix in filter logic.
- Dates: always convert to Date class explicitly (as.Date()). SAS dates from
  haven are already Date; parquet dates may need coercion.
- Collect lazily: filter and select before collect() so only needed rows cross
  the parquet → R boundary.
- After removing large objects: always call gc() to free RAM.

## Key domain terms
- pnr: encrypted CPR number (person identifier). Never appears as a literal value
  in code — only as a column name or variable holding a vector of IDs.
- DBSO: Databasen for Behandling af Svær Overvægt — Danish bariatric surgery
  quality registry. Long format: one row per clinic visit per patient.
- LPR2 (up to March 2019): lpr_adm (contacts) + lpr_diag (diagnoses), join on recnum.
- LPR3 (March 2019+): lpr_a_kontakt (contacts) + lpr_a_diagnose (diagnoses),
  join on dw_ek_kontakt.
- Psychiatric LPR2: t_psyk_adm + t_psyk_diag in parquet-external, via open_dataset.
- NMI: Nordic Multimorbidity Index — 50-predictor weighted comorbidity score
  (Kristensen et al. Clin Epidemiol 2022).
- RYGB: Roux-en-Y gastric bypass (SKS: KJDF10, KJDF11).
- SG: sleeve gastrectomy (SKS: KJDF40, KJDF41, KJDF96, KJDF97).
- Index date: date of bariatric surgery for BS patients; same date for matched
  comparators.
- c_diagtype / diagnosetype: "A" = primary, "B" = secondary, "G" = supplementary.
  Always filter to c("A","B") unless G codes are explicitly needed (NMI baseline).
- dodsaars: individual death records with exact death date (use for censoring).
  dodsaasg: cause-of-death classification (NOT for censoring).

## Working principles

### Think before coding
- State assumptions explicitly — ask rather than guess when uncertain.
- Present multiple interpretations rather than making silent decisions.
- Push back when warranted — suggest simpler approaches.
- Stop and request clarification when a requirement is unclear.

### Simplicity first
- Write the minimum code that solves the problem; nothing speculative.
- Exclude features beyond what was requested.
- Avoid abstractions for single-use code.
- Skip error handling or flexibility that was not requested.

### Surgical changes
- Touch only what is necessary; clean up only your own mess.
- Do not improve adjacent code, comments, or formatting.
- Do not refactor working code unless asked.
- Match existing style throughout the file.
- Mention unrelated issues but do not fix them unless asked.
- Remove only imports/variables your changes made unused.

### Goal-driven execution
- For multi-step tasks, state a brief plan with verifiable steps before starting.
- Use strong success criteria so outcomes can be checked independently.

## What NOT to do
- Never include a CPR/pnr literal value in any script — only column names and
  vectors. This is a DST microdata security rule.
- Do not add emoji to code or comments.
- Do not create markdown or README files unless explicitly asked.
- Do not change the variables_dictionary.txt register column lists without asking.
- Do not modify the DBSO column mapping in prepare_dbso.R without confirming
  against the actual SAS file (column names were confirmed from dfr_2025_10_31).
- Do not use dodsaasg for death date censoring — use dodsaars (doddato column).
- Do not use load_database() for t_psyk_adm / t_psyk_diag — use open_dataset()
  from the parquet-external path.
- Do not include "Co-Authored-By: Claude" in commit messages.
- Never write parquet-registries — the correct folder name is parquet-registers.
