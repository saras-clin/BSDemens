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
#     4.5 Format vars   — factors, date differences, age categories, calendar period,
#                         death_event and event_type (0/1/2) for Fine-Gray models,
#                         sensitivity outcomes: dementia_event_primary (7g.1),
#                         cataract_event (7g.6)
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
# 4.0 EMIGRATION DATES
# ============================================================================
# Persons who emigrate from Denmark can no longer be followed in Danish registers.
# get_emigration_dates() queries VNDS (migration register), filters to emigration
# events (indud_kode == "U"), and returns the earliest emigration date per person.
# Non-emigrants receive emigration_date = NA; pmin() in format_variables() then
# ignores the NA and censors at follow_up_end or bs_crossover_date instead.

get_emigration_dates <- function(pnr_vector) {
  # VNDS register: one row per migration event per person.
  # indud_kode == "U" = udrejse (emigration); "I" = indrejse (immigration).
  # haend_dato = event date (character "YYYY-MM-DD"; as.Date() required).
  # We take the FIRST emigration date per person — censoring at first departure.
  vnds <- load_database("vnds") %>% rename_with(tolower)   # migration register
  vnds %>%
    filter(pnr %in% !!pnr_vector, indud_kode == "U") %>%   # emigration events only
    select(pnr, haend_dato) %>%                             # haend_dato = emigration date
    collect() %>%                                           # pull into memory
    mutate(haend_dato = as.Date(haend_dato)) %>%            # character "YYYY-MM-DD" to Date
    group_by(pnr) %>%                                       # one row per person
    summarise(emigration_date = min(haend_dato, na.rm = TRUE), .groups = "drop")   # earliest emigration
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
  weights           <- load_rds("extract_weights.rds")            # DBSO weight outcomes from step 02 (BS cohort only)
  negative_controls <- load_rds("extract_negative_controls.rds")  # fracture and cataract dates (sensitivity 7g.6)

  full_cohort %>%
    left_join(demographics  %>% select(-surgery_date, -surgery_type), by = "pnr") %>%
    left_join(dementia,        by = "pnr") %>%   # includes date_dementia_primary for sensitivity 7g.1
    left_join(comorbidities,   by = "pnr") %>%
    left_join(nmi,             by = "pnr") %>%   # adds nmi_score column
    left_join(medications,     by = "pnr") %>%
    left_join(diabetes,        by = "pnr") %>%
    left_join(ses,             by = "pnr") %>%
    left_join(weights %>% select(pnr, weight_preop, height_preop, bmi_preop), by = "pnr") %>%
    left_join(negative_controls, by = "pnr")     # date_cataract (sensitivity 7g.6)
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
      # 4.5d COMPETING RISK INDICATORS (for Fine-Gray models)
      # -----------------------------------------------------------------------
      # death_event: 1 if the person died during follow-up WITHOUT a prior dementia
      # diagnosis. Death is the competing event for dementia — a person who dies
      # without dementia can never develop it, so they do not simply "drop out"
      # as in standard censoring. Fine-Gray subdistribution hazard models require
      # this distinction. Persons who died AFTER a dementia diagnosis contribute
      # to dementia_event = 1, not to death_event.
      death_event = as.integer(!is.na(death_date) & death_date <= censor_date & dementia_event == 0L),

      # event_type: three-level integer for competing risk analysis.
      #   0 = censored  — no event before censor_date (alive and dementia-free)
      #   1 = dementia  — primary outcome; dementia diagnosis before/on censor_date
      #   2 = death     — competing event; died before censor_date without dementia
      # Use in Surv(follow_up_days, event_type, type = "mstate") or cmprsk::crr().
      event_type = as.integer(case_when(
        dementia_event == 1L ~ 1L,   # dementia event takes priority
        death_event    == 1L ~ 2L,   # death without prior dementia = competing event
        TRUE                 ~ 0L    # censored: alive and dementia-free at end of follow-up
      )),

      # -----------------------------------------------------------------------
      # 4.5d.1 DIAGTYPE-A-ONLY DEMENTIA — sensitivity 7g.1
      # -----------------------------------------------------------------------
      # NOTE on naming: "primary" in date_dementia_primary / dementia_event_primary
      # refers to DIAGNOSIS TYPE A (primary diagnosis code in LPR), NOT to the
      # primary outcome. The main analysis uses diagtypes A+B (primary + secondary
      # hospital diagnoses). This sensitivity restricts to A-code contacts only,
      # which is more specific (the dementia diagnosis was the main reason for
      # that hospital contact) at the cost of lower sensitivity (misses dementia
      # coded as a secondary diagnosis on a contact for another condition).
      # In LPR: A = primary (hoveddiagnose), B = secondary (bidiagnose),
      #         G = supplementary underlying condition (grundmorbus).
      dementia_event_primary = as.integer(!is.na(date_dementia_primary) & date_dementia_primary <= censor_date),   # 1 if first A-diagtype dementia contact before/on censor_date
      follow_up_days_primary = as.numeric(difftime(
        if_else(dementia_event_primary == 1L, date_dementia_primary, censor_date),
        surgery_date, units = "days"
      )),   # time to first A-diagtype dementia or censor

      # -----------------------------------------------------------------------
      # 4.5d.2 NEGATIVE CONTROL OUTCOME — CATARACT (sensitivity 7g.6)
      # -----------------------------------------------------------------------
      # Cataract (H25, H26) has no plausible causal pathway from bariatric
      # surgery. HR ≈ 1.0 supports that the main dementia result is not driven
      # by residual confounding or differential surveillance. Fracture was
      # considered and rejected as a negative control: RYGB causes calcium
      # malabsorption and increased fracture risk, making a non-null HR
      # uninterpretable as a bias indicator. See study1_methods_plan.txt 7g.6.
      cataract_event = as.integer(!is.na(date_cataract) & date_cataract <= censor_date),
      follow_up_days_cataract = as.numeric(difftime(
        if_else(cataract_event == 1L, date_cataract, censor_date),
        surgery_date, units = "days"
      )),

      # -----------------------------------------------------------------------
      # 4.5e-ii HIP/KNEE OSTEOARTHRITIS (secondary negative control)
      # -----------------------------------------------------------------------
      # M16 = coxarthrosis (hip); M17 = gonarthrosis (knee). No plausible BS
      # pathway via disease aetiology, but BS may reduce joint load via weight
      # loss — interpret cautiously if HR < 1. See 02 comment for full rationale.
      oa_event = as.integer(!is.na(date_oa) & date_oa <= censor_date),
      follow_up_days_oa = as.numeric(difftime(
        if_else(oa_event == 1L, date_oa, censor_date),
        surgery_date, units = "days"
      )),


      # -----------------------------------------------------------------------
      # 4.5e ALZHEIMER'S DISEASE OUTCOME (secondary)
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
      # 4.5f VASCULAR DEMENTIA OUTCOME (secondary)
      # -----------------------------------------------------------------------
      # date_vascular: first F01 (vascular dementia) contact after the index date.
      # Same independent extraction logic as Alzheimer's.
      vascular_event = as.integer(!is.na(date_vascular) & date_vascular <= censor_date),
      follow_up_days_vasc = as.numeric(difftime(
        if_else(vascular_event == 1L, date_vascular, censor_date),
        surgery_date, units = "days"
      )),


      # -----------------------------------------------------------------------
      # 4.5g SEX
      # -----------------------------------------------------------------------
      # In DST registers, sex is stored as KOEN (Danish: "køn" = gender/sex).
      # KOEN = 1 → Male, KOEN = 2 → Female (DST coding convention for BEF register).
      # The conversion KOEN → sex ("Male"/"Female") was done in
      # extract_demographics() in 02_extract_outcomes_covariates.R.
      # Here we make it a factor for Cox regression. Reference level: Male.
      sex = factor(sex, levels = c("Male", "Female")),


      # -----------------------------------------------------------------------
      # 4.5h AGE AT INDEX DATE
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
      # 4.5i CALENDAR PERIOD
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
      # 4.5j DIABETES TYPE
      # -----------------------------------------------------------------------
      # Classified from the Open Source Diabetes Classifier (OSDC), a pre-computed
      # cohort file at E:/workdata/708421/cleaned-data/.../dm_population_1977_2022.rds.
      # Covers diagnoses up to 2022; patients with diabetes onset 2023-2024 will be
      # classified as No_diabetes (minor limitation, see MINOR-3 in TODO.txt).
      # Reference level: No_diabetes. T1D and T2D are compared against this.
      diabetes_type = factor(diabetes_type, levels = c("No_diabetes", "T1D", "T2D")),


      # -----------------------------------------------------------------------
      # 4.5k SOCIOECONOMIC POSITION (SEP)
      # -----------------------------------------------------------------------
      # All SEP variables derived in 03_extract_ses.R following the SEPLINE
      # algorithm (Hjorth et al., Clin Epidemiol 2025;17:593–624).
      #   education_cat: from UDDA register (hfaudd = ISCED education code).
      #                  Short (<= upper secondary), Medium (further/vocational),
      #                  Long (university). Reference: Medium (most common).
      #                  Adjust reference level before modelling if needed.
      education_cat  = factor(education_cat,
                              levels = c("Medium", "Short", "Long", "Unknown")),   # Medium first = default reference level

      #   income_cat: from FAIK register (famaekvivadisp_13 = equivalised
      #               disposable household income). Population-standardised quintiles:
      #               3-year average (surgery_year-1, -2, -3) compared against
      #               Q20/Q40/Q60/Q80 cutpoints from the full BEF population,
      #               stratified by sex x 5-year age group x reference year (SEPLINE).
      income_cat     = factor(income_cat,
                              levels = c("Medium", "Low", "High", "Unknown")),     # Medium first = default reference level

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

# ============================================================================
# RUN — execute each block interactively, or source the whole file
# ============================================================================

df <- load_and_merge()                             # joins all extract_*.rds + ses_data.rds

# Attach emigration dates from VNDS (indud_kode == "U"; haend_dato = emigration date).
# Persons not in VNDS or with no "U" event get emigration_date = NA.
emigration <- get_emigration_dates(df$pnr)         # earliest emigration date per person; NA if none
df <- df %>% left_join(emigration, by = "pnr")     # non-emigrants get emigration_date = NA

df <- apply_exclusions(df)                         # removes any prevalent dementia not caught in step 1
df <- combine_icd_rx_flags(df)                     # adds hypertension_combined, dyslipidemia_combined
df <- compute_multimorbidity_count(df)             # adds nmi_count (integer) and nmi_cat (factor 0/1/2/3+)
# nmi_score (weighted Kristensen index) already in df from load_and_merge() via extract_nmi.rds
df <- format_variables(df)                         # factors, date diffs, age_cat, surgery_period, event indicators

print(table(df$cohort))                            # cohort sizes
print(table(df$cohort, df$dementia_event, useNA = "ifany"))   # dementia events by cohort

saveRDS(df, file.path(path_output, "study1_clean.rds"))        # save final analysis dataset
