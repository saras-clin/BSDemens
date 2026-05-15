# ============================================================================
# PIPELINE STEP 5 — 05_inspect_data.R
# ============================================================================
# Data quality inspection before analysis.
# Run after Step 4 (04_data_management_dementia.R) has produced study1_clean.rds.
# No data are modified here — this script only flags and reports.
# Cleaning decisions (set to NA / exclude) must be made manually after review
# and implemented in a dedicated cleaning block at the end of this script.
#
# Checks performed:
#   5.1  DBSO date concordance — datoper_prim vs opdatelpr (within 7 days?)
#   5.2  DBSO anthropometrics — height, pre-op weight, surgery-day weight, BMI
#   5.3  study1_clean — age, dates, follow-up time, impossible values
#   5.4  Missing data summary — proportion missing per analysis variable
#   5.5  Plausibility flags — counts and records for manual review
#   5.6  Missing value strategy — options to consider per variable type
#
# Input:  datasets/study1_clean.rds
#         parquet-external/databasesvaerovervaegt/ (DBSO via load_database)
# Output: prints to console; flagged records saved to datasets/inspect_flags.rds
# ============================================================================

library(dplyr)
library(lubridate)
library(dstDataPrep)

path_datasets <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets"

study1 <- readRDS(file.path(path_datasets, "study1_clean.rds"))                   # analysis dataset from Step 4
dbso   <- load_database("dbso") %>% rename_with(tolower) %>% collect()            # DBSO in memory; one row per clinic visit


# ============================================================================
# 5.1 DBSO DATE CONCORDANCE: datoper_prim vs opdatelpr
# ============================================================================
# DBSO contains two surgery date fields:
#   datoper_prim = date as recorded by the operating clinic in DBSO
#   opdatelpr    = date as transmitted to LPR (Danish National Patient Registry)
# Both should agree for the same procedure. Discrepancies reflect administrative
# lag, coding differences, or data entry errors. The study uses datoper_prim
# as the index date. Pre-specified rule: if >= 95% of records agree within 7 days,
# datoper_prim is used without a sensitivity analysis (see methods plan 7g.5 —
# already resolved). This section confirms that rule holds and documents the
# distribution for the manuscript.

cat("\n=== 5.1 SURGERY DATE CONCORDANCE: datoper_prim vs opdatelpr ===\n")

dbso_dates <- dbso %>%
  filter(!is.na(datoper_prim)) %>%                                   # keep rows with a primary surgery date recorded
  mutate(
    datoper_prim = as.Date(datoper_prim),                            # ensure Date class; SAS dates from haven are already Date
    opdatelpr    = as.Date(opdatelpr),                               # ensure Date class for LPR date
    date_diff    = as.numeric(datoper_prim - opdatelpr)              # signed difference in days (positive = DBSO later than LPR)
  ) %>%
  filter(!is.na(opdatelpr))                                          # exclude rows where LPR date is missing (no LPR record)

cat("Rows with both datoper_prim and opdatelpr: ", nrow(dbso_dates), "\n")
cat("Rows where opdatelpr is NA (no LPR match): ",
    sum(!is.na(dbso$datoper_prim) & is.na(dbso$opdatelpr)), "\n")   # count procedures with no LPR date

cat("\nDate difference (datoper_prim - opdatelpr), in days:\n")
print(summary(dbso_dates$date_diff))                                 # distribution of discrepancies

cat("\nProportion within ± 7 days: ",
    round(mean(abs(dbso_dates$date_diff) <= 7, na.rm = TRUE) * 100, 1), "%\n")   # pre-specified threshold: >= 95%
cat("Proportion within ± 1 day:  ",
    round(mean(abs(dbso_dates$date_diff) <= 1, na.rm = TRUE) * 100, 1), "%\n")   # tighter check

cat("\nRecords with |difference| > 7 days:\n")
print(
  dbso_dates %>%
    filter(abs(date_diff) > 7) %>%
    select(pnr, datoper_prim, opdatelpr, date_diff) %>%
    arrange(desc(abs(date_diff)))                                     # sort largest discrepancies first
)


# ============================================================================
# 5.2 DBSO ANTHROPOMETRICS — PLAUSIBILITY CHECKS
# ============================================================================
# Plausibility limits (conservative; designed to catch data entry errors):
#   Height (hoejde):           130–230 cm  — adult range; < 130 or > 230 = implausible
#   Weight (any measure):       40–600 kg  — > 600 documented but extremely rare;
#                                             < 40 likely post-op recording error or entry error
#   BMI (bmi_preop in study1):  15–120     — < 15 suggests post-op weight entered pre-op field;
#                                             < 25 is unexpected (BS requires BMI >= 35 or >= 40)
#
# udgangsvaegt:         weight at programme entry / referral (may be months before surgery)
# udgangsvaegtpre_prim: weight at last pre-op clinic visit
# vaegtper_prim:        weight on surgery day (most relevant for analysis)
# vaegtfol:             weight at follow-up visits (post-op; lower bound relaxed)

cat("\n=== 5.2 DBSO ANTHROPOMETRIC DISTRIBUTIONS ===\n")

cat("\n--- Height (hoejde, cm) ---\n")
print(summary(dbso$hoejde))
cat("N missing:          ", sum(is.na(dbso$hoejde)), "\n")
cat("N < 130 cm:         ", sum(dbso$hoejde < 130, na.rm = TRUE), "\n")   # below adult plausibility threshold
cat("N > 230 cm:         ", sum(dbso$hoejde > 230, na.rm = TRUE), "\n")   # above adult plausibility threshold

cat("\n--- Programme entry weight (udgangsvaegt, kg) ---\n")
print(summary(dbso$udgangsvaegt))
cat("N missing:          ", sum(is.na(dbso$udgangsvaegt)), "\n")
cat("N < 40 kg:          ", sum(dbso$udgangsvaegt <  40,  na.rm = TRUE), "\n")
cat("N > 600 kg:         ", sum(dbso$udgangsvaegt > 600,  na.rm = TRUE), "\n")

cat("\n--- Pre-op weight at last visit (udgangsvaegtpre_prim, kg) ---\n")
print(summary(dbso$udgangsvaegtpre_prim))
cat("N missing:          ", sum(is.na(dbso$udgangsvaegtpre_prim)), "\n")
cat("N < 40 kg:          ", sum(dbso$udgangsvaegtpre_prim <  40,  na.rm = TRUE), "\n")
cat("N > 600 kg:         ", sum(dbso$udgangsvaegtpre_prim > 600,  na.rm = TRUE), "\n")

cat("\n--- Surgery-day weight (vaegtper_prim, kg) ---\n")
print(summary(dbso$vaegtper_prim))
cat("N missing:          ", sum(is.na(dbso$vaegtper_prim)), "\n")
cat("N < 40 kg:          ", sum(dbso$vaegtper_prim <  40,  na.rm = TRUE), "\n")
cat("N > 600 kg:         ", sum(dbso$vaegtper_prim > 600,  na.rm = TRUE), "\n")

cat("\n--- Follow-up weight (vaegtfol, kg) ---\n")
print(summary(dbso$vaegtfol))
cat("N missing:          ", sum(is.na(dbso$vaegtfol)), "\n")
cat("N < 30 kg:          ", sum(dbso$vaegtfol <  30,  na.rm = TRUE), "\n")   # post-op: lower bound relaxed
cat("N > 600 kg:         ", sum(dbso$vaegtfol > 600,  na.rm = TRUE), "\n")

cat("\n--- BMI at surgery day (bmi_preop, kg/m²) — BS cohort in study1_clean ---\n")
bs_only <- study1 %>% filter(cohort == "BS")                                    # comparators have no DBSO BMI
print(summary(bs_only$bmi_preop))
cat("N missing:          ", sum(is.na(bs_only$bmi_preop)), "\n")
cat("N < 15:             ", sum(bs_only$bmi_preop <  15, na.rm = TRUE), "\n")  # below any plausible pre-op BMI
cat("N < 25:             ", sum(bs_only$bmi_preop <  25, na.rm = TRUE), "\n")  # below overweight threshold; unexpected for BS candidate
cat("N > 120:            ", sum(bs_only$bmi_preop > 120, na.rm = TRUE), "\n")  # physiologically implausible


# ============================================================================
# 5.3 STUDY1_CLEAN — AGE, DATES, FOLLOW-UP TIME
# ============================================================================

cat("\n=== 5.3 STUDY1_CLEAN KEY VARIABLE CHECKS ===\n")

cat("\n--- Age at surgery/index date (age_at_surgery, years) ---\n")
print(summary(study1$age_at_surgery))
cat("N missing:          ", sum(is.na(study1$age_at_surgery)), "\n")
cat("N < 18:             ", sum(study1$age_at_surgery <  18, na.rm = TRUE), "\n")   # BS eligibility requires >= 18
cat("N >= 80:            ", sum(study1$age_at_surgery >= 80, na.rm = TRUE), "\n")   # not excluded, but flag for awareness

cat("\n--- Surgery / index date (surgery_date) ---\n")
print(summary(study1$surgery_date))
cat("N outside 2010–2024: ",
    sum(format(study1$surgery_date, "%Y") < "2010" |
        format(study1$surgery_date, "%Y") > "2024", na.rm = TRUE), "\n")            # all must be within study period

cat("\n--- Follow-up time (follow_up_days) ---\n")
print(summary(study1$follow_up_days))
cat("N missing:          ", sum(is.na(study1$follow_up_days)), "\n")
cat("N <= 0 days:        ", sum(study1$follow_up_days <= 0, na.rm = TRUE), "\n")    # impossible: censor/event must be after index date

cat("\n--- Censor date (censor_date) ---\n")
cat("N censor_date < surgery_date:  ",
    sum(study1$censor_date < study1$surgery_date, na.rm = TRUE), "\n")              # impossible: cannot be censored before start
cat("N censor_date > 2025-12-31:   ",
    sum(study1$censor_date > as.Date("2025-12-31"), na.rm = TRUE), "\n")            # cannot exceed administrative end of study

cat("\n--- Death date (death_date, among persons with recorded death) ---\n")
death_rows <- study1 %>% filter(!is.na(death_date))                                  # restrict to persons with a death record
cat("N with death_date:  ", nrow(death_rows), "\n")
cat("N death before surgery_date:   ",
    sum(death_rows$death_date < death_rows$surgery_date, na.rm = TRUE), "\n")        # should be 0 after 30-day exclusion


# ============================================================================
# 5.4 MISSING DATA SUMMARY — KEY ANALYSIS VARIABLES
# ============================================================================
# Covariates with > 5% missing may require multiple imputation or a sensitivity
# analysis using complete cases. Covariates with > 20% missing should be
# investigated before modelling — see section 5.6 for strategy options.

cat("\n=== 5.4 MISSING DATA SUMMARY ===\n")

analysis_vars <- c(
  # Outcome and follow-up
  "dementia_event", "follow_up_days",
  "alzheimers_event", "vascular_event",
  # Matching and design variables
  "cohort", "surgery_type", "surgery_date",
  # Demographics
  "age_at_surgery", "sex",
  # Clinical covariates
  "nmi_score", "nmi_count", "diabetes_type",
  "hypertension_combined", "dyslipidemia_combined",
  "antihypertensive", "lipid_lowering", "antidiabetic", "antidepressant",
  # SEP
  "education_cat", "income_cat", "occupation_cat",
  # DBSO anthropometrics (BS cohort only; NA for comparators by design)
  "weight_preop", "height_preop", "bmi_preop"
)

analysis_vars <- analysis_vars[analysis_vars %in% names(study1)]                     # keep only columns present

miss_df <- data.frame(
  variable    = analysis_vars,
  n_total     = nrow(study1),
  n_missing   = sapply(analysis_vars, function(v) sum(is.na(study1[[v]]))),
  pct_missing = round(100 * sapply(analysis_vars, function(v) mean(is.na(study1[[v]]))), 1)
)
miss_df$flag <- ifelse(miss_df$pct_missing > 20, "!!! >20%",
                ifelse(miss_df$pct_missing >  5, "!  >5%", ""))                      # flag high missingness

print(miss_df, row.names = FALSE)

cat("\nMissing data in BS cohort only (for DBSO-specific variables):\n")
bs_miss_vars <- c("weight_preop", "height_preop", "bmi_preop")
bs_miss_vars <- bs_miss_vars[bs_miss_vars %in% names(study1)]
bs_only_for_miss <- study1 %>% filter(cohort == "BS")                                # comparators have NA for DBSO vars by design

bs_miss_df <- data.frame(
  variable    = bs_miss_vars,
  n_bs        = nrow(bs_only_for_miss),
  n_missing   = sapply(bs_miss_vars, function(v) sum(is.na(bs_only_for_miss[[v]]))),
  pct_missing = round(100 * sapply(bs_miss_vars, function(v) mean(is.na(bs_only_for_miss[[v]]))), 1)
)
print(bs_miss_df, row.names = FALSE)


# ============================================================================
# 5.5 PLAUSIBILITY FLAGS — RECORDS FOR MANUAL REVIEW
# ============================================================================
# One row per patient (primary surgery record from DBSO).
# Records that fail ANY check below are printed for manual inspection.
# Do NOT auto-exclude. For each flagged record, decide:
#   (a) Correct value if recoverable from another variable (e.g. height_preop from study1)
#   (b) Set the specific measurement to NA (keeps the patient in the cohort)
#   (c) Exclude the patient only if the error is pervasive or the patient
#       is definitively outside the study population

dbso_primary <- dbso %>%
  filter(!is.na(datoper_prim)) %>%           # primary surgery visit rows only
  arrange(pnr, datoper_prim) %>%             # sort by patient then date
  group_by(pnr) %>%                          # one row per patient
  slice(1) %>%                               # earliest primary surgery record
  ungroup()                                  # remove grouping

dbso_primary <- dbso_primary %>%
  mutate(
    flag_height_low    = !is.na(hoejde) & hoejde < 130,                   # < 130 cm
    flag_height_high   = !is.na(hoejde) & hoejde > 230,                   # > 230 cm
    flag_weight_low    = !is.na(vaegtper_prim) & vaegtper_prim < 40,      # surgery-day weight < 40 kg
    flag_weight_high   = !is.na(vaegtper_prim) & vaegtper_prim > 600,     # surgery-day weight > 600 kg
    flag_preop_low     = !is.na(udgangsvaegtpre_prim) & udgangsvaegtpre_prim < 40,  # pre-op weight < 40 kg
    flag_preop_high    = !is.na(udgangsvaegtpre_prim) & udgangsvaegtpre_prim > 600, # pre-op weight > 600 kg
    flag_any           = flag_height_low | flag_height_high |
                         flag_weight_low | flag_weight_high |
                         flag_preop_low  | flag_preop_high             # any flag triggered
  )

cat("\n=== 5.5 PLAUSIBILITY FLAG COUNTS (primary surgery visit per patient) ===\n")
cat("Height < 130 cm:                         ", sum(dbso_primary$flag_height_low,  na.rm = TRUE), "\n")
cat("Height > 230 cm:                         ", sum(dbso_primary$flag_height_high, na.rm = TRUE), "\n")
cat("Surgery-day weight < 40 kg:              ", sum(dbso_primary$flag_weight_low,  na.rm = TRUE), "\n")
cat("Surgery-day weight > 600 kg:             ", sum(dbso_primary$flag_weight_high, na.rm = TRUE), "\n")
cat("Pre-op weight (last visit) < 40 kg:      ", sum(dbso_primary$flag_preop_low,   na.rm = TRUE), "\n")
cat("Pre-op weight (last visit) > 600 kg:     ", sum(dbso_primary$flag_preop_high,  na.rm = TRUE), "\n")
cat("ANY flag:                                ", sum(dbso_primary$flag_any,         na.rm = TRUE), "\n")

cat("\nFlagged records (inspect individually before any exclusion):\n")
flagged <- dbso_primary %>%
  filter(flag_any) %>%
  select(pnr, hoejde, udgangsvaegtpre_prim, vaegtper_prim, datoper_prim,
         flag_height_low, flag_height_high, flag_weight_low, flag_weight_high,
         flag_preop_low, flag_preop_high)                                            # show relevant fields only
print(flagged)

saveRDS(flagged, file.path(path_datasets, "inspect_flags.rds"))                      # save for later reference
cat("\nSaved flagged records: inspect_flags.rds\n")


# ============================================================================
# 5.6 MISSING VALUE STRATEGY — OPTIONS TO CONSIDER
# ============================================================================
# Review this section after running 5.4. Choose a strategy per variable type
# before fitting Cox models. Document the chosen approach in the methods section.
#
# OPTION A — Complete case analysis (CCA)
#   Include only persons with no missing values on any covariate in Model 3.
#   Valid if data are missing completely at random (MCAR) — unlikely for SEP variables.
#   Produces unbiased estimates under MCAR; biased under MAR or MNAR.
#   Appropriate for: variables missing < 1–2% with no pattern.
#
# OPTION B — Missing indicator (extra category)
#   Add an "Unknown" category to categorical variables and retain all persons.
#   Currently implemented for education_cat, income_cat, occupation_cat.
#   Valid if missingness itself is informative (e.g. "no education record" ~ foreign-born
#   or early cohort). The "Unknown" coefficient is interpretable.
#   Appropriate for: SEP variables where missingness has a substantive meaning.
#
# OPTION C — Multiple imputation (MI)
#   Impute missing values under missing at random (MAR) assumption using chained
#   equations (mice package). Pool estimates across imputed datasets (Rubin's rules).
#   Appropriate for: covariates missing 5–40% with plausible MAR mechanism.
#   Required if CCA would exclude > 5–10% of the cohort.
#
# OPTION D — Sensitivity analysis in complete cases
#   Run main analysis on full dataset (with missing indicator), then re-run on
#   complete cases only. If results agree, missing data are unlikely to drive findings.
#
# Variable-specific notes:
#   nmi_score:        missing if extract_nmi.rds failed to join for a person.
#                     Investigate root cause — should not be missing for any cohort member.
#   diabetes_type:    "No_diabetes" covers persons not in OSDC (onset 2023-2024 or not
#                     classified). Not truly missing — a substantive category.
#   education_cat:    "Unknown" already implemented (SEPLINE approach). No further action.
#   income_cat:       "Unknown" already implemented. Check whether "Unknown" clusters
#                     in specific calendar years (data availability before ~1987 is limited).
#   occupation_cat:   "Unknown" already implemented.
#   bmi_preop:        Missing only for BS patients. If > 10% missing, investigate whether
#                     specific hospitals had lower DBSO recording completeness.
#                     Cannot be imputed for comparators — only use within-BS analyses.
#
# ACTION: After reviewing 5.4 output, document the chosen strategy for each
# variable in study1_methods_plan.md section 10 (Open Issues) and in the
# statistical methods section of the manuscript.

cat("\n=== 5.6 MISSING VALUE STRATEGY ===\n")
cat("Review the notes in this section against the 5.4 output above.\n")
cat("Document chosen strategy (CCA / missing indicator / MI / sensitivity)\n")
cat("in study1_methods_plan.md section 10 before fitting Cox models.\n")


# ============================================================================
# NOTE ON APPLYING CLEANING RULES
# ============================================================================
# After manual review of inspect_flags.rds and the summaries above, add
# cleaning code below. Example structure:
#
#   dbso_clean <- dbso_primary %>%
#     mutate(
#       hoejde         = if_else(hoejde < 130 | hoejde > 230, NA_real_, hoejde),
#       vaegtper_prim  = if_else(vaegtper_prim < 40 | vaegtper_prim > 600,
#                                NA_real_, vaegtper_prim)
#     )
#
# Then re-run 02_extract_outcomes_covariates.R -> extract_weights() with the
# cleaned DBSO to regenerate extract_weights.rds before re-running Step 4.
