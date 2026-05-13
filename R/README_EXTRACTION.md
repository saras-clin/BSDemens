# BS & DEMENTIA / T1D STUDIES — PIPELINE OVERVIEW
Last updated: 2026-05-08

---

## Overview

This project extracts data from Danish Statistics (DST) registers for two studies:

- **Study 1:** Bariatric surgery and risk of dementia (BS vs general population and obesity comparators)
- **Study 2:** Bariatric surgery outcomes in Type 1 Diabetes (glycaemic and hospital endpoints)

Data live on the DST server (project 708421). All analysis runs on DST — data cannot be
downloaded. Registers are stored as Parquet files and accessed via `dstDataPrep::load_database()`
or `arrow::open_dataset()` (for DBSO and psychiatric registers in parquet-external).

---

## Directory structure

```
R/
  00_prepare_dbso.R              # Step 0 (one-time): convert DBSO SAS -> parquet
  01_build_cohorts.R             # Step 1: BS cohort + GP comparator + obesity comparator
  02_extract_outcomes_covariates.R  # Step 2: outcomes, comorbidities, medications, demographics
  03_extract_ses.R               # Step 3: socioeconomic variables (UDDA, FAIK, AKM)
  04_data_management_dementia.R  # Step 4: merge + exclusions + variable formatting (Study 1)
  variables_dictionary.txt    # Register variable reference
  functions_guide.txt         # Function inventory
  README_EXTRACTION.md        # This file
datasets/                     # gitignored: all .rds outputs
  full_cohort.rds             # produced by Step 1; one row per person (BS + GP + Obesity)
  extract_demographics.rds    # produced by Step 2
  extract_dementia.rds
  extract_comorbidities.rds
  extract_nmi.rds
  extract_medications.rds
  extract_diabetes.rds
  extract_weights.rds
  extract_dbso_clinical.rds
  extract_insulin.rds
  ses_data.rds                # produced by Step 3
  study1_clean.rds            # produced by Step 4; analysis-ready for Study 1
```

---

## Pipeline steps

### Step 0 — 00_prepare_dbso.R (one-time only)

Converts the DBSO SAS file from SunDK into a Parquet folder that the rest of the pipeline
can read via `arrow::open_dataset()`.

- Input:  `E:/rawdata/708421/Eksterne data/dfr_2025_10_31.sas7bdat`
- Output: `E:/workdata/708421/cleaned-data/parquet-external/dbso/part-0.parquet`

Run phases in order:
1. `inspect_dbso()` — print column names and first rows; verify the file is DFR_population
2. `explore_dbso(raw)` — structural checks including DatoPER_prim vs OpDateLPR date quality check
3. `prepare_dbso()` — clean and save as parquet

Key derived columns written to parquet:
- `pnr` — character patient ID (from CPR column)
- `surgery_date` — Date (from DatoPER_prim)
- `surgery_type` — "RYGB" / "SG" / "ReDo" / "Unknown" (from GastricBypass_prim / GastricSleeve_prim / ReDo_prim flags)
- `bmi_pre` — calculated from UdgangsvaegtPRE_prim and Hoejde

The DBSO parquet is **long format**: one row per clinic visit per patient
(PRE = pre-op assessment, PER = surgery visit, FOL = follow-up visits).
`surgery_date` and `surgery_type` are patient-level and identical across all visit rows.
Weight/BMI columns vary by visit row and are used by `extract_weight_outcomes()` in Step 2.

---

### Step 1 — 01_build_cohorts.R

Defines the three study groups and applies inclusion/exclusion criteria.
Run this before any extraction.

**BS cohort** is built directly from the DBSO parquet:
- Filters to `surgery_type %in% c("RYGB", "SG")` (drops revisions and unknowns)
- Filters to study period 2010–2024
- `distinct(pnr)` reduces to one row per patient (all visit rows for a patient
  share the same surgery_date and surgery_type, so no information is lost)
- Applies exclusions: death before surgery, age < 18, < 5 years registry history,
  pre-surgery dementia (LPR2 somatic + LPR2 psychiatric + LPR3),
  any N06D (antidementia) dispensing before surgery date,
  death within 30 days after surgery

**GP comparator** (1:25): sampled from BEF, matched on sex + birth year (±1).
Dead persons and prior-BS persons excluded from pool. Matched alive at each index date.
Pre-index dementia excluded after matching.

**Obesity comparator** (1:5): persons with ICD E66 in LPR before their matched BS
patient's index date. Same alive + prior-BS + dementia exclusions.

Output: `datasets/full_cohort.rds` — one row per person, columns:
`pnr`, `index_date`, `cohort` ("BS"/"GP"/"Obesity"), `surgery_type`, `matched_pnr`

---

### Step 2 — 02_extract_outcomes_covariates.R

Extracts all outcomes and covariates for every person in full_cohort.rds.
Run after Steps 0 and 1. Can run in parallel with Step 3.

**Register access:**

| Register | Access method | Key columns |
|---|---|---|
| bef | `load_database("bef")` | pnr, foed_dag, koen, aar |
| dodsaars | `load_database("dodsaars")` | pnr, d_dodsdto (death date — confirmed) |
| lpr_adm | `load_database("lpr_adm")` | pnr, recnum, d_inddto, c_pattype |
| lpr_diag | `load_database("lpr_diag")` | recnum, c_diag, c_diagtype |
| lpr_a_kontakt | `load_database("lpr_a_kontakt")` | pnr, dw_ek_kontakt, kont_starttidspunkt (contact date), kont_type (contact type) |
| lpr_a_diagnose | `load_database("lpr_a_diagnose")` | dw_ek_kontakt, diagnosekode, diagnosetype, senare_afkraeftet (CONFIRM-3b: not yet checked) |
| lmdb | `load_database("lmdb")` | pnr, atc, eksd |
| t_psyk_adm | `arrow::open_dataset(path_psyk_adm)` | v_cpr→pnr, k_recnum→recnum, d_inddto |
| t_psyk_diag | `arrow::open_dataset(path_psyk_diag)` | v_recnum→recnum, c_diag, c_diagtype |
| DBSO | `arrow::open_dataset(path_dbso)` | pnr, surgery_date, surgery_type, vaegtfol, etc. |

**ICD-10 note:** All diagnosis codes in DST have a leading "D" prefix (e.g., "DG30").
Strip with `substr(code, 2, 4)` (3-char) or `substr(code, 2, 5)` (4-char) before matching.

**LPR versions:**
- LPR2 (up to March 2019): `lpr_adm` + `lpr_diag`, joined on `recnum`
- LPR2 psychiatric (1995–March 2019): `t_psyk_adm` + `t_psyk_diag` via `open_dataset`
- LPR3 (March 2019+): `lpr_a_kontakt` + `lpr_a_diagnose`, joined on `dw_ek_kontakt`
  LPR3 is unified — covers somatic and psychiatric in one register.

**diagtype filters:**
- Outcomes (dementia events): diagtypes A and B only
- Baseline comorbidities (NMI): diagtypes A, B, and G (grundmorbus)

**Output files** saved to `datasets/`:

| File | Contents |
|---|---|
| extract_demographics.rds | sex, birth_date, death_date, age_at_surgery, follow_up_end |
| extract_dementia.rds | date_dementia, date_alzheimers, date_vascular |
| extract_comorbidities.rds | 33 binary NMI condition flags (baseline 5-year window) |
| extract_nmi.rds | nmi_score (Kristensen 2022 weighted sum; 50 predictors normally, 48 for Study 1 with dementia predictors excluded) |
| extract_medications.rds | antihypertensive, lipid_lowering, insulin, antidepressant, antidementia (binary) |
| extract_diabetes.rds | diabetes_type ("T1D"/"T2D"/"No_diabetes") from OSDC |
| extract_weights.rds | bmi_pre, weight at 3/6/12/24 months, %TWL, %EWL (Study 2 / BS only) |
| extract_dbso_clinical.rds | DBSO-computed outcomes: 30-day readmission, reoperation flags, EOSS, sleep apnea, nutritional supplements (Study 2 / BS only) |
| extract_insulin.rds | insulin prescription counts pre/post surgery by period (Study 2 / BS only) |
| extract_hospitals.rds | first acute inpatient admission dates for glycaemic and other endpoints (Study 2) |

---

### Step 3 — 03_extract_ses.R

Extracts socioeconomic position (SEP) for all cohort members.
Run in parallel with Step 2 (both read full_cohort.rds independently).
Follows SEPLINE guidelines (Hjorth et al. Clin Epidemiol 2025;17:593–624).

Reference year: `year(index_date) - 1` (year before surgery / matched index date).

| Dimension | Register | Variable | Categories |
|---|---|---|---|
| Education | UDDA / hfaudd | Most recent record up to index year | Short / Medium / Long / Unknown |
| Income | FAIK via BEF familie_id | famaekvivadisp_13, 3-year average; population-standardized quintiles by sex × 5-year age group × year (SEPLINE) | Low (Q1) / Medium (Q2–4) / High (Q5) / Unknown |
| Occupation | AKM / socio13 | Record at index year | Working / Unemployed / Outside_workforce / Retired / Student / Unknown |

Three separate SEP dimensions are used in models (no composite); per SEPLINE (Hjorth et al. Clin Epidemiol 2025;17:593–624).

Output: `datasets/ses_data.rds`

---

### Step 4 — 04_data_management_dementia.R (Study 1)

Merges all extract_*.rds and ses_data.rds into one analysis-ready dataset.

1. Load & merge — left-joins all extracts onto full_cohort.rds via pnr
2. Safety check — removes any pre-surgery dementia that slipped through
3. ICD + Rx supplement — combines hospital ICD flags with prescriptions for
   hypertension (C02/C03/C07–C09) and dyslipidemia (C10); these conditions are
   under-captured by hospital codes alone
4. NMI count — counts how many of 33 GMC conditions each person has (for Table 1
   descriptives); distinct from nmi_score (the weighted Kristensen 2022 score)
5. Emigration censoring — get_emigration_dates() is called to add emigration_date;
   currently a stub returning NA for all persons (register name not yet confirmed with
   data manager — see CRITICAL-4 in TODO.txt). Wire-in is complete; replace stub once
   register is confirmed.
6. Format variables — factors with reference levels, censor_date (includes emigration),
   outcome event flags, follow-up time in days, age categories, calendar period

Output: `datasets/study1_clean.rds` — one row per person, ready for Cox models and Table 1.

Note: `data_management_t1d.R` (Study 2 equivalent) does not yet exist.

---

## Running the pipeline on DST

```r
# Step 0: one-time DBSO conversion
source("R/00_prepare_dbso.R")
raw <- inspect_dbso()
explore_dbso(raw)   # check output before proceeding
dbso <- prepare_dbso()

# Step 1: build cohorts
source("R/01_build_cohorts.R")
full_cohort <- main_build_cohorts()

# Steps 2 + 3: run in parallel (separate R sessions on DST recommended)
source("R/02_extract_outcomes_covariates.R")
main_extraction()

source("R/03_extract_ses.R")
main_ses_extraction()

# Step 4: merge and clean
source("R/04_data_management_dementia.R")
study1 <- main_data_management()
```

**Before each session:** build the dstDataPrep package from source:
`E:/workdata/708421/workspaces/luke/dstDataPrep/dstDataPrep.Rproj`

---

## Open issues before first run (see TODO.txt)

- **CONFIRM-2:** RESOLVED — death date column is `d_dodsdto` (not doddato). Fixed in all scripts.
- **CONFIRM-3:** Verify diabetes_type values in OSDC file
  (`table(dm$diabetes_type)` — code assumes "T1D" / "T2D" string labels)
- **CRITICAL-4:** Emigration date register not yet wired up — confirm with data manager
  which register to use: VNDS, BEF-derived (gap in annual snapshots), or CPR Registeret
  (RVNDS). Once confirmed, replace stub in get_emigration_dates() (see CRITICAL-4 in
  TODO.txt for full detail). No other code changes needed — pmin() is already wired.
- **MINOR-8:** Confirm `aar` column name in UDDA, FAIK, AKM

---

## Key references

| Topic | Reference |
|---|---|
| NMI | Kristensen KB et al. Clin Epidemiol 2022;14:567–79 |
| SEP / SEPLINE | Hjorth CF et al. Clin Epidemiol 2025;17:593–624 |
| DBSO registry | Winckelmann LA et al. Surg Obes Relat Dis 2022;18(4):511–9 |
| DNPR (LPR) | Schmidt M et al. Clin Epidemiol 2015;7:449–90 |
| DCPRR | Mors O et al. Scand J Public Health 2011;39(7 Suppl):54–7 |
| Dementia PPV | Phung TK et al. Dement Geriatr Cogn Disord 2007;24(3):220–8 |
| E66 validity | Gribsholt SB et al. Clin Epidemiol 2019;11:845–54 |
