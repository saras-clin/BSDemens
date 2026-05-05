# ============================================================================
# PIPELINE STEP 0 (one-time) — prepare_dbso.R
# ============================================================================
# CONVERT DBSO FROM SAS TO PARQUET
#   DBSO (Databasen for Behandling af Svær Overvægt) is NOT part of the DST
#   parquet system — it arrives as a separate SAS file from SunDK.
#   Run this script ONCE before running the main pipeline.
#
#   Phase 1:  inspect_dbso()  — print column names and first rows; run first
#   Phase 1b: explore_dbso()  — answer specific structural questions (see below)
#   Phase 2:  prepare_dbso()  — clean and save as parquet after confirming names
#
# DBSO has TWO datasets — only DFR_population is needed here:
#   DFR_population     = bariatric surgery patients; one row per clinic visit
#                        (PRE = pre-op, PER = surgery, FOL = follow-up); contains
#                        weight, surgery type, dates, complications
#   DFR_MWL_population = patients who had Massive Weight Loss (MWL) PLASTIC surgery
#                        (body contouring after weight loss); different operation,
#                        not relevant for Study 1 or Study 2 primary outcomes
#
#   Input:   E:/rawdata/708421/Eksterne data/dfr_2025_10_31.sas7bdat
#   Output:  parquet-external/databasesvaerovervaegt/part-0.parquet
#            (read via arrow::open_dataset() in extract_outcomes_covariates.R)
# ============================================================================

library(haven)      # read_sas()
library(arrow)      # write_parquet()
library(dplyr)
library(lubridate)

path_sas              <- "E:/rawdata/708421/Eksterne data/dfr_2025_10_31.sas7bdat"
path_dbso_folder <- "E:/workdata/708421/cleaned-data/parquet-external/databasesvaerovervaegt"
path_output      <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets"  # own processed datasets

# ============================================================================
# PHASE 1: INSPECT — run this first to confirm which table is in the SAS file
# ============================================================================

inspect_dbso <- function() {
  cat("Reading SAS file...\n")
  raw <- read_sas(path_sas)

  cat("\nDimensions:", nrow(raw), "rows x", ncol(raw), "columns\n")

  cat("\nAll column names (lowercased):\n")
  print(tolower(names(raw)))

  cat("\nColumn types:\n")
  print(sapply(raw, class))

  cat("\nFirst 3 rows (all columns):\n")
  print(as.data.frame(head(raw, 3)))

  invisible(raw)
}

# Run Phase 1:
# raw_dbso <- inspect_dbso()


# ============================================================================
# PHASE 1b: EXPLORE — answer structural questions about the data
# ============================================================================
# Call with the raw object from inspect_dbso(), or load fresh:
#   raw <- read_sas(path_sas) %>% rename_with(tolower)
#   explore_dbso(raw)
#
# Questions answered:
#   1. Is this DFR_population or DFR_MWL_population?
#   2. How many rows per person (is it really long/multiple visits)?
#   3. Surgery type: GastricBypass_prim / GastricSleeve_prim / ReDo_prim — valid values?
#   4. FUMellem6mdr1aar and FUMellem1_5aar2_5aar — are they 0/1 flags?
#   5. Id_FUnaermest2aar — is it a 0/1 flag or a row ID?
#   6. DatoFOL - DatoPER_prim: follow-up time distribution
#   7. Udgangsvaegt vs UdgangsvaegtPRE_prim weight distributions
# ============================================================================

explore_dbso <- function(raw) {

  cat("=== WHICH TABLE IS THIS? ===\n")
  dfr_pop_cols     <- c("datoper_prim", "gastricbypass_prim", "gastricsleeve_prim", "vaegtfol", "datofol")
  dfr_mwl_cols     <- c("mwlopr_dato", "mwl_prockode_1", "mwl_genind_1_30d")
  cat("DFR_population key columns present:", sum(dfr_pop_cols %in% names(raw)), "/", length(dfr_pop_cols), "\n")
  cat("DFR_MWL_population key columns present:", sum(dfr_mwl_cols %in% names(raw)), "/", length(dfr_mwl_cols), "\n")

  cat("\n=== ROW STRUCTURE ===\n")
  cat("Total rows:", nrow(raw), "\n")
  n_pnr <- n_distinct(raw$cpr)
  cat("Unique CPR:", n_pnr, "\n")
  cat("Avg rows per person:", round(nrow(raw) / n_pnr, 1), "\n")
  cat("Rows per person (counts):\n")
  print(table(table(raw$cpr)))

  cat("\n=== SURGERY TYPE FLAGS (primære operation) ===\n")
  cat("GastricBypass_prim:\n"); print(table(raw$gastricbypass_prim, useNA = "always"))
  cat("GastricSleeve_prim:\n"); print(table(raw$gastricsleeve_prim, useNA = "always"))
  cat("ReDo_prim:\n");          print(table(raw$redo_prim,          useNA = "always"))
  cat("Combinations (bypass / sleeve / redo):\n")
  print(table(paste(raw$gastricbypass_prim, raw$gastricsleeve_prim, raw$redo_prim), useNA = "always"))

  cat("\n=== FOLLOW-UP WINDOW FLAGS ===\n")
  cat("FUMellem6mdr1aar (FU between 6mdr and 1.5yr):\n")
  print(table(raw$fumellem6mdr1aar, useNA = "always"))
  cat("FUMellem1_5aar2_5aar (FU between 1.5yr and 2.5yr):\n")
  print(table(raw$fumellem1_5aar2_5aar, useNA = "always"))

  cat("\n=== 2-YEAR FU IDENTIFIER ===\n")
  cat("Id_FUnaermest2aar — first 20 unique values:\n")
  print(head(unique(raw$id_funaermest2aar), 20))
  cat("Range:", range(raw$id_funaermest2aar, na.rm = TRUE), "\n")

  cat("\n=== DATE RANGES ===\n")
  cat("DatoPER_prim (surgery date):", format(range(as.Date(raw$datoper_prim), na.rm = TRUE)), "\n")
  cat("DatoPRE:                    ", format(range(as.Date(raw$datopre),      na.rm = TRUE)), "\n")
  cat("DatoFOL:                    ", format(range(as.Date(raw$datofol),      na.rm = TRUE)), "\n")

  cat("\n=== FOLLOW-UP TIME FROM SURGERY (DatoFOL - DatoPER_prim) ===\n")
  days_fu <- as.numeric(as.Date(raw$datofol) - as.Date(raw$datoper_prim))
  cat("Summary (for rows where DatoFOL is not NA):\n")
  print(summary(days_fu[!is.na(days_fu)]))
  cat("Approximate distribution by time window:\n")
  print(table(cut(days_fu / 365.25,
                  breaks = c(-Inf, 0, 0.5, 1, 1.5, 2, 2.5, 3, 5, Inf),
                  labels = c("<0", "0-6m", "6m-1yr", "1-1.5yr", "1.5-2yr", "2-2.5yr", "2.5-3yr", "3-5yr", ">5yr"),
                  right  = FALSE),
             useNA = "always"))

  cat("\n=== WEIGHT COLUMNS ===\n")
  cat("Udgangsvaegt (referral/program-entry weight?):\n")
  print(summary(raw$udgangsvaegt))
  cat("UdgangsvaegtPRE_prim (pre-surgery weight, from last pre-op form):\n")
  print(summary(raw$udgangsvaegtpre_prim))
  cat("VaegtPER_prim (peri-op weight at surgery):\n")
  print(summary(raw$vaegtper_prim))
  cat("VaegtFOL (weight at follow-up visit):\n")
  print(summary(raw$vaegtfol))
  cat("Hoejde (height, cm):\n")
  print(summary(raw$hoejde))

  invisible(raw)
}

# Run Phase 1b (requires raw from Phase 1 or reload):
# raw <- read_sas(path_sas) %>% rename_with(tolower)
# explore_dbso(raw)


# ============================================================================
# PHASE 2: CLEAN AND SAVE AS PARQUET
# ============================================================================
# Run AFTER Phase 1 confirms these column names are correct.
#
# Column mapping (after rename_with(tolower)):
#   Patient ID:    cpr            (CPR)
#   Surgery date:  datoper_prim   (DatoPER_prim — date of primary bariatric operation)
#   Surgery type:  derived from   gastricbypass_prim / gastricsleeve_prim / redo_prim (binary flags)
#   Pre-op date:   datopre        (DatoPRE)
#   Follow-up date:datofol        (DatoFOL)
#   Referral wt:   udgangsvaegt   (Udgangsvaegt — weight at program entry)
#   Pre-surg wt:   udgangsvaegtpre_prim (UdgangsvaegtPRE_prim — weight at last pre-op visit)
#   Surgery wt:    vaegtper_prim  (VaegtPER_prim — weight on surgery day)
#   Follow-up wt:  vaegtfol       (VaegtFOL — weight at follow-up visit)
#   Height:        hoejde         (Hoejde — height in cm)
#   BMI:           not in DBSO — calculated from weight / (height_m)^2
#
# Output is LONG FORMAT: one row per clinic visit per patient.
# Downstream extract_weight_outcomes() filters by follow-up window flags.
# ============================================================================

prepare_dbso <- function() {
  cat("Reading SAS file...\n")
  raw <- read_sas(path_sas) %>%
    rename_with(tolower)

  cat("Columns found:\n"); print(names(raw))

  # Fix types and add derived columns; keep ALL columns (parquet is cheap,
  # SAS re-reads are slow, and we don't yet know which columns we'll need).
  dbso_clean <- raw %>%
    mutate(
      pnr          = as.character(cpr),
      surgery_date = as.Date(datoper_prim),
      # Derive surgery type from binary flags; RYGB and SG are mutually exclusive at index op
      surgery_type = case_when(
        gastricbypass_prim == 1 ~ "RYGB",
        gastricsleeve_prim == 1 ~ "SG",
        redo_prim == 1          ~ "ReDo",
        TRUE                    ~ "Unknown"
      ),
      datopre = as.Date(datopre),
      datofol = as.Date(datofol),
      # BMI at pre-surgery (reference BMI for weight outcomes); no BMI column in DBSO
      bmi_pre = dplyr::if_else(
        !is.na(udgangsvaegtpre_prim) & !is.na(hoejde) & hoejde > 0,
        round(udgangsvaegtpre_prim / (hoejde / 100)^2, 1),
        NA_real_
      )
    ) %>%
    filter(!is.na(pnr))

  cat("\nRows after cleaning:", nrow(dbso_clean), "\n")
  cat("Unique patients:", n_distinct(dbso_clean$pnr), "\n")
  cat("Surgery date range:", format(range(dbso_clean$surgery_date, na.rm = TRUE)), "\n")
  cat("Surgery type distribution:\n"); print(table(dbso_clean$surgery_type, useNA = "always"))
  cat("Pre-surgery BMI range:", range(dbso_clean$bmi_pre, na.rm = TRUE), "\n")

  # Save as part-0.parquet inside the folder — Arrow open_dataset() convention.
  dir.create(path_dbso_folder, recursive = TRUE, showWarnings = FALSE)
  out_path <- file.path(path_dbso_folder, "part-0.parquet")
  write_parquet(dbso_clean, out_path)
  cat("\nSaved:", out_path, "\n")

  invisible(dbso_clean)
}

# Run Phase 2 AFTER confirming column names from Phase 1 / 1b:
# dbso <- prepare_dbso()
