# ============================================================================
# PIPELINE STEP 1 of 5 — 01_build_cohorts.R
# ============================================================================
#   Study groups:
#     BS cohort     — bariatric surgery patients 2010–2024 (source: DBSO)
#     GP comparator — 1:25 matched from the general population (BEF)
#                     Matching: same sex + birth year (±1 year)
#     Obesity comp. — 1:5 matched from persons with ICD-10 E66 (obesity) in LPR
#                     before their matched BS patient's surgery date
#                     Matching: same sex + birth year (±1 year)
#
#   Inputs:  parquet-external/databasesvaerovervaegt/part-0.parquet (DBSO, from 00_prepare_dbso.R)
#            load_database("bef")                     — population register
#            load_database("lpr_adm") + "lpr_diag"    — LPR2 somatic diagnoses
#            arrow::open_dataset(path_psyk_adm/diag)  — LPR2 psychiatric diagnoses
#            load_database("lpr_a_kontakt/diagnose")  — LPR3 unified diagnoses
#            load_database("dodsaars")                — death register
#
#   Output:  datasets/full_cohort.rds
#            One row per person. Columns: pnr, index_date, cohort
#            ("BS"/"GP"/"Obesity"), surgery_type ("RYGB"/"SG"/NA),
#            matched_pnr, bs_crossover_date (if comparators later have BS)
#
#   Exclusion criteria applied to ALL groups:
#     1. Dementia (F00–F03, G30–G31) any time before index date
#     2. Prior bariatric surgery (KJDF10/11, KJDF40/41/96/97) [for comparator members]
#     3. Emigration before index date
#     4. Death before index date
#     5. Age < 18 at surgery / < 5 years of registry history before index date
#
#   NOTE: The obesity comparator is defined by E66 diagnosis code — standard approach in Danish
#   register epidemiology.
#
#   Psychiatric LPR2: t_psyk_adm and t_psyk_diag are parquet folders in
#   parquet-external, accessed via arrow::open_dataset(). Raw DST column names
#   (v_cpr, k_recnum, v_recnum) are renamed in code after loading.
#
# TABLE OF CONTENTS
# -----------------
#   Packages / paths / constants              ~line  40
#   1.0  Helper functions                     ~line  68
#        get_prior_dementia_pnrs()            ~line  70
#        get_bs_surgery_dates()              ~line 171
#        get_bef_demographics()             ~line 194
#   1.1  build_bs_cohort()                   ~line 212
#   1.2  build_gp_comparator()              ~line 325
#        [Alt: exposureMatch version]        ~line 500
#   1.3  build_obesity_comparator()         ~line 575
#        [Alt: exposureMatch version]        ~line 768
#   1.4  main_build_cohorts()               ~line 840
# ============================================================================

# Packages ----
library(dstDataPrep)
library(arrow)
library(dplyr)
library(lubridate)
library(heaven)        # exposureMatch(), findCondition(), charlsonIndex(), edu_code, etc.

# Paths ----
path_output    <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets"
path_dm_pop    <- "E:/workdata/708421/cleaned-data/diabetes_register_pop/dm_population_1977_2022.rds"
path_psyk_adm  <- "E:/workdata/708421/cleaned-data/parquet-external/t_psyk_adm"
path_psyk_diag <- "E:/workdata/708421/cleaned-data/parquet-external/t_psyk_diag"
path_dbso      <- "E:/workdata/708421/cleaned-data/parquet-external/databasesvaerovervaegt"

# GP match ratio and obesity match ratio
N_GP_PER_BS      <- 25L
N_OBESITY_PER_BS <- 5L

# ICD codes for dementia (3-char, no D prefix)
DEMENTIA_ICD3 <- c("F00", "F01", "F02", "F03", "G30", "G31")

# SKS/NOMESCO procedure codes for bariatric surgery — reference only; not used in code.
# Cohort is defined via DBSO flags (gastricbypass_prim / gastricsleeve_prim), not SKS codes.
# RYGB: KJDF10, KJDF11 | SG: KJDF40, KJDF41, KJDF96, KJDF97
BS_PROC_CODES <- c("KJDF10", "KJDF11", "KJDF40", "KJDF41", "KJDF96", "KJDF97")

# ============================================================================
# 1.0 HELPER FUNCTIONS
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


get_bs_surgery_dates <- function(pnr_vector) {
  # Returns a data frame (pnr, bs_surgery_date) for pool members who appear in DBSO.
  # bs_surgery_date = the earliest surgery date in DBSO for that person.
  # Used in the matching loops for two purposes:
  #   (a) exclude candidates with bs_surgery_date <= index_date from each draw —
  #       they were already exposed at baseline and cannot serve as unexposed controls
  #   (b) record bs_crossover_date for sampled comparators whose bs_surgery_date is
  #       AFTER their assigned index_date — eligible controls at enrolment, censored
  #       when they later cross over to the exposed group
  # Pool members absent from DBSO receive bs_surgery_date = NA (left_join fills NA).
  # DBSO is the authoritative source for all public and private BS since 2010.
  arrow::open_dataset(path_dbso) %>%
    filter(pnr %in% !!pnr_vector, !is.na(datoper_prim)) %>%   # only rows with a recorded surgery date
    select(pnr, bs_surgery_date = datoper_prim) %>%            # rename for clarity in pool context; datoper_prim = surgery date in DBSO
    collect() %>%                                               # pull into memory for grouping
    mutate(bs_surgery_date = as.Date(bs_surgery_date)) %>%    # ensure Date class for comparisons in matching loops
    group_by(pnr) %>%
    arrange(bs_surgery_date) %>%
    slice(1) %>%                                               # earliest surgery date per person (DBSO has multiple rows per person)
    ungroup()
}


get_bef_demographics <- function(pnr_vector) {
  # Returns one row per pnr: koen (sex), foed_dag (birth date), most recent record
  bef <- load_database("bef") %>% rename_with(tolower)   # open BEF (population register) lazily; lowercase column names
  bef %>%
    filter(pnr %in% !!pnr_vector) %>%    # push cohort filter to parquet before pulling data into memory
    select(pnr, koen, foed_dag, aar) %>%  # only the columns we need; reduces data transferred to R
    group_by(pnr) %>%                     # group by person to pick one record per person
    arrange(desc(aar)) %>%                # most recent BEF year first so slice(1) picks the newest record
    slice(1) %>%                          # keep only the most recent record; BEF may have many years per person
    ungroup() %>%                         # release grouping after deduplication
    select(pnr, koen, foed_dag) %>%       # drop aar; no longer needed after dedup
    collect() %>%                         # pull deduplicated data from parquet into R memory
    mutate(birth_year = year(as.Date(foed_dag)))  # derive birth year for matching; as.Date needed if foed_dag is character
}


# ============================================================================
# 1.1 BUILD BS COHORT FROM DBSO
# ============================================================================
# Source: DBSO (Databasen for Behandling af Svær Overvægt) — the national mandatory
# bariatric surgery registry. Covers all public and private procedures since 2010.
# DBSO is more complete than LPR procedure codes alone because private clinics are
# obligated to report to DBSO but may not always submit to LPR.
#
# DBSO parquet is long format: one row per clinic visit per patient
# (PRE = pre-op assessment, PER = surgery, FOL = follow-up visits).
# surgery_type and index_date are derived here from raw DBSO flags/columns:
#   surgery_type: gastricbypass_prim == 1 -> "RYGB"; gastricsleeve_prim == 1 -> "SG"
#                 (redo_prim == 1 cases are excluded by the filter below)
#   index_date:   datoper_prim (DBSO's own clinical record of surgery date)

build_bs_cohort <- function() {
  dbso <- arrow::open_dataset(path_dbso) %>%           # open DBSO parquet lazily; long format
    filter(
      redo_prim != 1,                                   # exclude revision/redo surgeries
      gastricbypass_prim == 1 | gastricsleeve_prim == 1,  # primary RYGB or SG only
      !is.na(datoper_prim),                             # must have a valid surgery date
      as.Date(datoper_prim) >= as.Date("2010-01-01"),   # DBSO mandatory reporting began 2010; study start
      as.Date(datoper_prim) <= as.Date("2024-12-31")    # study end per protocol
    ) %>%
    select(pnr, datoper_prim, gastricbypass_prim, gastricsleeve_prim) %>%   # only columns needed to derive index_date and surgery_type
    collect() %>%                                       # pull filtered rows into R memory
    distinct(pnr, .keep_all = TRUE)                     # one row per patient; DBSO may have multiple visit rows per person

  n_dbso_start <- nrow(dbso)                            # attrition step 1: all DBSO RYGB/SG with valid date 2010-2024

  demo <- get_bef_demographics(unique(dbso$pnr))        # sex and birth date from BEF (for age and lookback checks)
  bs   <- dbso %>% left_join(demo, by = "pnr")          # attach demographics

  # Exclusion: died before surgery, age < 18 at surgery, < 5 years of registry history
  dod <- load_database("dodsaars") %>% rename_with(tolower)   # individual death records register
  deaths <- dod %>%
    filter(pnr %in% !!bs$pnr) %>%   # only DBSO patients' death records before collect
    select(pnr, doddato) %>%         # doddato = date of death (CONFIRM-2: column name assumed)
    collect()                         # pull into memory

  bs <- bs %>%
    left_join(deaths, by = "pnr") %>%   # attach death date; NA for living persons (absent from dodsaars)
    filter(
      # Protocol criterion 4: exclude death within 30 days of surgery.
      # doddato > datoper_prim + 30 excludes: (a) death before surgery (days < 0),
      # (b) death on day of surgery (day 0), (c) death within 30 days (days 1-30).
      # Patients who die in the perioperative period cannot contribute meaningful
      # dementia follow-up and represent extreme surgical risk; their exclusion
      # avoids immortal time and makes the BS cohort comparable to the protocol.
      is.na(doddato) | doddato > as.Date(datoper_prim) + 30,
      as.Date(datoper_prim) - as.Date(foed_dag) >= 365.25 * 18,  # age >= 18 at surgery
      as.Date(datoper_prim) >= as.Date(foed_dag) + 365.25 * 5    # >= 5 years of registry history before surgery
    )

  n_after_eligibility <- nrow(bs)                        # attrition step 2: after 30-day death / age / registry filters

  # Exclusion: pre-surgery dementia (LPR2 somatic + LPR2 psychiatric + LPR3)
  cutoffs       <- bs %>% transmute(pnr, index_date = as.Date(datoper_prim))   # per-person cutoff: their own surgery date
  dementia_pnrs <- get_prior_dementia_pnrs(bs$pnr, cutoffs)        # pnrs with any dementia diagnosis before surgery
  bs <- bs %>% filter(!pnr %in% dementia_pnrs)                     # remove pre-surgery dementia cases

  n_after_dementia <- nrow(bs)                           # attrition step 3: after pre-surgery dementia exclusion

  # Exclusion: antidementia medication (ATC N06D) dispensed before surgery
  # Protocol criterion 3. N06D at baseline (donepezil, rivastigmine, galantamine,
  # memantine) is diagnostic of either diagnosed or suspected dementia. Excluding
  # N06D users removes likely undiagnosed dementia cases that the ICD-code check
  # above may have missed (e.g. if the prescribing GP never registered a hospital
  # diagnosis). N06D users are also excluded from the NMI calculation (see TODO MINOR-4).
  lmdb <- load_database("lmdb") %>% rename_with(tolower)   # prescription register (DNPD/LMDB)

  max_surgery_date <- max(as.Date(bs$datoper_prim))         # upper bound for lazy parquet filter; per-person cutoff applied after collect

  n06d_pnrs <- lmdb %>%
    filter(
      pnr %in% !!bs$pnr,                                    # restrict to current BS candidates only
      substr(atc, 1, 4) == "N06D",                          # antidementia ATC class (CONFIRM-1: column name atc assumed)
      eksd <= !!max_surgery_date                             # pull all N06D dispensings up to latest surgery date
    ) %>%
    select(pnr, eksd, atc) %>%                              # only needed columns; reduce data before collect
    collect() %>%                                            # pull filtered records into memory
    inner_join(bs %>% transmute(pnr, surgery_date = as.Date(datoper_prim)), by = "pnr") %>%  # attach each person's surgery date
    filter(eksd < surgery_date) %>%    # any N06D dispensing at any time before surgery qualifies; no lower time bound (LMDB begins ~1994; same principle as ICD dementia: any prior record is an exclusion)
    distinct(pnr) %>%                                        # one row per person with any pre-surgery N06D
    pull(pnr)

  bs <- bs %>% filter(!pnr %in% n06d_pnrs)                  # remove persons with pre-surgery antidementia medication

  cohort <- bs %>%
    transmute(
      pnr,
      index_date        = as.Date(datoper_prim),                          # surgery date is the index date for the BS cohort
      cohort            = "BS",
      surgery_type      = if_else(gastricbypass_prim == 1, "RYGB", "SG"), # derive surgery type from DBSO flags; redo excluded above so all remaining are RYGB or SG
      matched_pnr       = pnr,                                            # BS patients reference themselves (used when linking to matched comparators)
      bs_crossover_date = NA_Date_                                        # not applicable for the exposed group; only comparators can cross over
    )

  list(
    cohort              = cohort,
    n_dbso_start        = n_dbso_start,        # n before any exclusions
    n_after_eligibility = n_after_eligibility, # n after 30-day death / age / registry filters
    n_after_dementia    = n_after_dementia,    # n after pre-surgery dementia exclusion
    n_final             = nrow(cohort)         # n after N06D exclusion
  )
}


# ============================================================================
# 1.2 BUILD GP COMPARATOR POOL (1:25 MATCHED, GENERAL POPULATION)
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

  # Attach BS surgery dates for pool members who appear in DBSO.
  # We do NOT exclude all DBSO members here — only those with BS before a specific
  # index date are ineligible for that particular match. The per-person date check
  # runs inside the matching loop so each BS patient applies its own index date as
  # the cutoff. Pool members with post-index BS remain eligible and are assigned
  # bs_crossover_date when sampled (censored in analysis, not excluded).
  bs_dates_in_pool <- get_bs_surgery_dates(bef_pool$pnr)        # pnr + earliest bs_surgery_date for DBSO members
  bef_pool <- bef_pool %>%
    left_join(bs_dates_in_pool, by = "pnr")                      # bs_surgery_date = NA for persons never in DBSO

  # Verify alive at each index date: load death dates for pool members.
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
  # birth_year is kept in the split data frames so the loop can check age >= 18.
  # This guards against the edge case where a comparator born 1 year later than an
  # 18-year-old BS patient would be 17 at the index date.
  pool_list <- split(bef_pool[, c("pnr", "birth_year", "death_date", "bs_surgery_date")],
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

    # Keep candidates who are:
    #   (1) alive at the index date (death_date is NA or after idx_date)
    #   (2) without bariatric surgery before or on the index date (bs_surgery_date is NA or after)
    #   (3) at least 18 years old at the index date — matches the BS cohort minimum age.
    #       This only matters when the BS patient was operated at exactly 18 years, in which
    #       case a comparator born 1 year later (within the ±1 year matching window) would be
    #       17 at the index date. Rare but worth enforcing for consistency.
    cand_df <- cand_df[
      (is.na(cand_df$death_date)      | cand_df$death_date      > idx_date) &
      (is.na(cand_df$bs_surgery_date) | cand_df$bs_surgery_date > idx_date) &
      lubridate::year(idx_date) - cand_df$birth_year >= 18L, ]
    candidates <- cand_df$pnr

    if (length(candidates) == 0) next   # no eligible match available for this BS patient

    n_sample     <- min(N_GP_PER_BS, length(candidates))
    sampled_pnrs <- sample(candidates, n_sample)   # random draw without replacement

    sampled_bs_dates <- cand_df$bs_surgery_date[match(sampled_pnrs, cand_df$pnr)]  # future BS date for each sampled control; NA if never in DBSO
    matched_rows[[i]] <- tibble(
      pnr               = sampled_pnrs,
      index_date        = idx_date,
      cohort            = "GP",
      surgery_type      = NA_character_,
      matched_pnr       = bs_pnr,
      bs_crossover_date = if_else(                                   # date this control later undergoes BS; NA if they never do
        !is.na(sampled_bs_dates) & sampled_bs_dates > idx_date,
        sampled_bs_dates, NA_Date_
      )
    )

    # Remove sampled pnrs from the pool: filter rows rather than setdiff on vectors.
    for (k in group_keys) {
      if (!is.null(pool_list[[k]])) {
        pool_list[[k]] <- pool_list[[k]][!pool_list[[k]]$pnr %in% sampled_pnrs, ]
      }
    }
  }

  gp_cohort <- bind_rows(matched_rows)

  # --------------------------------------------------------------------------
  # Match rate audit: check how many BS patients received fewer than the target
  # number of GP comparators. Zero-match patients have no controls and will be
  # invisible in all analyses — flag them explicitly so they are not silently lost.
  # --------------------------------------------------------------------------
  match_counts <- gp_cohort %>%                           # count GP comparators per BS patient
    dplyr::count(matched_pnr, name = "n_gp")
  n_zero   <- sum(!bs_cohort$pnr %in% match_counts$matched_pnr)  # BS patients with zero matches
  n_fewer  <- sum(match_counts$n_gp < N_GP_PER_BS)               # BS patients below the target ratio
  if (n_zero > 0) {
    warning("GP comparator: ", n_zero, " BS patient(s) received ZERO matches. ",
            "Consider widening birth-year window to ±2 years.")
  }
  if (n_fewer > 0) {
    message("GP comparator: ", n_fewer, " BS patient(s) matched to fewer than ",
            N_GP_PER_BS, " controls (pool exhaustion for rare birth years).")
  }

  n_matched_raw <- nrow(gp_cohort)                        # attrition: GP comparators before dementia exclusion

  # Exclude any GP comparators with pre-index dementia (ICD: F00-F03, G30-G31)
  cutoffs <- gp_cohort %>% select(pnr, index_date)
  dementia_pnrs <- get_prior_dementia_pnrs(gp_cohort$pnr, cutoffs)
  gp_after_dementia <- gp_cohort %>% filter(!pnr %in% dementia_pnrs)   # remove pre-index ICD dementia from GP comparators

  n_after_dementia <- nrow(gp_after_dementia)             # attrition after ICD dementia exclusion

  # Exclude GP comparators with pre-index N06D dispensing (same criterion as BS cohort, criterion 3a.3)
  # N06D is a proxy for undiagnosed or pre-clinical dementia not captured by ICD codes alone.
  # Applied symmetrically to all three cohorts: any dispensing before the person's index date qualifies.
  lmdb_gp <- load_database("lmdb") %>% rename_with(tolower)   # prescription register for GP comparators

  max_index_gp <- max(gp_after_dementia$index_date)           # upper bound for lazy parquet filter

  n06d_pnrs_gp <- lmdb_gp %>%
    filter(
      pnr %in% !!gp_after_dementia$pnr,                       # restrict to matched GP comparators
      substr(atc, 1, 4) == "N06D",                             # antidementia ATC class
      eksd <= !!max_index_gp                                   # pull up to latest index date; per-person cutoff applied after collect
    ) %>%
    select(pnr, eksd, atc) %>%                                 # only needed columns
    collect() %>%                                              # pull filtered records into memory
    inner_join(gp_after_dementia %>% select(pnr, index_date), by = "pnr") %>%  # attach each person's index date
    filter(eksd < index_date) %>%                              # dispensing must predate this person's index date
    distinct(pnr) %>%                                          # one row per person with any pre-index N06D
    pull(pnr)

  gp_final <- gp_after_dementia %>% filter(!pnr %in% n06d_pnrs_gp)   # remove pre-index antidementia medication users

  list(
    cohort           = gp_final,
    n_matched_raw    = n_matched_raw,     # before exclusions
    n_after_dementia = n_after_dementia,  # after ICD dementia exclusion
    n_final          = nrow(gp_final)     # after N06D exclusion
  )
}

## ---------------------------------------------------------------------------
## ALTERNATIVE FOR 1.2: heaven::exposureMatch()
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
# 1.3 BUILD OBESITY COMPARATOR POOL (1:5 MATCHED, E66 DIAGNOSIS)
# ============================================================================
# Pool: persons with E66 (obesity) diagnosis in LPR BEFORE their matched BS
# patient's index date, without prior bariatric surgery at the time of matching.
# (Post-index BS is handled by censoring at bs_crossover_date, not exclusion.)
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

  # Attach BS surgery dates — same approach as GP comparator.
  # Date-specific check inside the loop prevents pre-index BS from entering the pool
  # while allowing post-index BS candidates to be enrolled and later censored.
  bs_dates_in_pool <- get_bs_surgery_dates(obesity_pool$pnr)        # pnr + earliest bs_surgery_date for DBSO members
  obesity_pool <- obesity_pool %>%
    left_join(bs_dates_in_pool, by = "pnr")                          # bs_surgery_date = NA for persons never in DBSO

  # Verify alive at each index date: load death dates for pool members.
  dod <- load_database("dodsaars") %>% rename_with(tolower)
  pool_deaths <- dod %>%
    filter(pnr %in% !!obesity_pool$pnr) %>%
    select(pnr, death_date = doddato) %>%
    collect()

  obesity_pool <- obesity_pool %>%
    left_join(pool_deaths, by = "pnr")   # death_date = NA means still alive

  # Match to BS cohort (1:N_OBESITY_PER_BS) — same pre-split approach as GP comparator.
  # Splits into per-(koen, birth_year) data frames so we can filter on earliest_e66,
  # death_date, and bs_surgery_date inside the loop without scanning the full pool.
  bs_key <- bs_cohort %>%
    left_join(
      get_bef_demographics(bs_cohort$pnr) %>% select(pnr, koen, birth_year),
      by = "pnr"
    )

  # birth_year kept for the age >= 18 check inside the loop (same edge case as GP comparator).
  pool_list <- split(obesity_pool[, c("pnr", "birth_year", "earliest_e66", "death_date", "bs_surgery_date")],
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

    # Keep candidates whose E66 predates the index date, alive, without pre-index BS,
    # and at least 18 years old at the index date (same edge-case check as GP comparator).
    cand_df <- cand_df[
      cand_df$earliest_e66 < idx_date &
      (is.na(cand_df$death_date)      | cand_df$death_date      > idx_date) &
      (is.na(cand_df$bs_surgery_date) | cand_df$bs_surgery_date > idx_date) &
      lubridate::year(idx_date) - cand_df$birth_year >= 18L, ]
    candidates <- cand_df$pnr

    if (length(candidates) == 0) next

    n_sample     <- min(N_OBESITY_PER_BS, length(candidates))
    sampled_pnrs <- sample(candidates, n_sample)

    sampled_bs_dates <- cand_df$bs_surgery_date[match(sampled_pnrs, cand_df$pnr)]  # future BS date for each sampled control; NA if never in DBSO
    matched_rows[[i]] <- tibble(
      pnr               = sampled_pnrs,
      index_date        = idx_date,
      cohort            = "Obesity",
      surgery_type      = NA_character_,
      matched_pnr       = bs_pnr,
      bs_crossover_date = if_else(                                   # date this control later undergoes BS; NA if they never do
        !is.na(sampled_bs_dates) & sampled_bs_dates > idx_date,
        sampled_bs_dates, NA_Date_
      )
    )

    for (k in group_keys) {
      if (!is.null(pool_list[[k]])) {
        pool_list[[k]] <- pool_list[[k]][!pool_list[[k]]$pnr %in% sampled_pnrs, ]
      }
    }
  }

  ob_cohort <- bind_rows(matched_rows)

  # --------------------------------------------------------------------------
  # Match rate audit for obesity comparator.
  # Zero matches are more plausible here than for the GP comparator: early index
  # dates (2010–2012) have a smaller pool of E66-coded persons in LPR, since E66
  # coding in Danish hospitals ramped up gradually over the study period.
  # --------------------------------------------------------------------------
  ob_match_counts <- ob_cohort %>%
    dplyr::count(matched_pnr, name = "n_ob")
  n_ob_zero   <- sum(!bs_cohort$pnr %in% ob_match_counts$matched_pnr)
  n_ob_fewer  <- sum(ob_match_counts$n_ob < N_OBESITY_PER_BS)
  if (n_ob_zero > 0) {
    warning("Obesity comparator: ", n_ob_zero, " BS patient(s) received ZERO matches. ",
            "Consider widening birth-year window to ±2 years or checking E66 pool size by calendar year.")
  }
  if (n_ob_fewer > 0) {
    message("Obesity comparator: ", n_ob_fewer, " BS patient(s) matched to fewer than ",
            N_OBESITY_PER_BS, " controls.")
  }

  n_matched_raw <- nrow(ob_cohort)                        # attrition: obesity comparators before dementia exclusion

  # Exclude any obesity comparators with pre-index dementia (ICD: F00-F03, G30-G31)
  cutoffs <- ob_cohort %>% select(pnr, index_date)
  dementia_pnrs <- get_prior_dementia_pnrs(ob_cohort$pnr, cutoffs)
  ob_after_dementia <- ob_cohort %>% filter(!pnr %in% dementia_pnrs)   # remove pre-index ICD dementia from obesity comparators

  n_after_dementia <- nrow(ob_after_dementia)             # attrition after ICD dementia exclusion

  # Exclude obesity comparators with pre-index N06D dispensing (same criterion as BS cohort, criterion 3a.3)
  lmdb_ob <- load_database("lmdb") %>% rename_with(tolower)   # prescription register for obesity comparators

  max_index_ob <- max(ob_after_dementia$index_date)           # upper bound for lazy parquet filter

  n06d_pnrs_ob <- lmdb_ob %>%
    filter(
      pnr %in% !!ob_after_dementia$pnr,                       # restrict to matched obesity comparators
      substr(atc, 1, 4) == "N06D",                             # antidementia ATC class
      eksd <= !!max_index_ob                                   # pull up to latest index date; per-person cutoff applied after collect
    ) %>%
    select(pnr, eksd, atc) %>%                                 # only needed columns
    collect() %>%                                              # pull filtered records into memory
    inner_join(ob_after_dementia %>% select(pnr, index_date), by = "pnr") %>%  # attach each person's index date
    filter(eksd < index_date) %>%                              # dispensing must predate this person's index date
    distinct(pnr) %>%                                          # one row per person with any pre-index N06D
    pull(pnr)

  ob_final <- ob_after_dementia %>% filter(!pnr %in% n06d_pnrs_ob)   # remove pre-index antidementia medication users

  list(
    cohort           = ob_final,
    n_matched_raw    = n_matched_raw,     # before exclusions
    n_after_dementia = n_after_dementia,  # after ICD dementia exclusion
    n_final          = nrow(ob_final)     # after N06D exclusion
  )
}

## ---------------------------------------------------------------------------
## ALTERNATIVE FOR 1.3: heaven::exposureMatch()
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
# 1.4 MAIN: ASSEMBLE AND SAVE FULL COHORT
# ============================================================================

main_build_cohorts <- function() {
  cat("Building BS cohort and applying exclusions...\n")
  bs_result <- build_bs_cohort()                         # returns list(cohort, n_dbso_start, n_after_eligibility, n_final)
  bs_cohort  <- bs_result$cohort                         # extract cohort data frame from the result list
  # Sort by surgery date ascending before matching.
  # In incidence density sampling (risk-set matching), earlier cases draw from the
  # pool first, mimicking the temporal precedence of prospective enrollment. This
  # ensures patients with earlier surgery dates are not disadvantaged by pool
  # depletion caused by later patients being processed first.
  bs_cohort <- bs_cohort %>% dplyr::arrange(index_date)
  cat("  BS cohort n =", nrow(bs_cohort), "\n")

  cat("Building GP comparator cohort...\n")
  gp_result  <- build_gp_comparator(bs_cohort)           # returns list(cohort, n_matched_raw, n_final)
  gp_cohort  <- gp_result$cohort                         # extract cohort data frame
  cat("  GP comparator n =", nrow(gp_cohort), "\n")

  cat("Building obesity comparator cohort...\n")
  ob_result  <- build_obesity_comparator(bs_cohort)      # returns list(cohort, n_matched_raw, n_final)
  ob_cohort  <- ob_result$cohort                         # extract cohort data frame
  cat("  Obesity comparator n =", nrow(ob_cohort), "\n")

  # bs_crossover_date is set inside build_gp_comparator() and build_obesity_comparator()
  # at match time, so it is already present in gp_cohort and ob_cohort rows.
  # bs_cohort rows carry bs_crossover_date = NA_Date_ (set in build_bs_cohort()).
  # bind_rows aligns columns by name; no additional crossover logic needed here.
  full_cohort <- bind_rows(bs_cohort, gp_cohort, ob_cohort) %>%
    mutate(cohort = factor(cohort, levels = c("BS", "GP", "Obesity")))   # ordered factor for table/plot ordering

  # --------------------------------------------------------------------------
  # Attrition flow table — print to console for documentation and spot-checking.
  # Printed rather than saved so it is visible in the script log without
  # creating a separate output file. Capture with sink() if a log file is needed.
  # --------------------------------------------------------------------------
  cat("\n")
  cat(sprintf("%-52s %8s %12s\n", "Attrition step", "n", "Excluded"))
  cat(strrep("-", 74), "\n")
  cat(sprintf("%-52s %8d %12s\n",
      "DBSO: all RYGB/SG 2010-2024",
      bs_result$n_dbso_start, ""))
  cat(sprintf("%-52s %8d %12d\n",
      "  After: 30-day death / age <18 / <5-yr registry",
      bs_result$n_after_eligibility,
      bs_result$n_dbso_start - bs_result$n_after_eligibility))
  cat(sprintf("%-52s %8d %12d\n",
      "  After: pre-surgery dementia (ICD)",
      bs_result$n_after_dementia,
      bs_result$n_after_eligibility - bs_result$n_after_dementia))
  cat(sprintf("%-52s %8d %12d\n",
      "  After: pre-surgery N06D prescriptions",
      bs_result$n_final,
      bs_result$n_after_dementia - bs_result$n_final))
  cat(sprintf("%-52s %8d %12s\n", "BS cohort (final)", bs_result$n_final, ""))
  cat(strrep("-", 74), "\n")
  cat(sprintf("%-52s %8d %12s\n",
      "GP comparators matched (before dementia check)",
      gp_result$n_matched_raw, ""))
  cat(sprintf("%-52s %8d %12d\n",
      "  After: pre-index dementia (ICD)",
      gp_result$n_after_dementia,
      gp_result$n_matched_raw - gp_result$n_after_dementia))
  cat(sprintf("%-52s %8d %12d\n",
      "  After: pre-index N06D prescriptions",
      gp_result$n_final,
      gp_result$n_after_dementia - gp_result$n_final))
  cat(sprintf("%-52s %8d %12s\n", "GP cohort (final)", gp_result$n_final, ""))
  cat(strrep("-", 74), "\n")
  cat(sprintf("%-52s %8d %12s\n",
      "Obesity comparators matched (before dementia check)",
      ob_result$n_matched_raw, ""))
  cat(sprintf("%-52s %8d %12d\n",
      "  After: pre-index dementia (ICD)",
      ob_result$n_after_dementia,
      ob_result$n_matched_raw - ob_result$n_after_dementia))
  cat(sprintf("%-52s %8d %12d\n",
      "  After: pre-index N06D prescriptions",
      ob_result$n_final,
      ob_result$n_after_dementia - ob_result$n_final))
  cat(sprintf("%-52s %8d %12s\n", "Obesity cohort (final)", ob_result$n_final, ""))
  cat(strrep("-", 74), "\n")
  cat(sprintf("%-52s %8d %12s\n", "TOTAL full_cohort", nrow(full_cohort), ""))
  cat("\n")

  dir.create(path_output, showWarnings = FALSE, recursive = TRUE)
  saveRDS(full_cohort, file.path(path_output, "full_cohort.rds"))
  cat("Saved: full_cohort.rds\n")
  invisible(full_cohort)
}

# Run:
# full_cohort <- main_build_cohorts()
