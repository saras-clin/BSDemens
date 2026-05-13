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
#                    BEF family link), 3-year average (surgery_year-1, -2, -3);
#                    population-standardised quintiles by sex x 5-yr age group x year
#     Occupation   — labour market status (AKM/socio13), year before surgery
#     No composite SEP variable — per SEPLINE (Hjorth et al. 2025)
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
library(tidyr)         # pivot_longer() used in 3-year income window construction
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
#         plus raw register codes (hfaudd, famaekvivadisp_13, income_quintile, socio13)
#         No composite sep_category — per SEPLINE (Hjorth et al. 2025)
#
# Internal sections:
#   3.1 Education (UDDA / HFAUDD)
#   3.2 Household income (FAIK / FAMAEKVIVADISP_13) — population-standardised quintiles
#   3.3 Occupation (AKM / SOCIO13)
#   3.4 Combine (no composite)

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
  #
  # SEPLINE (Hjorth et al. 2025) Table 9 specifies:
  #   (a) 3-year average income: average over surgery_year-1, surgery_year-2,
  #       surgery_year-3 to reduce year-to-year volatility.
  #       In code: index_year, index_year-1, index_year-2 (since index_year = surgery_year-1).
  #   (b) Population-standardized quintile cutpoints: quintile boundaries computed
  #       in the GENERAL POPULATION (all BEF persons), stratified by 5-year age
  #       group AND sex for the reference year (= index_year = surgery_year-1).
  #       This prevents cohort-level income distribution from distorting the
  #       quintile thresholds (BS patients are not representative of the full
  #       age-sex-matched general population income distribution).
  #   (c) Quintile assignment: Q1 -> Low, Q2-Q4 -> Medium, Q5 -> High.
  #
  # Statistics Denmark does NOT publish pre-computed quintile cutpoints by
  # age-group x sex x year. We compute them from the full BEF x FAIK population.
  #
  # IMPLEMENTATION STEPS:
  #   Step A: For COHORT MEMBERS — compute their 3-year average income
  #           (surgery_year-1, -2, -3 per person).
  #   Step B: For the GENERAL POPULATION — compute population quintile cutpoints
  #           (Q20/Q40/Q60/Q80) by sex x 5-year age group x reference year.
  #   Step C: Assign each cohort member to a quintile using population cutpoints
  #           for their sex, age group, and reference year.
  # --------------------------------------------------------------------------

  bef  <- load_database("bef")  %>% rename_with(tolower)   # population register: pnr, aar, koen, foed_dag, familie_id
  faik <- load_database("faik") %>% rename_with(tolower)   # household income register: familie_id, aar, famaekvivadisp_13

  # index_year = surgery_year - 1 (the SEP reference year, same as education and occupation).
  # The 3-year average uses years: index_year, index_year-1, index_year-2
  # (= surgery_year-1, surgery_year-2, surgery_year-3 per the methods plan).
  # The population quintile reference year = index_year (= surgery_year-1),
  # consistent with all other SEP measures. Age for population stratification
  # is computed at index_year.
  income_ref_years <- sort(unique(c(unique_years, unique_years - 1L, unique_years - 2L)))        # income years: surgery_year-1, -2, -3

  # -- Step A: cohort member income for all 3 reference years --
  # Pull FAIK for cohort members over the 3 reference years (lazy filter on parquet).
  # BEF needed for familie_id link and age/sex (used later for population quintiles).
  bef_cohort <- bef %>%
    dplyr::filter(pnr %in% !!pnrs, aar %in% !!income_ref_years) %>%    # cohort members in reference years
    dplyr::select(pnr, aar, koen, foed_dag, familie_id) %>%
    dplyr::collect()                                                      # BEF is large; filter pushed to parquet first

  faik_cohort_ref <- faik %>%
    dplyr::filter(aar %in% !!income_ref_years) %>%                        # families in surgery_year-1, -2, -3 for cohort 3yr average
    dplyr::select(familie_id, aar, famaekvivadisp_13) %>%
    dplyr::collect()                                                        # collected once; reused across all cohort members' income calculations

  # Join BEF <-> FAIK for cohort members; then join cohort_years to restrict to each
  # person's 3 income years (index_year, index_year-1, index_year-2).
  cohort_ref_lookup <- cohort_years %>%                                    # pnr + index_year
    dplyr::mutate(                                                          # expand to 3 income years per person
      yr1 = index_year,                                                     # surgery_year - 1 = index_year itself
      yr2 = index_year - 1L,                                               # surgery_year - 2
      yr3 = index_year - 2L                                                # surgery_year - 3
    ) %>%
    tidyr::pivot_longer(cols = c(yr1, yr2, yr3),                           # one row per (pnr, income year)
                        names_to = NULL, values_to = "ref_year")

  cohort_3yr_income <- bef_cohort %>%
    dplyr::inner_join(cohort_ref_lookup, by = c("pnr", "aar" = "ref_year")) %>%  # restrict to each person's 3 reference years
    dplyr::left_join(faik_cohort_ref, by = c("familie_id", "aar")) %>%           # attach household income for that year
    dplyr::group_by(pnr, index_year) %>%                                          # average across the 3 years per person
    dplyr::summarise(
      income_3yr_avg = mean(famaekvivadisp_13, na.rm = TRUE),              # 3-year average equivalised disposable income
      koen_ref       = dplyr::first(koen),                                  # sex (for quintile stratum lookup)
      age_ref        = dplyr::first(index_year) -                            # age at index_year (= surgery_year - 1) for stratum lookup
                       lubridate::year(as.Date(dplyr::first(foed_dag))),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      income_3yr_avg = dplyr::if_else(is.nan(income_3yr_avg), NA_real_, income_3yr_avg),  # nan -> NA if all 3 years missing
      age_group5     = floor(age_ref / 5L) * 5L                             # 5-year age group lower bound (e.g. 45 = ages 45-49)
    )

  # -- Step B: population quintile cutpoints --
  # Use the FULL BEF population for each reference year (not just cohort members).
  # We compute the quintile cutpoints (the 20th, 40th, 60th, 80th percentile boundaries)
  # for each sex x 5-year age group x year stratum, then use these to assign quintiles
  # to cohort members. Using population cutpoints instead of within-cohort boundaries
  # ensures quintile assignment is not affected by the cohort's non-representative
  # income distribution (bariatric surgery patients skew younger and more female
  # compared to the age-sex-matched general population).
  #
  # Performance note: BEF has ~5M rows per year. For ~15 reference years (2009-2023)
  # this is ~75M rows. Filter to working-age persons (18-90) to reduce memory use.
  pop_income_years <- sort(unique(unique_years))         # index_year = surgery_year - 1; this is the SEP reference year per SEPLINE

  bef_pop <- bef %>%
    dplyr::filter(aar %in% !!pop_income_years) %>%                         # reference years for population quintile computation
    dplyr::select(pnr, aar, koen, foed_dag, familie_id) %>%
    dplyr::collect() %>%                                                    # large pull; filters pushed to parquet first
    dplyr::mutate(
      age_ref    = aar - lubridate::year(as.Date(foed_dag)),
      age_group5 = floor(age_ref / 5L) * 5L
    ) %>%
    dplyr::filter(age_ref >= 18L, age_ref <= 90L)                          # restrict to working/older adults; reduces memory

  faik_pop_ref <- faik %>%
    dplyr::filter(aar %in% !!pop_income_years) %>%
    dplyr::select(familie_id, aar, famaekvivadisp_13) %>%
    dplyr::collect()

  pop_3yr_income <- bef_pop %>%
    dplyr::left_join(faik_pop_ref, by = c("familie_id", "aar"))            # attach household income for the reference year

  # Compute quintile cutpoints (Q20/Q40/Q60/Q80 = breaks between quintiles) for each
  # sex x age_group5 x reference year cell. These four cutpoints define 5 quintile bands.
  pop_quintile_cutpoints <- pop_3yr_income %>%
    dplyr::filter(!is.na(famaekvivadisp_13)) %>%                            # exclude persons without income data from reference distribution
    dplyr::group_by(koen, age_group5, aar) %>%
    dplyr::summarise(
      q20 = stats::quantile(famaekvivadisp_13, 0.20, na.rm = TRUE),        # upper bound of Q1 (20th percentile)
      q40 = stats::quantile(famaekvivadisp_13, 0.40, na.rm = TRUE),        # upper bound of Q2
      q60 = stats::quantile(famaekvivadisp_13, 0.60, na.rm = TRUE),        # upper bound of Q3
      q80 = stats::quantile(famaekvivadisp_13, 0.80, na.rm = TRUE),        # upper bound of Q4; above this = Q5
      .groups = "drop"
    )

  # -- Step C: assign cohort members to population quintile --
  # ref_year = index_year because index_year is already the SEP reference year
  # (= surgery_year - 1) and pop_quintile_cutpoints is keyed on that same year.
  income <- cohort_3yr_income %>%
    dplyr::mutate(ref_year = index_year) %>%                               # index_year = surgery_year - 1 = SEP reference year
    dplyr::left_join(
      pop_quintile_cutpoints,
      by = c("koen_ref" = "koen", "age_group5", "ref_year" = "aar")       # match on sex, age group, reference year
    ) %>%
    dplyr::mutate(
      # Assign quintile by comparing 3-year average income to population cutpoints.
      # income_3yr_avg NA -> quintile NA -> income_cat "Unknown" via case_when.
      income_quintile = dplyr::case_when(
        is.na(income_3yr_avg)         ~ NA_integer_,
        income_3yr_avg <= q20         ~ 1L,
        income_3yr_avg <= q40         ~ 2L,
        income_3yr_avg <= q60         ~ 3L,
        income_3yr_avg <= q80         ~ 4L,
        income_3yr_avg >  q80         ~ 5L
      ),
      income_cat = dplyr::case_when(
        income_quintile == 1          ~ "Low",
        income_quintile %in% 2L:4L   ~ "Medium",
        income_quintile == 5L         ~ "High",
        TRUE                          ~ "Unknown"   # NA income or no FAIK record -> Unknown
      )
    ) %>%
    dplyr::select(pnr, famaekvivadisp_13 = income_3yr_avg, income_quintile, income_cat)   # rename 3yr avg to famaekvivadisp_13 for downstream compatibility

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
  # 3.4 Combine all SEP dimensions — NO composite variable
  # SEPLINE (Hjorth et al., Clin Epidemiol 2025;17:593-624) explicitly does NOT
  # recommend a composite SEP variable. Each dimension captures a distinct aspect
  # of social position and should be entered separately in regression models.
  # A composite conflates three different pathways (material deprivation, social
  # capital, labour-market attachment) into a single scale that has no theoretical
  # justification. The three dimensions are retained as separate columns.
  # --------------------------------------------------------------------------
  cohort_years %>%                                           # start from all cohort members (pnr + index_year)
    dplyr::left_join(education,  by = "pnr") %>%            # left so persons with no UDDA record get NA -> Unknown
    dplyr::left_join(income,     by = "pnr") %>%            # left so persons with no FAIK record get NA -> Unknown
    dplyr::left_join(occupation, by = "pnr") %>%            # left so persons with no AKM record get NA -> Unknown
    dplyr::select(
      pnr, index_year,
      hfaudd, education_cat,                               # raw HFAUDD code and derived education category
      famaekvivadisp_13, income_quintile, income_cat,      # raw income, quintile rank, and category
      socio13, occupation_cat                              # raw SOCIO13 code and derived occupation category
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
