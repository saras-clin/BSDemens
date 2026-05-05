# ============================================================================
# BS & DEMENTIA / T1D STUDIES - DATA EXTRACTION SETUP GUIDE
# ============================================================================

## Overview

This project extracts data from Danish Statistics (DST) registers for two studies:
1. **Study 1:** Association between bariatric surgery and dementia
2. **Study 2:** Outcomes of bariatric surgery in Type 1 Diabetes patients

The exposure (bariatric surgery cohort) is already defined through the Danish Quality Registry for Severe Obesity Treatment (DBSO). This guide focuses on extracting **outcomes and covariates only**.

---

## Project Structure

```
BS_demens/
├── R/
│   ├── variables_dictionary.txt      # All variables needed for studies
│   ├── extract_outcomes_covariates.R # Main extraction script
│   └── [your scripts]
├── data/
│   ├── extracted/                      # Output: cleaned datasets
│   ├── bs_cohort.rds                   # Input: existing BS cohort
│   └── [raw data folder on DST]
├── claude.md                           # Project documentation
└── doc/
    └── [protocol documents]
```

---

## Key Learning Points from Onboarding

### 1. DST Environment Basics

- **Remote access:** You work on Statistics Denmark's virtual machines
- **Security:** Data cannot be downloaded; analysis must be done on DST
- **Registers available:**
  - CRS (Civil Registration System): Demographics, death dates
  - DNPR (National Patient Registry): Diagnoses, hospital admissions
  - DNPD (Prescription Database): Medications
  - DCPRR (Psychiatric Registry): Psychiatric diagnoses
  - DBSO (Obesity Registry): Surgical & anthropometric data
  - IDLMR (Labour Market Database): Education, income

### 2. Data Formats: Parquet & DuckDB

**Why use them?**
- Data on DST is stored as **Parquet files** (columnar format)
- More memory-efficient than CSV
- **DuckDB** processes data without loading everything into RAM
- **duckplyr** lets you use familiar `dplyr` syntax

**Basic workflow:**
```r
# Open dataset
data <- arrow::open_dataset("E:/workdata/708421/cleaned-data/parquet-registries/<registry-name>") |>
  duckplyr::as_duckplyr_table()

# Use familiar dplyr verbs (lazy evaluation)
result <- data |>
  filter(condition) |>
  select(columns)

# Execute and get results
result |> collect()
```

### 3. DST Best Practices (from onboarding)

- **Memory management:** Only load data you need. Use filtering early
- **Lazy evaluation:** Operations aren't executed until you call `collect()`
- **Working directories:** Set up a project folder in Workspaces
- **Naming:** Keep ICD-10 codes in consistent format
- **Variables:** Use `names()`, `str()`, `glimpse()` to explore data before processing

### 4. Code Patterns from Existing Projects

The existing code in `archive/other peoples code/` shows:
- How to loop through yearly datasets (e.g., SSSY, SYSI for services)
- How to stack multiple data sources (e.g., psychiatric register pre/post 1995)
- How to harmonize diagnoses across time periods
- How to distinguish patient types (inpatient, outpatient, ER)
- How to create derived variables (e.g., time between prescriptions)

---

## Data Extraction Strategy

### Step 1: Load Existing BS Cohort
- Source: DBSO (mandatory registry since 2010)
- Variables: PNR, surgery date, surgery type (RYGB vs SG)
- This is your denominator for all downstream extractions
- **Workspace save path:** `E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets`

### Step 2: Extract by Data Source

Each `extract_*` function loads one register and:
1. Filters to your BS cohort PNRs
2. Takes observations relevant to index date
3. Extracts needed variables
4. Returns clean, wide format (one row per person)

### DST Registry Mapping
- **CRS / CPR:** demographics, sex, birth date, death date
- **LPR2:** `lpr_adm` (contacts) + `lpr_diag` (diagnoses)
- **LPR3:** `kontakter` (contacts) + `diagnoser` (diagnoses)
- **SES:** `faik` (family income), `udda` (education)
- **Diabetes classification:** OSDC cohort or `dm_population_1977_2022.rds`

### Diabetes covariate classification
Use the Open Source Diabetes Classifier (OSDC) for diabetes type. The onboarding guide already refers to a locally prepared diabetes cohort file:

`E:/workdata/708421/cleaned-data/diabetes_register_pop/dm_population_1977_2022.rds`

This is the preferred source for classifying T1D vs T2D vs non-diabetes.

**Study 1 needs:**
- Dementia diagnoses (DNPR + DCPRR) → outcome
- NMI comorbidities (DNPR) → covariates
- Medications (DNPD) → covariates
- Education (IDLMR) → covariates

**Study 2 needs:**
- Weight/BMI (DBSO) → outcome
- Insulin doses (DNPD) → outcome
- Hospital contacts (DNPR) → outcome
- Comorbidities (DNPR) → covariates
- Medications (DNPD) → covariates

### Step 3: Join Everything
- Use `pnr` as join key
- Keep all BS cohort members (left join)
- Missing values indicate no event or medication

---

## How to Run This On DST

### 1. Set Up Your Environment

```r
# Install packages (first time only)
packages_needed <- c("dplyr", "duckplyr", "arrow", "tidyr", "lubridate", "here")
install.packages(packages_needed)

# Update duckplyr if on old DST version
install.packages("duckplyr")
```

### 2. Configure Paths

Edit these paths in `extract_outcomes_covariates.R`:

```r
path_dst_raw <- "path/to/dst/raw/data"  # Ask DST for correct path
path_output <- here::here("data", "extracted")
```

**Note:** DST paths are typically like `/rawdata/[project_number]/grunddata/` or similar.

### 3. Load Your BS Cohort

The script expects `data/bs_cohort.rds` containing:
```
pnr (CPR number)
surgery_date (date of bariatric surgery)
surgery_type ("RYGB" or "SG")
```

Create it first:
```r
# Example: if you have it as CSV
bs_cohort <- read.csv("path/to/bs_cohort.csv")
saveRDS(bs_cohort, "data/bs_cohort.rds")
```

### 4. Run Extraction

```r
source("R/extract_outcomes_covariates.R")
results <- main_extraction()

# This produces:
# - data/extracted/study1_dementia_data.rds
# - data/extracted/study2_t1d_data.rds
# - (+ CSV versions)
```

### 5. Quality Check

```r
# Quick data quality checks
study1 <- readRDS("data/extracted/study1_dementia_data.rds")

nrow(study1)  # How many people?
colnames(study1)  # What variables?
summary(study1)  # Descriptive stats
sum(is.na(study1$pnr))  # Any missing PNRs?
```

---

## Common Issues & Solutions

### Issue: "Package not found on DST"
**Solution:** DST has a pre-installed snapshot of CRAN. Most packages are there. If not:
1. Check `packageVersion("package_name")`
2. Try `install.packages("package_name")` anyway
3. If duckplyr is old (< 1.1), update it

### Issue: "Data loads but operations are very slow"
**Solution:** 
- You're probably not using lazy evaluation correctly
- Make sure to `filter()` early before `collect()`
- Check memory indicator in RStudio (red = bad)
- Consider splitting work across multiple scripts

### Issue: "Can't find the Parquet files"
**Solution:**
- Ask DST exactly where data is stored
- Use `dir()` to browse folders
- Path might be `/rawdata/[your_project_id]/grunddata/DNPR/`

### Issue: "Diagnosis codes don't match expected results"
**Solution:**
- ICD-10 codes vary in length (e.g., "I10" vs "I10A0")
- Use `substr()` to extract consistent portions
- Check existing code for how they handle it
- Reference: https://www.dst.dk/da/Statistik/dokumentation/Times

---

## Key ICD-10 Codes to Know

**Dementia (Study 1):**
- G30: Alzheimer's disease
- G31: Other degenerative diseases
- F01: Vascular dementia

**Diabetes (Study 2):**
- E10: Type 1 Diabetes
- E11: Type 2 Diabetes
- E15: Nondiabetic hypoglycemia

**NMI Conditions:**
- I21-I23: Myocardial infarction
- I63-I64: Stroke
- J40-J44: COPD
- K70-K74: Liver disease
- N18-N19: Kidney disease

**ATC Codes:**
- A10A: Insulin
- A10B: Other antidiabetic drugs
- C10: Lipid-lowering drugs
- N06A: Antidepressants

---

## Important Considerations

1. **Time windows:** Always specify date ranges to avoid loading unnecessary data
2. **Lookback periods:** Use 5 years before surgery for baseline covariates
3. **First occurrence:** Usually take first diagnosis/prescription date
4. **Missing data:** NAs are expected for people without events
5. **Competing risk:** Death is a competing risk for dementia and hospitalizations
6. **Follow-up duration:** Different studies end at different dates (2025 vs 2024)

---

## Next Steps

1. **Validate BS cohort:** Confirm it matches DBSO expectations
2. **Test extraction:** Start with one small register (e.g., CRS)
3. **Check outputs:** Compare with known cohort size/characteristics
4. **Iterate:** Adjust ICD-10 codes based on domain knowledge
5. **Document:** Keep notes on any modifications made

---

## Resources

- **DST documentation:** https://www.dst.dk/da/Statistik/dokumentation/Times
- **Onboarding guide:** See `archive/onbording/`
- **Existing code examples:** See `archive/other peoples code/`
- **Open Source Diabetes Classifier:** https://steno-aarhus.github.io/osdc/
- **STROBE checklist:** https://www.equator-network.org/
