# ============================================================================
# PIPELINE STEP 5 — 05_descriptive_statistics_study1.R
# ============================================================================
# Descriptive statistics for Study 1 (bariatric surgery and dementia).
# Run after Step 4 (04_data_management_dementia.R) has produced study1_clean.rds.
#
# DBSO-specific checks (weight distributions, follow-up timing) load directly
# from the DBSO parquet produced in Step 0 (00_prepare_dbso.R).
#
# Input:  datasets/study1_clean.rds
#         parquet-external/databasesvaerovervaegt/part-0.parquet
# ============================================================================

library(dplyr)
library(arrow)
library(lubridate)

path_dbso_folder <- "E:/workdata/708421/cleaned-data/parquet-external/databasesvaerovervaegt"
path_datasets    <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets"

study1  <- readRDS(file.path(path_datasets, "study1_clean.rds"))   # analysis-ready dataset from Step 4
dbso    <- arrow::open_dataset(path_dbso_folder) %>% collect()     # DBSO long format (one row per visit)


# ============================================================================
# DBSO — follow-up visit structure
# ============================================================================

days_fu <- as.numeric(as.Date(dbso$datofol) - as.Date(dbso$datoper_prim))   # days from surgery to each follow-up visit row; as.Date() is harmless if already Date class

table(table(dbso$pnr[!is.na(dbso$datofol)]))   # number of follow-up visits per patient

hist(days_fu[days_fu > 0 & !is.na(days_fu)],
     breaks = 50,
     main   = "Days from surgery to follow-up visit",
     xlab   = "Days")   # check whether visits cluster at expected DBSO windows (6m, 1yr, 2yr)


# ============================================================================
# DBSO — weight distributions
# ============================================================================

summary(dbso$udgangsvaegt)           # wgt at program entry / referral
summary(dbso$udgangsvaegtpre_prim)   # wgt at last pre-op visit
summary(dbso$vaegtper_prim)          # wgt on surgery day
summary(dbso$vaegtfol)               # wgt at follow-up visit
summary(dbso$hoejde)                 # height (cm)
