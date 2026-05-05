# ============================================================================
# PIPELINE STEP 1 of 5 — build_cohorts.R
# ============================================================================
# WHO ARE WE STUDYING?
#   Defines the three study groups and applies all inclusion/exclusion criteria.
#   Run this FIRST, before any extraction or analysis.
#
#   BS cohort     — all bariatric surgery patients 2010–2024 (from bs_cohort.rds)
#   GP comparator — matched 1:25 from general population (BEF), same sex + birth year ±1
#   Obesity comp. — matched 1:5 from persons with E66 diagnosis BEFORE their index date
#
#   Exclusions for all groups: pre-surgery dementia, prior bariatric surgery, death before index
#   Produces: datasets/full_cohort.rds  (one row per person, all three cohorts combined)
# ============================================================================
# COHORT BUILDING
# ============================================================================
# Purpose: Combines the existing BS cohort with matched comparison cohorts
#          and applies inclusion/exclusion criteria to all groups.
#
# Run BEFORE extract_outcomes_covariates.R and extract_ses.R.
#
# Input:  bs_cohort.rds  (existing file with BS patients)
# Output: full_cohort.rds
#           pnr, index_date, cohort ("BS"/"GP"/"Obesity"),
#           surgery_type ("RYGB"/"SG"/NA), matched_pnr (pnr of the matched BS patient)
#
# Comparison cohorts:
#   GP comparator   – matched 1:25 on sex + birth year (±1) from BEF
#   Obesity cohort  – matched 1:5  on sex + birth year (±1) from BEF,
#                     restricted to persons with ICD-10 E66 in LPR before index
#   Note: there is no population-level BMI register in Denmark. The obesity
#   comparator is defined by E66 diagnosis code (standard approach in Danish
#   register epidemiology).
#
# Exclusion criteria applied to ALL groups:
#   1. Dementia diagnosis (F00–F03, G30–G31) any time before index date
#   2. Prior bariatric surgery (KJDF10, KJDF11, KJDF40, KJDF41, KJDF96, KJDF97)
#      [only relevant for GP and obesity pools]
#   3. Emigration before index date
#   4. Death before index date
#   5. < 5 years of registry history before index date
#
# ============================================================================
# PSYCHIATRIC LPR2 REGISTER — CONFIRMED ACCESS METHOD
#   t_psyk_adm and t_psyk_diag are parquet folders in parquet-external.
#   Accessed via arrow::open_dataset(path_psyk_adm / path_psyk_diag).
#   Raw DST column names (v_cpr, k_recnum, v_recnum) — renamed in code.
# ============================================================================

# Packages ----
library(dstDataPrep)
library(arrow)
library(dplyr)
library(lubridate)
library(heaven)        # exposureMatch(), findCondition(), charlsonIndex(), edu_code, etc.

# Paths ----
path_output    <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets"
path_bs_cohort <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets/bs_cohort.rds"
path_dm_pop    <- "E:/workdata/708421/cleaned-data/diabetes_register_pop/dm_population_1977_2022.rds"
path_psyk_adm  <- "E:/workdata/708421/cleaned-data/parquet-external/t_psyk_adm"
path_psyk_diag <- "E:/workdata/708421/cleaned-data/parquet-external/t_psyk_diag"
path_dbso      <- "E:/workdata/708421/cleaned-data/parquet-external/databasesvaerovervaegt"

# GP match ratio and obesity match ratio
N_GP_PER_BS      <- 25L
N_OBESITY_PER_BS <- 5L

# ICD codes for dementia (3-char, no D prefix)
DEMENTIA_ICD3 <- c("F00", "F01", "F02", "F03", "G30", "G31")

# SKS/NOMESCO procedure codes for bariatric surgery
BS_PROC_CODES <- c("KJDF10", "KJDF11", "KJDF40", "KJDF41", "KJDF96", "KJDF97")

# ============================================================================
# HELPERS
# ============================================================================

get_prior_dementia_pnrs <- function(pnr_vector, before_dates) {
  # Returns pnrs that have ANY dementia diagnosis (F00-F03, G30-G31) before their
  # respective cutoff date. Covers three data sources:
  #
  #   1. LPR2 somatic     (lpr_adm + lpr_diag):         somatic contacts up to March 2019
  #   2. LPR2 psychiatric (t_psyk_adm + t_psyk_diag):   psychiatric contacts 1995-March 2019
  #      Names confirmed from archive/other peoples code/psyc2021.R (DST project 708614).
  #      Confirmed: accessible via arrow::open_dataset(path_psyk_adm/path_psyk_diag).
  #   3. LPR3 unified     (kontakter + diagnoser):       all contacts from March 2019 onwards.
  #      LPR3 covers BOTH somatic and psychiatric in one register — no separate psych table needed.

  # --- Source 1: LPR2 somatic ---
  lpr_adm  <- load_database("lpr_adm")  %>% rename_with(tolower)
  lpr_diag <- load_database("lpr_diag") %>% rename_with(tolower)

  lpr2_dementia <- lpr_adm %>%
    filter(pnr %in% !!pnr_vector) %>%
    select(pnr, recnum, date_contact = d_inddto) %>%
    inner_join(
      lpr_diag %>%
        filter(c_diagtype %in% c("A", "B")) %>%
        mutate(icd3 = substr(c_diag, 2, 4)) %>%
        filter(icd3 %in% !!DEMENTIA_ICD3) %>%
        select(recnum, icd3),
      by = "recnum"
    ) %>%
    select(pnr, date_contact) %>%
    collect()

  # --- Source 2: LPR2 psychiatric (1995-March 2019) ---
  # Geropsychiatric departments record F00-F03 dementia in their own separate register.
  # Without this source, all F-code dementia diagnosed before 2019 in psychiatric
  # memory clinics would be silently missed — prevalent cases would stay in the cohort
  # and be misclassified as incident post-surgery dementia.
  #
  # Confirmed path: parquet-external folder (not via load_database).
  # Raw DST column names — rename v_cpr->pnr, k_recnum->recnum, v_recnum->recnum.
  psyk_adm  <- arrow::open_dataset(path_psyk_adm)  %>% rename_with(tolower) %>%
    rename(pnr = v_cpr, recnum = k_recnum)
  psyk_diag <- arrow::open_dataset(path_psyk_diag) %>% rename_with(tolower) %>%
    rename(recnum = v_recnum)

  lpr2_psyk_dementia <- psyk_adm %>%
    filter(pnr %in% !!pnr_vector) %>%
    select(pnr, recnum, date_contact = d_inddto) %>%
    inner_join(
      psyk_diag %>%
        filter(c_diagtype %in% c("A", "B")) %>%
        mutate(icd3 = substr(c_diag, 2, 4)) %>%
        filter(icd3 %in% !!DEMENTIA_ICD3) %>%
        select(recnum, icd3),
      by = "recnum"
    ) %>%
    select(pnr, date_contact) %>%
    collect()

  # --- Source 3: LPR3 (March 2019 onwards) ---
  # Unified register: somatic and psychiatric contacts in one place.
  # All F00-F03 and G30-G31 contacts captured regardless of department.
  kontakter <- load_database("lpr_a_kontakt") %>% rename_with(tolower)  # alt name: "lpr3f_kontakter"
  diagnoser <- load_database("lpr_a_diagnose") %>% rename_with(tolower)  # alt name: "lpr3f_diagnoser"

  lpr3_dementia <- kontakter %>%
    filter(pnr %in% !!pnr_vector) %>%
    select(pnr, dw_ek_kontakt, dato_start) %>%
    inner_join(
      diagnoser %>%
        filter(
          diagnosetype %in% c("A", "B"),
          # senare_afkraeftet == "Ja" means the diagnosis was later retracted — exclude those
          is.na(senere_afkraeftet) | senare_afkraeftet != "Ja"
        ) %>%
        mutate(icd3 = substr(diagnosekode, 2, 4)) %>%
        filter(icd3 %in% !!DEMENTIA_ICD3) %>%
        select(dw_ek_kontakt, icd3),
      by = "dw_ek_kontakt"
    ) %>%
    collect() %>%
    mutate(date_contact = as.Date(dato_start)) %>%
    select(pnr, date_contact)

  # Combine all three sources, then filter to contacts before each person's cutoff date
  all_dementia <- bind_rows(lpr2_dementia, lpr2_psyk_dementia, lpr3_dementia)

  if (is.data.frame(before_dates)) {
    # before_dates must have columns pnr + index_date (one cutoff per person)
    all_dementia %>%
      inner_join(before_dates, by = "pnr") %>%
      filter(date_contact < index_date) %>%
      distinct(pnr) %>%
      pull(pnr)
  } else {
    # before_dates is a single scalar date applied uniformly to all pnrs
    all_dementia %>%
      filter(date_contact < before_dates) %>%
      distinct(pnr) %>%
      pull(pnr)
  }
}


get_prior_bs_pnrs <- function(pnr_vector) {
  # Returns pnrs from pnr_vector who appear in DBSO — i.e., have had bariatric surgery.
  # DBSO (Danish Quality Registry for Treatment of Severe Obesity) is the authoritative
  # source: all public and private BS procedures are mandatorily reported since 2010.
  # Minor limitation: procedures before DBSO's 2010 start are not captured, but these
  # are very rare (BS was uncommon in Denmark pre-2010).
  arrow::open_dataset(path_dbso) %>%
    filter(pnr %in% !!pnr_vector) %>%
    distinct(pnr) %>%
    collect() %>%
    pull(pnr)
}


get_bef_demographics <- function(pnr_vector) {
  # Returns one row per pnr: koen (sex), foed_dag (birth date), most recent record
  bef <- load_database("bef") %>% rename_with(tolower)
  bef %>%
    filter(pnr %in% !!pnr_vector) %>%
    select(pnr, koen, foed_dag, aar) %>%
    group_by(pnr) %>%
    arrange(desc(aar)) %>%
    slice(1) %>%
    ungroup() %>%
    select(pnr, koen, foed_dag) %>%
    collect() %>%
    mutate(birth_year = year(as.Date(foed_dag)))
}


# ============================================================================
# STEP 1: LOAD AND CLEAN BS COHORT
# ============================================================================

build_bs_cohort <- function() {
  bs_raw <- readRDS(path_bs_cohort)
  # Expected columns: pnr, surgery_date, surgery_type

  # Get birth dates for the >=5 year lookback check
  demo  <- get_bef_demographics(unique(bs_raw$pnr))
  bs    <- bs_raw %>% left_join(demo, by = "pnr")

  # Exclusion 4+5: died before surgery or insufficient lookback
  dod <- load_database("dodsaars") %>% rename_with(tolower)
  deaths <- dod %>%
    filter(pnr %in% !!bs$pnr) %>%
    select(pnr, doddato) %>%
    collect()

  bs <- bs %>%
    left_join(deaths, by = "pnr") %>%
    filter(
      is.na(doddato) | doddato >= surgery_date,             # alive at surgery
      surgery_date - as.Date(foed_dag) >= 365.25 * 18,     # age >= 18
      surgery_date >= as.Date(foed_dag) + 365.25 * 5       # >= 5 year history
                                                             # (all 2010+ patients born <= 2005 -> fine)
    )

  # Exclusion 1: pre-surgery dementia
  cutoffs <- bs %>% select(pnr, index_date = surgery_date)
  dementia_pnrs <- get_prior_dementia_pnrs(bs$pnr, cutoffs)
  bs <- bs %>% filter(!pnr %in% dementia_pnrs)

  bs %>%
    transmute(
      pnr,
      index_date    = surgery_date,
      cohort        = "BS",
      surgery_type,
      matched_pnr   = pnr   # matches itself
    )
}


# ============================================================================
# STEP 2: BUILD GP COMPARATOR POOL
# ============================================================================
# Strategy: group BEF by sex + birth_year, for each BS patient sample N_GP_PER_BS
# people from the matching group who are alive at the index date and dementia-free.

build_gp_comparator <- function(bs_cohort) {
  bef <- load_database("bef") %>% rename_with(tolower)

  # Pull only the years when surgeries occurred — people in BEF those years were alive then.
  surgery_years <- unique(year(bs_cohort$index_date))

  # One record per person (most recent year). Deduplicate BEFORE pulling into memory
  # by doing group_by + slice inside the lazy DuckDB query, so only one row per person
  # crosses the parquet → R boundary. On a full BEF table this is the main cost saving.
  bef_pool <- bef %>%
    filter(aar %in% !!surgery_years) %>%
    select(pnr, koen, foed_dag, aar) %>%
    group_by(pnr) %>%
    arrange(desc(aar)) %>%
    slice(1) %>%        # keep most recent record per person — done lazily before collect()
    ungroup() %>%
    collect() %>%       # bring deduplicated records into memory
    mutate(birth_year = year(as.Date(foed_dag))) %>%
    select(pnr, koen, birth_year) %>%
    filter(!pnr %in% bs_cohort$pnr)   # remove BS patients from pool

  # Remove anyone who already had bariatric surgery (they are exposed, not controls)
  bs_pnrs_in_pool <- get_prior_bs_pnrs(bef_pool$pnr)
  bef_pool <- bef_pool %>% filter(!pnr %in% bs_pnrs_in_pool)

  # [FIX] Verify alive at each index date: load death dates for pool members.
  # BEF is an annual January 1 snapshot — appearing in BEF 2012 means alive 2012-01-01,
  # not necessarily alive on Sept 15 2012. Without this step, persons who died mid-year
  # could be drawn as comparators for surgeries occurring later that same year.
  dod <- load_database("dodsaars") %>% rename_with(tolower)
  pool_deaths <- dod %>%
    filter(pnr %in% !!bef_pool$pnr) %>%
    select(pnr, death_date = doddato) %>%
    collect()

  bef_pool <- bef_pool %>%
    left_join(pool_deaths, by = "pnr")   # death_date = NA means still alive (living persons absent from dod)

  # Pre-split pool into a named list of data frames, one element per (koen, birth_year) group.
  # Key insight: instead of dplyr::filter(pool, koen==x, birth_year %in% c(y-1,y,y+1)) on
  # every loop iteration — which scans the whole data frame each time — we do a single
  # split() up front. Inside the loop we do three O(1) list lookups and filter on small dfs.
  # For a BS cohort of n=5000 and BEF pool of n=3M, this avoids 5000 × 3M comparisons.
  pool_list <- split(bef_pool[, c("pnr", "death_date")],
                     paste(bef_pool$koen, bef_pool$birth_year, sep = "_"))

  # Fetch sex + birth_year for the BS cohort (needed for matching key)
  bs_key <- bs_cohort %>%
    left_join(
      get_bef_demographics(bs_cohort$pnr) %>% select(pnr, koen, birth_year),
      by = "pnr"
    )

  set.seed(42)
  matched_rows <- vector("list", nrow(bs_key))   # pre-allocate for speed

  for (i in seq_len(nrow(bs_key))) {
    bs_pnr   <- bs_key$pnr[i]
    idx_date <- bs_key$index_date[i]
    sex      <- bs_key$koen[i]
    by       <- bs_key$birth_year[i]

    # Collect candidates from the three adjacent birth-year groups (same sex, year ±1)
    group_keys <- paste(sex, by + (-1L:1L), sep = "_")
    cand_df    <- dplyr::bind_rows(pool_list[group_keys])

    # [FIX] Only keep candidates alive at this specific index date.
    cand_df    <- cand_df[is.na(cand_df$death_date) | cand_df$death_date > idx_date, ]
    candidates <- cand_df$pnr

    if (length(candidates) == 0) next   # no eligible match available for this BS patient

    n_sample     <- min(N_GP_PER_BS, length(candidates))
    sampled_pnrs <- sample(candidates, n_sample)   # random draw without replacement

    matched_rows[[i]] <- tibble(
      pnr          = sampled_pnrs,
      index_date   = idx_date,
      cohort       = "GP",
      surgery_type = NA_character_,
      matched_pnr  = bs_pnr
    )

    # Remove sampled pnrs from the pool: filter rows rather than setdiff on vectors.
    for (k in group_keys) {
      if (!is.null(pool_list[[k]])) {
        pool_list[[k]] <- pool_list[[k]][!pool_list[[k]]$pnr %in% sampled_pnrs, ]
      }
    }
  }

  gp_cohort <- bind_rows(matched_rows)

  # Exclude any GP comparators with pre-index dementia
  cutoffs <- gp_cohort %>% select(pnr, index_date)
  dementia_pnrs <- get_prior_dementia_pnrs(gp_cohort$pnr, cutoffs)
  gp_cohort %>% filter(!pnr %in% dementia_pnrs)
}

## ---------------------------------------------------------------------------
## ALTERNATIVE GP MATCHING: heaven::exposureMatch()
## Commented out — the manual loop above is the default.
##
## heaven::exposureMatch() (= riskSetMatch) does validated risk-set matching
## and is the standard tool used by the CTP group on DST. It handles alive/
## event-free eligibility via the end.followup parameter.
##
## KEY LIMITATION vs current approach: terms= does EXACT matching only.
## Our protocol specifies birth year ±1. Options:
##   (a) Exact birth year — simpler; very minor reduction in match rate for
##       rare birth years at the edges of the study period.
##   (b) Collapse to 2-year birth groups before calling exposureMatch.
##
## To activate: replace the body of build_gp_comparator() with this block.
## ---------------------------------------------------------------------------
## build_gp_comparator_exposureMatch <- function(bs_cohort) {
##   bef_pool <- ...   # same pool preparation as above (lines 260-295)
##
##   bs_key <- bs_cohort %>%
##     left_join(get_bef_demographics(bs_cohort$pnr) %>%
##                 select(pnr, koen, birth_year), by = "pnr") %>%
##     left_join(pool_deaths %>% select(pnr, death_date), by = "pnr") %>%
##     mutate(
##       is_case      = 1L,
##       case_index   = index_date,
##       end_followup = pmin(coalesce(death_date, as.Date("2025-12-31")),
##                           as.Date("2025-12-31"), na.rm = TRUE),
##       koen         = as.character(koen),          # terms must be character
##       birth_year   = as.character(birth_year)
##     )
##
##   ctrl_dt <- bef_pool %>%
##     mutate(
##       is_case      = 0L,
##       case_index   = as.Date(NA),                 # NA = never exposed
##       end_followup = pmin(coalesce(death_date, as.Date("2025-12-31")),
##                           as.Date("2025-12-31"), na.rm = TRUE),
##       koen         = as.character(koen),
##       birth_year   = as.character(birth_year)
##     )
##
##   combined <- data.table::rbindlist(
##     list(data.table::as.data.table(bs_key),
##          data.table::as.data.table(ctrl_dt)), fill = TRUE
##   )
##
##   matched <- heaven::exposureMatch(
##     ptid         = "pnr",
##     event        = "is_case",       # 1 = BS patient, 0 = GP control
##     terms        = c("koen", "birth_year"),
##     data         = combined,
##     n.controls   = N_GP_PER_BS,
##     case.index   = "case_index",
##     end.followup = "end_followup",
##     seed         = 42
##   )
##
##   # Format to match current output structure
##   case_ids <- matched[matched$is_case == 1, c("pnr", "case.id")]
##   names(case_ids)[1] <- "matched_pnr"
##
##   gp_cohort <- matched[matched$is_case == 0, ] %>%
##     dplyr::left_join(case_ids, by = "case.id") %>%
##     dplyr::mutate(cohort = "GP", surgery_type = NA_character_) %>%
##     dplyr::select(pnr, index_date = case_index, cohort, surgery_type, matched_pnr)
##
##   cutoffs <- gp_cohort %>% select(pnr, index_date)
##   dementia_pnrs <- get_prior_dementia_pnrs(gp_cohort$pnr, cutoffs)
##   gp_cohort %>% filter(!pnr %in% dementia_pnrs)
## }


# ============================================================================
# STEP 3: BUILD OBESITY COMPARATOR POOL
# ============================================================================
# Pool: persons with E66 (obesity) diagnosis in LPR BEFORE their matched BS
# patient's index date, never having had bariatric surgery.
# Same sex + birth year (±1) matching as GP comparator.

build_obesity_comparator <- function(bs_cohort) {
  # Get all E66 contacts from LPR, keeping the contact date.
  # We need the date to enforce: E66 diagnosis must predate the BS patient's index date.
  # [FIX] Without this, a person who received an E66 diagnosis in 2020 could be matched
  # to a BS patient with surgery in 2012, violating the study design.
  lpr_adm  <- load_database("lpr_adm")  %>% rename_with(tolower)
  lpr_diag <- load_database("lpr_diag") %>% rename_with(tolower)

  # LPR2 E66 contacts with date
  obesity_lpr2 <- lpr_adm %>%
    select(pnr, recnum, date_contact = d_inddto) %>%
    inner_join(
      lpr_diag %>%
        filter(c_diagtype %in% c("A", "B")) %>%   # exclude auxiliary "G" diagnoses
        mutate(icd3 = substr(c_diag, 2, 4)) %>%
        filter(icd3 == "E66") %>%
        select(recnum),
      by = "recnum"
    ) %>%
    select(pnr, date_contact) %>%
    collect()

  # LPR3 E66 contacts with date
  kontakter <- load_database("lpr_a_kontakt") %>% rename_with(tolower)  # alt name: "lpr3f_kontakter"
  diagnoser <- load_database("lpr_a_diagnose") %>% rename_with(tolower)  # alt name: "lpr3f_diagnoser"

  obesity_lpr3 <- kontakter %>%
    select(pnr, dw_ek_kontakt, dato_start) %>%
    inner_join(
      diagnoser %>%
        filter(diagnosetype %in% c("A", "B")) %>%   # exclude auxiliary "G" diagnoses
        mutate(icd3 = substr(diagnosekode, 2, 4)) %>%
        filter(icd3 == "E66", is.na(senare_afkraeftet) | senare_afkraeftet != "Ja") %>%
        select(dw_ek_kontakt),
      by = "dw_ek_kontakt"
    ) %>%
    collect() %>%
    mutate(date_contact = as.Date(dato_start)) %>%
    select(pnr, date_contact)

  # Earliest E66 date per person — used in the loop to enforce pre-index diagnosis
  obesity_dates <- dplyr::bind_rows(obesity_lpr2, obesity_lpr3) %>%
    dplyr::group_by(pnr) %>%
    dplyr::summarise(earliest_e66 = min(date_contact, na.rm = TRUE), .groups = "drop")

  # Get demographics for obesity pool
  obesity_pool <- get_bef_demographics(obesity_dates$pnr) %>%
    filter(!pnr %in% bs_cohort$pnr) %>%
    inner_join(obesity_dates, by = "pnr")   # attach earliest_e66

  # Remove prior BS from pool
  bs_in_pool <- get_prior_bs_pnrs(obesity_pool$pnr)
  obesity_pool <- obesity_pool %>% filter(!pnr %in% bs_in_pool)

  # [FIX] Verify alive at each index date: load death dates for pool members.
  dod <- load_database("dodsaars") %>% rename_with(tolower)
  pool_deaths <- dod %>%
    filter(pnr %in% !!obesity_pool$pnr) %>%
    select(pnr, death_date = doddato) %>%
    collect()

  obesity_pool <- obesity_pool %>%
    left_join(pool_deaths, by = "pnr")   # death_date = NA means still alive

  # Match to BS cohort (1:N_OBESITY_PER_BS) — same pre-split approach as GP comparator.
  # Splits into per-(koen, birth_year) data frames so we can filter on earliest_e66
  # and death_date inside the loop without scanning the full pool each iteration.
  bs_key <- bs_cohort %>%
    left_join(
      get_bef_demographics(bs_cohort$pnr) %>% select(pnr, koen, birth_year),
      by = "pnr"
    )

  pool_list <- split(obesity_pool[, c("pnr", "earliest_e66", "death_date")],
                     paste(obesity_pool$koen, obesity_pool$birth_year, sep = "_"))

  set.seed(42)
  matched_rows <- vector("list", nrow(bs_key))

  for (i in seq_len(nrow(bs_key))) {
    bs_pnr   <- bs_key$pnr[i]
    idx_date <- bs_key$index_date[i]
    sex      <- bs_key$koen[i]
    by       <- bs_key$birth_year[i]

    group_keys <- paste(sex, by + (-1L:1L), sep = "_")
    cand_df    <- dplyr::bind_rows(pool_list[group_keys])

    # [FIX] Only candidates whose E66 diagnosis predates the index date, AND who are alive.
    cand_df    <- cand_df[
      cand_df$earliest_e66 < idx_date &
      (is.na(cand_df$death_date) | cand_df$death_date > idx_date), ]
    candidates <- cand_df$pnr

    if (length(candidates) == 0) next

    n_sample     <- min(N_OBESITY_PER_BS, length(candidates))
    sampled_pnrs <- sample(candidates, n_sample)

    matched_rows[[i]] <- tibble(
      pnr          = sampled_pnrs,
      index_date   = idx_date,
      cohort       = "Obesity",
      surgery_type = NA_character_,
      matched_pnr  = bs_pnr
    )

    for (k in group_keys) {
      if (!is.null(pool_list[[k]])) {
        pool_list[[k]] <- pool_list[[k]][!pool_list[[k]]$pnr %in% sampled_pnrs, ]
      }
    }
  }

  ob_cohort <- bind_rows(matched_rows)

  cutoffs <- ob_cohort %>% select(pnr, index_date)
  dementia_pnrs <- get_prior_dementia_pnrs(ob_cohort$pnr, cutoffs)
  ob_cohort %>% filter(!pnr %in% dementia_pnrs)
}

## ---------------------------------------------------------------------------
## ALTERNATIVE OBESITY MATCHING: heaven::exposureMatch()
## Commented out — the manual loop above is the default.
##
## The E66 pre-index requirement (control must have E66 before case's index
## date) maps to date.terms = "earliest_e66". exposureMatch interprets this
## as: if the case has not yet reached the date at case.index (NA for BS
## patients), the control must also not have reached it — which is the
## opposite of what we need. Pre-filtering the pool to earliest_e66 < ANY
## index date, then letting exposureMatch handle per-patient eligibility via
## end.followup, is the practical workaround.
##
## To activate: replace the body of build_obesity_comparator() with this block.
## ---------------------------------------------------------------------------
## build_obesity_comparator_exposureMatch <- function(bs_cohort) {
##   # Build obesity_pool with earliest_e66 and death_date as above (lines 387-437)
##   # obesity_pool already filtered to: !pnr %in% bs_cohort, E66 confirmed
##
##   bs_key <- bs_cohort %>%
##     left_join(get_bef_demographics(bs_cohort$pnr) %>%
##                 select(pnr, koen, birth_year), by = "pnr") %>%
##     mutate(
##       is_case      = 1L,
##       case_index   = index_date,
##       end_followup = as.Date("2025-12-31"),
##       koen         = as.character(koen),
##       birth_year   = as.character(birth_year)
##     )
##
##   # For obesity controls, end.followup = earliest_e66 ensures a control is
##   # only eligible at index dates AFTER their E66 diagnosis.
##   ctrl_dt <- obesity_pool %>%
##     mutate(
##       is_case      = 0L,
##       case_index   = as.Date(NA),
##       end_followup = pmin(coalesce(death_date, as.Date("2025-12-31")),
##                           as.Date("2025-12-31"), na.rm = TRUE),
##       koen         = as.character(koen),
##       birth_year   = as.character(birth_year)
##     )
##
##   combined <- data.table::rbindlist(
##     list(data.table::as.data.table(bs_key),
##          data.table::as.data.table(ctrl_dt)), fill = TRUE
##   )
##
##   matched <- heaven::exposureMatch(
##     ptid         = "pnr",
##     event        = "is_case",
##     terms        = c("koen", "birth_year"),
##     data         = combined,
##     n.controls   = N_OBESITY_PER_BS,
##     case.index   = "case_index",
##     end.followup = "end_followup",
##     seed         = 42
##   )
##
##   case_ids <- matched[matched$is_case == 1, c("pnr", "case.id")]
##   names(case_ids)[1] <- "matched_pnr"
##
##   ob_cohort <- matched[matched$is_case == 0, ] %>%
##     dplyr::left_join(case_ids, by = "case.id") %>%
##     dplyr::mutate(cohort = "Obesity", surgery_type = NA_character_) %>%
##     dplyr::select(pnr, index_date = case_index, cohort, surgery_type, matched_pnr)
##
##   cutoffs <- ob_cohort %>% select(pnr, index_date)
##   dementia_pnrs <- get_prior_dementia_pnrs(ob_cohort$pnr, cutoffs)
##   ob_cohort %>% filter(!pnr %in% dementia_pnrs)
## }


# ============================================================================
# MAIN
# ============================================================================

main_build_cohorts <- function() {
  cat("Building BS cohort and applying exclusions...\n")
  bs_cohort <- build_bs_cohort()
  cat("  BS cohort n =", nrow(bs_cohort), "\n")

  cat("Building GP comparator cohort...\n")
  gp_cohort <- build_gp_comparator(bs_cohort)
  cat("  GP comparator n =", nrow(gp_cohort), "\n")

  cat("Building obesity comparator cohort...\n")
  ob_cohort <- build_obesity_comparator(bs_cohort)
  cat("  Obesity comparator n =", nrow(ob_cohort), "\n")

  full_cohort <- bind_rows(bs_cohort, gp_cohort, ob_cohort) %>%
    mutate(cohort = factor(cohort, levels = c("BS", "GP", "Obesity")))

  # Flag comparators who later undergo bariatric surgery.
  # These must be censored at their own surgery date in time-to-event analyses.
  bs_raw_dates <- readRDS(path_bs_cohort) %>% select(pnr, bs_surgery_date = surgery_date)
  full_cohort <- full_cohort %>%
    left_join(bs_raw_dates, by = "pnr") %>%
    mutate(
      bs_crossover_date = if_else(
        as.character(cohort) != "BS" & !is.na(bs_surgery_date) & bs_surgery_date > index_date,
        bs_surgery_date, NA_Date_
      )
    ) %>%
    select(-bs_surgery_date)

  cat("Total full_cohort n =", nrow(full_cohort), "\n")

  dir.create(path_output, showWarnings = FALSE, recursive = TRUE)
  saveRDS(full_cohort, file.path(path_output, "full_cohort.rds"))
  cat("Saved: full_cohort.rds\n")
  invisible(full_cohort)
}

# Run:
# full_cohort <- main_build_cohorts()
