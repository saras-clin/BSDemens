# ============================================================================
# PIPELINE STEP 0 (one-time) — 00_prepare_dbso.R
# ============================================================================
# CONVERT DBSO FROM SAS TO PARQUET
#   
#   Section 0.1:  load and check column names / bmi_pre inputs
#   Section 0.2:  clean and save as parquet
#
#   DFR_population     = bariatric surgery patients; one row per clinic visit
#                        (PRE = pre-op, PER = surgery, FOL = follow-up); contains
#                        weight, surgery type, dates, complications
#
#   Input:   E:/rawdata/708421/Eksterne data/dfr_2025_10_31.sas7bdat
#   Output:  parquet-external/databasesvaerovervaegt/part-0.parquet
#            (read via arrow::open_dataset() in 02_extract_outcomes_covariates.R)
# ============================================================================

library(haven)      # read_sas()
library(arrow)      # write_parquet()
library(dplyr)
library(lubridate)

path_sas         <- "E:/rawdata/708421/Eksterne data/dfr_2025_10_31.sas7bdat"
path_dbso_folder <- "E:/workdata/708421/cleaned-data/parquet-external/databasesvaerovervaegt"
path_output      <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets"  # own processed datasets

# ----------------------------------------------------------------------------
# 0.1 EXPLORE — confirm column names and bmi_pre inputs before prepare_dbso()
# ----------------------------------------------------------------------------

raw <- haven::read_sas(path_sas) %>% rename_with(tolower)   # load DBSO SAS file and lowercase all column names

names(raw)                          # verify expected columns are present (datoper_prim, udgangsvaegtpre_prim, hoejde, gastricbypass_prim, etc.)
sapply(raw, class)                  # check column types — confirm date columns are Date not numeric; if already Date, as.Date() in 0.2 is harmless but can be removed
summary(raw$udgangsvaegtpre_prim)   # pre-surgery weight — check it is populated and plausible
summary(raw$hoejde)                 # height — check for zeros or implausible values


# ----------------------------------------------------------------------------
# 0.2 CLEAN AND SAVE AS PARQUET
# ----------------------------------------------------------------------------
# Run after 0.1 confirms column names and bmi_pre inputs look correct.
#
# Derived columns added (all other columns retain their lowercased SAS names):
#   pnr ← cpr  (CPR) — patient ID renamed for pipeline consistency
# All other columns (datoper_prim, datopre, datofol, surgery flags, weight columns)
# are kept with their original lowercased SAS names. Renaming, type coercion, surgery_type
# derivation, and BMI calculations are done downstream in 01_build_cohorts.R and
# 04_data_management_dementia.R.
#
# Output is LONG FORMAT: one row per clinic visit per patient.
# ----------------------------------------------------------------------------
dbso_clean <- raw %>%
  mutate(
    pnr          = as.character(cpr),    # patient ID — renamed from CPR for pipeline consistency
    datoper_prim = as.Date(datoper_prim), # surgery date — character "YYYY-MM-DD" to Date class
    datopre      = as.Date(datopre),      # pre-op visit date — character to Date class
    datofol      = as.Date(datofol)       # follow-up visit date — character to Date class
  ) 
  
n_distinct(dbso_clean$pnr)    # number of unique patients

arrow::write_parquet(dbso_clean, "E:/workdata/708421/cleaned-data/parquet-external/databasesvaerovervaegt/part-0.parquet")   # save as parquet; part-0 naming follows Arrow open_dataset() convention
