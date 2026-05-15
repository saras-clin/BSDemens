# ============================================================================
# PIPELINE STEP 6 — 06_descriptive_statistics_dementia.R
# ============================================================================
# Descriptive statistics for Study 1 (bariatric surgery and dementia).
# Run after Step 5 (05_inspect_data.R) has confirmed data quality.
#
# Contents:
#   6.1  Table 1: Baseline characteristics by cohort (with SMDs)   [§7a]
#   6.2  Cohort flow numbers for Figure 1 (CONSORT-style)          [§8, Fig 1]
#
# Input:  datasets/study1_clean.rds
# Output: datasets/table1_bs_vs_gp.csv, datasets/table1_bs_vs_obesity.csv
# ============================================================================

library(dplyr)
library(tableone)      # CreateTableOne() for Table 1 with SMD

path_datasets <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets"

study1 <- readRDS(file.path(path_datasets, "study1_clean.rds"))   # analysis dataset from Step 4


# ============================================================================
# 6.1 TABLE 1: BASELINE CHARACTERISTICS
# ============================================================================
# Columns: BS total | RYGB | SG | GP comparator | Obesity comparator
# SMD reported pairwise: BS vs GP and BS vs Obesity. No p-values (methods plan §7a).

vars_cont <- c(
  "age_at_surgery",     # age in years at index date
  "nmi_score",          # Kristensen 2022 weighted 48-predictor NMI (continuous)
  "follow_up_days"      # person-time in days
)

vars_cat <- c(
  "sex",                # Male / Female
  "surgery_period",     # 2010–2014 / 2015–2019 / 2020–2024
  "age_cat",            # <50 / 50–59 / 60–69 / ≥70
  "nmi_cat",            # 0 / 1 / 2 / 3+
  "diabetes_type",      # No_diabetes / T1D / T2D
  # NMI conditions
  "mi", "stroke_tia", "pad", "ihd", "heart_failure", "afib",
  "hypertension_combined", "dyslipidemia_combined",
  "thyroid", "gout", "copd", "asthma",
  "liver", "peptic_ulcer", "ibd", "diverticular",
  "ckd", "prostate", "connective_tissue", "osteoporosis",
  "depression", "bipolar",
  "parkinsons", "epilepsy", "ms", "migraine", "neuropathy",
  "cancer", "anemia", "hiv", "vision", "hearing",
  # Medications
  "antihypertensive", "lipid_lowering", "antidiabetic", "antidepressant",
  # SEP
  "education_cat", "income_cat", "occupation_cat"
)

vars_cont <- vars_cont[vars_cont %in% names(study1)]   # keep only columns that exist in dataset
vars_cat  <- vars_cat[vars_cat   %in% names(study1)]

# --- Table 1a: BS vs GP comparator ---
tab1_bs_gp <- CreateTableOne(
  vars       = c(vars_cont, vars_cat),
  strat      = "cohort",              # one column per cohort
  data       = study1 %>% filter(cohort %in% c("BS", "GP")),
  factorVars = vars_cat,
  addOverall = FALSE
)
print(tab1_bs_gp, smd = TRUE, showAllLevels = TRUE, quote = FALSE, noSpaces = TRUE)

write.csv(
  print(tab1_bs_gp, smd = TRUE, showAllLevels = TRUE,
        quote = FALSE, noSpaces = TRUE, printToggle = FALSE),   # capture matrix without re-printing
  file.path(path_datasets, "table1_bs_vs_gp.csv")
)

# --- Table 1b: BS vs Obesity comparator ---
tab1_bs_ob <- CreateTableOne(
  vars       = c(vars_cont, vars_cat),
  strat      = "cohort",
  data       = study1 %>% filter(cohort %in% c("BS", "Obesity")),
  factorVars = vars_cat,
  addOverall = FALSE
)
print(tab1_bs_ob, smd = TRUE, showAllLevels = TRUE, quote = FALSE, noSpaces = TRUE)

write.csv(
  print(tab1_bs_ob, smd = TRUE, showAllLevels = TRUE,
        quote = FALSE, noSpaces = TRUE, printToggle = FALSE),
  file.path(path_datasets, "table1_bs_vs_obesity.csv")
)

# --- Table 1c: RYGB vs SG within BS cohort ---
tab1_rygb_sg <- CreateTableOne(
  vars       = c(vars_cont, vars_cat),
  strat      = "surgery_type",        # RYGB vs SG
  data       = study1 %>% filter(cohort == "BS", !is.na(surgery_type)),
  factorVars = vars_cat,
  addOverall = FALSE
)
print(tab1_rygb_sg, smd = TRUE, showAllLevels = TRUE, quote = FALSE, noSpaces = TRUE)


# ============================================================================
# 6.2 COHORT FLOW — NUMBERS FOR FIGURE 1 (CONSORT-STYLE)
# ============================================================================

flow <- study1 %>%
  group_by(cohort, surgery_type) %>%
  summarise(
    n            = n(),
    n_dementia   = sum(dementia_event,   na.rm = TRUE),
    n_alzheimers = sum(alzheimers_event, na.rm = TRUE),
    n_vascular   = sum(vascular_event,   na.rm = TRUE),
    n_death      = sum(death_event,      na.rm = TRUE),
    median_fu_yr = round(median(follow_up_days, na.rm = TRUE) / 365.25, 1),
    total_py     = round(sum(follow_up_days, na.rm = TRUE) / 365.25, 0)
  ) %>%
  ungroup()

print(flow, width = Inf)   # print full width without truncation

# Surgery type split within BS cohort
study1 %>% filter(cohort == "BS") %>% count(surgery_type)

# Events by cohort
table(study1$cohort, study1$dementia_event, useNA = "ifany")
