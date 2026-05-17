# ============================================================================
# SEPLINE — Socioeconomic Position in Danish Register-Based Epidemiology
# ============================================================================
# Based on https://doi.org/10.2147/CLEP.S520772
# ============================================================================
# HOW TO USE THIS SCRIPT
# ============================================================================
#
#   PROJECT
#     Pre-specified for DST project 708421 (DARTER).
#     Colleagues on other DST projects: update path_output and path_cohort
#     in Section 0. If load_database() is unavailable, replace each call with
#     arrow::open_dataset() pointing to the register paths listed in Section 0.
#
#   STEP 1 — Change the two paths in Section 0 (search for "CHANGE THIS"):
#              path_output  : folder where ses_data.rds will be saved
#              path_cohort  : full path to your cohort .rds file
#
#   STEP 2 — Make sure your cohort file has these two columns:
#              pnr          : encrypted CPR number (person identifier)
#              index_date   : Date class — surgery/diagnosis/recruitment date
#             (See Section 1 for details)
#
#   STEP 3 — Run the script top to bottom:
#              Source the entire file:  source("help/SEPLINE.R")
#              Or run section by section interactively in RStudio using
#              Ctrl+Enter (Windows) / Cmd+Enter (Mac).
#
#   STEP 4 — The output ses_data.rds is saved to path_output.
#             In your analysis script, load it with:
#               ses <- readRDS(file.path(path_output, "ses_data.rds")) %>%
#                 select(pnr, education_cat, income_cat, occupation_cat)
#               df <- df %>% left_join(ses, by = "pnr")
#
#   WHAT YOU GET:
#     ses_data.rds — one row per person, columns:
#       education_cat    Short / Medium / Long / Unknown
#       income_cat       Low / Medium / High / Unknown
#       occupation_cat   Working / Unemployed / Outside_workforce /
#                        Retired / Student / Unknown
#     Plus raw register codes (hfaudd, famaekvivadisp_13,
#     income_quintile, socio13) retained for audit purposes.
#
#   QUESTIONS / ISSUES:
#     Contact: Sara Schwartz (sarasschwartz@gmail.com)
#     Reference: Hjorth CF et al. Clin Epidemiol. 2025;17:593-624.
#                DOI: 10.2147/CLEP.S464446
#
# ============================================================================
#
# PURPOSE
#   Standalone extraction script for the three SEP dimensions recommended by
#   the SEPLINE guideline for use in Danish register-based cohort studies.
#   Copy this script into your own project and adapt the path and cohort input.
#
# REFERENCE
#   Hjorth CF, Gamst-Jensen H, Fenger-Gron M, et al.
#   Socioeconomic position in epidemiological research: guidance from the
#   SEPLINE Collaborative.
#   Clin Epidemiol. 2025;17:593-624.
#   DOI: 10.2147/CLEP.S464446
#
# WHAT THIS SCRIPT PRODUCES
#   One row per person. Columns:
#     education_cat     — Short / Medium / Long / Unknown
#     income_cat        — Low / Medium / High / Unknown
#     occupation_cat    — Working / Unemployed / Outside_workforce / Retired /
#                         Student / Unknown
#     hfaudd            — raw UDDA education code (keep for audit)
#     famaekvivadisp_13 — raw 3-year average equivalised income (keep for audit)
#     income_quintile   — quintile 1-5 in the population (keep for audit)
#     socio13           — raw AKM occupation code (keep for audit)
#
# KEY SEPLINE DECISIONS IMPLEMENTED HERE
#   (a) Three separate dimensions — do NOT combine into a composite score.
#       Education, income, and occupation each represent a distinct causal
#       pathway. Composites obscure which dimension drives an association
#       and cannot be meaningfully compared across studies.
#   (b) Reference year = calendar year BEFORE the index date (surgery_year - 1).
#       Using the index year itself risks reverse causation: illness leading to
#       surgery can reduce income and employment in the same year.
#   (c) Income: 3-year average (index_year, index_year-1, index_year-2) to
#       reduce year-to-year volatility from e.g. parental leave, short-term
#       unemployment, or one-off financial events.
#   (d) Income quintiles: computed from the FULL Danish population (BEF),
#       stratified by sex x 5-year age group x reference year — not from
#       within-cohort distributions, which are unrepresentative.
#   (e) Education: most recent UDDA record at or before the reference year.
#       UDDA is event-based, not annual — a person who finished their degree in
#       2005 will not appear in UDDA for 2018. Always take the most recent
#       record up to and including the reference year (aar <= index_year).
#
# REGISTERS USED
#   UDDA  — education register (pnr, hfaudd, aar)
#   FAIK  — household income register (familie_id, famaekvivadisp_13, aar)
#   BEF   — population register (pnr, koen, foed_dag, familie_id, aar)
#           needed as a bridge: faik does not contain pnr, only familie_id
#   AKM   — employment/labour market register (pnr, socio13, aar)
#
# HOW TO USE IN COX MODELS
#   In your coxph() call:
#     coxph(Surv(follow_up_days, event) ~
#             exposure +
#             age_at_index + sex +          # or matched on these
#             nmi_score +                   # comorbidity
#             education_cat +               # SEP dimension 1
#             income_cat +                  # SEP dimension 2
#             occupation_cat +              # SEP dimension 3
#             surgery_period,               # calendar period
#           data = df,
#           cluster = matched_pnr)          # adjust for your design
#   Each _cat variable is entered as a separate factor term.
#   Do NOT sum or combine them into a single index.
#
# ============================================================================
# TABLE OF CONTENTS
# -----------------
#   0.  Packages and paths
#   1.  Cohort input — what your input data frame must look like
#   2.  Education (UDDA / HFAUDD)
#       2.1  Load UDDA and filter to cohort
#       2.2  Take most recent record at or before reference year
#       2.3  Categorise HFAUDD into Short / Medium / Long / Unknown
#   3.  Income (FAIK via BEF)
#       3.1  Step A — cohort member 3-year average income
#       3.2  Step B — population quintile cutpoints (sex x age group x year)
#       3.3  Step C — assign cohort members to population quintile
#       3.4  Categorise quintile into Low / Medium / High / Unknown
#   4.  Occupation (AKM / SOCIO13)
#       4.1  Load AKM and filter to cohort reference year
#       4.2  Categorise SOCIO13 into occupation groups
#   5.  Combine all three dimensions — no composite
#   6.  Save output
# ============================================================================


# ============================================================================
# 0. PACKAGES AND PATHS
# ============================================================================

library(dstDataPrep)   # load_database() — DST parquet interface; must be built from source on the DST server
                       # Author:  Luke W. Johnston (lwjohnst86)
                       # Source:  E:/workdata/708421/workspaces/luke/dstDataPrep/dstDataPrep.Rproj
                       # Build:   open dstDataPrep.Rproj in RStudio, then Build > Install Package
                       # Note:    internal DST tool — no public repository or DOI
library(arrow)         # open_dataset() if needed for registers outside load_database
library(dplyr)         # data manipulation throughout
library(tidyr)         # pivot_longer() used in the 3-year income window construction
library(lubridate)     # year(), as.Date() for date handling

# --- Output and cohort paths --- CHANGE THESE TWO LINES FOR YOUR PROJECT ---
# path_output : folder on the DST server where ses_data.rds will be saved.
#               Format: "E:/workdata/<project_id>/workspaces/<YourName>/<Project>/datasets"
# path_cohort : full path to your cohort .rds file (must contain pnr + index_date).
#               If your file lives inside path_output, use file.path() as shown below.

path_output <- "E:/workdata/708421/workspaces/YourName/YourProject/datasets"   # CHANGE THIS: replace YourName/YourProject with your own workspace
path_cohort <- file.path(path_output, "full_cohort.rds")                       # CHANGE THIS: full path to your cohort .rds file

# Catch the most common mistake: forgetting to update the paths above.
if (grepl("YourName", path_output) || grepl("YourName", path_cohort))
  stop(
    "Paths have not been updated. Search for 'CHANGE THIS' in Section 0 ",
    "and replace YourName/YourProject with your own workspace folder."
  )

# --- Register locations on the DST server (project 708421 / DARTER) ---
# The four registers used by this script are accessed via load_database(), which
# reads from the shared parquet-registers folder for this project. You do NOT
# need to set these paths manually — load_database() handles them internally.
# They are listed here for transparency and audit purposes only.
#
#   UDDA  (education):
#     E:/workdata/708421/parquet-registers/udda/
#     Columns used: pnr, aar, hfaudd
#
#   FAIK  (household income):
#     E:/workdata/708421/parquet-registers/faik/
#     Columns used: familie_id, aar, famaekvivadisp_13
#     NOTE: FAIK does not contain pnr — linked via familie_id from BEF
#
#   BEF   (population register — bridge between pnr and familie_id):
#     E:/workdata/708421/parquet-registers/bef/
#     Columns used: pnr, aar, koen, foed_dag, familie_id
#
#   AKM   (employment / labour market):
#     E:/workdata/708421/parquet-registers/akm/
#     Columns used: pnr, aar, socio13
#
# If you are on a different DST project, confirm register access with your
# project manager and verify column names with load_database("udda") etc.


# ============================================================================
# 1. COHORT INPUT — WHAT YOUR DATA FRAME MUST LOOK LIKE
# ============================================================================
# Your cohort data frame must have AT MINIMUM these two columns:
#
#   pnr          — encrypted CPR number (person identifier). Character or numeric.
#                  Never appears as a literal value — only as a column name.
#   index_date   — Date class. The date from which SEP is measured.
#                  Typically: surgery date, diagnosis date, or recruitment date.
#                  SEP reference year = year(index_date) - 1.
#
# Load your cohort here. The example below reads a saved .rds file.
# Replace with however you construct your cohort.

cohort <- readRDS(path_cohort)   # load cohort file; must have columns pnr and index_date

# Input validation: fail immediately with a clear message rather than a cryptic
# arrow or dplyr error deep in the extraction code.
if (!all(c("pnr", "index_date") %in% names(cohort)))
  stop(
    "Cohort is missing required columns. Need: pnr, index_date. ",
    "Found: ", paste(names(cohort), collapse = ", ")
  )
if (!inherits(cohort$index_date, "Date"))
  stop(
    "'index_date' must be Date class. Got: ", class(cohort$index_date)[1], ". ",
    "Convert with: cohort$index_date <- as.Date(cohort$index_date)"
  )

n_dup_pnr <- sum(duplicated(cohort$pnr))   # count pnrs that appear more than once
if (n_dup_pnr > 0)
  warning(
    n_dup_pnr, " duplicate pnr(s) found in cohort. Each person should appear once. ",
    "Duplicates will be handled within each section, but left_joins in Section 5 ",
    "may produce more rows than expected. Check your cohort construction."
  )

# Derive the SEP reference year for each person (one year before index date).
# Using year(index_date) - 1 avoids reverse causation: illness in the same
# year as the index event can depress income and employment status, so we look
# back one year to capture pre-morbid socioeconomic position.
cohort_years <- cohort %>%
  mutate(index_year = year(as.Date(index_date)) - 1L) %>%   # reference year = calendar year before index date
  select(pnr, index_year)                                   # keep only the two columns needed for the joins below

pnrs         <- unique(cohort_years$pnr)          # vector of all cohort pnrs; used to push filters to parquet before collecting
unique_years <- unique(cohort_years$index_year)   # all reference years in the cohort; used to limit register pulls


# ============================================================================
# 2. EDUCATION (UDDA / HFAUDD)
# ============================================================================
# REGISTER: UDDA (uddannelsesregistret)
# KEY COLUMN: hfaudd — highest completed education code (ISCED-based Danish
#             classification). 4-digit code; first 2 digits determine the ISCED
#             level per SEPLINE Table 3.
#
# IMPORTANT: UDDA is EVENT-BASED, not annual.
#   A row only appears in UDDA when a person's highest attained education changes.
#   If someone completed a master's degree in 2003 and you have a surgery in 2018,
#   they will not appear in UDDA for the year 2018. You must take the most recent
#   record at or before the reference year (aar <= index_year), NOT aar == index_year.
#
# HFAUDD CATEGORY MAPPING (SEPLINE Table 3):
#   First 2 digits:
#   "10" = Primary / lower secondary (folkeskole)           -> Short
#   "15" = Preparatory basic education (efg/hge)            -> Short
#   "20" = General upper secondary (STX, HF, HTX, HHX)      -> Medium
#   "30" = Vocational education and training (EUD)          -> Medium
#   "35" = Programs qualifying for higher education entry   -> Medium
#   "40" = Academy profession programs (erhvervsakademi)    -> Long
#   "50" = Professional bachelor's programs (profbachelor)  -> Long
#   "60" = Bachelor's programs (BA/BSc)                     -> Long
#   "70" = Master's programs (kandidat/MA/MSc)              -> Long
#   "80" = PhD programs (forskeruddannelse)                 -> Long
#   "90" = Unknown / not classifiable / missing             -> Unknown
#   NA   = Not in UDDA (likely short education, coded as Unknown for safety)

# 2.1 Load UDDA and filter to cohort
message("Section 2: loading UDDA education register for ", length(pnrs), " cohort members...")
udda <- load_database("udda") %>% rename_with(tolower)   # open UDDA register lazily; lowercase column names

max_index_year <- max(unique_years)   # upper bound for the lazy parquet filter; pulls all records up to the latest reference year in the cohort

edu_raw <- udda %>%
  filter(
    pnr %in% !!pnrs,             # push cohort filter to parquet before collecting (avoids loading all of UDDA)
    aar <= !!max_index_year      # pull all historical records up to the latest reference year; per-person cutoff applied after collect
  ) %>%
  select(pnr, aar, hfaudd) %>%   # only the three columns needed; reduces data transferred from parquet to R
  collect()                      # pull filtered rows into R memory

# 2.2 Take most recent education record at or before each person's reference year
# We join cohort_years to apply the person-specific cutoff (aar <= index_year),
# then take the most recent record (highest aar) per person.
education <- edu_raw %>%
  inner_join(cohort_years, by = "pnr") %>%    # attach each person's reference year for person-level cutoff
  filter(aar <= index_year) %>%               # keep only records at or before this person's reference year
  group_by(pnr) %>%                           # group so slice picks one row per person
  arrange(desc(aar)) %>%                      # sort descending so the most recent record is first
  slice(1) %>%                                # keep only the most recent education record
  ungroup()                                   # release grouping after deduplication

# 2.3 Categorise HFAUDD into Short / Medium / Long / Unknown
education <- education %>%
  mutate(
    edu_level     = substr(as.character(hfaudd), 1, 2),   # extract first two characters of HFAUDD (determines ISCED level)
    education_cat = case_when(
      edu_level %in% c("10", "15")                   ~ "Short",    # primary and lower secondary
      edu_level %in% c("20", "30", "35")             ~ "Medium",   # upper secondary and vocational
      edu_level %in% c("40", "50", "60", "70", "80") ~ "Long",     # higher education (academy to PhD)
      edu_level == "90" | is.na(hfaudd)              ~ "Unknown",  # explicitly unknown or not in register
      TRUE                                            ~ "Unknown"  # catch-all for unrecognised codes
    )
  ) %>%
  select(pnr, hfaudd, education_cat)   # keep pnr, raw code (for audit), and category (for models)


# ============================================================================
# 3. INCOME (FAIK VIA BEF)
# ============================================================================
# REGISTER: FAIK (familieindkomstregistret) linked via BEF (befolkningsregistret)
# KEY COLUMN: famaekvivadisp_13 — equivalised disposable household income.
#   "Equivalised" means household income is adjusted for household size using
#   the OECD-modified equivalence scale, making incomes comparable across
#   single-person and multi-person households.
#   "_13" suffix indicates the 2013-price-deflated series (inflation-adjusted).
#
# IMPORTANT: FAIK does not contain pnr — only familie_id (family unit identifier).
#   BEF is the bridge: it contains both pnr and familie_id for each year.
#   You must link BEF to FAIK via familie_id and aar to attach income to persons.
#
# SEPLINE INCOME APPROACH (three steps):
#   Step A: Compute each cohort member's 3-year average income.
#           Average over: index_year, index_year-1, index_year-2
#           (= surgery_year-1, surgery_year-2, surgery_year-3).
#           3-year averaging reduces volatility from parental leave, short
#           unemployment spells, or one-off events. SEPLINE Table 9.
#   Step B: Compute population quintile cutpoints (Q20/Q40/Q60/Q80) from the
#           FULL Danish BEF population, stratified by sex x 5-year age group
#           x reference year. Do NOT use within-cohort distributions: your
#           cohort is not representative of the general population income
#           distribution (e.g. bariatric surgery patients are younger and more
#           female). Population cutpoints ensure quintiles have the same meaning
#           across different patient cohorts and calendar periods.
#   Step C: Assign each cohort member to a quintile using the population
#           cutpoints for their sex, age group, and reference year.
#           Q1 -> Low / Q2-Q4 -> Medium / Q5 -> High / NA -> Unknown.

bef  <- load_database("bef")  %>% rename_with(tolower)   # population register: pnr, aar, koen, foed_dag, familie_id
faik <- load_database("faik") %>% rename_with(tolower)   # household income: familie_id, aar, famaekvivadisp_13

# The 3-year average spans: index_year, index_year-1, index_year-2
# (where index_year = surgery_year - 1, so these are surgery_year-1, -2, -3).
income_ref_years <- sort(unique(c(unique_years,
                                  unique_years - 1L,
                                  unique_years - 2L)))   # all calendar years needed for cohort 3-year income averages


# ============================================================================
# 3.1 STEP A — COHORT MEMBER 3-YEAR AVERAGE INCOME
# ============================================================================

# Pull BEF for cohort members across all 3 reference years.
# BEF is needed to get the familie_id link to FAIK, plus sex/birth date for
# the age-group stratum used in the population quintile lookup.
bef_cohort <- bef %>%
  filter(pnr %in% !!pnrs, aar %in% !!income_ref_years) %>%     # restrict to cohort members in the 3 reference years
  select(pnr, aar, koen, foed_dag, familie_id) %>%             # only columns needed for income join and quintile stratum
  collect()                                                    # pull into memory after parquet-side filter

# Pull FAIK for all families in the 3 reference years.
# Collected once and reused; avoids re-querying parquet for each person.
faik_cohort_ref <- faik %>%
  filter(aar %in% !!income_ref_years) %>%              # families appearing in any of the 3 income years
  select(familie_id, aar, famaekvivadisp_13) %>%       # only household identifier, year, and income variable
  collect()                                            # pull into memory

# Expand cohort_years to 3 rows per person (one per income reference year),
# then join to BEF and FAIK to attach income for each of the 3 years.
cohort_ref_lookup <- cohort_years %>%
  mutate(
    yr1 = index_year,       # reference year 1: surgery_year - 1
    yr2 = index_year - 1L,  # reference year 2: surgery_year - 2
    yr3 = index_year - 2L   # reference year 3: surgery_year - 3
  ) %>%
  pivot_longer(cols = c(yr1, yr2, yr3),
               names_to  = NULL,
               values_to = "ref_year")   # one row per (pnr, income reference year)

cohort_3yr_income <- bef_cohort %>%
  inner_join(cohort_ref_lookup,
             by = c("pnr", "aar" = "ref_year")) %>%           # match BEF records to each person's 3 income years
  left_join(faik_cohort_ref,
            by = c("familie_id", "aar")) %>%                  # attach household income for that year; NA if family not in FAIK
  group_by(pnr, index_year) %>%                               # summarise within person x index_year (one average per person)
  summarise(
    income_3yr_avg = mean(famaekvivadisp_13, na.rm = TRUE),   # 3-year average income; na.rm so partial years still contribute
    koen_ref       = first(koen),                             # sex (integer: 1 = male, 2 = female) for quintile stratum
    age_ref        = first(index_year) -
                     year(as.Date(first(foed_dag))),          # age in years at the reference year (= surgery_year - 1)
    .groups = "drop"
  ) %>%
  mutate(
    income_3yr_avg = if_else(is.nan(income_3yr_avg),
                             NA_real_,
                             income_3yr_avg),   # mean() returns NaN when all 3 years are NA; coerce to NA
    age_group5     = floor(age_ref / 5L) * 5L   # 5-year age group lower bound (e.g. age 47 -> group 45, covering ages 45-49)
  )


# ============================================================================
# 3.2 STEP B — POPULATION QUINTILE CUTPOINTS
# ============================================================================
# Compute the four quintile boundaries (20th, 40th, 60th, 80th percentiles)
# from the FULL Danish population (all BEF persons) for each:
#   sex x 5-year age group x reference year
#
# We only need the index_year as the reference year for population cutpoints
# (not all 3 income years) — the quintile stratum is anchored to index_year.
# The 3-year average is what we compare against those cutpoints.

pop_income_years <- sort(unique(unique_years))   # only index_year (= surgery_year - 1) needed for population cutpoint reference

# Pull the full BEF population for the reference years.
# Filter to working-age adults (18-90) to exclude children and very elderly
# whose income distributions are qualitatively different (student grants,
# pension schemes) and would distort the working-age income quintiles.
#
# WHY THIS IS SLOW: BEF contains ~5 million persons per year. If your cohort
# spans, say, 10 reference years, this pulls ~50 million rows into memory.
# This is necessary because SEPLINE requires quintile cutpoints from the
# FULL Danish population — not just your cohort — stratified by sex x 5-year
# age group x year. Using within-cohort cutpoints would give wrong quintiles
# because bariatric surgery patients are not representative of the national
# income distribution. The age filter (18-90) reduces the pull by ~20%.
# Expected runtime: 2-5 minutes depending on server load and number of years.
message(
  "Section 3.2: pulling full BEF population for ", length(pop_income_years),
  " reference year(s) (", paste(pop_income_years, collapse = ", "), "). ",
  "This may take several minutes — BEF has ~5M rows per year."
)
bef_pop <- bef %>%
  filter(aar %in% !!pop_income_years) %>%           # reference years; pushed to parquet before collecting
  select(pnr, aar, koen, foed_dag, familie_id) %>%  # columns needed for age calculation and familie_id link
  collect() %>%                                     # large pull (millions of rows per year); filter first
  mutate(
    age_ref    = aar - year(as.Date(foed_dag)),     # age in years at the reference year
    age_group5 = floor(age_ref / 5L) * 5L           # 5-year age group lower bound
  ) %>%
  filter(age_ref >= 18L, age_ref <= 90L)            # working and older adults only

# Pull FAIK for the population reference years.
faik_pop_ref <- faik %>%
  filter(aar %in% !!pop_income_years) %>%           # limit to reference years used in population quintile calculation
  select(familie_id, aar, famaekvivadisp_13) %>%    # only needed columns
  collect()

# Join BEF population to FAIK to attach income for each reference year.
pop_income <- bef_pop %>%
  left_join(faik_pop_ref, by = c("familie_id", "aar"))   # attach income; persons without FAIK record get NA

# Compute the four quintile boundaries for each sex x age_group5 x year cell.
# These cutpoints define the edges between quintile bands in the general population.
pop_quintile_cutpoints <- pop_income %>%
  filter(!is.na(famaekvivadisp_13)) %>%             # exclude persons without income data from the reference distribution
  group_by(koen, age_group5, aar) %>%
  summarise(
    q20 = quantile(famaekvivadisp_13, 0.20, na.rm = TRUE),   # upper boundary of Q1 (20th percentile)
    q40 = quantile(famaekvivadisp_13, 0.40, na.rm = TRUE),   # upper boundary of Q2 (40th percentile)
    q60 = quantile(famaekvivadisp_13, 0.60, na.rm = TRUE),   # upper boundary of Q3 (60th percentile)
    q80 = quantile(famaekvivadisp_13, 0.80, na.rm = TRUE),   # upper boundary of Q4 (80th percentile); above this = Q5
    .groups = "drop"
  )


# ============================================================================
# 3.3 STEP C — ASSIGN COHORT MEMBERS TO POPULATION QUINTILE
# ============================================================================
# Match each cohort member's 3-year average income against the population
# cutpoints for their sex, 5-year age group, and reference year (index_year).

income <- cohort_3yr_income %>%
  mutate(ref_year = index_year) %>%    # index_year = surgery_year - 1 = the SEP reference year; rename to match cutpoints key
  left_join(
    pop_quintile_cutpoints,
    by = c("koen_ref" = "koen",        # sex
           "age_group5",               # 5-year age group
           "ref_year" = "aar")         # reference year
  ) %>%
  mutate(
    # Assign quintile by comparing each person's 3-year average income to
    # the population cutpoints for their sex-age group-year stratum.
    income_quintile = case_when(
      is.na(income_3yr_avg)        ~ NA_integer_,    # no income data -> no quintile
      income_3yr_avg <= q20        ~ 1L,             # bottom fifth of the population
      income_3yr_avg <= q40        ~ 2L,             # second fifth
      income_3yr_avg <= q60        ~ 3L,             # middle fifth
      income_3yr_avg <= q80        ~ 4L,             # fourth fifth
      income_3yr_avg >  q80        ~ 5L              # top fifth of the population
    ),
    # 3.4 Categorise into Low / Medium / High per SEPLINE:
    #   Q1              -> Low    (bottom 20% of the population)
    #   Q2, Q3, Q4      -> Medium (middle 60% of the population)
    #   Q5              -> High   (top 20% of the population)
    # Unknown covers both missing income data and persons whose sex-age-year
    # stratum did not have a sufficient population for stable cutpoints.
    income_cat = case_when(
      income_quintile == 1L              ~ "Low",
      income_quintile %in% c(2L, 3L, 4L) ~ "Medium",
      income_quintile == 5L              ~ "High",
      TRUE                               ~ "Unknown"   # NA income or no matching cutpoints
    )
  ) %>%
  select(pnr,
         famaekvivadisp_13 = income_3yr_avg,     # rename 3-year average to the raw register column name for clarity
         income_quintile,                        # quintile position 1-5 in the general population (keep for audit)
         income_cat)                             # analysis-ready category: Low / Medium / High / Unknown


# ============================================================================
# 4. OCCUPATION (AKM / SOCIO13)
# ============================================================================
# REGISTER: AKM (arbejdsklassifikationsmodulet)
# KEY COLUMN: socio13 — socioeconomic classification code; annual snapshot
#             as of November each year (Statistics Denmark convention).
#             AKM is ANNUAL (unlike UDDA), so we can filter directly to
#             aar == index_year.
#
# SEPLINE CATEGORY MAPPING (SEPLINE Table 6):
#
#   Self-employed:
#     110-114, 120     = Self-employed with/without employees; freelance
#   Managers and employees (classified as Working):
#     131, 132         = Managers at upper and intermediate levels
#     133, 134, 135    = Employees (skilled, semi-skilled, unskilled)
#     139              = Other employees
#   Students:
#     310              = Students (STU/university/vocational)
#   Unemployed (available for work, receiving unemployment benefit):
#     210              = Unemployed (dagpenge/kontanthjaelp)
#     410              = Unemployed (no benefit)
#   Outside the workforce (not employed, not actively seeking work):
#     220              = On sick leave or other leave
#     321              = Disability pension (fopension)
#     330              = Social security / flex job / other schemes
#   Retired (receiving age-related pension):
#     322              = Early retirement pension (efterloen)
#     323              = Old-age pension (folkepension)
#   Unknown:
#     0, 420, missing  = Children, unclassified, or not in register

message("Section 4: loading AKM occupation register for ", length(pnrs), " cohort members...")
akm <- load_database("akm") %>% rename_with(tolower)   # open AKM register lazily; lowercase column names

# 4.1 Load AKM and filter to cohort reference year
# AKM is annual so we filter directly to aar == index_year for each person.
# We do not need historical records here (unlike education).
occ_raw <- akm %>%
  filter(
    pnr %in% !!pnrs,           # restrict to cohort members before collecting
    aar %in% !!unique_years    # only the reference years (index_year) appearing in the cohort
  ) %>%
  select(pnr, aar, socio13) %>%   # pnr, year, and the socioeconomic classification code
  collect()                       # pull into memory after parquet-side filter

# 4.2 Categorise SOCIO13 into occupation groups
occupation <- occ_raw %>%
  inner_join(cohort_years,
             by = c("pnr", "aar" = "index_year")) %>%   # restrict to each person's own reference year (index_year)
  mutate(
    socio13_num    = as.integer(socio13),                # coerce to integer for range comparisons in case_when
    occupation_cat = case_when(
      socio13_num %in% c(110:114, 120,
                         131:135, 139)  ~ "Working",             # self-employed, managers, and employees of all skill levels
      socio13_num == 310                ~ "Student",             # enrolled in education
      socio13_num %in% c(210, 410)      ~ "Unemployed",          # actively seeking work, with or without benefit
      socio13_num %in% c(220, 321, 330) ~ "Outside_workforce",   # sick leave, disability pension, flex job
      socio13_num %in% c(322, 323)      ~ "Retired",             # early or old-age pension
      TRUE                              ~ "Unknown"              # code 0, 420, missing, or not in AKM
    )
  ) %>%
  select(pnr, socio13, occupation_cat)   # raw code for audit, derived category for models


# ============================================================================
# 5. COMBINE ALL THREE DIMENSIONS — NO COMPOSITE
# ============================================================================
# Join the three separate dimensions to the cohort.
# Left joins ensure that persons absent from a register get NA, which is then
# captured as "Unknown" in the factor encoding below.
# SEPLINE explicitly does NOT recommend a composite SEP variable.
# Enter education_cat, income_cat, and occupation_cat as separate terms in
# your regression models. Do not sum or weight them together.

ses_data <- cohort_years %>%
  left_join(education,  by = "pnr") %>%   # attach education; persons absent from UDDA get hfaudd = NA -> Unknown
  left_join(income,     by = "pnr") %>%   # attach income; persons absent from FAIK get income_3yr_avg = NA -> Unknown
  left_join(occupation, by = "pnr") %>%   # attach occupation; persons absent from AKM get socio13 = NA -> Unknown
  select(
    pnr, index_year,
    hfaudd, education_cat,                          # raw code + derived category for education
    famaekvivadisp_13, income_quintile, income_cat, # raw 3yr average + quintile + derived category for income
    socio13, occupation_cat                         # raw code + derived category for occupation
  )

# Row count check: ses_data must have exactly one row per cohort member.
# More rows = duplicate pnrs in one of the dimension tables (join explosion).
# Fewer rows = pnrs dropped unexpectedly (should not happen with left_join).
if (nrow(ses_data) != nrow(cohort))
  warning(
    "Row count mismatch after combining: cohort has ", nrow(cohort),
    " rows but ses_data has ", nrow(ses_data), " rows. ",
    "Likely cause: duplicate pnrs in education, income, or occupation. ",
    "Check for duplicates with: ses_data %>% filter(duplicated(pnr))"
  )

# Convert to factors with reference levels before saving.
# SEPLINE does not specify a single required reference level — choose what is
# most common in your cohort or most interpretable for your research question.
#
# Recommended defaults:
#   education_cat:  "Medium" as reference (most common in Danish population)
#   income_cat:     "Medium" as reference (middle 60% of the population)
#   occupation_cat: "Working" as reference (employed as the baseline status)
#
# If you need a different reference level, use relevel() before modelling.

ses_data <- ses_data %>%
  mutate(
    education_cat  = factor(education_cat,
                            levels = c("Medium", "Short", "Long", "Unknown")),   # Medium first = default reference level in Cox models

    income_cat     = factor(income_cat,
                            levels = c("Medium", "Low", "High", "Unknown")),     # Medium first = default reference level in Cox models

    occupation_cat = factor(occupation_cat,
                            levels = c("Working", "Unemployed", "Outside_workforce",
                                       "Retired", "Student", "Unknown"))         # Working = employed; reference for interpretation
  )


# ============================================================================
# 6. SAVE OUTPUT
# ============================================================================

dir.create(path_output, showWarnings = FALSE, recursive = TRUE)    # create output directory if it does not already exist
saveRDS(ses_data, file.path(path_output, "ses_data.rds"))          # save to disk; load in your data management script with readRDS()

cat("ses_data.rds saved to", path_output, "\n")                    # confirm path to console
cat("Rows:", nrow(ses_data), " (cohort rows: ", nrow(cohort), ")\n", sep = "")   # should match

# Unknown rate check: >5% Unknown in any dimension likely means a register
# access problem (wrong path, wrong year range, or register not loaded).
pct_unk_edu <- round(100 * mean(as.character(ses_data$education_cat)  == "Unknown", na.rm = TRUE), 1)
pct_unk_inc <- round(100 * mean(as.character(ses_data$income_cat)     == "Unknown", na.rm = TRUE), 1)
pct_unk_occ <- round(100 * mean(as.character(ses_data$occupation_cat) == "Unknown", na.rm = TRUE), 1)
message("Unknown rates (>5% suggests a register access or linkage problem):")
message("  Education:  ", pct_unk_edu, "%")
message("  Income:     ", pct_unk_inc, "%")
message("  Occupation: ", pct_unk_occ, "%")

print(table(ses_data$education_cat,  useNA = "ifany"))             # distribution check: education
print(table(ses_data$income_cat,     useNA = "ifany"))             # distribution check: income
print(table(ses_data$occupation_cat, useNA = "ifany"))             # distribution check: occupation


# ============================================================================
# HOW TO LOAD AND USE IN YOUR ANALYSIS SCRIPT
# ============================================================================
#
# In your data management or analysis script:
#
#   ses <- readRDS(file.path(path_output, "ses_data.rds")) %>%
#     select(pnr, education_cat, income_cat, occupation_cat)
#
#   df <- df %>%
#     left_join(ses, by = "pnr")
#
#   # Cox Model 3 — fully adjusted including SEP:
#   fit <- coxph(
#     Surv(follow_up_days, event) ~
#       exposure +
#       age_at_index + sex +
#       nmi_score +
#       education_cat +      # SEP dimension 1: highest attained education
#       income_cat +         # SEP dimension 2: household income quintile
#       occupation_cat +     # SEP dimension 3: labour market status
#       surgery_period,      # calendar period covariate
#     data = df,
#     cluster = matched_pnr  # adjust for matched design if applicable
#   )
#
# Report:
#   - All three SEP dimensions in Table 1 (baseline characteristics)
#   - All three as separate adjustment terms in Model 3
#   - Cite: Hjorth CF et al. Clin Epidemiol. 2025;17:593-624.
#           DOI: 10.2147/CLEP.S464446
# ============================================================================
