# DST Helper Scripts

Scripts for use on Statistics Denmark (DST) servers for Danish register-based epidemiology.  
Pre-specified for DST project 708421 (DARTER). Colleagues on other projects: update the two paths
in Section 0 of each script (search for `CHANGE THIS`).

Questions: Sara Schwartz (sarasschwartz@gmail.com)

---

## SEPLINE

**Socioeconomic Position in Epidemiological Research — A National Guideline on Danish Registry Data**  
Hjorth CF et al. *Clin Epidemiol.* 2025;17:593-624.  
<https://doi.org/10.2147/CLEP.S520772>

**Script:** `SEPLINE.R`

Extracts the three SEP dimensions recommended by the SEPLINE guideline: education (UDDA),
household income (FAIK via BEF, population-standardised quintiles), and occupation (AKM).
Produces one row per person with `education_cat`, `income_cat`, and `occupation_cat`.
Do **not** combine into a composite score — enter each as a separate term in regression models.

### How to use

**Step 1** — Change the two paths in Section 0 (search for `CHANGE THIS`):

| Parameter | Description |
|---|---|
| `path_output` | Folder where `ses_data.rds` will be saved |
| `path_cohort` | Full path to your cohort `.rds` file |

**Step 2** — Make sure your cohort file has these two columns:

| Column | Description |
|---|---|
| `pnr` | Encrypted CPR number (person identifier) |
| `index_date` | `Date` class — surgery, diagnosis, or recruitment date |

**Step 3** — Run the script top to bottom:

```r
source("help/SEPLINE.R")
```

Or run section by section interactively in RStudio using Ctrl+Enter (Windows) / Cmd+Enter (Mac).

**Step 4** — Load the output in your analysis script:

```r
ses <- readRDS(file.path(path_output, "ses_data.rds")) %>%
  select(pnr, education_cat, income_cat, occupation_cat)
df <- df %>% left_join(ses, by = "pnr")
```

### What you get

`ses_data.rds` — one row per person:

| Column | Values |
|---|---|
| `education_cat` | Short / Medium / Long / Unknown |
| `income_cat` | Low / Medium / High / Unknown |
| `occupation_cat` | Working / Unemployed / Outside_workforce / Retired / Student / Unknown |
| `hfaudd` | Raw UDDA education code (audit) |
| `famaekvivadisp_13` | Raw 3-year average equivalised income (audit) |
| `income_quintile` | Quintile 1–5 in the general population (audit) |
| `socio13` | Raw AKM occupation code (audit) |

Reference levels: `education_cat` = Medium, `income_cat` = Medium, `occupation_cat` = Working.

---

## Nordic Multimorbidity Index (NMI)

**Nordic Multimorbidity Index: Development and Validation of a Nordic Multimorbidity Index Based on Hospital Diagnoses and Filled Prescriptions**  
Kristensen KB et al. *Clin Epidemiol.* 2022;14:567-579.  
<https://doi.org/10.2147/CLEP.S353398>

**Script:** `NMI.R`

Extracts a continuous weighted comorbidity score with 50 predictors (29 ICD-10 diagnosis groups +
21 ATC medication groups). Designed to predict 1-year all-cause mortality in primary care.
Uses a 5-year lookback for diagnoses and 6-month lookback for prescriptions.
Enter `nmi_score` as a **continuous** covariate in Cox models — do not categorise it.

### How to use

**Step 1** — Change the two paths in Section 0 (search for `CHANGE THIS`):

| Parameter | Description |
|---|---|
| `path_output` | Folder where `nmi_data.rds` will be saved |
| `path_cohort` | Full path to your cohort `.rds` file |

**Step 2** — Make sure your cohort file has these two columns:

| Column | Description |
|---|---|
| `pnr` | Encrypted CPR number (person identifier) |
| `index_date` | `Date` class — surgery, diagnosis, or recruitment date |

**Step 3** — Run the script top to bottom:

```r
source("help/NMI.R")
```

Or run section by section interactively in RStudio using Ctrl+Enter (Windows) / Cmd+Enter (Mac).

**Step 4** — Load the output in your analysis script:

```r
nmi <- readRDS(file.path(path_output, "nmi_data.rds")) %>%
  select(pnr, nmi_score)
df <- df %>% left_join(nmi, by = "pnr")
```

For Table 1 condition prevalences, load the full file and use the 50 flag columns:

```r
nmi_full <- readRDS(file.path(path_output, "nmi_data.rds"))
df <- df %>% left_join(nmi_full, by = "pnr")
```

### What you get

`nmi_data.rds` — one row per person:

| Column | Description |
|---|---|
| `nmi_score` | Continuous weighted score — can be negative (see below) |
| `dx_B18` … `dx_N18_N19` | 29 binary (0/1) diagnosis flags, one per NMI group |
| `rx_A06A` … `rx_R03BB04_07` | 21 binary (0/1) prescription flags, one per NMI group |

> **nmi_score can be negative.** Two NMI components have protective (negative) weights:
> `C09C/C09D` (ARBs/sartans) = −2 and `C10AA` (statins) = −3.
> A person on both with no other conditions scores −5.
> Enter `nmi_score` as a continuous covariate in Cox. Do **not** categorise it.
