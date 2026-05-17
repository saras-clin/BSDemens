# ============================================================================
# NMI — Nordic Multimorbidity Index
# ============================================================================
#
# ============================================================================
# HOW TO USE THIS SCRIPT
# ============================================================================
#
#   PROJECT
#     Pre-specified for DST project 708421 (DARTER).
#     Colleagues on other DST projects: update path_output and path_cohort
#     in Section 0. If load_database() is unavailable, replace each call with
#     arrow::open_dataset() pointing to the register paths listed in Section 0.
#
#   STEP 1 — Change the two paths in Section 0 (search for "CHANGE THIS"):
#              path_output : folder where nmi_data.rds will be saved
#              path_cohort : full path to your cohort .rds file
#
#   STEP 2 — Make sure your cohort file has these two columns:
#              pnr          : encrypted CPR number (person identifier)
#              index_date   : Date class — surgery/diagnosis/recruitment date
#             (See Section 1 for details)
#
#   STEP 3 — Run the script top to bottom:
#              Source the entire file:  source("help/NMI.R")
#              Or run section by section interactively in RStudio using
#              Ctrl+Enter (Windows) / Cmd+Enter (Mac).
#
#   STEP 4 — The output nmi_data.rds is saved to path_output.
#             In your analysis script, load it with:
#               nmi <- readRDS(file.path(path_output, "nmi_data.rds")) %>%
#                 select(pnr, nmi_score)
#               df <- df %>% left_join(nmi, by = "pnr")
#
#   WHAT YOU GET:
#     nmi_data.rds — one row per person, columns:
#       nmi_score              continuous weighted score (can be negative; see below)
#       dx_B18 ... dx_N18_N19 29 binary (0/1) diagnosis flags, one per NMI group
#       rx_A06A ... rx_R03BB04_07  21 binary (0/1) prescription flags, one per NMI group
#
#   IMPORTANT — nmi_score CAN BE NEGATIVE:
#     Two NMI components have protective (negative) weights:
#       C09C/C09D (ARBs/sartans) = -2
#       C10AA (statins)          = -3
#     A person on both with no other conditions scores -5.
#     Enter nmi_score as a continuous covariate in Cox. Do NOT categorise it.
#
#   QUESTIONS / ISSUES:
#     Contact: Sara Schwartz (sarasschwartz@gmail.com)
#     Reference: Kristensen KB et al. Clin Epidemiol. 2022;14:567-579.
#                DOI: 10.2147/CLEP.S353398
#
# ============================================================================
#
# PURPOSE
#   Standalone extraction script for the Nordic Multimorbidity Index (NMI),
#   a continuous weighted comorbidity score with 50 predictors (29 ICD-10
#   diagnosis groups + 21 ATC medication groups). Designed to predict 1-year
#   all-cause mortality in primary care. Widely used as a comorbidity covariate
#   in Danish register-based cohort studies.
#
# REFERENCE
#   Kristensen KB, Schmidt M, Botker HE, et al.
#   Nordic Multimorbidity Index: development and validation of a comorbidity
#   index for prediction of 1-year all-cause mortality in primary care.
#   Clin Epidemiol. 2022;14:567-579.
#   DOI: 10.2147/CLEP.S353398
#   Official Stata code: https://pharmacoepi.sdu.dk/nmi/
#   The ICD patterns and weights used here are translated directly from the
#   official Stata implementation (online_nmi.do) — not from the paper text.
#
# WHAT THIS SCRIPT PRODUCES
#   One row per person. Columns:
#     nmi_score              — continuous weighted score; sum of component weights.
#                              Typically 0-80+, but can be negative (ARBs/statins).
#                              Use as continuous covariate in Cox — do NOT categorise.
#     dx_B18 ... dx_N18_N19  — 29 binary (0/1) diagnosis flags, one per NMI group.
#                              1 = person had at least one matching diagnosis in the
#                              5-year lookback window. Retained for audit and Table 1.
#     rx_A06A ... rx_R03BB04_07 — 21 binary (0/1) prescription flags, one per NMI group.
#                              1 = person had at least one matching dispensing in the
#                              6-month lookback window. Retained for audit and Table 1.
#
# KEY DECISIONS IMPLEMENTED HERE
#   (a) Look-back windows (Kristensen 2022, Table 2):
#         Diagnoses:     5 years before index date
#         Prescriptions: 6 months before index date
#       5-year lookback captures the full chronic disease burden. 6-month lookback
#       for prescriptions captures current pharmacological treatment — older
#       prescriptions may no longer reflect active disease.
#   (b) Diagnosis types: A (primary), B (secondary), G (grundmorbus).
#       G codes are included for comorbidity capture — unlike outcome extraction,
#       which uses A+B only. Including G ensures conditions managed alongside a
#       different primary reason for the hospital contact are also captured.
#   (c) Three LPR sources:
#         LPR2 somatic:      lpr_adm + lpr_diag           (all contacts up to March 2019)
#         LPR2 psychiatric:  t_psyk_adm + t_psyk_diag     (psychiatric contacts up to March 2019)
#         LPR3:              lpr_a_kontakt + lpr_a_diagnose (all contacts from March 2019)
#       Psychiatric diagnoses — especially F10 (alcohol) and F17 (tobacco), both NMI
#       components — would be missed if the LPR2 psychiatric register is omitted.
#
# REGISTERS USED
#   LPR2 somatic:      E:/workdata/708421/parquet-registers/lpr_adm/
#                      E:/workdata/708421/parquet-registers/lpr_diag/
#                      Joined on recnum. Columns: pnr, d_inddto, c_diagtype, c_diag.
#   LPR2 psychiatric:  t_psyk_adm (v_cpr -> pnr, k_recnum -> recnum)
#                      t_psyk_diag (v_recnum -> recnum)
#   LPR3:              E:/workdata/708421/parquet-registers/lpr_a_kontakt/
#                      E:/workdata/708421/parquet-registers/lpr_a_diagnose/
#                      Joined on dw_ek_kontakt.
#   LMDB:              E:/workdata/708421/parquet-registers/lmdb/
#                      Columns: pnr, atc, eksd.
#
# HOW TO USE IN COX MODELS
#   coxph(Surv(follow_up_days, event) ~
#           exposure +
#           age_at_index + sex +
#           nmi_score +      # continuous; do NOT categorise
#           education_cat +  # SEP dimension 1 (from SEPLINE.R)
#           income_cat +     # SEP dimension 2 (from SEPLINE.R)
#           occupation_cat + # SEP dimension 3 (from SEPLINE.R)
#           surgery_period,
#         data = df,
#         cluster = matched_pnr)
#
# ============================================================================
# TABLE OF CONTENTS
# -----------------
#   0.  Packages, paths, and key parameters
#   1.  Cohort input — what your input data frame must look like
#   2.  Pull all diagnoses from LPR (5-year lookback, diagtypes A + B + G)
#       2.1  LPR2 somatic (lpr_adm + lpr_diag, up to March 2019)
#       2.2  LPR2 psychiatric (t_psyk_adm + t_psyk_diag, up to March 2019)
#       2.3  LPR3 unified (lpr_a_kontakt + lpr_a_diagnose, March 2019+)
#       2.4  Combine all three sources and apply 5-year lookback filter
#   3.  Diagnosis flags — 29 NMI groups (Table 2, Kristensen 2022)
#       3.1  ICD patterns and weights
#       3.2  Flag each person per group
#   4.  Prescription flags — 21 NMI groups (Table 2, Kristensen 2022)
#       4.1  Load LMDB and apply 6-month lookback
#       4.2  ATC patterns and weights
#       4.3  Flag each person per group
#   5.  Compute NMI score (weighted sum)
#   6.  Combine: score + all 50 flags — one row per person
#   7.  Save output
# ============================================================================


# ============================================================================
# 0. PACKAGES, PATHS, AND KEY PARAMETERS
# ============================================================================

library(dstDataPrep)   # load_database() — DST parquet interface; must be built from source on the DST server
                       # Author:  Luke W. Johnston (lwjohnst86)
                       # Source:  E:/workdata/708421/workspaces/luke/dstDataPrep/dstDataPrep.Rproj
                       # Build:   open dstDataPrep.Rproj in RStudio, then Build > Install Package
                       # Note:    internal DST tool — no public repository or DOI
library(arrow)         # open_dataset() if needed for registers outside load_database
library(dplyr)         # data manipulation throughout
library(lubridate)     # year(), as.Date() for date handling

# --- Output and cohort paths --- CHANGE THESE TWO LINES FOR YOUR PROJECT ---
path_output <- "E:/workdata/708421/workspaces/YourName/YourProject/datasets"   # CHANGE THIS: replace YourName/YourProject with your own workspace
path_cohort <- file.path(path_output, "full_cohort.rds")                       # CHANGE THIS: full path to your cohort .rds file

# Catch the most common mistake: forgetting to update the paths above.
if (grepl("YourName", path_output) || grepl("YourName", path_cohort))
  stop(
    "Paths have not been updated. Search for 'CHANGE THIS' in Section 0 ",
    "and replace YourName/YourProject with your own workspace folder."
  )


# ============================================================================
# 1. COHORT INPUT — WHAT YOUR DATA FRAME MUST LOOK LIKE
# ============================================================================
# Your cohort data frame must have AT MINIMUM these two columns:
#
#   pnr          — encrypted CPR number (person identifier). Character or numeric.
#                  Never appears as a literal value — only as a column name.
#   index_date   — Date class. The date from which the NMI lookback is measured.
#                  Diagnoses: 5 years before index_date.
#                  Prescriptions: 6 months before index_date.
#                  Typically: surgery date, diagnosis date, or recruitment date.

cohort <- readRDS(path_cohort)   # load cohort; must have columns pnr and index_date

# Input validation: fail immediately with a clear message rather than a cryptic
# arrow or dplyr error deep inside the LPR or LMDB extraction.
if (!all(c("pnr", "index_date") %in% names(cohort)))
  stop(
    "Cohort is missing required columns. Need: pnr, index_date. ",
    "Found: ", paste(names(cohort), collapse = ", ")
  )
if (!inherits(cohort$index_date, "Date"))
  stop(
    "'index_date' must be Date class. Got: ", class(cohort$index_date)[1], ". ",
    "Convert with: cohort$index_date <- as.Date(cohort$index_date)"
  )

n_dup_pnr <- sum(duplicated(cohort$pnr))   # count persons appearing more than once
if (n_dup_pnr > 0)
  warning(
    n_dup_pnr, " duplicate pnr(s) found in cohort. Each person should appear once. ",
    "Duplicates cause left_joins in Section 6 to produce more rows than expected. ",
    "Check your cohort construction."
  )

pnrs <- unique(cohort$pnr)   # deduplicated vector of all cohort person IDs; used to push filters to parquet


# ============================================================================
# 2. PULL ALL DIAGNOSES FROM LPR (5-YEAR LOOKBACK, DIAGTYPES A + B + G)
# ============================================================================
# The NMI uses three LPR data sources, each covering a different time period
# or patient population. All three must be included to avoid undercounting.
#
# Diagnosis types used: A (primary), B (secondary), G (grundmorbus).
# G codes are included here — unlike outcome extraction which uses A+B only.
# G captures conditions a patient has alongside the primary reason for the contact.
#
# ICD codes in DST registers carry a leading "D" prefix (e.g. "DG30", "DF10").
# We strip this with substr(code, 2, 5) to get 4-char ICD-10 (e.g. "G30", "F10").
# All NMI regex patterns are matched against this 4-char code (icd4).
#
# WHY THIS PULL IS SLOW:
#   LPR2 + LPR2-psyk + LPR3 together span 1977-2025. Even filtered to cohort pnrs
#   and a 5-year lookback, this can involve millions of rows per data source.
#   Expected runtime: 5-15 minutes depending on cohort size and server load.
#   The three sources are pulled separately and then combined (Section 2.4).

diagtypes <- c("A", "B", "G")   # diagnosis types for baseline comorbidity (NMI specification)

# ============================================================================
# 2.1 LPR2 SOMATIC (lpr_adm + lpr_diag, contacts up to March 2019)
# ============================================================================
message("Section 2.1: loading LPR2 somatic diagnoses for ", length(pnrs),
        " cohort members (this may take several minutes)...")

lpr_adm  <- load_database("lpr_adm")  %>% rename_with(tolower)   # LPR2 somatic admission table; key columns: pnr, recnum, d_inddto
lpr_diag <- load_database("lpr_diag") %>% rename_with(tolower)   # LPR2 somatic diagnosis table; key columns: recnum, c_diagtype, c_diag

lpr2_somatic <- lpr_adm %>%
  filter(pnr %in% !!pnrs) %>%                    # push cohort filter to parquet before collecting
  select(pnr, recnum, date_contact = d_inddto) %>%  # d_inddto = admission date; rename for consistency
  inner_join(
    lpr_diag %>%
      filter(c_diagtype %in% diagtypes) %>%       # A, B, G diagnosis types for comorbidity capture
      mutate(
        icd4 = substr(c_diag, 2, 5)              # strip DST "D" prefix; icd4 = 4-char ICD-10 code
      ) %>%
      select(recnum, icd4),
    by = "recnum"                                 # join admissions to diagnoses on the record number
  ) %>%
  select(pnr, date_contact, icd4) %>%
  collect()                                       # pull filtered rows into R memory

message("Section 2.1 complete: ", nrow(lpr2_somatic), " LPR2 somatic diagnosis records.")

# ============================================================================
# 2.2 LPR2 PSYCHIATRIC (t_psyk_adm + t_psyk_diag, up to March 2019)
# ============================================================================
# Psychiatric contacts before March 2019 are in a SEPARATE register.
# F10 (alcohol use disorder) and F17 (tobacco dependence) are NMI components
# that would be missed entirely if this register is excluded.
# Column names differ from LPR2 somatic: v_cpr -> pnr, k_recnum/v_recnum -> recnum.
message("Section 2.2: loading LPR2 psychiatric diagnoses...")

psyk_adm  <- load_database("t_psyk_adm")  %>% rename_with(tolower) %>%
  rename(pnr = v_cpr, recnum = k_recnum)    # v_cpr = person ID, k_recnum = record ID (DST psychiatric naming)
psyk_diag <- load_database("t_psyk_diag") %>% rename_with(tolower) %>%
  rename(recnum = v_recnum)                  # v_recnum = record ID on the diagnosis side

lpr2_psyk <- psyk_adm %>%
  filter(pnr %in% !!pnrs) %>%                    # cohort filter pushed to parquet
  select(pnr, recnum, date_contact = d_inddto) %>%  # d_inddto = admission date (same column name as somatic)
  inner_join(
    psyk_diag %>%
      filter(c_diagtype %in% diagtypes) %>%       # A, B, G as above
      mutate(icd4 = substr(c_diag, 2, 5)) %>%    # strip "D" prefix
      select(recnum, icd4),
    by = "recnum"
  ) %>%
  select(pnr, date_contact, icd4) %>%
  collect()

message("Section 2.2 complete: ", nrow(lpr2_psyk), " LPR2 psychiatric diagnosis records.")

# ============================================================================
# 2.3 LPR3 UNIFIED (lpr_a_kontakt + lpr_a_diagnose, March 2019 onwards)
# ============================================================================
# LPR3 covers BOTH somatic and psychiatric contacts — no separate psychiatric
# table is needed for contacts from March 2019 onwards.
# Key differences from LPR2: person ID = pnr (no rename), join key = dw_ek_kontakt,
# date column = kont_starttidspunkt (datetime -> extract date with as.Date()),
# diagnosis type column = diag_kode_type (equivalent to c_diagtype in LPR2).
# Retracted diagnoses: filter out later_afkraeftet == "Ja" (diagnosis later retracted).
message("Section 2.3: loading LPR3 diagnoses...")

kontakter <- load_database("lpr_a_kontakt") %>% rename_with(tolower)   # LPR3 contacts; key columns: pnr, dw_ek_kontakt, kont_starttidspunkt
diagnoser <- load_database("lpr_a_diagnose") %>% rename_with(tolower)  # LPR3 diagnoses; key columns: dw_ek_kontakt, diag_kode, diag_kode_type, senere_afkraeftet

lpr3 <- kontakter %>%
  filter(pnr %in% !!pnrs) %>%                           # cohort filter pushed to parquet
  select(pnr, dw_ek_kontakt, kont_starttidspunkt) %>%   # only the three columns needed for the join and date
  inner_join(
    diagnoser %>%
      filter(
        diag_kode_type %in% diagtypes,                  # A, B, G diagnosis types
        is.na(senere_afkraeftet) | senere_afkraeftet != "Ja"  # exclude diagnoses later retracted; keep NAs (defensive)
      ) %>%
      mutate(icd4 = substr(diag_kode, 2, 5)) %>%        # strip DST "D" prefix from LPR3 diagnosis code
      select(dw_ek_kontakt, icd4),
    by = "dw_ek_kontakt"                                 # LPR3 join key (replaces recnum used in LPR2)
  ) %>%
  collect() %>%
  mutate(date_contact = as.Date(kont_starttidspunkt)) %>%   # kont_starttidspunkt is a datetime; extract date component
  select(pnr, date_contact, icd4)

message("Section 2.3 complete: ", nrow(lpr3), " LPR3 diagnosis records.")

# ============================================================================
# 2.4 COMBINE ALL THREE SOURCES AND APPLY 5-YEAR LOOKBACK FILTER
# ============================================================================
# Bind the three LPR sources and apply the 5-year lookback per person.
# The lookback is applied AFTER combining so we only make one join to the cohort.
# 365.25 days/year accounts for leap years over the 5-year window.

all_dx <- bind_rows(lpr2_somatic, lpr2_psyk, lpr3) %>%   # one long table: pnr, date_contact, icd4 from all three LPR sources
  inner_join(
    cohort %>% select(pnr, index_date),   # attach each person's index date for per-person lookback calculation
    by = "pnr"
  ) %>%
  filter(
    date_contact >= index_date - 365.25 * 5,   # 5-year lookback: Kristensen 2022 specification
    date_contact <  index_date                 # strictly before index date — no diagnoses on or after surgery counted as baseline
  ) %>%
  select(pnr, icd4)   # only pnr and icd4 needed for the regex flag loop; drop date_contact to reduce memory

rm(lpr2_somatic, lpr2_psyk, lpr3)   # free memory from the three raw pulls before the flag loops
gc()                                  # release freed memory back to the OS


# ============================================================================
# 3. DIAGNOSIS FLAGS — 29 NMI GROUPS (TABLE 2, KRISTENSEN 2022)
# ============================================================================
# Each group is defined by a regex pattern matched against icd4 (4-char ICD-10,
# DST "D" prefix stripped). Patterns are taken verbatim from the official Stata
# code (online_nmi.do, https://pharmacoepi.sdu.dk/nmi/).
#
# Flag = 1 if the person had at least one diagnosis matching the pattern
#          in the 5-year lookback window; 0 otherwise.
#
# NB: grepl() is vectorised and fast on collected data. We do not use
# heaven::findCondition() here because all_dx is already collected and
# prefix-stripped; restructuring to raw parquet format would add complexity
# without a meaningful speed gain at this stage.
#
# ============================================================================
# 3.1 ICD PATTERNS AND WEIGHTS
# ============================================================================
# Named character vector: name = predictor label (used as column name in output),
# value = regex pattern matched against icd4.
# Patterns requiring 4-char precision use icd4 directly (e.g. ^I110, ^D43[0-2]).

dx_patterns <- c(
  dx_B18      = "^B18",                                                    # Chronic viral hepatitis (B18.0-B18.9)
  dx_C34      = "^C34",                                                    # Lung and bronchus cancer
  dx_C50      = "^C50",                                                    # Breast cancer
  dx_C61      = "^C61",                                                    # Prostate cancer
  dx_C67      = "^C67",                                                    # Bladder cancer
  dx_C70_D432 = "^C7[01]|^C75[1-3]|^D32|^D33[0-2]|^D35[2-4]|^D42|^D43[0-2]|^D44[3-5]",
                                                                            # Brain/CNS tumours (malignant and uncertain behaviour)
  dx_C76_C80  = "^C7[6-9]|^C80",                                          # Secondary and unspecified malignancies
  dx_C91_C95  = "^C9[1-5]",                                               # Haematological cancers (leukaemia, lymphoma)
  dx_D50_D64  = "^D5[0-9]|^D6[0-4]",                                     # Anaemia and other blood disorders
  dx_E11      = "^E11",                                                    # Type 2 diabetes mellitus
  dx_E86      = "^E86",                                                    # Volume depletion / dehydration
  dx_F00_G30  = "^F0[0-3]|^G30",                                          # Dementia (F00-F03) and Alzheimer's (G30)
                                                                            # NOTE: G31 is NOT an NMI component per Kristensen 2022 Table 2
  dx_F10      = "^F10",                                                    # Alcohol use disorder
  dx_F17      = "^F17",                                                    # Tobacco use disorder / dependence
  dx_G20_G22  = "^G2[0-2]",                                               # Parkinson's disease and parkinsonism
  dx_G35      = "^G35",                                                    # Multiple sclerosis
  dx_G40_G41  = "^G4[01]",                                                # Epilepsy and status epilepticus
  dx_I05_I35  = "^I0[56]|^I3[45]",                                       # Valvular heart disease
  dx_I110_I50 = "^I110|^I13[02]|^I42[06789]|^I50",                      # Heart failure (hypertensive and other cardiomyopathies)
  dx_I60_I69  = "^I6[0-9]",                                               # Cerebrovascular disease (stroke, TIA, sequelae)
  dx_I70_I77  = "^I7[0347]",                                              # Peripheral arterial disease and aortic disease
  dx_I71_I72  = "^I7[12]",                                                # Aortic aneurysm and dissection
  dx_J12_J18  = "^J1[2-8]",                                               # Pneumonia (viral, bacterial, unspecified)
  dx_J41_J47  = "^J4[12347]|^J96[19]",                                   # COPD, bronchiectasis, and respiratory failure
  dx_J84      = "^J84",                                                    # Interstitial lung disease / pulmonary fibrosis
  dx_K02_K08  = "^K0[234568]",                                            # Dental caries and other oral diseases
  dx_K70_K767 = "^K7[024]|^K76[67]",                                     # Liver disease (alcoholic, cirrhosis, portal hypertension)
  dx_L89      = "^L89",                                                    # Pressure ulcers (decubitus ulcers)
  dx_N18_N19  = "^N1[89]"                                                 # Chronic kidney disease and renal failure
)

# Weights from Kristensen 2022 Table 2 (verbatim from official Stata code).
# Higher weight = stronger predictor of 1-year mortality.
# All are positive except for the two protective prescription predictors (in Section 4).
dx_weights <- c(
  dx_B18      = 10,  dx_C34      = 19,  dx_C50      = 4,   dx_C61      = 5,
  dx_C67      = 8,   dx_C70_D432 = 8,   dx_C76_C80  = 22,  dx_C91_C95  = 8,
  dx_D50_D64  = 5,   dx_E11      = 2,   dx_E86      = 6,   dx_F00_G30  = 9,
  dx_F10      = 12,  dx_F17      = 4,   dx_G20_G22  = 7,   dx_G35      = 7,
  dx_G40_G41  = 5,   dx_I05_I35  = 2,   dx_I110_I50 = 4,   dx_I60_I69  = 4,
  dx_I70_I77  = 5,   dx_I71_I72  = 4,   dx_J12_J18  = 4,   dx_J41_J47  = 4,
  dx_J84      = 7,   dx_K02_K08  = 5,   dx_K70_K767 = 13,  dx_L89      = 11,
  dx_N18_N19  = 7
)

# ============================================================================
# 3.2 FLAG EACH PERSON PER DIAGNOSIS GROUP
# ============================================================================
# For each of the 29 groups: flag = 1 if person had any matching diagnosis in
# the 5-year lookback window; 0 if not.
# Loop builds result incrementally: one column per group, left_joined to a
# one-row-per-person frame. NA from left_join (= no matching diagnosis) -> 0.

result <- cohort %>% select(pnr)   # start with one row per person; flag columns added in the loop below

message("Section 3: computing diagnosis flags for ", length(dx_patterns), " NMI groups...")

for (pred_name in names(dx_patterns)) {
  matched <- all_dx %>%
    filter(grepl(dx_patterns[[pred_name]], icd4)) %>%   # regex match of ICD pattern against 4-char code
    distinct(pnr) %>%                                    # one row per person; we only need presence, not count
    mutate(!!pred_name := 1L)                           # flag column named after the predictor (e.g. dx_C34)
  result <- result %>%
    left_join(matched, by = "pnr")                      # persons without a match get NA
  result[[pred_name]] <- coalesce(result[[pred_name]], 0L)   # replace NA with 0 (no diagnosis = absent)
}

rm(all_dx)   # free the large combined diagnosis table; no longer needed after flag loop
gc()          # release freed memory

message("Section 3 complete: diagnosis flags computed for ", nrow(result), " persons.")


# ============================================================================
# 4. PRESCRIPTION FLAGS — 21 NMI GROUPS (TABLE 2, KRISTENSEN 2022)
# ============================================================================

# ============================================================================
# 4.1 LOAD LMDB AND APPLY 6-MONTH LOOKBACK
# ============================================================================
# LMDB: laegemiddelstatistikregistret (the Danish prescription register).
# One row per dispensing (not prescription). Key columns: pnr, atc, eksd (dispense date).
# ATC codes have no prefix stripping — matched against the full ATC string.
#
# 6-month lookback (180 days) is shorter than the diagnosis lookback because
# current medication use reflects current disease status; old prescriptions
# may have been discontinued and may not represent the patient's present state.

message("Section 4.1: loading LMDB prescription data for ", length(pnrs),
        " cohort members (6-month lookback)...")

lmdb <- load_database("lmdb") %>% rename_with(tolower)   # prescription register; lazy tbl

rx_baseline <- lmdb %>%
  filter(pnr %in% !!pnrs) %>%      # push cohort filter to parquet before collecting
  select(pnr, atc, eksd) %>%       # atc = ATC code (full string), eksd = dispense date
  collect() %>%                     # pull filtered dispensings into R memory
  inner_join(
    cohort %>% select(pnr, index_date),   # attach each person's index date for lookback filter
    by = "pnr"
  ) %>%
  filter(
    eksd >= index_date - 180,   # 6-month lookback: 180 days before index date (NMI specification)
    eksd <  index_date          # strictly before index date — no post-surgery prescriptions
  ) %>%
  select(pnr, atc)   # drop eksd and index_date after filtering; only atc needed for pattern matching

message("Section 4.1 complete: ", nrow(rx_baseline), " prescription records in 6-month lookback.")

# ============================================================================
# 4.2 ATC PATTERNS AND WEIGHTS
# ============================================================================
# Named character vector: name = predictor label, value = regex pattern.
# Patterns are matched against the full ATC code string (no prefix stripping needed).
# Two predictors have NEGATIVE weights (protective associations with 1-year mortality):
#   rx_C09C_C09D (ARBs/sartans) = -2 — likely healthy-user effect (adherent patients)
#   rx_C10AA     (statins)      = -3 — similar healthy-user effect; preventive use

rx_patterns <- c(
  rx_A06A          = "^A06A",          # Laxatives (bulk-forming, osmotic, stimulant)
  rx_A07DA         = "^A07DA",         # Opioid antidiarrhoeals (e.g. loperamide)
  rx_A10A          = "^A10A",          # Insulin (all types)
  rx_B01AC         = "^B01AC",         # Platelet aggregation inhibitors (aspirin, clopidogrel, ticagrelor)
  rx_B03A          = "^B03A",          # Iron preparations (oral and parenteral)
  rx_C01AA         = "^C01AA",         # Cardiac glycosides (digoxin)
  rx_C03C_C03EB    = "^C03C|^C03EB",  # High-ceiling / loop diuretics (furosemide, bumetanide)
  rx_C03DA         = "^C03DA",         # Aldosterone antagonists (spironolactone, eplerenone)
  rx_C09C_C09D     = "^C09[CD]",      # ARBs / sartans (losartan, valsartan etc.) — NEGATIVE weight (-2)
  rx_C10AA         = "^C10AA",         # Statins (atorvastatin, simvastatin etc.)  — NEGATIVE weight (-3)
  rx_H02AB         = "^H02AB",         # Systemic glucocorticoids (prednisolone, dexamethasone)
  rx_J01C          = "^J01C",          # Penicillins — used here as a severity/comorbidity marker
  rx_N02A          = "^N02A",          # Opioid analgesics (morphine, oxycodone, fentanyl)
  rx_N02BE         = "^N02BE",         # Paracetamol (acetaminophen)
  rx_N05BA_N05CF   = "^N05BA|^N05C[DF]",  # Anxiolytics (benzodiazepines) and hypnotics (Z-drugs)
  rx_N05AA_N05AX   = "^N05A[A-L]|^N05AX", # Antipsychotics (typical and atypical)
  rx_N06A          = "^N06A",          # Antidepressants (all classes: SSRI, SNRI, TCA, etc.)
  rx_N06D          = "^N06D",          # Anti-dementia drugs (cholinesterase inhibitors, memantine)
  rx_N07BC         = "^N07BC",         # Opioid dependence treatment (methadone, buprenorphine)
  rx_R03AC02_05    = "^R03AC0[2-5]",  # Short-acting beta-2 agonists (salbutamol, terbutaline)
  rx_R03BB04_07    = "^R03BB0[4-7]"   # Long-acting anticholinergics for COPD (tiotropium, glycopyrronium)
)

# Weights from Kristensen 2022 Table 2 (verbatim from official Stata code).
# Negative weights for C09C_C09D and C10AA reflect protective associations.
rx_weights <- c(
  rx_A06A          = 8,   rx_A07DA         = 5,   rx_A10A          = 4,
  rx_B01AC         = 2,   rx_B03A          = 5,   rx_C01AA         = 4,
  rx_C03C_C03EB    = 5,   rx_C03DA         = 3,   rx_C09C_C09D     = -2,
  rx_C10AA         = -3,  rx_H02AB         = 2,   rx_J01C          = 1,
  rx_N02A          = 2,   rx_N02BE         = 2,   rx_N05BA_N05CF   = 1,
  rx_N05AA_N05AX   = 7,   rx_N06A          = 3,   rx_N06D          = 11,
  rx_N07BC         = 7,   rx_R03AC02_05    = 3,   rx_R03BB04_07    = 5
)

# ============================================================================
# 4.3 FLAG EACH PERSON PER PRESCRIPTION GROUP
# ============================================================================
# Same logic as Section 3.2: flag = 1 if any matching dispensing in the
# 6-month window; 0 if not. Left_join NA -> 0 via coalesce().

message("Section 4.3: computing prescription flags for ", length(rx_patterns), " NMI groups...")

for (pred_name in names(rx_patterns)) {
  matched <- rx_baseline %>%
    filter(grepl(rx_patterns[[pred_name]], atc)) %>%   # regex match against full ATC code
    distinct(pnr) %>%                                   # one row per person; presence not count
    mutate(!!pred_name := 1L)                          # flag column named after the predictor
  result <- result %>%
    left_join(matched, by = "pnr")                     # non-users get NA
  result[[pred_name]] <- coalesce(result[[pred_name]], 0L)   # NA -> 0 (no dispensing = absent)
}

rm(rx_baseline)   # free the prescription lookback table; no longer needed
gc()               # release freed memory

message("Section 4.3 complete: prescription flags computed.")


# ============================================================================
# 5. COMPUTE NMI SCORE (WEIGHTED SUM)
# ============================================================================
# The NMI score = sum over all 50 predictors of (flag * weight).
# Each person's score is the total weighted burden across all diagnosis and
# prescription components present in their lookback windows.
#
all_weights    <- c(dx_weights, rx_weights)   # single named weight vector for all 50 predictors
predictor_cols <- names(all_weights)          # column names in result that hold the 0/1 flags

message("Section 5: computing NMI score from all ", length(all_weights), " predictors.")

# sweep() multiplies each flag column by its weight (column-wise scaling).
# rowSums() sums across all weighted columns to give each person's total NMI score.
# Example: dx_C34 = 1 (lung cancer, weight 19) + rx_C10AA = 1 (statin, weight -3)
# with no other flags = score of 19 + (-3) = 16.
nmi_scores <- rowSums(
  sweep(
    as.matrix(result[, predictor_cols]),   # flag matrix: rows = persons, cols = predictors
    2,                                      # margin 2 = apply across columns
    all_weights[predictor_cols],            # weight vector aligned to column order
    "*"                                     # multiply each flag by its weight
  )
)


# ============================================================================
# 6. COMBINE: SCORE + ALL 50 FLAGS — ONE ROW PER PERSON
# ============================================================================
# Attach nmi_score to the flag table. All 50 flag columns are retained regardless
# of exclude_dementia_predictors, so colleagues can audit individual conditions.

nmi_data <- result %>%
  mutate(nmi_score = nmi_scores)   # attach continuous NMI score; all 50 flag columns already in result

# Column ordering: pnr, nmi_score first (the main output), then all 50 flag columns.
nmi_data <- nmi_data %>%
  select(pnr, nmi_score, everything())   # nmi_score first; flag columns follow in dx_ then rx_ order

# Row count check: nmi_data must have exactly one row per cohort member.
# More rows = duplicate pnrs introduced somewhere in the flag loop (should not happen).
if (nrow(nmi_data) != nrow(cohort))
  warning(
    "Row count mismatch: cohort has ", nrow(cohort),
    " rows but nmi_data has ", nrow(nmi_data), " rows. ",
    "Check for duplicate pnrs with: nmi_data %>% filter(duplicated(pnr))"
  )


# ============================================================================
# 7. SAVE OUTPUT
# ============================================================================

dir.create(path_output, showWarnings = FALSE, recursive = TRUE)   # create output directory if it does not already exist
saveRDS(nmi_data, file.path(path_output, "nmi_data.rds"))         # save to disk; load in analysis script with readRDS()

cat("nmi_data.rds saved to", path_output, "\n")
cat("Rows:", nrow(nmi_data), " (cohort rows: ", nrow(cohort), ")\n", sep = "")
cat("NMI score — mean:", round(mean(nmi_data$nmi_score), 2),
    " | median:", median(nmi_data$nmi_score),
    " | range:", min(nmi_data$nmi_score), "to", max(nmi_data$nmi_score), "\n")
cat("Persons with nmi_score <= 0:", sum(nmi_data$nmi_score <= 0),
    " (expected if persons have statins/ARBs and no other conditions)\n")

# Condition prevalence spot-check (most common NMI components in typical Danish cohorts).
# High prevalence of dx_F17 (tobacco) or rx_C10AA (statins) is expected in BS populations.
cat("\nCondition prevalences (% with flag = 1):\n")
cat("  dx_E11 (T2D):        ", round(100 * mean(nmi_data$dx_E11),       1), "%\n", sep = "")
cat("  dx_F17 (tobacco):    ", round(100 * mean(nmi_data$dx_F17),       1), "%\n", sep = "")
cat("  dx_F10 (alcohol):    ", round(100 * mean(nmi_data$dx_F10),       1), "%\n", sep = "")
cat("  dx_I60_I69 (stroke): ", round(100 * mean(nmi_data$dx_I60_I69),   1), "%\n", sep = "")
cat("  rx_C10AA (statins):  ", round(100 * mean(nmi_data$rx_C10AA),     1), "%\n", sep = "")
cat("  rx_N06A (antidep):   ", round(100 * mean(nmi_data$rx_N06A),      1), "%\n", sep = "")
cat("  dx_F00_G30 (dement): ", round(100 * mean(nmi_data$dx_F00_G30), 1), "%\n", sep = "")
cat("  rx_N06D (anti-dem):  ", round(100 * mean(nmi_data$rx_N06D),    1), "%\n", sep = "")


# ============================================================================
# HOW TO LOAD AND USE IN YOUR ANALYSIS SCRIPT
# ============================================================================
#
# In your data management or analysis script:
#
#   nmi <- readRDS(file.path(path_output, "nmi_data.rds")) %>%
#     select(pnr, nmi_score)   # select only the score for Cox; add flag columns if needed for Table 1
#
#   df <- df %>%
#     left_join(nmi, by = "pnr")
#
#   # Cox model with NMI adjustment:
#   fit <- coxph(
#     Surv(follow_up_days, event) ~
#       exposure +
#       age_at_index + sex +
#       nmi_score +          # continuous — do NOT categorise
#       education_cat +      # SEP dimension 1 (from SEPLINE.R)
#       income_cat +         # SEP dimension 2 (from SEPLINE.R)
#       occupation_cat +     # SEP dimension 3 (from SEPLINE.R)
#       surgery_period,
#     data = df,
#     cluster = matched_pnr
#   )
#
# For Table 1: load the full nmi_data.rds and use the flag columns to compute
# condition prevalences in the BS vs comparator groups.
#   nmi_full <- readRDS(file.path(path_output, "nmi_data.rds"))
#   df <- df %>% left_join(nmi_full, by = "pnr")
#   # Then pass to gtsummary::tbl_summary() or similar.
#
# Report:
#   - nmi_score as a continuous covariate in Table 2 (model covariate table)
#   - Individual condition prevalences in Table 1 (baseline characteristics)
#   - Cite: Kristensen KB et al. Clin Epidemiol. 2022;14:567-579.
#           DOI: 10.2147/CLEP.S353398
# ============================================================================
