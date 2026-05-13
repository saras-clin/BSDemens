# ============================================================================
# PIPELINE STEP 4 of 5 — 04_data_management_dementia.R
# ============================================================================
# MAKE THE DATA ANALYSIS-READY (STUDY 1 ONLY)
#   Merges all extracted pieces into one clean dataset for the dementia study.
#   Run AFTER Steps 1–3 have completed:
#     01_build_cohorts.R               → full_cohort.rds
#     02_extract_outcomes_covariates.R → extract_*.rds files
#     03_extract_ses.R                 → ses_data.rds
#   Study 2 (T1D) will have its own script: 05_data_management_t1d.R
#
#   What this script does, in order:
#     4.1 Load & merge  — joins full_cohort + all extract_*.rds + ses_data.rds
#     4.2 Safety check  — removes anyone with pre-surgery dementia that slipped
#                         through (safety net for F-code from LPR2 psychiatric)
#     4.3 ICD + Rx      — supplements hypertension and dyslipidemia flags with
#                         prescriptions (under-captured by hospital ICD codes alone)
#     4.4 NMI count     — counts how many GMC conditions the person has (Table 1)
#                         NOTE: nmi_score (Kristensen 2022 weighted index) is
#                         separate — already in the merged data from extract_nmi.rds
#                         nmi_count = simple count (for Table 1 descriptives)
#                         nmi_score = weighted sum of 50 predictors (for Cox models)
#     4.5 Format vars   — factors, date differences, age categories, calendar period
#
#   Inputs:  datasets/full_cohort.rds, datasets/extract_*.rds, datasets/ses_data.rds
#   Output:  datasets/study1_clean.rds  (one row per person; ready for Cox models)
# ============================================================================

library(dplyr)
library(lubridate)
library(heaven)        # exposureMatch(), charlsonIndex(), etc.

# Paths ----
path_output <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets"

load_rds <- function(name) {
  readRDS(file.path(path_output, name))
}

# ============================================================================
# 4.0 EMIGRATION DATES [STUB — CRITICAL: NOT YET IMPLEMENTED]
# ============================================================================
# Persons who emigrate from Denmark leave Danish registers and can no longer be
# followed for dementia. Continuing to count their time as at-risk after
# emigration overstates person-time and biases hazard ratios if emigration rates
# differ between BS and comparator groups (e.g. if healthy migrants preferentially
# have surgery abroad, or if obesity affects emigration rates differently).
#
# Emigration is a COMPETING RISK for dementia: someone who emigrates can no
# longer be observed for dementia regardless of whether they later develop it.
# The correct handling is to CENSOR at the emigration date, exactly as we censor
# at death or at the end of the study period.
#
# This function is a STUB — it returns NA_Date_ for all persons.
# With emigration_date = NA, pmin(..., na.rm = TRUE) in censor_date below will
# ignore the NA and fall back to follow_up_end / bs_crossover_date as before.
# No data are affected until this stub is replaced with a real register query.
#
# ACTION REQUIRED from data manager (project 708421):
#   Confirm which register and column to use:
#   Option A — VNDS register: load_database("vnds"); check column for departure date.
#   Option B — BEF-derived: persons who appear in BEF year Y but not in Y+1 are
#              assumed to have emigrated. Less precise (date unknown within year).
#   Option C — CPR Registeret (RVNDS): contact DST for direct extract.
#
# Once confirmed, replace the body of this function with the register query.
# pmin() in format_variables() will then automatically apply emigration censoring.

get_emigration_dates <- function(pnr_vector) {
  # STUB: returns NA for all persons — emigration censoring not yet applied.
  data.frame(                              # return a data frame for left_join compatibility
    pnr             = pnr_vector,          # same ordering as input pnrs
    emigration_date = as.Date(NA_character_)  # NA means no censoring until register is wired up
  )
}

# ============================================================================
# 4.1 LOAD AND MERGE ALL EXTRACTED DATASETS
# ============================================================================

load_and_merge <- function() {
  full_cohort   <- load_rds("full_cohort.rds") %>% rename(surgery_date = index_date)
  demographics  <- load_rds("extract_demographics.rds")
  dementia      <- load_rds("extract_dementia.rds")
  comorbidities <- load_rds("extract_comorbidities.rds")
  nmi           <- load_rds("extract_nmi.rds")        # weighted NMI score (Kristensen 2022): pnr + nmi_score
  medications   <- load_rds("extract_medications.rds")
  diabetes      <- load_rds("extract_diabetes.rds")
  ses           <- load_rds("ses_data.rds") %>%
    select(pnr, education_cat, income_cat, occupation_cat)   # sep_category removed: SEPLINE does not recommend a composite

  # demographics contains surgery_date and surgery_type which already exist in full_cohort —
  # drop them before joining to avoid duplicate columns.
  weights <- load_rds("extract_weights.rds")   # DBSO weight outcomes from step 02 (BS cohort only)

  full_cohort %>%
    left_join(demographics  %>% select(-surgery_date, -surgery_type), by = "pnr") %>%
    left_join(dementia,      by = "pnr") %>%
    left_join(comorbidities, by = "pnr") %>%
    left_join(nmi,           by = "pnr") %>%   # adds nmi_score column
    left_join(medications,   by = "pnr") %>%
    left_join(diabetes,      by = "pnr") %>%
    left_join(ses,           by = "pnr") %>%
    left_join(weights %>% select(pnr, weight_preop, height_preop, bmi_preop), by = "pnr")
}

# ============================================================================
# 4.2 RENAME AND COMPUTE DBSO WEIGHT VARIABLES
# ============================================================================
# weight_preop, height_preop, bmi_preop arrive from extract_weights.rds with
# provisional names assigned during extraction (step 02). Descriptive analysis
# names are assigned here. BMI at program entry (baseline_bmi) is also computed
# here from udgangsvaegt (referral weight); note this requires adding
# referral_wgt extraction to extract_weight_outcomes() in step 02 if needed.
#
#   pre_surgery_wgt — weight (kg) at last pre-op clinic visit (from udgangsvaegtpre_prim)
#   pre_surgery_bmi — BMI at last pre-op clinic visit (computed in step 02)
#   height          — height in cm (from hoejde)

rename_weight_vars <- function(df) {
  df %>%
    rename(
      pre_surgery_wgt = weight_preop,   # wgt (kg) at last pre-op visit
      pre_surgery_bmi = bmi_preop,      # BMI at last pre-op visit
      height          = height_preop    # height (cm)
    )
}

# ============================================================================
# 4.2 EXCLUSIONS: PRE-SURGERY DEMENTIA (SAFETY CHECK)
# ============================================================================
# The primary pre-surgery dementia exclusion runs in 01_build_cohorts.R using
# get_prior_dementia_pnrs(). That function covers LPR2 somatic (lpr_adm/lpr_diag),
# LPR2 psychiatric (psyk_adm/psyk_diag via arrow::open_dataset), and LPR3
# (lpr_a_kontakt/lpr_a_diagnose). All three sources are now included.
#
# F-code dementia (F00 Alzheimer's, F01 vascular, F02 other, F03 unspecified)
# is routinely diagnosed in geropsychiatric outpatient memory clinics. Before
# March 2019 these contacts live in the separate psychiatric register on DST,
# which get_prior_dementia_pnrs() now queries directly.
#
# This function is a safety net: it re-applies the same filter on the joined
# analysis dataset. With all three LPR sources included upstream, it should
# print 0 exclusions — treat any non-zero count as a signal to investigate.

apply_exclusions <- function(df) {
  n_before <- nrow(df)

  # date_dementia is the raw first dementia date from 02_extract_outcomes_covariates.R.
  # Keep only rows where dementia is absent (NA) or occurred AFTER the surgery/index date.
  # Rows where date_dementia <= surgery_date have prevalent dementia: exclude them.
  df <- df %>%
    filter(is.na(date_dementia) | date_dementia > surgery_date)

  n_after <- nrow(df)
  if (n_before > n_after) {
    message("Excluded ", n_before - n_after,
            " person(s) with pre-surgery dementia caught at data-management stage.",
            " Likely F-code cases from the LPR2 psychiatric register not caught upstream.")
  }

  df
}

# ============================================================================
# 4.3 SUPPLEMENT: HYPERTENSION AND DYSLIPIDEMIA WITH PRESCRIPTION DATA
# ============================================================================
# The NMI (Kristensen et al., Clin Epidemiol 2022) is defined using ICD-10 codes
# from hospital registers. However, hypertension and dyslipidemia are primarily
# managed in primary care in Denmark and are often UNDER-captured by hospital ICD
# codes alone. We supplement these two conditions with prescription data to improve
# sensitivity, consistent with common practice in Danish register epidemiology.
#
# Diabetes is NOT supplemented here because:
#   - The OSDC pre-computed file provides far more accurate diabetes classification
#     than anything derived from ICD codes or A10 prescriptions alone.
#   - The OSDC flag (diabetes_nmi) is created in compute_nmi() directly from
#     the diabetes_type variable from extract_diabetes.rds.
#   - GLP-1 receptor agonists (A10BJ) are commonly prescribed for weight loss in
#     bariatric surgery patients with NO diabetes, making A10-based flagging
#     unreliable in this population.
#
# Decision: if you prefer strict NMI (ICD-only for all conditions), remove this
# function and replace hypertension_combined/dyslipidemia_combined with hypertension
# and dyslipidemia in the nmi_vars list in compute_nmi().

combine_icd_rx_flags <- function(df) {
  df %>%
    mutate(
      # Hypertension: ICD I10-I15 (from LPR) OR antihypertensive prescription
      # (C02/C03/C07/C08/C09 from lmdb). Either source alone is sufficient.
      hypertension_combined = as.integer(hypertension == 1 | antihypertensive == 1),

      # Dyslipidemia: ICD E78 (from LPR) OR lipid-lowering prescription (C10 from lmdb).
      dyslipidemia_combined = as.integer(dyslipidemia == 1 | lipid_lowering == 1)
    )
}

# ============================================================================
# 4.4 MULTIMORBIDITY COUNT AND CATEGORY (FOR TABLE 1)
# ============================================================================
# Counts how many of the 33 GMC baseline conditions the person has at surgery.
# Produces nmi_count (integer) and nmi_cat (factor 0/1/2/3+) for Table 1 descriptives.
#
# !! This is NOT the same as the Kristensen NMI weighted score !!
#    nmi_score  = weighted sum of 50 predictors from extract_nmi.rds — use in Cox models
#    nmi_count  = simple count of how many conditions are present — use in Table 1
#
# Three sources feed the condition flags:
#   - ICD codes from LPR (all conditions via extract_baseline_comorbidities.rds)
#   - Prescription supplement for hypertension + dyslipidemia (STEP 3 above)
#   - OSDC classification for diabetes (most accurate source)

compute_multimorbidity_count <- function(df) {
  # Derive diabetes flag from OSDC classification (diabetes_type from extract_diabetes.rds).
  # "No_diabetes" = not classified as T1D or T2D by OSDC → flag = 0.
  # This is more accurate than ICD E10-E14 or A10 prescriptions for diabetes in this cohort.
  df <- df %>%
    mutate(diabetes_nmi = as.integer(diabetes_type != "No_diabetes"))

  # Binary condition columns (0/1) to count across.
  # hypertension_combined and dyslipidemia_combined are ICD + prescription (see STEP 3).
  # All other conditions: ICD-only from extract_baseline_comorbidities.rds.
  nmi_vars <- c(
    "mi", "stroke_tia", "pad", "ihd", "heart_failure", "afib",
    "hypertension_combined",
    "diabetes_nmi",
    "dyslipidemia_combined",
    "thyroid", "gout",
    "copd", "asthma",
    "liver", "peptic_ulcer", "ibd", "diverticular",
    "ckd", "prostate",
    "connective_tissue", "osteoporosis",
    "depression", "bipolar",
    "parkinsons", "epilepsy", "ms", "migraine", "neuropathy",
    "cancer", "anemia", "hiv",
    "vision", "hearing"
  )

  # Keep only columns that exist in df (defensive in case some are missing)
  nmi_vars <- nmi_vars[nmi_vars %in% names(df)]

  df %>%
    mutate(
      nmi_count = rowSums(across(all_of(nmi_vars)), na.rm = TRUE),
      nmi_cat   = case_when(
        nmi_count == 0 ~ "0",
        nmi_count == 1 ~ "1",
        nmi_count == 2 ~ "2",
        nmi_count >= 3 ~ "3+"
      ) %>% factor(levels = c("0", "1", "2", "3+"))
    )
}

# ============================================================================
# 4.5 FORMAT VARIABLES FOR ANALYSIS
# ============================================================================

format_variables <- function(df) {
  df %>%
    mutate(

      # -----------------------------------------------------------------------
      # 4.5a COHORT AND SURGERY TYPE
      # Convert to factors with explicit reference levels for Cox regression.
      # -----------------------------------------------------------------------

      # cohort: three-level factor. "BS" = the bariatric surgery group (exposed).
      # "GP" = general population comparator. "Obesity" = obese-but-no-BS comparator.
      # The reference level in Cox models is typically set to the comparator group,
      # not BS — flip with relevel() at modelling time.
      cohort = factor(cohort, levels = c("BS", "GP", "Obesity")),

      # surgery_type: RYGB or SG. NA for GP and Obesity comparators (no surgery).
      # Reference level: RYGB. SG hazard ratios will therefore be relative to RYGB.
      surgery_type = factor(surgery_type, levels = c("RYGB", "SG")),


      # -----------------------------------------------------------------------
      # 4.5b CENSORING DATE (censor_date)
      # -----------------------------------------------------------------------
      # In survival analysis every person's observable follow-up ends at the
      # EARLIEST of several competing events. We call this the censor_date.
      #
      # For this study, censor_date = min of:
      #
      #   (a) follow_up_end — already the minimum of:
      #         - death_date (from dod register; DODDATO, Danish Death Register)
      #         - 2025-12-31 (administrative end of study, no more data after this)
      #       Computed in extract_demographics() in 02_extract_outcomes_covariates.R.
      #
      #   (b) bs_crossover_date — applies ONLY to GP and Obesity comparators who
      #       LATER underwent bariatric surgery after their index date.
      #       These individuals were enrolled as "never-BS" controls. Once they
      #       get surgery, they are no longer unexposed. We stop counting their
      #       time as control person-time at the date of their BS.
      #       They are CENSORED at that date — they do NOT become cases even if
      #       they develop dementia later (that would be on the BS side of the
      #       comparison). bs_crossover_date is set in 01_build_cohorts.R.
      #       It is NA for all BS patients and for comparators who never had BS.
      #
      # emigration_date: from get_emigration_dates() in section 4.0.
      #   Currently NA for all persons (stub). Once the register is confirmed,
      #   persons who emigrate will be censored at their departure date.
      #   emigration_date is wired into pmin() now so no further code changes
      #   will be needed when the stub is replaced.
      #
      # pmin(..., na.rm = TRUE): returns the smallest non-NA value per row.
      #   When bs_crossover_date and emigration_date are NA (most rows),
      #   censor_date = follow_up_end.
      censor_date = pmin(follow_up_end, bs_crossover_date, emigration_date, na.rm = TRUE),


      # -----------------------------------------------------------------------
      # 4.5c ALL-CAUSE DEMENTIA OUTCOME (primary)
      # -----------------------------------------------------------------------
      # date_dementia: first contact with ANY dementia ICD code (F00-F03, G30-G31)
      # AFTER the index date. Extracted from LPR2 + LPR3 in
      # extract_dementia_outcomes() in 02_extract_outcomes_covariates.R.
      # NA if the person never received a dementia diagnosis during follow-up.
      #
      # dementia_event: 1 if dementia occurred AND before censor_date, else 0.
      # A dementia diagnosis that falls after censor_date is NOT counted as an
      # event — the person was no longer in their control follow-up at that point
      # (e.g. they had already crossed over to BS). Treating post-crossover
      # diagnoses as events would contaminate the control group with exposed time.
      dementia_event = as.integer(!is.na(date_dementia) & date_dementia <= censor_date),

      # follow_up_days: person-time contribution in days, used as the time variable
      # in Surv() for Cox models and as the denominator for incidence rate calculations.
      # If event occurred: time from surgery/index date to the dementia diagnosis date.
      # If censored: time from surgery/index date to censor_date.
      follow_up_days = as.numeric(difftime(
        if_else(dementia_event == 1L, date_dementia, censor_date),
        surgery_date, units = "days"
      )),


      # -----------------------------------------------------------------------
      # 4.5d ALZHEIMER'S DISEASE OUTCOME (secondary)
      # -----------------------------------------------------------------------
      # date_alzheimers: first G30 (Alzheimer's disease, neurological) or F00
      # (Alzheimer's, psychiatric coding) contact after the index date.
      # Extracted independently of date_dementia: the Alzheimer's date may differ
      # from the all-cause dementia date if another dementia code appeared first.
      # This is intentional — secondary outcome analyses run separately.
      alzheimers_event = as.integer(!is.na(date_alzheimers) & date_alzheimers <= censor_date),
      follow_up_days_alz = as.numeric(difftime(
        if_else(alzheimers_event == 1L, date_alzheimers, censor_date),
        surgery_date, units = "days"
      )),


      # -----------------------------------------------------------------------
      # 4.5e VASCULAR DEMENTIA OUTCOME (secondary)
      # -----------------------------------------------------------------------
      # date_vascular: first F01 (vascular dementia) contact after the index date.
      # Same independent extraction logic as Alzheimer's.
      vascular_event = as.integer(!is.na(date_vascular) & date_vascular <= censor_date),
      follow_up_days_vasc = as.numeric(difftime(
        if_else(vascular_event == 1L, date_vascular, censor_date),
        surgery_date, units = "days"
      )),


      # -----------------------------------------------------------------------
      # 4.5f SEX
      # -----------------------------------------------------------------------
      # In DST registers, sex is stored as KOEN (Danish: "køn" = gender/sex).
      # KOEN = 1 → Male, KOEN = 2 → Female (DST coding convention for BEF register).
      # The conversion KOEN → sex ("Male"/"Female") was done in
      # extract_demographics() in 02_extract_outcomes_covariates.R.
      # Here we make it a factor for Cox regression. Reference level: Male.
      sex = factor(sex, levels = c("Male", "Female")),


      # -----------------------------------------------------------------------
      # 4.5g AGE AT INDEX DATE
      # -----------------------------------------------------------------------
      # age_at_surgery: continuous age in years, computed from FOED_DAG (birth date
      # in BEF) and surgery_date in extract_demographics(). Here we create clinical
      # age bands for stratified analyses and table 1.
      # Reference level for Cox: <50 (youngest, lowest dementia incidence).
      age_cat = case_when(
        age_at_surgery <  50 ~ "<50",
        age_at_surgery <  60 ~ "50–59",
        age_at_surgery <  70 ~ "60–69",
        age_at_surgery >= 70 ~ "≥70"
      ) %>% factor(levels = c("<50", "50–59", "60–69", "≥70")),


      # -----------------------------------------------------------------------
      # 4.5h CALENDAR PERIOD
      # -----------------------------------------------------------------------
      # Captures secular trends in BS technique (RYGB vs SG mix changed over time)
      # and in dementia diagnostic practice (increased awareness, new criteria).
      # Used as a covariate in fully adjusted models and as a stratification variable.
      surgery_year   = year(surgery_date),
      surgery_period = case_when(
        surgery_year < 2015  ~ "2010–2014",
        surgery_year < 2020  ~ "2015–2019",
        surgery_year >= 2020 ~ "2020–2024"
      ) %>% factor(levels = c("2010–2014", "2015–2019", "2020–2024")),


      # -----------------------------------------------------------------------
      # 4.5i DIABETES TYPE
      # -----------------------------------------------------------------------
      # Classified from the Open Source Diabetes Classifier (OSDC), a pre-computed
      # cohort file at E:/workdata/708421/cleaned-data/.../dm_population_1977_2022.rds.
      # Covers diagnoses up to 2022; patients with diabetes onset 2023-2024 will be
      # classified as No_diabetes (minor limitation, see MINOR-3 in TODO.txt).
      # Reference level: No_diabetes. T1D and T2D are compared against this.
      diabetes_type = factor(diabetes_type, levels = c("No_diabetes", "T1D", "T2D")),


      # -----------------------------------------------------------------------
      # 4.5j SOCIOECONOMIC POSITION (SEP)
      # -----------------------------------------------------------------------
      # All SEP variables derived in 03_extract_ses.R following the SEPLINE
      # algorithm (Hjorth et al., Clin Epidemiol 2025;17:593–624).
      #   education_cat: from UDDA register (hfaudd = ISCED education code).
      #                  Short (<= upper secondary), Medium (further/vocational),
      #                  Long (university). Reference: Medium (most common).
      #                  Adjust reference level before modelling if needed.
      education_cat  = factor(education_cat,
                              levels = c("Short", "Medium", "Long", "Unknown")),

      #   income_cat: from FAIK register (famaekvivadisp_13 = equivalised
      #               disposable household income). Population-standardised quintiles:
      #               3-year average (surgery_year-1, -2, -3) compared against
      #               Q20/Q40/Q60/Q80 cutpoints from the full BEF population,
      #               stratified by sex x 5-year age group x reference year (SEPLINE).
      income_cat     = factor(income_cat,
                              levels = c("Low", "Medium", "High", "Unknown")),

      #   occupation_cat: from AKM register (socio13 = socioeconomic classification).
      #                   Reference level: Working (employed at index date).
      occupation_cat = factor(occupation_cat,
                              levels = c("Working", "Unemployed", "Outside_workforce",
                                         "Retired", "Student", "Unknown")),

      # sep_category composite removed: SEPLINE (Hjorth et al. 2025) does not recommend
      # a composite SEP variable. Use education_cat, income_cat, and occupation_cat
      # as three separate terms in Cox models.
    )
}

# ============================================================================
# 4.6 MAIN: ASSEMBLE AND SAVE STUDY1_CLEAN.RDS
# ============================================================================

main_data_management <- function() {
  cat("Loading and merging extracted data...\n")
  df <- load_and_merge()
  cat("  n =", nrow(df), "before exclusions\n")

  # Attach emigration dates — currently a stub returning NA for all persons.
  # When the register is confirmed, get_emigration_dates() is updated and
  # pmin() in format_variables() automatically applies emigration censoring.
  emigration <- get_emigration_dates(df$pnr)        # one row per person with emigration_date
  df <- df %>% left_join(emigration, by = "pnr")    # join; emigration_date = NA until stub is replaced

  cat("Applying exclusions...\n")
  df <- apply_exclusions(df)
  cat("  n =", nrow(df), "after exclusions\n")

  cat("Combining ICD + prescription flags...\n")
  df <- combine_icd_rx_flags(df)

  cat("Computing multimorbidity condition count and category (Table 1)...\n")
  df <- compute_multimorbidity_count(df)
  # nmi_score (weighted Kristensen NMI) is already in df from load_and_merge() via extract_nmi.rds

  cat("Formatting variables...\n")
  df <- format_variables(df)

  # Cohort sizes
  cat("\nCohort sizes:\n")
  print(table(df$cohort))

  cat("\nDementia events by cohort:\n")
  print(table(df$cohort, df$dementia_event, useNA = "ifany"))

  saveRDS(df, file.path(path_output, "study1_clean.rds"))
  cat("\nSaved: study1_clean.rds\n")
  invisible(df)
}

# Run:
# study1 <- main_data_management()
