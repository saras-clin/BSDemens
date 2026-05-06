# ============================================================================
# PIPELINE STEP 3 of 5 — 03_extract_ses.R
# ============================================================================
# WHAT IS EACH PERSON'S SOCIAL POSITION?
#   Extracts socioeconomic variables for all cohort members following SEPLINE
#   guidelines (Hjorth et al., Clin Epidemiol 2025;17:593-624).
#   Can run in parallel with 02_extract_outcomes_covariates.R — both read
#   full_cohort.rds independently and write their own output files.
#
#   Variables extracted:
#     Education    — highest attained (UDDA/hfaudd), most recent record
#                    up to the year before surgery
#     Income       — equivalised household disposable income (FAIK via
#                    BEF family link), year before surgery
#     Occupation   — labour market status (AKM/socio13), year before surgery
#     SEP category — composite (High / Medium / Low / Unknown)
#
#   Reference year: year(surgery_date) - 1  (year before surgery/index date)
#
#   Inputs:  datasets/full_cohort.rds (from 01_build_cohorts.R)
#            load_database("udda")  — education register (pnr, hfaudd, aar)
#            load_database("faik")  — household income register (familie_id,
#                                     famaekvivadisp_13, aar)
#            load_database("bef")   — population register for familie_id link
#            load_database("akm")   — employment/labour market register
#                                     (pnr, socio13, aar)
#
#   Output:  datasets/ses_data.rds
# ============================================================================

# Packages ----
library(dstDataPrep)   # load_database() - pre-installed on DST, must be built first
library(arrow)
library(dplyr)
library(lubridate)
library(heaven)        # exposureMatch(), edu_code, charlsonIndex(), etc.
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
# 3.0 MAIN SES EXTRACTION FUNCTION
# ============================================================================
# Input:  full_cohort (pnr + surgery_date for all cohort members)
# Output: one row per person with education_cat, income_cat, occupation_cat,
#         sep_category, plus raw register codes (hfaudd, famaekvivadisp_13, socio13)
#
# Internal sections:
#   3.1 Education (UDDA / HFAUDD)
#   3.2 Household income (FAIK / FAMAEKVIVADISP_13)
#   3.3 Occupation (AKM / SOCIO13)
#   3.4 Composite SEP category

extract_ses <- function(bs_cohort) {
  # Add baseline year (year before surgery)
  cohort_years <- bs_cohort %>%
    dplyr::mutate(index_year = lubridate::year(surgery_date) - 1L) %>%
    dplyr::select(pnr, index_year)

  unique_years <- unique(cohort_years$index_year)
  pnrs         <- unique(cohort_years$pnr)

  # --------------------------------------------------------------------------
  # 3.1 Education: HFAUDD from UDDA
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
    dplyr::select(pnr, aar, hfaudd) %>%  # pull only needed columns; reduce data before collect
    dplyr::collect() %>%                  # bring filtered UDDA records into R memory
    dplyr::inner_join(cohort_years, by = "pnr") %>%  # attach each person's index_year so we can apply person-level cutoffs
    dplyr::filter(aar <= index_year) %>%  # keep only records at or before each person's index year
    dplyr::group_by(pnr) %>%             # group to get one record per person
    dplyr::arrange(dplyr::desc(aar)) %>%  # most recent year first so slice picks it
    dplyr::slice(1) %>%                   # most recent education record up to index year
    dplyr::ungroup() %>%                  # release grouping after slice
    dplyr::mutate(
      edu_level = substr(as.character(hfaudd), 1, 2),  # first 2 digits of HFAUDD determine ISCED category
      education_cat = dplyr::case_when(
        edu_level %in% c("10", "15")                         ~ "Short",
        edu_level %in% c("20", "30", "35")                   ~ "Medium",
        edu_level %in% c("40", "50", "60", "70", "80")       ~ "Long",
        edu_level %in% c("90") | is.na(hfaudd)               ~ "Unknown",
        TRUE                                                  ~ "Unknown"
      )
    ) %>%
    dplyr::select(pnr, hfaudd, education_cat)   # keep pnr, raw HFAUDD code for reference, and derived category

  # --------------------------------------------------------------------------
  # 3.2 Household income: FAMAEKVIVADISP_13 from FAIK, linked via FAMILIE_ID in BEF
  # Income quintile per SEPLINE Table 9:
  #   Q1          -> Low
  #   Q2, Q3, Q4  -> Medium
  #   Q5          -> High
  # Note: SEPLINE recommends age/sex standardized quintiles within the general
  # population. Here we use within-cohort quintiles as a pragmatic simplification.
  # --------------------------------------------------------------------------
  bef  <- load_database("bef")  %>% rename_with(tolower)   # open BEF lazily; needed for familie_id link to FAIK
  faik <- load_database("faik") %>% rename_with(tolower)   # open FAIK lazily; household income register

  bef_family <- bef %>%
    dplyr::filter(
      pnr %in% !!pnrs,           # restrict to cohort members only
      aar %in% !!unique_years     # only the years matching our index years; BEF is annual
    ) %>%
    dplyr::select(pnr, aar, familie_id) %>%   # familie_id links person (BEF) to household (FAIK)
    dplyr::collect()                           # pull into memory; BEF is large, filter pushed to parquet first

  faik_income <- faik %>%
    dplyr::filter(aar %in% !!unique_years) %>%              # pull FAIK for all families in these years
    dplyr::select(familie_id, aar, famaekvivadisp_13) %>%  # equivalised disposable household income column
    dplyr::collect()                                         # pull into memory; join to BEF families after collect

  income <- bef_family %>%
    dplyr::inner_join(cohort_years, by = c("pnr", "aar" = "index_year")) %>%  # keep only the record matching each person's index year
    dplyr::left_join(faik_income, by = c("familie_id", "aar")) %>%             # bring in household income; NA if no FAIK record
    dplyr::mutate(
      income_quintile = dplyr::ntile(famaekvivadisp_13, 5),  # within-cohort quintile (1=lowest, 5=highest); see MINOR-1 for pop-reference alternative
      income_cat = dplyr::case_when(
        income_quintile == 1          ~ "Low",
        income_quintile %in% 2:4      ~ "Medium",
        income_quintile == 5          ~ "High",
        TRUE                          ~ "Unknown"   # NA income -> Unknown (no FAIK record or zero income)
      )
    ) %>%
    dplyr::select(pnr, famaekvivadisp_13, income_quintile, income_cat)   # keep raw income and quintile alongside category

  # --------------------------------------------------------------------------
  # 3.3 Occupation: SOCIO13 from AKM
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
  akm <- load_database("akm") %>% rename_with(tolower)   # open AKM (employment/labour market register) lazily

  occupation <- akm %>%
    dplyr::filter(
      pnr %in% !!pnrs,            # restrict to cohort members only
      aar %in% !!unique_years      # only the years matching our index years; AKM is annual
    ) %>%
    dplyr::select(pnr, aar, socio13) %>%   # socio13 = socioeconomic classification code
    dplyr::collect() %>%                    # pull filtered data into memory
    dplyr::inner_join(cohort_years, by = c("pnr", "aar" = "index_year")) %>%  # keep only the record matching each person's index year
    dplyr::mutate(
      socio13_num = as.integer(socio13),   # coerce to integer so range comparisons in case_when work safely
      occupation_cat = dplyr::case_when(
        socio13_num %in% c(110:114, 120, 131:135, 139) ~ "Working",
        socio13_num == 310                              ~ "Student",
        socio13_num %in% c(210, 410)                   ~ "Unemployed",
        socio13_num %in% c(220, 321, 330)              ~ "Outside_workforce",
        socio13_num %in% c(322, 323)                   ~ "Retired",
        TRUE                                           ~ "Unknown"   # 0, 420, or missing = children/unknown
      )
    ) %>%
    dplyr::select(pnr, socio13, occupation_cat)   # keep raw code alongside category

  # --------------------------------------------------------------------------
  # 3.4 Combine and compute composite SEP category
  # Simple composite: Low if any dimension Low, High if all dimensions High
  # --------------------------------------------------------------------------
  cohort_years %>%                                           # start from all cohort members (pnr + index_year)
    dplyr::left_join(education,  by = "pnr") %>%            # left so persons with no UDDA record get NA -> Unknown
    dplyr::left_join(income,     by = "pnr") %>%            # left so persons with no FAIK record get NA -> Unknown
    dplyr::left_join(occupation, by = "pnr") %>%            # left so persons with no AKM record get NA -> Unknown
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
      hfaudd, education_cat,              # raw HFAUDD code and derived education category
      famaekvivadisp_13, income_quintile, income_cat,   # raw income, quintile rank, and category
      socio13, occupation_cat,            # raw SOCIO13 code and derived occupation category
      sep_category                        # composite SEP summary (High / Medium / Low / Unknown)
    )
}

# ============================================================================
# 3.5 MAIN: RUN AND SAVE
# ============================================================================

main_ses_extraction <- function() {
  bs_cohort <- load_full_cohort()                                              # loads full_cohort.rds (all three cohort groups: BS, GP, Obesity)
  ses_data  <- extract_ses(bs_cohort)                                          # runs education, income, and occupation extractions; combines into one data frame
  dir.create(path_output, showWarnings = FALSE, recursive = TRUE)              # create output directory if it does not already exist
  saveRDS(ses_data, file.path(path_output, "ses_data.rds"))                    # write results to disk; loaded by 04_data_management_dementia.R
  invisible(ses_data)                                                          # return silently; caller can capture result if needed
}

# Run:
# ses_results <- main_ses_extraction()
