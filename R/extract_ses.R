# ============================================================================
# PIPELINE STEP 3 of 5 — extract_ses.R
# ============================================================================
# WHAT IS EACH PERSON'S SOCIAL POSITION?
#   Extracts socioeconomic variables for all cohort members. Run in parallel with
#   extract_outcomes_covariates.R (both read full_cohort.rds, both write independently).
#   Following SEPLINE guidelines (Hjorth et al., Clin Epidemiol 2025).
#
#   Education    — highest education (UDDA/hfaudd), most recent record up to index year
#   Income       — equivalised household disposable income (FAIK via BEF family link)
#   Occupation   — labour market status (AKM/socio13) at index year
#   SEP category — composite: High / Medium / Low / Unknown
#
#   Reference year: year(surgery_date) - 1  (year before surgery/index date)
#   Output: datasets/ses_data.rds
# ============================================================================
# SOCIOECONOMIC STATUS (SES) EXTRACTION
# ============================================================================
# Based on SEPLINE guidelines:
# Hjorth CF et al. "SEPLINE: Socioeconomic Position in Epidemiological Research —
# A National Guideline on Danish Registry Data." Clin Epidemiol. 2025;17:593-624.
# https://www.dovepress.com/sepline-socioeconomic-position-in-epidemiological-researcha-national-g-peer-reviewed-fulltext-article-CLEP
#
# DST parquet folders used:
#   udda  - education register (pnr, hfaudd, aar)
#   faik  - family income register (familie_id, famaekvivadisp_13, aar)
#   bef   - population register for familie_id linkage (pnr, familie_id, aar)
#   akm   - employment classification (pnr, socio13, aar)
#
# All variables use year = year(surgery_date) - 1 as the baseline reference year.
# ============================================================================

# Packages ----
library(dstDataPrep)   # load_database() - pre-installed on DST, must be built first
library(arrow)
library(dplyr)
library(lubridate)
# On DST: update duckplyr if needed - old pre-installed version has limited functionality
# install.packages("duckplyr")

# Paths ----
path_output      <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets"
path_full_cohort <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets/full_cohort.rds"

load_full_cohort <- function() {
  readRDS(path_full_cohort) %>%
    rename(surgery_date = index_date)
}

# ============================================================================
# MAIN SES EXTRACTION
# ============================================================================

extract_ses <- function(bs_cohort) {
  # Add baseline year (year before surgery)
  cohort_years <- bs_cohort %>%
    dplyr::mutate(index_year = lubridate::year(surgery_date) - 1L) %>%
    dplyr::select(pnr, index_year)

  unique_years <- unique(cohort_years$index_year)
  pnrs         <- unique(cohort_years$pnr)

  # --------------------------------------------------------------------------
  # Education: HFAUDD from UDDA
  # HFAUDD codes (first 2 characters determine education level per SEPLINE Table 3):
  #   "10" = Primary/lower secondary (ISCED 1-2)     -> Short
  #   "15" = Preparatory basic education             -> Short
  #   "20" = General upper secondary (STX, HF, HTX)  -> Medium
  #   "30" = Vocational education (EUD)              -> Medium
  #   "35" = Programs qualifying for admission        -> Medium
  #   "40" = Academy profession programs (AK)         -> Long
  #   "50" = Professional bachelor's programs         -> Long
  #   "60" = Bachelor's programs                      -> Long
  #   "70" = Master's programs                        -> Long
  #   "80" = PhD programs                             -> Long
  #   "90" = Unknown/imputed/missing                  -> Unknown
  # --------------------------------------------------------------------------
  udda <- load_database("udda") %>% rename_with(tolower)

  # [FIX] UDDA is an event-based register — a row appears only when a person's highest
  # education changes. Filtering aar == index_year misses persons whose last education
  # event was before the index year (e.g. completed university in 2005, surgery in 2018).
  # Fix: take the most recent record up to and including the index year (aar <= index_year).
  max_index_year <- max(unique_years)   # pull all records up to the latest surgery year

  education <- udda %>%
    dplyr::filter(
      pnr %in% !!pnrs,
      aar <= !!max_index_year            # include all historical records up to study end
    ) %>%
    dplyr::select(pnr, aar, hfaudd) %>%
    dplyr::collect() %>%
    dplyr::inner_join(cohort_years, by = "pnr") %>%
    dplyr::filter(aar <= index_year) %>%  # keep only records at or before each person's index year
    dplyr::group_by(pnr) %>%
    dplyr::arrange(dplyr::desc(aar)) %>%
    dplyr::slice(1) %>%                   # most recent education record up to index year
    dplyr::ungroup() %>%
    dplyr::mutate(
      edu_level = substr(as.character(hfaudd), 1, 2),
      education_cat = dplyr::case_when(
        edu_level %in% c("10", "15")                         ~ "Short",
        edu_level %in% c("20", "30", "35")                   ~ "Medium",
        edu_level %in% c("40", "50", "60", "70", "80")       ~ "Long",
        edu_level %in% c("90") | is.na(hfaudd)               ~ "Unknown",
        TRUE                                                  ~ "Unknown"
      )
    ) %>%
    dplyr::select(pnr, hfaudd, education_cat)

  # --------------------------------------------------------------------------
  # Household income: FAMAEKVIVADISP_13 from FAIK, linked via FAMILIE_ID in BEF
  # Income quintile per SEPLINE Table 9:
  #   Q1          -> Low
  #   Q2, Q3, Q4  -> Medium
  #   Q5          -> High
  # Note: SEPLINE recommends age/sex standardized quintiles within the general
  # population. Here we use within-cohort quintiles as a pragmatic simplification.
  # --------------------------------------------------------------------------
  bef  <- load_database("bef")  %>% rename_with(tolower)
  faik <- load_database("faik") %>% rename_with(tolower)

  bef_family <- bef %>%
    dplyr::filter(
      pnr %in% !!pnrs,
      aar %in% !!unique_years
    ) %>%
    dplyr::select(pnr, aar, familie_id) %>%
    dplyr::collect()

  faik_income <- faik %>%
    dplyr::filter(aar %in% !!unique_years) %>%
    dplyr::select(familie_id, aar, famaekvivadisp_13) %>%
    dplyr::collect()

  income <- bef_family %>%
    dplyr::inner_join(cohort_years, by = c("pnr", "aar" = "index_year")) %>%
    dplyr::left_join(faik_income, by = c("familie_id", "aar")) %>%
    dplyr::mutate(
      income_quintile = dplyr::ntile(famaekvivadisp_13, 5),
      income_cat = dplyr::case_when(
        income_quintile == 1          ~ "Low",
        income_quintile %in% 2:4      ~ "Medium",
        income_quintile == 5          ~ "High",
        TRUE                          ~ "Unknown"
      )
    ) %>%
    dplyr::select(pnr, famaekvivadisp_13, income_quintile, income_cat)

  # --------------------------------------------------------------------------
  # Occupation: SOCIO13 from AKM
  # SOCIO13 numeric codes per SEPLINE Table 6:
  #   110-114, 120          = Self-employed             -> Working
  #   131, 132              = Manager/high-level        -> Working
  #   133-135, 139          = Employee                  -> Working
  #   310                   = Student                   -> Student
  #   210, 410              = Unemployed                -> Unemployed
  #   220                   = Sick/other leave          -> Outside_workforce
  #   321                   = Disability pension        -> Outside_workforce
  #   330                   = Social security/flex job  -> Outside_workforce
  #   322                   = Post-employment pension   -> Retired
  #   323                   = Age retirement pension    -> Retired
  #   0, 420, missing       = Children/unknown          -> Unknown
  # --------------------------------------------------------------------------
  akm <- load_database("akm") %>% rename_with(tolower)

  occupation <- akm %>%
    dplyr::filter(
      pnr %in% !!pnrs,
      aar %in% !!unique_years
    ) %>%
    dplyr::select(pnr, aar, socio13) %>%
    dplyr::collect() %>%
    dplyr::inner_join(cohort_years, by = c("pnr", "aar" = "index_year")) %>%
    dplyr::mutate(
      socio13_num = as.integer(socio13),
      occupation_cat = dplyr::case_when(
        socio13_num %in% c(110:114, 120, 131:135, 139) ~ "Working",
        socio13_num == 310                              ~ "Student",
        socio13_num %in% c(210, 410)                   ~ "Unemployed",
        socio13_num %in% c(220, 321, 330)              ~ "Outside_workforce",
        socio13_num %in% c(322, 323)                   ~ "Retired",
        TRUE                                           ~ "Unknown"
      )
    ) %>%
    dplyr::select(pnr, socio13, occupation_cat)

  # --------------------------------------------------------------------------
  # Combine and compute composite SEP score
  # Simple composite: Low if any dimension Low, High if all dimensions High
  # --------------------------------------------------------------------------
  cohort_years %>%
    dplyr::left_join(education,  by = "pnr") %>%
    dplyr::left_join(income,     by = "pnr") %>%
    dplyr::left_join(occupation, by = "pnr") %>%
    dplyr::mutate(
      # [FIX] Unknown logic was too strict: previously required ALL THREE dimensions to be
      # Unknown. A person with Unknown education + Medium income + Working occupation was
      # classified "Medium" even though their SEP cannot be reliably determined.
      # New logic (ordered priority):
      #   1. High:    all three clearly high signals (requires complete data)
      #   2. Low:     any one clearly low signal — even with missing dimensions, known
      #               deprivation in one domain is informative
      #   3. Unknown: any remaining dimension is Unknown (low signal didn't fire, so we
      #               can't confidently classify)
      #   4. Medium:  all dimensions known and no High/Low signal
      sep_category = dplyr::case_when(
        education_cat == "Long"   & income_cat == "High" & occupation_cat == "Working"    ~ "High",
        education_cat == "Short"  | income_cat == "Low"  | occupation_cat == "Unemployed" ~ "Low",
        education_cat == "Unknown" | income_cat == "Unknown" | occupation_cat == "Unknown" ~ "Unknown",
        TRUE ~ "Medium"
      )
    ) %>%
    dplyr::select(
      pnr, index_year,
      hfaudd, education_cat,
      famaekvivadisp_13, income_quintile, income_cat,
      socio13, occupation_cat,
      sep_category
    )
}

# ============================================================================
# MAIN
# ============================================================================

main_ses_extraction <- function() {
  bs_cohort <- load_full_cohort()
  ses_data  <- extract_ses(bs_cohort)
  dir.create(path_output, showWarnings = FALSE, recursive = TRUE)
  saveRDS(ses_data, file.path(path_output, "ses_data.rds"))
  invisible(ses_data)
}

# Run:
# ses_results <- main_ses_extraction()
