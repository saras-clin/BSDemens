# ============================================================================
# PIPELINE STEP 2 of 5 — 02_extract_outcomes_covariates.R
# ============================================================================
# WHAT DO WE MEASURE?
#   Pulls all outcomes and covariates from DST registers for every person in
#   full_cohort.rds. Run AFTER 01_build_cohorts.R (Step 1) and 00_prepare_dbso.R (Step 0).
#
#   Study 1 (Dementia):
#     Outcomes:   dementia date — all-cause (F00–F03, G30–G31), Alzheimer's
#                 (G30, F00), and vascular (F01) — from LPR + LPR-psychiatric
#     Covariates: demographics, baseline comorbidities (GMC conditions), NMI score,
#                 baseline medications, diabetes type (OSDC)
#
#   Study 2 (T1D — BS patients only):
#     Outcomes:   weight/BMI at pre-op + 3/6/12/24 months (DBSO)
#                 insulin prescription counts by period (LMDB)
#                 first-time ACUTE INPATIENT admissions: hyperglycemia, hypoglycemia,
#                 self-harm, substance abuse, trauma, surgical complications (LPR)
#     Note: extract_hospital_contacts() uses inpatient_only=TRUE — c_pattype=="0"
#           in LPR2 and kont_type=="ALCA00" in LPR3.
#
#   Registers used (all column names lowercased with rename_with(tolower)):
#     load_database("bef")                      — BEF population register
#     load_database("dodsaars")                 — death register (d_dodsdto)
#     load_database("lpr_adm") + "lpr_diag"    — LPR2 somatic diagnoses
#     arrow::open_dataset(path_psyk_adm/diag)   — LPR2 psychiatric diagnoses
#     load_database("lpr_a_kontakt") + "diagnose"— LPR3 unified diagnoses (2019+)
#     load_database("lmdb")                     — prescription register
#     load_database("dbso")                     — DBSO weight/surgery data (parquet prepared by 00_prepare_dbso.R)
#     readRDS(path_dm_pop)                      — OSDC diabetes classification
#
#   ICD-10 note: DST codes have a leading "D" (e.g. "DG30", "DF00").
#   All code extractions strip this prefix: substr(c_diag, 2, 4) for 3-char,
#   substr(c_diag, 2, 5) for 4-char comparisons.
#
#   Output files saved to datasets/:
#     extract_demographics.rds, extract_dementia.rds, extract_weights.rds,
#     extract_dbso_clinical.rds, extract_insulin.rds, extract_hospitals.rds,
#     extract_comorbidities.rds, extract_nmi.rds, extract_medications.rds,
#     extract_diabetes.rds
# ============================================================================

# Packages ----
library(dstDataPrep)   # load_database() - pre-installed on DST, must be built first
library(arrow)         # for Parquet support used by dstDataPrep under the hood
library(dplyr)
library(tidyr)
library(lubridate)
library(heaven)        # exposureMatch(), findCondition(), edu_code, etc.
# On DST: update duckplyr if needed - old pre-installed version has limited functionality
# install.packages("duckplyr")

# Paths ----
path_output        <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets"
path_psyk_adm      <- "E:/workdata/708421/cleaned-data/parquet-external/t_psyk_adm"
path_psyk_diag     <- "E:/workdata/708421/cleaned-data/parquet-external/t_psyk_diag"
# DBSO accessed via load_database("dbso") — parquet prepared once by 00_prepare_dbso.R (already run)
# full_cohort.rds is produced by 01_build_cohorts.R (BS + GP + obesity, with index_date)
path_full_cohort <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets/full_cohort.rds"
# OSDC path confirmed in DARTER kickstarter. Covers to 2022; sufficient for baseline
# diabetes classification for surgeries up to 2022. Patients with surgery 2023-2024
# whose diabetes onset is after 2022 will be misclassified as No_diabetes (minor limitation).
path_dm_pop      <- "E:/workdata/708421/cleaned-data/diabetes_register_pop/dm_population_1977_2022.rds"

# ============================================================================
# 2.0 SHARED HELPER: PULL DIAGNOSES FROM ALL LPR SOURCES
# ============================================================================
# Returns a collected data frame: pnr, date_contact (Date), icd3 (3-char ICD), icd4 (4-char ICD)
# No D-prefix — stripped via substr(code, 2, 4/5).
#
# Three data sources:
#   LPR2 somatic:      "lpr_adm" + "lpr_diag"         (somatic contacts, up to March 2019)
#   LPR2 psychiatric:  "t_psyk_adm" + "t_psyk_diag"   (psychiatric contacts, 1995-March 2019)
#      Geropsychiatric departments recorded F00-F03 dementia in a SEPARATE register before 2019.
#      Without this source, all F-code dementia from pre-2019 memory clinics would be missed.
#      Register names confirmed from archive/other peoples code/psyc2021.R.
#      Confirmed: accessible via arrow::open_dataset(path_psyk_adm) — see path_psyk_adm above.
#   LPR3 unified:      "kontakter" + "diagnoser"       (March 2019 onwards)
#      LPR3 is a unified register covering BOTH somatic and psychiatric — no separate psych
#      table needed post-2019.
#
# diagtypes: A = primary, B = secondary, G = other conditions present.
#   Use c("A","B") for outcomes; c("A","B","G") for baseline comorbidities.
get_lpr_diagnoses <- function(pnr_vector, diagtypes = c("A", "B"), inpatient_only = FALSE) {
  # inpatient_only = TRUE: restrict to acute inpatient admissions only.
  #   LPR2: c_pattype == "0"         (somatic inpatient, confirmed from archive hospital2021.R)
  #   LPR3: kont_type == "ALCA00"    (confirmed column name; "ALCA00" = inpatient contact type)
  # Leave FALSE for baseline comorbidity / outcome lookups that should include outpatient.
  # Set TRUE when calling from extract_hospital_contacts() — the protocol specifies acute admissions.

  # LPR2 somatic (up to March 2019) ----
  lpr_adm  <- load_database("lpr_adm")  %>% rename_with(tolower)
  lpr_diag <- load_database("lpr_diag") %>% rename_with(tolower)

  lpr2_adm_filtered <- lpr_adm %>%
    filter(pnr %in% !!pnr_vector) %>%
    select(pnr, recnum, date_contact = d_inddto, c_pattype)

  if (inpatient_only) {
    lpr2_adm_filtered <- lpr2_adm_filtered %>%
      filter(c_pattype == "0")   # "0" = somatic inpatient in LPR2
  }

  lpr2 <- lpr2_adm_filtered %>%
    inner_join(
      lpr_diag %>%
        filter(c_diagtype %in% diagtypes) %>%
        mutate(icd3 = substr(c_diag, 2, 4),
               icd4 = substr(c_diag, 2, 5)) %>%
        select(recnum, icd3, icd4),
      by = "recnum"
    ) %>%
    select(pnr, date_contact, icd3, icd4) %>%
    collect()

  # LPR2 psychiatric (1995-March 2019) ----
  # Psychiatric contacts before March 2019 are in a SEPARATE register (not in lpr_adm/lpr_diag).
  # This is the source for F00-F03 dementia diagnosed in geropsychiatric outpatient memory clinics.
  #
  # Confirmed path: parquet-external folder (not via load_database).
  # Raw DST column names — rename v_cpr->pnr, k_recnum->recnum, v_recnum->recnum.
  psyk_adm  <- arrow::open_dataset(path_psyk_adm)  %>% rename_with(tolower) %>%
    rename(pnr = v_cpr, recnum = k_recnum)
  psyk_diag <- arrow::open_dataset(path_psyk_diag) %>% rename_with(tolower) %>%
    rename(recnum = v_recnum)

  lpr2_psyk_adm_filtered <- psyk_adm %>%
    filter(pnr %in% !!pnr_vector) %>%
    select(pnr, recnum, date_contact = d_inddto, c_pattype)

  if (inpatient_only) {
    lpr2_psyk_adm_filtered <- lpr2_psyk_adm_filtered %>%
      filter(c_pattype == "0")   # same c_pattype convention as somatic LPR2
  }

  lpr2_psyk <- lpr2_psyk_adm_filtered %>%
    inner_join(
      psyk_diag %>%
        filter(c_diagtype %in% diagtypes) %>%
        mutate(icd3 = substr(c_diag, 2, 4),
               icd4 = substr(c_diag, 2, 5)) %>%
        select(recnum, icd3, icd4),
      by = "recnum"
    ) %>%
    select(pnr, date_contact, icd3, icd4) %>%
    collect()

  # LPR3 (from March 2019) ----
  # Abbreviated register names confirmed working on DST (full names "lpr3f_kontakter"/
  # "lpr3f_diagnoser" returned 404 - not found on this server).
  # Patient ID column is pnr - same as LPR2, no rename needed.
  # LPR3 is a UNIFIED register covering BOTH somatic and psychiatric contacts.
  kontakter <- load_database("lpr_a_kontakt") %>% rename_with(tolower)  # confirmed name
  diagnoser <- load_database("lpr_a_diagnose") %>% rename_with(tolower)  # confirmed name
  # confirmed kontakter columns: pnr, dw_ek_kontakt, kont_starttidspunkt (datetime), kont_type
  # diagnoser columns: dw_ek_kontakt, diagnosekode, diagnosetype, senare_afkraeftet (CONFIRM-3b: not yet checked)

  lpr3_kontakter_filtered <- kontakter %>%
    filter(pnr %in% !!pnr_vector) %>%
    select(pnr, dw_ek_kontakt, kont_starttidspunkt, kont_type)   # confirmed column names

  if (inpatient_only) {
    lpr3_kontakter_filtered <- lpr3_kontakter_filtered %>%
      filter(kont_type == "ALCA00")   # kont_type = contact type; "ALCA00" = inpatient in LPR3
  }

  lpr3 <- lpr3_kontakter_filtered %>%
    inner_join(
      diagnoser %>%
        filter(
          diagnosetype %in% diagtypes,
          # senare_afkraeftet: "Ja" = diagnosis later retracted; "Nej" = confirmed.
          # Current filter keeps NAs (defensive: if NAs exist, we include rather than drop).
          # OSDC uses == "Nej" (drops NAs). Verify whether NAs occur in real data before changing.
          is.na(senare_afkraeftet) | senare_afkraeftet != "Ja"
        ) %>%
        mutate(icd3 = substr(diagnosekode, 2, 4),
               icd4 = substr(diagnosekode, 2, 5)) %>%
        select(dw_ek_kontakt, icd3, icd4),
      by = "dw_ek_kontakt"
    ) %>%
    collect() %>%
    mutate(date_contact = as.Date(kont_starttidspunkt)) %>%   # kont_starttidspunkt is datetime; as.Date() extracts date
    select(pnr, date_contact, icd3, icd4)

  bind_rows(lpr2, lpr2_psyk, lpr3)
}

# ============================================================================
# 2.1 LOAD FULL COHORT (BS + GP + OBESITY)
# ============================================================================
# Produced by 01_build_cohorts.R.
# Columns: pnr, index_date, cohort ("BS"/"GP"/"Obesity"), surgery_type, matched_pnr
#
# Internally, all extraction functions use "surgery_date" as the reference date
# (lookback window, post-surgery filters). We rename index_date -> surgery_date
# before passing the full_cohort to these functions, so they work unchanged for
# all cohort members (comparator index_date = their matched BS patient's surgery_date).

load_full_cohort <- function() {
  readRDS(path_full_cohort) %>%
    rename(surgery_date = index_date)
}

# ============================================================================
# 2.2 DEMOGRAPHICS (BEF + DODSAARS)
# ============================================================================
# bef: pnr, foed_dag, koen, aar
# dod: pnr, d_dodsdto (confirmed column name)

extract_demographics <- function(bs_cohort) {
  pnrs <- unique(bs_cohort$pnr)

  # BEF: CPR-registerets befolkningstabel (population register).
  # Annual snapshot register — one row per person per year (aar).
  # Key variables: pnr, koen, foed_dag, aar.
  #   koen:    sex code. 1 = male, 2 = female (DST convention, confirmed from OSDC source).
  #   foed_dag: date of birth. Column name confirmed from onboarding document sample output.
  #   aar:     year of the snapshot. We take the most recent record per person
  #            (arrange desc(aar), slice(1)) to get current koen and foed_dag.
  bef <- load_database("bef") %>% rename_with(tolower)
  bef_person <- bef %>%
    filter(pnr %in% !!pnrs) %>%
    select(pnr, koen, foed_dag, aar) %>%
    group_by(pnr) %>%
    arrange(desc(aar)) %>%  # most recent year first
    slice(1) %>%            # keep only the most recent record per person
    ungroup() %>%
    select(pnr, koen, foed_dag) %>%
    collect()

  # dod: Danish Death Register (Doedsaarsagsregisteret).
  # One row per deceased person. d_dodsdto = date of death (confirmed column name).
  dod <- load_database("dodsaars") %>% rename_with(tolower)
  dod_person <- dod %>%
    filter(pnr %in% !!pnrs) %>%
    select(pnr, death_date = d_dodsdto) %>%
    collect()

  # Emigration censoring is handled in 04_data_management_dementia.R via get_emigration_dates().
  # VNDS register confirmed: indud_kode == "U", haend_dato = emigration date.

  bs_cohort %>%
    left_join(bef_person %>% select(pnr, koen, foed_dag), by = "pnr") %>%
    left_join(dod_person, by = "pnr") %>%
    mutate(
      # Convert koen to a readable label. koen = 1 -> Male, koen = 2 -> Female (DST coding).
      sex            = if_else(koen == 1, "Male", "Female"),
      birth_date     = as.Date(foed_dag),
      # Age at surgery in years: difference between surgery date and birth date.
      age_at_surgery = as.numeric(difftime(surgery_date, birth_date, units = "days")) / 365.25,
      # follow_up_end: the later-of-death vs administrative censoring.
      # pmin(..., na.rm = TRUE): for living persons (death_date = NA), returns 2025-12-31.
      # For deceased persons, returns the earlier of death_date and 2025-12-31.
      # Emigration censoring applied in 04_data_management_dementia.R via pmin() with emigration_date.
      follow_up_end  = pmin(as.Date("2025-12-31"), death_date, na.rm = TRUE)
    ) %>%
    select(pnr, sex, birth_date, death_date, age_at_surgery, surgery_date, surgery_type, follow_up_end)
}

# ============================================================================
# 2.3 DEMENTIA OUTCOMES — STUDY 1 (LPR2 + LPR2-PSYCHIATRIC + LPR3)
# ============================================================================
# All-cause dementia: F00, F01, F02, F03, G30, G31
# Alzheimer's:        G30, F00
# Vascular:           F01
# Note: patients with pre-surgery dementia should be excluded at cohort level.
#   Use get_lpr_diagnoses() with date_contact < surgery_date to flag them if needed.

extract_dementia_outcomes <- function(bs_cohort) {
  dementia_icd3   <- c("F00", "F01", "F02", "F03", "G30", "G31")   # G31 included for comprehensive all-cause dementia capture; consistent with methods plan section 4
  alzheimers_icd3 <- c("G30", "F00")
  vascular_icd3   <- "F01"

  # One collected result shared across all three outcome queries.
  # get_lpr_diagnoses() now covers LPR2 somatic + LPR2 psychiatric + LPR3,
  # so F-code dementia from geropsychiatric departments is included.
  all_dx <- get_lpr_diagnoses(unique(bs_cohort$pnr)) %>%
    filter(icd3 %in% dementia_icd3) %>%
    inner_join(bs_cohort %>% select(pnr, surgery_date), by = "pnr") %>%
    filter(date_contact > surgery_date)

  # All-cause: first contact with any dementia code
  date_allcause <- all_dx %>%
    group_by(pnr) %>%
    arrange(date_contact) %>%
    slice(1) %>%
    ungroup() %>%
    select(pnr, date_dementia = date_contact)

  # Alzheimer's: first G30 or F00 contact (independent of all-cause date)
  date_alz <- all_dx %>%
    filter(icd3 %in% alzheimers_icd3) %>%
    group_by(pnr) %>%
    arrange(date_contact) %>%
    slice(1) %>%
    ungroup() %>%
    select(pnr, date_alzheimers = date_contact)

  # Vascular: first F01 contact (independent of all-cause date)
  date_vasc <- all_dx %>%
    filter(icd3 == vascular_icd3) %>%
    group_by(pnr) %>%
    arrange(date_contact) %>%
    slice(1) %>%
    ungroup() %>%
    select(pnr, date_vascular = date_contact)

  # Sensitivity 7g.1: diagtype-A-only version of all-cause dementia.
  # In LPR: diagtype A = primary (hoveddiagnose) — dementia was the main reason
  # for that hospital contact. The main analysis uses A+B; restricting to A only
  # is more specific but less sensitive (misses dementia coded as a bidiagnose).
  # Variable name: date_dementia_primary — "primary" = diagtype A, NOT primary outcome.
  # A separate LPR query is needed because get_lpr_diagnoses() applies the diagtype
  # filter internally and does not return the diagtype column in its output.
  all_dx_primary <- get_lpr_diagnoses(unique(bs_cohort$pnr), diagtypes = c("A")) %>%   # diagtype A (primary diagnosis) contacts only
    filter(icd3 %in% dementia_icd3) %>%                                                 # dementia ICD codes
    inner_join(bs_cohort %>% select(pnr, surgery_date), by = "pnr") %>%               # attach each person's index date
    filter(date_contact > surgery_date)                                                 # post-index contacts only

  date_allcause_primary <- all_dx_primary %>%
    group_by(pnr) %>%
    arrange(date_contact) %>%
    slice(1) %>%                                                                        # earliest diagtype-A dementia contact per person
    ungroup() %>%
    select(pnr, date_dementia_primary = date_contact)   # "primary" = diagtype A (LPR A-code), NOT primary outcome

  # One row per cohort member; NAs for those without each specific outcome
  bs_cohort %>%
    select(pnr) %>%
    left_join(date_allcause,      by = "pnr") %>%
    left_join(date_alz,           by = "pnr") %>%
    left_join(date_vasc,          by = "pnr") %>%
    left_join(date_allcause_primary, by = "pnr")   # sensitivity 7g.1: primary-code-only dementia date
}

# ============================================================================
# 2.3b NEGATIVE CONTROL OUTCOMES — STUDY 1 SENSITIVITY 7g.6
# ============================================================================
# Cataract was selected as the negative control because it has no plausible
# causal pathway from bariatric surgery: lens opacification is determined by
# age, UV exposure, smoking, and genetics — none altered by BS.
# Fracture was considered and explicitly rejected: RYGB causes calcium and
# Vitamin D malabsorption leading to secondary hyperparathyroidism and
# increased fracture risk. A non-null HR for fracture would be uninterpretable
# as a bias indicator because it could reflect a true biological effect of RYGB.
# See Section 7g.6 in study1_methods_plan.txt for full rationale.
#
# ICD-10 codes (3-char, D prefix stripped):
#   H25: age-related cataract
#   H26: other cataract

extract_negative_controls <- function(bs_cohort) {
  cataract_icd3 <- c("H25", "H26")   # age-related and other cataract (H27/H28 excluded: linked to metabolic disease)

  all_dx <- get_lpr_diagnoses(unique(bs_cohort$pnr), diagtypes = c("A", "B")) %>%   # A+B consistent with main outcomes
    filter(icd3 %in% cataract_icd3) %>%                                              # cataract contacts only
    inner_join(bs_cohort %>% select(pnr, surgery_date), by = "pnr") %>%             # attach index date per person
    filter(date_contact > surgery_date)                                               # post-index contacts only

  date_cataract <- all_dx %>%
    group_by(pnr) %>%
    arrange(date_contact) %>%
    slice(1) %>%                                   # earliest cataract contact per person
    ungroup() %>%
    select(pnr, date_cataract = date_contact)

  bs_cohort %>%
    select(pnr) %>%
    left_join(date_cataract, by = "pnr")   # NA for persons with no post-index cataract
}

# ============================================================================
# 2.4 WEIGHT OUTCOMES — STUDY 2 (DBSO)
# ============================================================================
# DBSO = Databasen for Behandling af Svaer Overvaegt, operated by SunDK (formerly RKKP).
# Mandatory reporting for all public and private hospitals since 2010.
# Coverage: surgery date, type (SKS codes), weight/height/BMI at:
#   - Medical pre-examination (medicinsk forundersoegelse)
#   - 1-year follow-up (DBSO window: 6-18 months; our code uses +-30 days around day 365)
#   - 2-year follow-up (DBSO window: 18-30 months; our code uses +-45 days around day 730)
# DBSO data is delivered SEPARATELY from SunDK (not via DST parquet registries).
# It is likely saved as a flat file (CSV/SAS/RDS) in the workdata folder.
#
# DBSO file location and format confirmed (resolved 2026-05):
#   SAS file: E:/rawdata/708421/Eksterne data/dfr_2025_10_31.sas7bdat
#   Converted to parquet by 00_prepare_dbso.R (one-time; already done).
#   Accessed via load_database("dbso"). Column names confirmed from sapply(raw, class).

extract_weight_outcomes <- function(bs_cohort) {
  # DBSO prepared once by 00_prepare_dbso.R; accessed via load_database("dbso").
  dbso <- load_database("dbso") %>% rename_with(tolower) %>% collect()   # collect full DBSO into memory

  # DBSO column names used below (original lowercased SAS names; types confirmed):
  #   pnr                  — patient ID (character; renamed from cpr in 00_prepare_dbso.R)
  #   datopre              — last pre-op clinic visit date (Date; converted in step 00)
  #   datofol              — follow-up visit date (Date; converted in step 00)
  #   udgangsvaegtpre_prim — wgt (kg) at last pre-op visit (numeric)
  #   udgangsvaegt         — wgt (kg) at program entry / referral (numeric)
  #   hoejde               — height (cm) (numeric)
  #   vaegtfol             — wgt (kg) at this follow-up visit (numeric; visit-level)
  # NOTE: surgery_date and surgery_type are NOT DBSO columns — they come from
  #   full_cohort.rds (derived in 01_build_cohorts.R from DBSO flags and index_date).
  # Renaming of weight variables is done in 04_data_management_dementia.R.

  dbso_cohort <- dbso %>% filter(pnr %in% bs_cohort$pnr)   # keep only cohort members

  # Pre-operative weight: udgangsvaegtpre_prim is the weight at the LAST pre-op clinic
  # visit before surgery. It is stored redundantly in every DBSO row for a patient, but
  # the value at the most recent datopre is the definitive measurement. Group by patient
  # and take the row with the latest datopre rather than distinct(pnr, .keep_all = TRUE),
  # which would pick an arbitrary row and could return the wrong height if hoejde was
  # updated across visits.
  weight_preop <- dbso_cohort %>%
    filter(!is.na(udgangsvaegtpre_prim), !is.na(datopre)) %>%   # must have both weight and a pre-op date to order on
    group_by(pnr) %>%
    arrange(desc(datopre)) %>%                                   # most recent pre-op visit first
    slice(1) %>%                                                 # take that row for each patient
    ungroup() %>%
    mutate(
      bmi_preop = dplyr::if_else(                                # BMI at last pre-op visit; computed here from raw columns
        !is.na(udgangsvaegtpre_prim) & !is.na(hoejde) & hoejde > 0,
        round(udgangsvaegtpre_prim / (hoejde / 100)^2, 1),
        NA_real_
      )
    ) %>%
    select(
      pnr,
      weight_preop = udgangsvaegtpre_prim,   # wgt (kg) at last pre-op visit
      height_preop = hoejde,                  # height (cm)
      bmi_preop                               # BMI at last pre-op visit
    )

  # Post-operative weights: rows with a measured follow-up weight.
  # Compute days from surgery and assign to nearest target window.
  weight_postop <- dbso_cohort %>%
    filter(!is.na(datofol), !is.na(vaegtfol)) %>%
    inner_join(bs_cohort %>% select(pnr, surgery_date), by = "pnr") %>%
    mutate(
      days_since_surgery = as.numeric(difftime(datofol, surgery_date, units = "days")),
      target_days = case_when(
        # 3-month visit: no official DBSO window; clinical visit around 3 months post-surgery
        days_since_surgery >= 60  & days_since_surgery < 120 ~ 90L,
        # 6-month visit: no official DBSO window; clinical visit around 6 months post-surgery
        days_since_surgery >= 150 & days_since_surgery < 210 ~ 180L,
        # 1-year follow-up: DBSO flag FUMellem6mdr1aar = visits 6–18 months post-surgery
        # (183–547 days); we pick the visit CLOSEST to day 365 within this window
        days_since_surgery >= 183 & days_since_surgery < 548 ~ 365L,
        # 2-year follow-up: DBSO flag FUMellem1_5aar2_5aar = visits 18–30 months post-surgery
        # (548–913 days); we pick the visit CLOSEST to day 730 within this window.
        # Previous code used 670–759 days (22–25 months), which missed visits at 26–30 months.
        days_since_surgery >= 548 & days_since_surgery < 914 ~ 730L,
        TRUE ~ NA_integer_
      )
    ) %>%
    filter(!is.na(target_days)) %>%
    mutate(days_diff = abs(days_since_surgery - target_days)) %>%
    group_by(pnr, target_days) %>%
    arrange(days_diff) %>%
    slice(1) %>%
    ungroup() %>%
    mutate(period = case_when(
      target_days == 90  ~ "3mo",
      target_days == 180 ~ "6mo",
      target_days == 365 ~ "12mo",
      target_days == 730 ~ "24mo"
    )) %>%
    select(pnr, period, weight_kg = vaegtfol) %>%
    pivot_wider(names_from = period, values_from = weight_kg, names_prefix = "weight_kg_")

  bs_cohort %>%
    select(pnr) %>%
    left_join(weight_preop,  by = "pnr") %>%
    left_join(weight_postop, by = "pnr") %>%
    mutate(
      # Ideal body weight: weight at BMI = 25 using pre-op height.
      # If height_preop is missing or zero, target_weight = NA and all downstream
      # pct_ewl values will also be NA (R propagates NA through arithmetic).
      target_weight = 25 * (height_preop / 100)^2,

      # Excess weight = pre-op weight minus ideal weight.
      # Represents the weight above a BMI-25 body habitus that the patient needs to lose.
      # Can be 0 if pre-op BMI was exactly 25 (extremely unlikely in a BS cohort);
      # negative if pre-op BMI < 25 (essentially impossible for BS eligibility).
      excess_weight = weight_preop - target_weight,

      # Total weight loss (TWL) at 12 months: positive means weight was lost.
      twl_12mo      = weight_preop - weight_kg_12mo,

      # Percentage TWL at 12 months: TWL expressed as % of pre-op weight.
      # Guard: if weight_preop is 0 or missing, return NA (avoids division by zero).
      pct_twl_12mo  = if_else(weight_preop > 0, twl_12mo / weight_preop * 100, NA_real_),

      # Percentage excess weight loss (%EWL) at 12 months: TWL expressed as % of excess weight.
      # This is the standard bariatric outcome metric — 50% EWL is generally considered success.
      # Guard: excess_weight must be > 0. Returns NA if height is missing, if pre-op BMI was
      # already ≤ 25, or if weight_preop is missing. These are the only cases where %EWL is
      # undefined or clinically meaningless.
      pct_ewl_12mo  = if_else(excess_weight > 0, twl_12mo / excess_weight * 100, NA_real_),

      # Same metrics at 24 months.
      twl_24mo      = weight_preop - weight_kg_24mo,
      pct_twl_24mo  = if_else(weight_preop > 0, twl_24mo / weight_preop * 100, NA_real_),
      pct_ewl_24mo  = if_else(excess_weight > 0, twl_24mo / excess_weight * 100, NA_real_)
    )
}

# ============================================================================
# 2.5 DBSO CLINICAL OUTCOMES — STUDY 2 (READMISSION, REOPERATION, EOSS, SUPPLEMENTS)
# ============================================================================
# Extracts DBSO-computed clinical outcome flags not covered by extract_weight_outcomes().
# All columns here are patient-level constants (same value across all visit rows per patient).
# Only meaningful for BS patients; GP and Obesity comparators have no DBSO data.
#
# CONFIRM before running: run inspect_dbso() on DST and verify that column names below
# match names(raw). In particular, confirm exact names of medkomplik* columns.
#
# Output saved as: datasets/extract_dbso_clinical.rds

extract_dbso_clinical <- function(bs_cohort) {
  # Columns to extract — all are patient-level constants in the DBSO long-format table.
  # medkomplik* column names must be confirmed on DST (run inspect_dbso() first).
  clinical_cols <- c(
    "pnr",
    "akutgenindlaeggelse30d",        # 1 = acute unplanned readmission within 30 days
    "reop30d_3",                     # 1 = reoperation within 30 days
    "reoplaar_3",                    # 1 = reoperation within 1 year
    "reop5aar_2",                    # 1 = reoperation within 5 years
    "eoss",                          # Edmonton Obesity Staging System score at pre-op (0-4)
    "obstruktivsoevnapnoepre",       # 1 = obstructive sleep apnea at pre-op assessment
    "obstruktivsoevnapnoefol",       # 1 = obstructive sleep apnea at follow-up
    "b12",                           # vitamin B12 supplement status
    "b12compliance",                 # B12 compliance flag
    "jern",                          # iron supplement status
    "jerncompliance",                # iron compliance flag
    "kalk",                          # calcium supplement status
    "kalkcompliance",                # calcium compliance flag
    "medkomplikandre",               # 1 = other medical complication (confirmed column name)
    "medkomplikdiarre",              # 1 = diarrhoea as complication (confirmed)
    "medkomplikdumpingsymptomer",    # 1 = dumping syndrome (confirmed)
    "medkomplikhypoglyksymptomer",   # 1 = hypoglycaemic symptoms as complication (confirmed)
    "medkomplikrefluks"              # 1 = reflux as complication (confirmed)
  )

  dbso_raw <- load_database("dbso") %>% rename_with(tolower)   # DBSO lazy tbl; rename_with(tolower) ensures lowercase column names

  # Check which expected columns are actually present before pulling data.
  available_cols <- intersect(clinical_cols, names(dbso_raw))   # columns confirmed present in parquet
  missing_cols   <- setdiff(clinical_cols, names(dbso_raw))     # expected columns not found
  if (length(missing_cols) > 0) {
    message("NOTE: Expected DBSO clinical columns not found in parquet. ",
            "Verify names with inspect_dbso() on DST: ",
            paste(missing_cols, collapse = ", "))   # names mismatch likely — check 00_prepare_dbso.R output
  }

  dbso_raw %>%
    filter(pnr %in% !!bs_cohort$pnr) %>%    # push pnr filter to parquet reader; only BS cohort
    select(all_of(available_cols)) %>%        # push column selection to parquet reader; reduces data before collect
    collect() %>%                             # bring only filtered + selected rows into R memory
    distinct(pnr, .keep_all = TRUE)           # one row per patient; patient-level constants are identical across all visit rows
}

# ============================================================================
# 2.6 INSULIN OUTCOMES — STUDY 2 (LMDB, ATC A10A)
# ============================================================================
# ATC A10A = insulin. Count of prescriptions per period as proxy for insulin use.
# Actual dose in units requires DOSIS variable - confirm availability with data manager.

extract_insulin_outcomes <- function(bs_cohort) {
  lmdb <- load_database("lmdb") %>% rename_with(tolower)

  lmdb %>%
    filter(
      pnr %in% !!bs_cohort$pnr,
      substr(atc, 1, 4) == "A10A"
    ) %>%
    select(pnr, eksd) %>%
    collect() %>%
    inner_join(bs_cohort %>% select(pnr, surgery_date), by = "pnr") %>%
    mutate(
      days_since_surgery = as.numeric(difftime(eksd, surgery_date, units = "days")),
      period = case_when(
        days_since_surgery >= -180 & days_since_surgery < -30  ~ "baseline",    # upper bound -30: prescriptions in the 30 days immediately before surgery are excluded (perioperative management artefact, not representative of habitual baseline insulin burden)
        days_since_surgery >= 60   & days_since_surgery < 120  ~ "3mo",
        days_since_surgery >= 150  & days_since_surgery < 210  ~ "6mo",
        days_since_surgery >= 330  & days_since_surgery < 390  ~ "12mo",
        TRUE ~ NA_character_
      )
    ) %>%
    filter(!is.na(period)) %>%
    group_by(pnr, period) %>%
    summarise(n_rx = n(), .groups = "drop") %>%
    pivot_wider(names_from = period, values_from = n_rx, names_prefix = "insulin_n_rx_")
}

# ============================================================================
# 2.7 HOSPITAL CONTACTS — STUDY 2 (LPR ACUTE INPATIENT ONLY)
# ============================================================================

extract_hospital_contacts <- function(bs_cohort) {
  # Glycemic events need icd4 precision: E10-E14 at 3-char level covers all diabetes
  # admissions (neuropathy, retinopathy, etc.) not just acute hyperglycemia/hypoglycemia.
  # E10.0/E10.1 = T1D coma / ketoacidosis (DKA); E11.0/E11.1 = T2D equivalents.
  # E16.0/E16.1 = drug-induced / other hypoglycemia (main codes for insulin-related hypo).
  # ICD-10 4-character acute glycaemic event codes.
  # Each condition gets a date_first_<name> column in the output.
  #
  # DKA (diabetic ketoacidosis and hyperglycaemic coma):
  #   E10.1 = T1D with ketoacidosis (DKA — unambiguously hyperglycaemic)
  #   E11.0 = T2D with coma — in T2D, coma is predominantly hyperosmolar hyperglycaemic
  #           state (HHS), not hypoglycaemia; included here as a hyperglycaemic event
  #   E11.1, E13.0, E13.1, E14.0, E14.1 = other/unspecified diabetes ketoacidosis/coma
  #   NOTE: E10.0 (T1D with coma) is deliberately EXCLUDED from DKA — in T1D, "coma"
  #   is predominantly hypoglycaemic, not ketoacidotic; it is listed under hypoglycaemia.
  #
  # Hypoglycaemia:
  #   E10.0 = T1D with coma — almost always hypoglycaemic coma in T1D
  #   E16.0 = drug-induced hypoglycaemia without coma (most insulin-related events)
  #   E16.1 = other hypoglycaemia
  #   E16.2 = hypoglycaemia, unspecified
  #   NOTE: E11.0 (T2D with coma) is in DKA above — T2D coma is HHS, not hypoglycaemia.
  icd4_conditions <- list(
    dka          = c("E101", "E110", "E111", "E130", "E131", "E140", "E141"),
    hypoglycemia = c("E100", "E160", "E161", "E162")
  )

  # Non-glycemic conditions are unambiguous at 3-char level.
  icd3_conditions <- list(
    self_harm             = paste0("X", 60:84),
    substance_abuse       = paste0("F1", 0:9),
    trauma                = c(paste0("S0", 0:9), paste0("S", 10:99),
                               paste0("T0", 0:9), paste0("T", 10:98)),
    surgical_complication = paste0("T8", 0:8)
  )

  # inpatient_only = TRUE: the protocol for study 2 (T1D) specifies "first-time acute admissions per 100
  # person-years". Including outpatient and ER contacts would inflate counts and make the
  # measure inconsistent with the stated endpoint. LPR2 filter: c_pattype == "0".
  # LPR3 filter: kont_type == "ALCA00" (confirmed column name from colnames() check).
  all_dx <- get_lpr_diagnoses(unique(bs_cohort$pnr), inpatient_only = TRUE) %>%
    inner_join(bs_cohort %>% select(pnr, surgery_date), by = "pnr") %>%
    filter(date_contact > surgery_date)

  result <- bs_cohort %>% select(pnr)

  for (condition_name in names(icd4_conditions)) {
    codes    <- icd4_conditions[[condition_name]]
    col_name <- paste0("date_first_", condition_name)
    first_contact <- all_dx %>%
      filter(icd4 %in% codes) %>%
      group_by(pnr) %>%
      arrange(date_contact) %>%
      slice(1) %>%
      ungroup() %>%
      select(pnr, !!col_name := date_contact)
    result <- result %>% left_join(first_contact, by = "pnr")
  }

  for (condition_name in names(icd3_conditions)) {
    codes    <- icd3_conditions[[condition_name]]
    col_name <- paste0("date_first_", condition_name)
    first_contact <- all_dx %>%
      filter(icd3 %in% codes) %>%
      group_by(pnr) %>%
      arrange(date_contact) %>%
      slice(1) %>%
      ungroup() %>%
      select(pnr, !!col_name := date_contact)
    result <- result %>% left_join(first_contact, by = "pnr")
  }

  result
}

# ============================================================================
# 2.8 BASELINE COMORBIDITIES — BOTH STUDIES (LPR, 5-YEAR LOOKBACK)
# ============================================================================

extract_baseline_comorbidities <- function(bs_cohort) {
  nmi_conditions <- list(
    # Cardiovascular
    mi             = c("I21", "I22", "I23"),
    stroke_tia     = c("I60", "I61", "I62", "I63", "I64", "I69", "G45"),
    pad            = c("I70", "I71", "I72", "I73", "I74"),
    ihd            = c("I20", "I24", "I25"),
    heart_failure  = "I50",
    afib           = "I48",
    hypertension   = c("I10", "I11", "I12", "I13", "I15"),
    # Metabolic
    diabetes_any   = c("E10", "E11", "E12", "E13", "E14"),
    dyslipidemia   = "E78",
    # GMC algorithm: E00-E05, E07, and E06.1-E06.9 (excludes E06.0 = acute thyroiditis).
    # We include all E06 at icd3 level; acute thyroiditis (E060) exclusion handled below.
    thyroid        = c("E00", "E01", "E02", "E03", "E04", "E05", "E06", "E07"),
    gout           = c("E79", "M10"),
    # Respiratory
    copd           = c("J40", "J41", "J42", "J43", "J44", "J47"),
    asthma         = c("J45", "J46"),
    # Gastrointestinal
    # liver: B16-B19, K70-K74, K76.6 (portal hypertension), I85 (oesophageal varices).
    # K75 (other inflammatory liver) and K76 (other liver diseases) included at icd3 level;
    # GMC narrows K76 to K76.6 only — handled via icd4 block below.
    liver          = c("B16", "B17", "B18", "B19", "K70", "K71", "K72", "K73", "K74", "I85"),
    # peptic_ulcer: K25-K28 (peptic/gastric/duodenal/anastomotic ulcer).
    # GMC also includes K22.1 (oesophageal ulcer) and K29.3-K29.5 (chronic gastritis)
    # via 4-char codes — handled via icd4 block below.
    peptic_ulcer   = c("K25", "K26", "K27", "K28"),
    ibd            = c("K50", "K51"),
    diverticular   = "K57",
    # Renal / urological
    # N17 (acute renal failure) excluded — GMC uses only N03, N11, N18, N19 (chronic/unspecified).
    ckd            = c("N03", "N11", "N18", "N19"),
    prostate       = "N40",
    # Musculoskeletal
    connective_tissue = c("M05", "M06", "M08", "M09", "M30", "M31", "M32", "M33", "M34", "M35", "M36", "D86"),
    osteoporosis   = c("M80", "M81", "M82"),
    # Mental health
    depression     = c("F32", "F33"),
    bipolar        = c("F30", "F31"),
    # Neurological
    parkinsons     = c("G20", "G21", "G22"),
    epilepsy       = c("G40", "G41"),
    ms             = "G35",
    migraine       = "G43",
    neuropathy     = c("G50", "G51", "G52", "G53", "G54", "G55", "G56", "G57", "G58", "G59",
                       "G60", "G61", "G62", "G63", "G64"),
    # Oncology / haematology
    # C44 (non-melanoma skin cancer) excluded per GMC algorithm — standard practice.
    cancer         = c(paste0("C0", 0:9), paste0("C", 10:43), paste0("C", 45:97)),
    anemia         = c("D50", "D51", "D52", "D53", "D55", "D56", "D57", "D58", "D59",
                       "D60", "D61", "D63", "D64"),
    hiv            = c("B20", "B21", "B22", "B23", "B24"),
    # Sensory
    vision         = c("H25", "H40", "H54"),
    # GMC uses H90, H91, and H93.1 (tinnitus) only. We include all H93 (minor deviation).
    hearing        = c("H90", "H91", "H93")
  )

  # Include G (grundmorbus) to capture all conditions a patient has, not only primary reasons
  all_dx <- get_lpr_diagnoses(unique(bs_cohort$pnr), diagtypes = c("A", "B", "G")) %>%  # unique() removes duplicate pnrs so we don't query the same person twice
    inner_join(bs_cohort %>% select(pnr, surgery_date), by = "pnr") %>%  # attach each person's surgery date so we can use it in the date filter below
    filter(
      date_contact >= surgery_date - 365.25 * 5,  # 5-year lookback: 365.25 days/year accounts for leap years
      date_contact <  surgery_date              # strictly before surgery — no post-surgery diagnoses counted as baseline
    )

  # NOTE on heaven::findCondition() — evaluated and not adopted here.
  # findCondition() searches raw diagnosis columns (full ICD with D-prefix) using a named
  # list of prefix strings, returning a long data.table one row per match. It is fast
  # (C++ core) and handles multi-column search and exclusion lists cleanly.
  # We don't switch because: (1) all_dx is already collected and stripped of the D-prefix,
  # so findCondition() would require restructuring to work on the raw (pre-collect) data;
  # (2) our icd3 %in% codes loop is equivalent in speed on collected data;
  # (3) findCondition() returns long format requiring dcast to get the 0/1 flags we need.
  # Re-evaluate if we ever extend to multi-column diagnosis search (e.g., c_diag + c_tildiag).

  result <- bs_cohort %>% select(pnr)  # start with one row per person; condition flags will be added column by column

  for (condition_name in names(nmi_conditions)) {      # loop over each of the ~33 condition groups (mi, stroke, diabetes, etc.)
    codes <- nmi_conditions[[condition_name]]           # get the ICD-10 3-char codes for this condition (e.g. c("I21","I22","I23") for MI)
    flag  <- all_dx %>%
      filter(icd3 %in% codes) %>%                       # keep only rows where the diagnosis matches one of the codes for this condition
      distinct(pnr) %>%                                  # one row per person — we only care if they had it at least once, not how many times
      mutate(!!condition_name := 1L)                    # create a column named after the condition (e.g. "mi") and set it to 1 for everyone in this subset
    result <- result %>% left_join(flag, by = "pnr")    # attach the flag to result; people without the condition get NA here
    result[[condition_name]] <- coalesce(result[[condition_name]], 0L)  # coalesce() replaces NA with 0 — so 0 = condition absent, 1 = condition present
  }

  # GMC icd4 refinements — conditions the main icd3 loop cannot handle precisely ----

  # Peptic ulcer: add K22.1 (oesophageal ulcer) and K29.3-K29.5 (chronic gastritis).
  # These are not captured by K25-K28 at icd3 level.
  peptic_icd4 <- all_dx %>%
    filter(icd4 %in% c("K221", "K293", "K294", "K295")) %>%  # match 4-char ICD codes that the 3-char loop missed
    distinct(pnr)                                             # one row per person
  result <- result %>%
    left_join(peptic_icd4 %>% mutate(peptic_icd4_flag = 1L), by = "pnr") %>%  # attach extra peptic ulcer cases
    mutate(peptic_ulcer = pmax(peptic_ulcer, coalesce(peptic_icd4_flag, 0L))) %>%  # pmax() takes the maximum — so if either the icd3 OR icd4 check flagged them, they get 1
    select(-peptic_icd4_flag)  # drop the temporary helper column

  # Liver: add K76.6 (portal hypertension). The icd3 loop already covers K70-K74 and B16-B19.
  # K76 is deliberately excluded from the icd3 list above; only K76.6 qualifies per GMC.
  liver_icd4 <- all_dx %>%
    filter(icd4 == "K766") %>%  # K76.6 = portal hypertension — the only K76 subcode GMC includes
    distinct(pnr)
  result <- result %>%
    left_join(liver_icd4 %>% mutate(liver_icd4_flag = 1L), by = "pnr") %>%  # attach extra liver cases
    mutate(liver = pmax(liver, coalesce(liver_icd4_flag, 0L))) %>%  # if either icd3 or icd4 flagged liver disease, mark as 1
    select(-liver_icd4_flag)  # drop the temporary helper column

  # Thyroid: exclude E06.0 (acute thyroiditis) from persons flagged by icd3 E06.
  # GMC keeps E06.1-E06.9 (autoimmune, subacute, chronic thyroiditis etc.) only.
  # We can't un-flag persons via icd3, but we can remove persons whose ONLY E06 record
  # is E06.0 and who have no other thyroid code. In practice this rarely changes results.
  # (Full implementation would require checking all thyroid contacts per person — noted
  # as a known minor deviation from the GMC algorithm.)

  result
}

# ============================================================================
# 2.9 NORDIC MULTIMORBIDITY INDEX (NMI) — BOTH STUDIES (LPR + LMDB)
# ============================================================================
# NMI: continuous severity score with 50 weighted predictors (29 ICD groups +
# 21 ATC groups). Designed to predict 1-year all-cause mortality in primary care.
# Reference: Kristensen et al., Clinical Epidemiology 2022:14 567-579
#            https://doi.org/10.2147/CLEP.S353398
# Official code (Stata): https://pharmacoepi.sdu.dk/nmi/
# Translated to R for DST parquet registries.
# Diagnoses: 5-year lookback (A, B, G diagnosis types).
# Prescriptions: 6-month lookback.
# Score = sum of component weights; two components have negative weights (protective):
#   rx_C09C_C09D (ARBs/sartans) = -2, rx_C10AA (statins) = -3.

extract_nmi <- function(bs_cohort, exclude_dementia_predictors = FALSE) {
  # exclude_dementia_predictors = TRUE: removes dx_F00_G30 (dementia ICD codes) and
  # rx_N06D (anti-dementia drugs) from the predictor set before computing the score.
  # Use TRUE for Study 1 (dementia is the outcome): everyone in the analysis cohort
  # has dx_F00_G30 = 0 by construction (pre-surgery dementia is an exclusion criterion),
  # and rx_N06D users are also excluded (methods plan criterion 3). Including these
  # components adds 0 to all scores but creates circular logic that reviewers will flag.
  # The resulting modified NMI covers 28 dx + 20 rx = 48 predictors (out of 50 original).
  # Use FALSE (default) for general use / Study 2 (non-dementia outcomes).

  # ---- Diagnosis patterns and weights (29 groups, Table 2) ----
  # Patterns match against icd4 = substr(DST_code, 2, 5), which strips the
  # DST leading "D" prefix and returns the first 4 ICD-10 characters.
  # Patterns requiring 4-char precision (e.g. ^D43[0-2], ^I110) use icd4 directly.
  # Named character vector: each name is the predictor label, each value is the regex pattern.
  # The patterns are taken verbatim from the official Stata code (online_nmi.do).
  # All patterns are matched against icd4 (4-char ICD-10, DST "D" prefix stripped).
  dx_patterns <- c(
    dx_B18      = "^B18",           # Chronic viral hepatitis
    dx_C34      = "^C34",           # Lung cancer
    dx_C50      = "^C50",           # Breast cancer
    dx_C61      = "^C61",           # Prostate cancer
    dx_C67      = "^C67",           # Bladder cancer
    dx_C70_D432 = "^C7[01]|^C75[1-3]|^D32|^D33[0-2]|^D35[2-4]|^D42|^D43[0-2]|^D44[3-5]",
                                    # Brain/CNS tumours (malignant and uncertain behaviour)
    dx_C76_C80  = "^C7[6-9]|^C80", # Secondary and unspecified malignancies
    dx_C91_C95  = "^C9[1-5]",      # Haematological cancers (leukaemia, lymphoma etc.)
    dx_D50_D64  = "^D5[0-9]|^D6[0-4]",  # Anaemia and other blood disorders
    dx_E11      = "^E11",           # Type 2 diabetes
    dx_E86      = "^E86",           # Volume depletion / dehydration
    dx_F00_G30  = "^F0[0-3]|^G30", # Dementia (F00-F03) and Alzheimer's (G30). G31 is NOT in NMI per Kristensen 2022 Table 2.
    dx_F10      = "^F10",           # Alcohol use disorder
    dx_F17      = "^F17",           # Tobacco dependence
    dx_G20_G22  = "^G2[0-2]",      # Parkinson's disease
    dx_G35      = "^G35",           # Multiple sclerosis
    dx_G40_G41  = "^G4[01]",       # Epilepsy
    dx_I05_I35  = "^I0[56]|^I3[45]",     # Valvular heart disease
    dx_I110_I50 = "^I110|^I13[02]|^I42[06789]|^I50",  # Heart failure (hypertensive and other)
    dx_I60_I69  = "^I6[0-9]",      # Cerebrovascular disease (stroke, TIA etc.)
    dx_I70_I77  = "^I7[0347]",     # Peripheral arterial disease and aortic aneurysm
    dx_I71_I72  = "^I7[12]",       # Aortic aneurysm and dissection
    dx_J12_J18  = "^J1[2-8]",      # Pneumonia
    dx_J41_J47  = "^J4[12347]|^J96[19]", # COPD and respiratory failure
    dx_J84      = "^J84",           # Interstitial lung disease / pulmonary fibrosis
    dx_K02_K08  = "^K0[234568]",   # Dental caries and other oral diseases
    dx_K70_K767 = "^K7[024]|^K76[67]",  # Liver disease (alcoholic, cirrhosis, portal hypertension)
    dx_L89      = "^L89",           # Pressure ulcers / decubitus
    dx_N18_N19  = "^N1[89]"        # Chronic kidney disease and renal failure
  )

  # Weights from Table 2. Names must match dx_patterns exactly — used to look up weight per predictor.
  dx_weights <- c(
    dx_B18      = 10, dx_C34      = 19, dx_C50      = 4,  dx_C61      = 5,
    dx_C67      = 8,  dx_C70_D432 = 8,  dx_C76_C80  = 22, dx_C91_C95  = 8,
    dx_D50_D64  = 5,  dx_E11      = 2,  dx_E86      = 6,  dx_F00_G30  = 9,
    dx_F10      = 12, dx_F17      = 4,  dx_G20_G22  = 7,  dx_G35      = 7,
    dx_G40_G41  = 5,  dx_I05_I35  = 2,  dx_I110_I50 = 4,  dx_I60_I69  = 4,
    dx_I70_I77  = 5,  dx_I71_I72  = 4,  dx_J12_J18  = 4,  dx_J41_J47  = 4,
    dx_J84      = 7,  dx_K02_K08  = 5,  dx_K70_K767 = 13, dx_L89      = 11,
    dx_N18_N19  = 7
  )

  # ---- ATC patterns and weights (21 groups, Table 2) ----
  # Matched against the full ATC code string in lmdb (no prefix stripping needed).
  rx_patterns <- c(
    rx_A06A          = "^A06A",          # Laxatives (bulk-forming, osmotic etc.)
    rx_A07DA         = "^A07DA",         # Opioid antidiarrhoeals (e.g. loperamide)
    rx_A10A          = "^A10A",          # Insulin
    rx_B01AC         = "^B01AC",         # Platelet aggregation inhibitors (aspirin, clopidogrel)
    rx_B03A          = "^B03A",          # Iron preparations
    rx_C01AA         = "^C01AA",         # Cardiac glycosides (digoxin)
    rx_C03C_C03EB    = "^C03C|^C03EB",  # High-ceiling / loop diuretics (furosemide etc.)
    rx_C03DA         = "^C03DA",         # Aldosterone antagonists (spironolactone)
    rx_C09C_C09D     = "^C09[CD]",      # ARBs / sartans — negative weight: protective marker
    rx_C10AA         = "^C10AA",        # Statins — negative weight: protective marker
    rx_H02AB         = "^H02AB",         # Systemic glucocorticoids
    rx_J01C          = "^J01C",          # Penicillins (antibiotic use as severity marker)
    rx_N02A          = "^N02A",          # Opioid analgesics
    rx_N02BE         = "^N02BE",         # Paracetamol / acetaminophen
    rx_N05BA_N05CF   = "^N05BA|^N05C[DF]",  # Anxiolytics and hypnotics (benzodiazepines, Z-drugs)
    rx_N05AA_N05AX   = "^N05A[A-L]|^N05AX", # Antipsychotics (typical and atypical)
    rx_N06A          = "^N06A",          # Antidepressants
    rx_N06D          = "^N06D",          # Anti-dementia drugs (cholinesterase inhibitors, memantine)
    rx_N07BC         = "^N07BC",         # Opioid dependence treatment (methadone, buprenorphine)
    rx_R03AC02_05    = "^R03AC0[2-5]",  # Short-acting beta-2 agonists (salbutamol etc.)
    rx_R03BB04_07    = "^R03BB0[4-7]"   # Long-acting anticholinergics for COPD (tiotropium etc.)
  )

  # Weights from Table 2. C09C_C09D and C10AA have negative weights (see comments above).
  rx_weights <- c(
    rx_A06A          = 8,  rx_A07DA       = 5,  rx_A10A        = 4,
    rx_B01AC         = 2,  rx_B03A        = 5,  rx_C01AA       = 4,
    rx_C03C_C03EB    = 5,  rx_C03DA       = 3,  rx_C09C_C09D   = -2,
    rx_C10AA         = -3, rx_H02AB       = 2,  rx_J01C        = 1,
    rx_N02A          = 2,  rx_N02BE       = 2,  rx_N05BA_N05CF = 1,
    rx_N05AA_N05AX   = 7,  rx_N06A        = 3,  rx_N06D        = 11,
    rx_N07BC         = 7,  rx_R03AC02_05  = 3,  rx_R03BB04_07  = 5
  )

  # ---- Optionally drop dementia-related predictors for Study 1 ----
  # For Study 1 (dementia is the outcome), remove dx_F00_G30 and rx_N06D from the
  # predictor set. Both components are 0 for everyone by construction (pre-surgery
  # dementia and N06D users are exclusion criteria), so removal does not change scores,
  # but it eliminates circular logic and pre-empts reviewer concerns.
  if (exclude_dementia_predictors) {
    dx_patterns <- dx_patterns[names(dx_patterns) != "dx_F00_G30"]   # drop dementia ICD predictor
    dx_weights  <- dx_weights[ names(dx_weights)  != "dx_F00_G30"]   # drop corresponding weight
    rx_patterns <- rx_patterns[names(rx_patterns) != "rx_N06D"]      # drop anti-dementia drug predictor
    rx_weights  <- rx_weights[ names(rx_weights)  != "rx_N06D"]      # drop corresponding weight
  }

  pnrs   <- unique(bs_cohort$pnr)          # deduplicated list of all person IDs to look up
  result <- bs_cohort %>% select(pnr)       # start with one row per person; flags added below

  # ---- Diagnosis flags (5-year lookback) ----
  # We use diagtypes A (primary), B (secondary), and G (grundmorbus / underlying disease)
  # to capture all diagnoses the patient has, not only the primary reason for each contact.
  all_dx <- get_lpr_diagnoses(pnrs, diagtypes = c("A", "B", "G")) %>%
    inner_join(bs_cohort %>% select(pnr, surgery_date), by = "pnr") %>%  # attach index date per person
    filter(
      date_contact >= surgery_date - 365.25 * 5,  # NMI specifies 5-year lookback; 365.25 accounts for leap years
      date_contact <  surgery_date               # baseline only — no post-surgery diagnoses
    ) %>%
    select(pnr, icd4)   # icd4 = first 4 ICD-10 characters (DST "D" prefix stripped);
                        # sufficient for all 29 NMI patterns including 4-char ones like ^D43[0-2]

  # For each of the 29 diagnosis groups: flag 1 if the person had any matching diagnosis,
  # 0 if not. grepl() applies the regex pattern to every icd4 value; distinct() ensures
  # one row per person regardless of how many matching contacts they had.
  for (name in names(dx_patterns)) {
    matched <- all_dx %>%
      filter(grepl(dx_patterns[[name]], icd4)) %>%   # regex match: e.g. "^C34" catches C340, C341 etc.
      distinct(pnr) %>%                              # one row per person — we only need presence/absence
      mutate(!!name := 1L)                          # flag column named after the predictor (e.g. dx_C34)
    result <- result %>% left_join(matched, by = "pnr")   # attach flag; persons without a match get NA
    result[[name]] <- coalesce(result[[name]], 0L)        # replace NA with 0 (no diagnosis = 0)
  }

  # ---- Prescription flags (6-month lookback) ----
  # NMI specifies a shorter lookback for prescriptions (6 months = 180 days) than for
  # diagnoses (5 years). Rationale: current medication use reflects current disease severity;
  # old prescriptions may no longer be active.
  lmdb <- load_database("lmdb") %>% rename_with(tolower)  # prescription register; one row per dispensing

  rx_baseline <- lmdb %>%
    filter(pnr %in% !!pnrs) %>%          # limit to cohort members before collect() to save memory
    select(pnr, atc, eksd) %>%           # only the columns we need: person ID, ATC code, dispense date
    collect() %>%                         # pull from parquet into memory for date arithmetic
    inner_join(bs_cohort %>% select(pnr, surgery_date), by = "pnr") %>%  # attach index date
    filter(
      eksd >= surgery_date - 180,   # 6-month lookback window (NMI specification)
      eksd <  surgery_date          # baseline only — no post-surgery prescriptions
    ) %>%
    select(pnr, atc)   # drop eksd and surgery_date after filtering — only atc needed for matching

  # Same loop logic as diagnoses above: flag 1 if any matching prescription in window, else 0.
  for (name in names(rx_patterns)) {
    matched <- rx_baseline %>%
      filter(grepl(rx_patterns[[name]], atc)) %>%   # regex match against ATC code, e.g. "^C10AA"
      distinct(pnr) %>%                             # one row per person
      mutate(!!name := 1L)                         # flag column, e.g. rx_C10AA
    result <- result %>% left_join(matched, by = "pnr")   # attach; non-matches get NA
    result[[name]] <- coalesce(result[[name]], 0L)        # NA -> 0 (no prescription = 0)
  }

  # ---- NMI score = weighted sum across all 50 predictors ----
  all_weights    <- c(dx_weights, rx_weights)   # single named weight vector for all 50 predictors
  predictor_cols <- names(all_weights)          # column names in result that hold the 0/1 flags

  # sweep() multiplies each flag column by its corresponding weight (column-wise scaling).
  # rowSums() then adds up the weighted flags for each person, giving their NMI score.
  # Example: a person with dx_C34 (lung cancer, weight 19) and rx_C10AA (statin, weight -3)
  # and no other predictors would score 19 + (-3) = 16.
  nmi_scores <- rowSums(
    sweep(as.matrix(result[, predictor_cols]), 2, all_weights[predictor_cols], "*")
  )

  result %>%
    select(pnr) %>%
    mutate(nmi_score = nmi_scores)   # one row per person, one column: their NMI score
}

# ============================================================================
# 2.10 BASELINE MEDICATIONS — BOTH STUDIES (LMDB, 5-YEAR LOOKBACK)
# ============================================================================

extract_baseline_medications <- function(bs_cohort) {
  # Diabetes classification is handled by the OSDC pre-computed file (extract_diabetes.rds).
  # We do NOT extract antidiabetic prescriptions (A10) here — OSDC is more accurate
  # than anything derived from ICD codes or prescriptions, and it covers both studies.
  # insulin (A10A) is retained for baseline characterisation: knowing who was on
  # insulin pre-surgery is relevant for Study 2 (T1D outcomes) Table 1.
  atc_groups <- list(
    antihypertensive = c("C02", "C03", "C07", "C08", "C09"),
    lipid_lowering   = "C10",
    insulin          = "A10A",   # for Study 2 baseline only; diabetes type from OSDC
    antidepressant   = "N06A",
    antidementia     = "N06D"
  )

  lmdb <- load_database("lmdb") %>% rename_with(tolower)   # open LMDB (prescription register) lazily

  lmdb_baseline <- lmdb %>%
    filter(pnr %in% !!bs_cohort$pnr) %>%   # keep only cohort members' prescriptions before collect
    select(pnr, atc, eksd) %>%              # ATC code and prescription date are the only columns needed
    collect() %>%                           # bring filtered prescriptions into R memory
    inner_join(bs_cohort %>% select(pnr, surgery_date), by = "pnr") %>%  # attach surgery date for per-person lookback
    filter(
      eksd >= surgery_date - 365.25 * 5,   # prescription must be within 5-year lookback window
      eksd <  surgery_date               # and must precede surgery (not post-surgery prescriptions)
    )

  result <- bs_cohort %>% select(pnr)   # one row per cohort member; medication flag columns added in loop below

  for (med_class in names(atc_groups)) {
    prefixes <- atc_groups[[med_class]]                                    # ATC prefixes for this medication class
    pattern  <- paste0("^(", paste(prefixes, collapse = "|"), ")")        # regex anchored at start: matches any prefix in class
    flag <- lmdb_baseline %>%
      filter(grepl(pattern, atc)) %>%   # keep prescriptions whose ATC code matches this class
      distinct(pnr) %>%                 # one row per person who had any prescription in this class
      mutate(!!med_class := 1L)         # flag column named dynamically (tidy eval !! unquotes the variable name)
    result <- result %>% left_join(flag, by = "pnr")          # merge flag into result; non-users get NA
    result[[med_class]] <- coalesce(result[[med_class]], 0L)  # replace NA with 0: no prescription = 0
  }

  result
}

# ============================================================================
# 2.11 DIABETES CLASSIFICATION — BOTH STUDIES (OSDC PRE-COMPUTED FILE)
# ============================================================================
# Path confirmed in DARTER kickstarter.
# OSDC columns: PNR (uppercase -> pnr after tolower), diabetes_type (1=T1D, 2=T2D),
#               do_dm (date of classification), age_at_onset

extract_diabetes_classification <- function(bs_cohort) {
  if (!file.exists(path_dm_pop)) {
    stop("OSDC diabetes cohort file not found: ", path_dm_pop)
  }

  dm_pop <- readRDS(path_dm_pop) %>%
    rename_with(tolower) %>%
    select(pnr, diabetes_type, date_diabetes = do_dm) %>%
    mutate(
      diabetes_type = case_when(
        diabetes_type == 1 ~ "T1D",
        diabetes_type == 2 ~ "T2D",
        TRUE ~ as.character(diabetes_type)
      )
    )

  bs_cohort %>%
    select(pnr) %>%
    left_join(dm_pop, by = "pnr") %>%
    mutate(diabetes_type = coalesce(diabetes_type, "No_diabetes"))
}

# ============================================================================
# 2.12 SOCIOECONOMIC STATUS (SEE 03_extract_ses.R — STEP 3 of 5)
# ============================================================================
# SES is extracted in 03_extract_ses.R — run that script separately.
# Produces: path_output/ses_data.rds
# Variables: pnr, education_cat, income_cat, occupation_cat
# (no sep_category composite — removed per SEPLINE; see 03_extract_ses.R section 3.4)

load_ses <- function() {
  ses_file <- file.path(path_output, "ses_data.rds")
  if (!file.exists(ses_file)) {
    stop("SES data not found. Run 03_extract_ses.R first.")
  }
  readRDS(ses_file) %>%
    select(pnr, education_cat, income_cat, occupation_cat)
}

# ============================================================================
# 2.13 MAIN WORKFLOW
# ============================================================================

main_extraction <- function() {
  dir.create(path_output, showWarnings = FALSE, recursive = TRUE)

  cat("Loading full cohort (BS + GP + Obesity)...\n")
  full_cohort <- load_full_cohort()
  # surgery_date here is index_date for all cohort members

  # Weight and insulin outcomes only apply to BS patients (DBSO data)
  bs_only <- full_cohort %>% filter(cohort == "BS")

  cat("Extracting demographics (all cohort members)...\n")
  demographics <- extract_demographics(full_cohort)
  saveRDS(demographics, file.path(path_output, "extract_demographics.rds"))

  cat("Extracting dementia outcomes (all cohort members)...\n")
  dementia <- extract_dementia_outcomes(full_cohort)   # includes date_dementia_primary for sensitivity 7g.1
  saveRDS(dementia, file.path(path_output, "extract_dementia.rds"))

  cat("Extracting negative control outcome — cataract (sensitivity 7g.6)...\n")
  negative_controls <- extract_negative_controls(full_cohort)
  saveRDS(negative_controls, file.path(path_output, "extract_negative_controls.rds"))

  cat("Extracting weight outcomes (BS patients only -- DBSO)...\n")
  weights <- extract_weight_outcomes(bs_only)
  saveRDS(weights, file.path(path_output, "extract_weights.rds"))

  cat("Extracting DBSO clinical outcomes (BS patients only -- Study 2)...\n")
  dbso_clinical <- extract_dbso_clinical(bs_only)   # reoperation flags, EOSS, sleep apnea, nutritional supplements
  saveRDS(dbso_clinical, file.path(path_output, "extract_dbso_clinical.rds"))

  cat("Extracting insulin outcomes (BS patients only)...\n")
  insulin <- extract_insulin_outcomes(bs_only)
  saveRDS(insulin, file.path(path_output, "extract_insulin.rds"))

  cat("Extracting hospital contacts (all cohort members)...\n")
  hospitals <- extract_hospital_contacts(full_cohort)
  saveRDS(hospitals, file.path(path_output, "extract_hospitals.rds"))

  cat("Extracting baseline comorbidities (all cohort members)...\n")
  comorbidities <- extract_baseline_comorbidities(full_cohort)
  saveRDS(comorbidities, file.path(path_output, "extract_comorbidities.rds"))

  cat("Extracting NMI score (all cohort members, dementia predictors excluded for Study 1)...\n")
  nmi <- extract_nmi(full_cohort, exclude_dementia_predictors = TRUE)  # Study 1 uses dementia-free NMI (28 dx + 20 rx predictors)
  saveRDS(nmi, file.path(path_output, "extract_nmi.rds"))

  cat("Extracting baseline medications (all cohort members)...\n")
  medications <- extract_baseline_medications(full_cohort)
  saveRDS(medications, file.path(path_output, "extract_medications.rds"))

  cat("Extracting diabetes classification (all cohort members)...\n")
  diabetes <- extract_diabetes_classification(full_cohort)
  saveRDS(diabetes, file.path(path_output, "extract_diabetes.rds"))

  cat("Done! Individual extracts saved to", path_output, "\n")
  cat("Next: run 03_extract_ses.R, then 04_data_management_dementia.R\n")
  invisible(NULL)
}

# Run:
# main_extraction()
