# ============================================================================
# PIPELINE STEP 7 — 07_analysis_dementia.R
# ============================================================================
# Statistical analyses for Study 1 (bariatric surgery and dementia).
# Run after Step 6 (06_descriptive_statistics_dementia.R).
#
# Run each section interactively by selecting and executing the block.
# Sections build on each other only where noted (Cox results reused in Table 3).
#
# Contents:
#   7.1  Crude incidence rates                                      [§7b]
#   7.2  Time-band incidence rates [0–1 yr] and [1 yr+]            [§7e]
#   7.3  Stratified incidence rates (sex, age, diabetes)            [§7b]
#   7.4  Main Cox models (3 comparisons × 3 models × 3 outcomes)   [§7c]
#   7.5  Proportional hazards assumption checks                     [§7c]
#   7.6  Competing risk — Fine-Gray (all-cause dementia, Model 3)   [§7d]
#   7.7  Table 3: Cox + Fine-Gray combined
#   7.8  Subgroup analyses (BS vs GP, Model 3)                      [§7f]
#   7.9  Sensitivity analyses SA1–SA5                               [§7g]
#
# NOTE — clustering: cluster(matched_pnr) used for matched comparisons
#   (robust sandwich SE). TBD: strata(matched_pnr) alternative — see [B1].
# NOTE — SA3 and SA4 print a skip message if required columns are absent.
#
# Input:  datasets/study1_clean.rds
# Output: datasets/table2_ir.csv, table3_cox_finegray.csv,
#         table4_subgroups.csv, table_sensitivity.csv
# ============================================================================

library(dplyr)
library(survival)      # coxph(), Surv(), cox.zph(), finegray()
library(broom)         # tidy() for model output
library(ggplot2)       # log-log plots

path_datasets <- "E:/workdata/708421/workspaces/SaraSchwartz/BS_demens/datasets"

study1 <- readRDS(file.path(path_datasets, "study1_clean.rds"))   # analysis dataset from Steps 4–5


# ============================================================================
# ANALYSIS PARAMETERS
# Edit this block to change comparisons, outcomes, or covariate sets globally.
# ============================================================================

comparisons <- list(
  list(label = "BS_vs_GP",
       filter = quote(cohort %in% c("BS", "GP")),
       exposure = "cohort", ref = "GP",      cluster = TRUE),
  list(label = "BS_vs_Obesity",
       filter = quote(cohort %in% c("BS", "Obesity")),
       exposure = "cohort", ref = "Obesity", cluster = TRUE),
  list(label = "RYGB_vs_SG",
       filter = quote(cohort == "BS" & !is.na(surgery_type)),
       exposure = "surgery_type", ref = "SG", cluster = FALSE)
)

outcomes <- list(
  list(event = "dementia_event",   time = "follow_up_days",      label = "All-cause dementia"),
  list(event = "alzheimers_event", time = "follow_up_days_alz",  label = "Alzheimers disease"),
  list(event = "vascular_event",   time = "follow_up_days_vasc", label = "Vascular dementia")
)

adj_models <- list(
  list(label = "Model1", covars = character(0)),
  list(label = "Model2", covars = c("age_at_surgery", "sex")),
  list(label = "Model3", covars = c("age_at_surgery", "sex", "nmi_score",
                                     "education_cat", "income_cat",
                                     "occupation_cat", "surgery_period"))
)


# ============================================================================
# SMALL HELPERS (called repeatedly inside loops below)
# ============================================================================

ir_row <- function(n_events, person_years, per = 100) {
  # Exact Poisson 95% CI for one incidence rate.
  data.frame(
    n_events     = n_events,
    person_years = round(person_years, 1),
    IR    = round(n_events / person_years * per, 2),
    CI_lo = round(qgamma(0.025, shape = n_events)     / person_years * per, 2),
    CI_hi = round(qgamma(0.975, shape = n_events + 1) / person_years * per, 2)
  )
}

prep_comp <- function(df, comp) {
  # Filter to two groups and set reference level for Cox.
  df %>%
    filter(eval(comp$filter)) %>%
    mutate(!!comp$exposure := relevel(factor(.data[[comp$exposure]]), ref = comp$ref))
}

run_cox <- function(df, time_var, event_var, exposure_var, covars, use_cluster) {
  # Fit one Cox model. Returns coxph object.
  terms       <- c(exposure_var, covars)
  cluster_str <- if (use_cluster) " + cluster(matched_pnr)" else ""
  formula_str <- paste0("Surv(", time_var, ", ", event_var, ") ~ ",
                        paste(terms, collapse = " + "), cluster_str)
  coxph(as.formula(formula_str), data = df, ties = "efron")
}

extract_hr <- function(fit, exposure_var, comp_label, outcome_label, model_label) {
  # Pull HR + 95% CI + p from a coxph object for the exposure term only.
  tidy(fit, exponentiate = TRUE, conf.int = TRUE) %>%
    filter(startsWith(term, exposure_var)) %>%
    slice(1) %>%
    transmute(comparison = comp_label, outcome = outcome_label, model = model_label,
              HR = round(estimate, 2), CI_lo = round(conf.low, 2),
              CI_hi = round(conf.high, 2), p_value = round(p.value, 4))
}


# ============================================================================
# 7.1 CRUDE INCIDENCE RATES — TABLE 2
# ============================================================================
# All outcomes × all cohorts. Exact Poisson 95% CI. Per 100 person-years.

table2_ir <- bind_rows(lapply(outcomes, function(o) {
  rates <- study1 %>%
    group_by(cohort) %>%
    summarise(n_ev = sum(.data[[o$event]], na.rm = TRUE),
              py   = sum(.data[[o$time]],  na.rm = TRUE) / 365.25) %>%
    ungroup()

  bind_rows(lapply(seq_len(nrow(rates)), function(i) {
    cbind(data.frame(outcome = o$label, cohort = as.character(rates$cohort[i])),
          ir_row(rates$n_ev[i], rates$py[i]))
  }))
}))

print(table2_ir, row.names = FALSE)
write.csv(table2_ir, file.path(path_datasets, "table2_ir.csv"), row.names = FALSE)


# ============================================================================
# 7.2 TIME-BAND INCIDENCE RATES — [0–1 YR] AND [1 YR+]
# ============================================================================
# Addresses surveillance bias question: are early events (0–1 yr) driving
# the association, or does the pattern hold in the long-term period (1 yr+)?
# NOTE: two-band approach pending supervisor confirmation — see TODO [ANALYSIS-1].

bands <- list(
  list(start =    0, end =  365, label = "0-1yr"),
  list(start =  365, end =  Inf, label = "1yr+")
)

table2b_bands <- bind_rows(lapply(outcomes, function(o) {
  bind_rows(lapply(bands, function(b) {
    df_band <- study1 %>%
      filter(.data[[o$event]] == 0 | .data[[o$time]] > b$start) %>%   # event-free at band start
      mutate(
        band_event = as.integer(.data[[o$event]] == 1 &
                                  .data[[o$time]] >  b$start &
                                  .data[[o$time]] <= b$end),
        band_time  = (pmin(.data[[o$time]], b$end) - b$start) / 365.25
      ) %>%
      filter(band_time > 0)

    rates <- df_band %>%
      group_by(cohort) %>%
      summarise(n_ev = sum(band_event), py = sum(band_time)) %>%
      ungroup()

    bind_rows(lapply(seq_len(nrow(rates)), function(i) {
      cbind(data.frame(outcome = o$label, band = b$label,
                       cohort = as.character(rates$cohort[i])),
            ir_row(rates$n_ev[i], rates$py[i]))
    }))
  }))
}))

print(table2b_bands, row.names = FALSE)
write.csv(table2b_bands, file.path(path_datasets, "table2b_timeband_ir.csv"), row.names = FALSE)


# ============================================================================
# 7.3 STRATIFIED INCIDENCE RATES — BS VS GP, ALL-CAUSE DEMENTIA
# ============================================================================
# Stratified by sex, age (<50 / ≥50), and baseline diabetes status.

study1 <- study1 %>%
  mutate(age_50 = factor(ifelse(age_at_surgery < 50, "<50", ">=50"),
                         levels = c(">=50", "<50")))   # binary age for subgroup analyses

df_bsgp <- study1 %>% filter(cohort %in% c("BS", "GP"))   # primary comparison only

strat_vars <- list(
  list(var = "sex",          label = "Sex"),
  list(var = "age_50",       label = "Age group (<50 / >=50)"),
  list(var = "diabetes_type",label = "Diabetes status")
)

table2c_strat <- bind_rows(lapply(strat_vars, function(sv) {
  rates <- df_bsgp %>%
    group_by(cohort, .data[[sv$var]]) %>%
    summarise(n_ev = sum(dementia_event, na.rm = TRUE),
              py   = sum(follow_up_days, na.rm = TRUE) / 365.25) %>%
    ungroup()

  bind_rows(lapply(seq_len(nrow(rates)), function(i) {
    cbind(data.frame(stratifier = sv$label,
                     stratum    = as.character(rates[[sv$var]][i]),
                     cohort     = as.character(rates$cohort[i])),
          ir_row(rates$n_ev[i], rates$py[i]))
  }))
}))

print(table2c_strat, row.names = FALSE)
write.csv(table2c_strat, file.path(path_datasets, "table2c_stratified_ir.csv"), row.names = FALSE)


# ============================================================================
# 7.4 MAIN COX MODELS — TABLE 3 (Cox portion)
# ============================================================================
# 3 comparisons × 3 models × 3 outcomes = 27 Cox models.

cox_results <- bind_rows(lapply(comparisons, function(comp) {
  df_comp <- prep_comp(study1, comp)

  bind_rows(lapply(outcomes, function(o) {
    bind_rows(lapply(adj_models, function(m) {
      fit <- run_cox(df_comp, o$time, o$event,
                     comp$exposure, m$covars, comp$cluster)
      extract_hr(fit, comp$exposure, comp$label, o$label, m$label)
    }))
  }))
}))

print(cox_results, row.names = FALSE)


# ============================================================================
# 7.5 PROPORTIONAL HAZARDS ASSUMPTION — LOG-LOG PLOTS + SCHOENFELD RESIDUALS
# ============================================================================
# Model 3, all-cause dementia, all three comparisons.
# cox.zph(): p < 0.05 indicates violation of PH assumption.
# Log-log plots saved as PDFs (Supplementary Figure S1).

for (comp in comparisons) {
  df_comp <- prep_comp(study1, comp)
  fit_ph  <- run_cox(df_comp, "follow_up_days", "dementia_event",
                     comp$exposure, adj_models[[3]]$covars, comp$cluster)

  cat("\n--- PH check:", comp$label, "---\n")
  print(cox.zph(fit_ph))   # Schoenfeld residual test per covariate

  # Log-log plot: parallel lines = PH holds
  pdf(file.path(path_datasets, paste0("ph_loglog_", comp$label, ".pdf")))
  plot(
    survfit(as.formula(paste0("Surv(follow_up_days, dementia_event) ~ ", comp$exposure)),
            data = df_comp),
    fun  = "cloglog",
    main = paste("Log-log:", comp$label),
    xlab = "log(days)", ylab = "log(-log(S))"
  )
  dev.off()
}


# ============================================================================
# 7.6 FINE-GRAY COMPETING RISK — ALL-CAUSE DEMENTIA, MODEL 3
# ============================================================================
# Subdistribution hazard model (Fine-Gray) for all-cause dementia.
# Death is the competing event (event_type: 0=censored, 1=dementia, 2=death).
# For secondary outcomes (Alzheimer's, vascular), cause-specific Cox is
# reported; Fine-Gray for subtypes requires a separate event_type coding.

study1 <- study1 %>%
  mutate(
    event_f = factor(event_type, levels = c(0, 1, 2),
                     labels = c("censored", "dementia", "death"))   # factor needed by finegray()
  )

fg_results <- bind_rows(lapply(comparisons, function(comp) {
  df_comp <- prep_comp(study1, comp) %>%
    mutate(event_f = factor(event_type, levels = c(0, 1, 2),
                            labels = c("censored", "dementia", "death")))

  fg_covars <- c(comp$exposure, adj_models[[3]]$covars)   # exposure + Model 3 covariates

  fg_data <- finegray(
    as.formula(paste0("Surv(follow_up_days, event_f) ~ ",
                      paste(fg_covars, collapse = " + "))),
    data  = df_comp,
    etype = "dementia"    # dementia is the cause of interest; death is competing
  )

  fit_fg <- coxph(
    as.formula(paste0("Surv(fgstart, fgstop, fgstatus) ~ ",
                      paste(fg_covars, collapse = " + "))),
    data   = fg_data,
    weight = fgwt,        # subdistribution weights from finegray()
    ties   = "efron"
  )

  extract_hr(fit_fg, comp$exposure, comp$label,
             "All-cause dementia (Fine-Gray)", "Model3")
}))

print(fg_results, row.names = FALSE)


# ============================================================================
# 7.7 TABLE 3: COX + FINE-GRAY COMBINED
# ============================================================================

table3 <- bind_rows(
  cox_results %>% mutate(method = "Cox"),
  fg_results  %>% mutate(method = "Fine-Gray")
)

print(table3, row.names = FALSE)
write.csv(table3, file.path(path_datasets, "table3_cox_finegray.csv"), row.names = FALSE)


# ============================================================================
# 7.8 SUBGROUP ANALYSES — TABLE 4
# ============================================================================
# All-cause dementia, BS vs GP, Model 3. Pre-specified subgroups: sex, age
# (<50/≥50), diabetes status, surgery type (within BS cohort).
# Interaction p-value from likelihood ratio test.

df_comp_bsgp <- prep_comp(study1, comparisons[[1]])   # BS vs GP, reference = GP

subgroup_vars <- list(
  list(var = "sex",          label = "Sex"),
  list(var = "age_50",       label = "Age at surgery"),
  list(var = "diabetes_type",label = "Diabetes status")
)

table4 <- bind_rows(lapply(subgroup_vars, function(sv) {
  base_covars <- adj_models[[3]]$covars

  # Main effects model (no interaction)
  fit_main <- run_cox(df_comp_bsgp, "follow_up_days", "dementia_event",
                      "cohort", c(sv$var, base_covars), use_cluster = TRUE)

  # Interaction model
  int_terms <- c(paste0("cohort * ", sv$var), base_covars)
  fit_int   <- coxph(
    as.formula(paste0("Surv(follow_up_days, dementia_event) ~ ",
                      paste(int_terms, collapse = " + "),
                      " + cluster(matched_pnr)")),
    data = df_comp_bsgp, ties = "efron"
  )

  p_int <- anova(fit_main, fit_int)[["P(>|Chi|)"]][2]   # LRT interaction p-value

  # Stratum-specific HRs: refit Model 3 within each stratum
  strata_levels <- levels(df_comp_bsgp[[sv$var]])
  bind_rows(lapply(strata_levels, function(s) {
    df_s     <- df_comp_bsgp %>% filter(.data[[sv$var]] == s)
    n_events <- sum(df_s$dementia_event)

    if (n_events < 5) {    # flag strata with too few events rather than crashing
      return(data.frame(stratifier = sv$label, stratum = s,
                        n = nrow(df_s), n_events = n_events,
                        HR = NA, CI_lo = NA, CI_hi = NA,
                        p_value = NA, p_interaction = round(p_int, 4)))
    }

    fit_s <- run_cox(df_s, "follow_up_days", "dementia_event",
                     "cohort", base_covars, use_cluster = FALSE)   # no cluster within stratum

    extract_hr(fit_s, "cohort", "BS_vs_GP", "All-cause dementia", sv$label) %>%
      mutate(stratifier = sv$label, stratum = s,
             n = nrow(df_s), n_events = n_events,
             p_interaction = round(p_int, 4))
  }))
}))

# Surgery type subgroup: RYGB vs SG within BS cohort (no GP needed here)
df_bs_type <- study1 %>%
  filter(cohort == "BS", !is.na(surgery_type)) %>%
  mutate(surgery_type = relevel(factor(surgery_type), ref = "SG"))

fit_stype  <- run_cox(df_bs_type, "follow_up_days", "dementia_event",
                      "surgery_type", adj_models[[3]]$covars, use_cluster = FALSE)
subtype_row <- extract_hr(fit_stype, "surgery_type", "BS_vs_GP",
                           "All-cause dementia", "Surgery type") %>%
  mutate(stratifier = "Surgery type", stratum = "RYGB vs SG",
         n = nrow(df_bs_type), n_events = sum(df_bs_type$dementia_event),
         p_interaction = NA_real_)

table4 <- bind_rows(table4, subtype_row)

print(table4 %>% select(stratifier, stratum, n, n_events, HR, CI_lo, CI_hi,
                         p_value, p_interaction), row.names = FALSE)
write.csv(table4, file.path(path_datasets, "table4_subgroups.csv"), row.names = FALSE)


# ============================================================================
# 7.9 SENSITIVITY ANALYSES — SUPPLEMENTARY TABLE
# ============================================================================
# Each SA runs Model 3, BS vs GP and BS vs Obesity (unless stated otherwise).
# See methods plan §7g for rationale of each.

sa_results <- list()

# --- SA1: A-code only dementia (§7g.1) ---
# Restricts to diagnosis type A (primary diagnosis / hoveddiagnose) only.
sa_results[["SA1_Acode"]] <- bind_rows(lapply(comparisons[1:2], function(comp) {
  df_comp <- prep_comp(study1, comp)
  fit     <- run_cox(df_comp, "follow_up_days_primary", "dementia_event_primary",
                     comp$exposure, adj_models[[3]]$covars, comp$cluster)
  extract_hr(fit, comp$exposure, comp$label,
             "All-cause dementia (SA1: A-code only)", "Model3")
}))

# --- SA2: Exclude first 12 months (§7g.2) ---
# Removes events in first year to address surveillance bias / unmasking.
df_sa2 <- study1 %>%
  filter(follow_up_days > 365 | dementia_event == 0) %>%   # keep event-free at 1 year
  mutate(
    follow_up_days_sa2 = follow_up_days - 365,              # restart time from 1-year landmark
    dementia_event_sa2 = as.integer(dementia_event == 1 & follow_up_days > 365)
  )

sa_results[["SA2_exclude12mo"]] <- bind_rows(lapply(comparisons[1:2], function(comp) {
  df_comp <- prep_comp(df_sa2, comp)
  fit     <- run_cox(df_comp, "follow_up_days_sa2", "dementia_event_sa2",
                     comp$exposure, adj_models[[3]]$covars, comp$cluster)
  extract_hr(fit, comp$exposure, comp$label,
             "All-cause dementia (SA2: exclude 12 months)", "Model3")
}))

# --- SA3: No comparator crossover censoring (§7g.4) ---
# Main analysis censors comparators when they receive BS. This SA removes that
# censoring. Requires follow_up_end column; skip if absent.
if (!"follow_up_end" %in% names(study1)) {
  cat("SA3 SKIPPED: follow_up_end not in study1_clean.rds.\n")
  cat("  Add follow_up_end to 04_data_management_dementia.R merge, then re-run.\n")
} else {
  df_sa3 <- study1 %>%
    mutate(
      censor_sa3 = follow_up_end,                             # ignore bs_crossover_date
      dementia_event_sa3 = as.integer(!is.na(date_dementia) & date_dementia <= censor_sa3),
      follow_up_days_sa3 = as.numeric(difftime(
        if_else(dementia_event_sa3 == 1L, date_dementia, censor_sa3),
        surgery_date, units = "days"
      ))
    )
  sa_results[["SA3_no_crossover"]] <- bind_rows(lapply(comparisons[1:2], function(comp) {
    df_comp <- prep_comp(df_sa3, comp)
    fit     <- run_cox(df_comp, "follow_up_days_sa3", "dementia_event_sa3",
                       comp$exposure, adj_models[[3]]$covars, comp$cluster)
    extract_hr(fit, comp$exposure, comp$label,
               "All-cause dementia (SA3: no crossover censoring)", "Model3")
  }))
}

# --- SA4: GLP-1 censoring of obesity comparators (§[B5]) ---
# Censors obesity comparators at first GLP-1 RA dispensing at obesity dose.
# Requires date_glp1_obesity in study1_clean.rds; skip if absent.
if (!"date_glp1_obesity" %in% names(study1)) {
  cat("SA4 SKIPPED: date_glp1_obesity not in study1_clean.rds.\n")
  cat("  Extract first A10BJ dispensing (liraglutide >= 2.4mg or semaglutide >= 1mg)\n")
  cat("  for obesity comparators from LMDB in 02, add to merge in 04, then re-run.\n")
} else {
  df_sa4 <- study1 %>%
    mutate(
      censor_sa4 = if_else(
        cohort == "Obesity" & !is.na(date_glp1_obesity) & date_glp1_obesity < censor_date,
        date_glp1_obesity, censor_date                     # censor obesity comparators at GLP-1 start
      ),
      dementia_event_sa4 = as.integer(!is.na(date_dementia) & date_dementia <= censor_sa4),
      follow_up_days_sa4 = as.numeric(difftime(
        if_else(dementia_event_sa4 == 1L, date_dementia, censor_sa4),
        surgery_date, units = "days"
      ))
    )
  df_bsob_sa4 <- df_sa4 %>%
    filter(cohort %in% c("BS", "Obesity")) %>%
    mutate(cohort = relevel(factor(cohort), ref = "Obesity"))

  fit_sa4 <- run_cox(df_bsob_sa4, "follow_up_days_sa4", "dementia_event_sa4",
                     "cohort", adj_models[[3]]$covars, use_cluster = TRUE)

  sa_results[["SA4_GLP1"]] <- extract_hr(fit_sa4, "cohort", "BS_vs_Obesity",
                                          "All-cause dementia (SA4: GLP-1 censoring)", "Model3")
}

# --- SA5: Negative control outcome — cataract (§7g.6) ---
# H25 + H26 (without H28). No plausible causal pathway from BS.
# HR near 1.0 supports internal validity of the main result.
sa_results[["SA5_cataract"]] <- bind_rows(lapply(comparisons[1:2], function(comp) {
  df_comp <- prep_comp(study1, comp)
  fit     <- run_cox(df_comp, "follow_up_days_cataract", "cataract_event",
                     comp$exposure, adj_models[[3]]$covars, comp$cluster)
  extract_hr(fit, comp$exposure, comp$label,
             "Cataract (SA5: negative control)", "Model3")
}))

# Combine and save
table_sa <- bind_rows(sa_results)
print(table_sa, row.names = FALSE)
write.csv(table_sa, file.path(path_datasets, "table_sensitivity.csv"), row.names = FALSE)
