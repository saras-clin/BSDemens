---
title: "Study 1: Bariatric Surgery and Dementia — Methods Plan"
date: "Last updated: 2026-05-08"
---

**Based on:** Protocol draft "BS and dementia\_SS.txt" — reviewed and reconciled  
**Journal target:** To be decided

---

## 1. Study Design and Setting

Nationwide population-based retrospective cohort study using linked Danish health registries. Denmark is an ideal setting: bariatric surgery is centralised, all procedures (public and private, ~50% each) are mandatorily reported to the Danish Quality Registry for Treatment of Severe Obesity (**DBSO**) since 2010, and the universal tax-funded health system provides near-complete registration.

- **Study period:** January 1, 2010 – December 31, 2024 (surgery / index date)
- **Follow-up end:** December 31, 2025
- **Minimum lookback before index:** 5 years (required to ascertain baseline comorbidities per NMI)

---

## 2. Data Sources

- **DBSO** (SunDK): surgery dates, procedure type, anthropometric data.
  - *Index date source:* DatoPER\_prim (DBSO's own clinical record of surgery date). DBSO also contains OpDateLPR (surgery date as recorded in LPR). These two dates should agree closely; discrepancies reflect administrative lag or coding differences.
  - *Planned data quality check:* Distribution of (DatoPER\_prim − OpDateLPR) in days. If ≥95% agree within 7 days → use DatoPER\_prim, no sensitivity analysis. If systematic discrepancy → add sensitivity analysis 7g.5.
  - *Reporting completeness note:* DBSO became mandatory in 2010 but completeness likely improved over the first years. Incomplete reporting primarily affects the obesity comparator pool — persons who had bariatric surgery before 2010 would not appear in DBSO and cannot be flagged as previously bariatric-operated. The match-rate audit will flag BS patients who receive zero obesity comparator matches. If ≥5% of 2010–2012 BS patients have zero obesity comparator matches, a sensitivity analysis restricting to index dates from 2013 onwards will be added. Confirm exact completeness figures with DBSO registry managers (SunDK) before citing specific years or percentages in the manuscript.

- **CRS / BEF + DOD:** age, sex, birth date, migration, vital status (since 1968)
- **DNPR / LPR2 + LPR3:** somatic hospital diagnoses and procedures (since 1995)
- **DCPRR:** all psychiatric hospital/clinic contacts (since 1970). *Reference: Mors O, Perto GP, Mortensen PB. Scand J Public Health 2011;39(7 Suppl):54–7.*
- **DNPD / LMDB:** redeemed prescriptions (since 1994)
- **IDLMR (UDDA + AKM + FAIK):** education, occupation, income (since 1980). *Reference: Petersson F et al. Scand J Public Health 2011;39(7 Suppl):95–8.*

---

## 3. Study Population

### 3a. Exposed Cohort — Bariatric Surgery (BS) Patients

All Danish residents who underwent primary **RYGB** or **sleeve gastrectomy (SG)** between January 1, 2010 and December 31, 2024, as recorded in DBSO. DBSO is used in preference to LPR procedure codes because it provides the authoritative surgery date and is more complete for private-clinic procedures.

- **RYGB:** GastricBypass\_prim = 1 (SKS codes: KJDF10, KJDF11)
- **SG:** GastricSleeve\_prim = 1 (SKS codes: KJDF40, KJDF41, KJDF96, KJDF97)

The cohort is divided into an RYGB sub-cohort and an SG sub-cohort.

#### Exclusion Criteria (applied in order)

1. **Revision surgery or any prior bariatric procedure.**  
   DBSO records ReDo\_prim = 1 for all revision/redo operations, covering revision bypass (GastricBypass\_prim = 1 AND ReDo\_prim = 1), revision sleeve (GastricSleeve\_prim = 1 AND ReDo\_prim = 1, or GastricSleeveReDo = 1), and conversion procedures (Konverteret = 1). Implementation: prepare\_dbso.R checks ReDo\_prim first — a revision bypass is classified as "ReDo", not "RYGB". build\_bs\_cohort() then filters surgery\_type %in% c("RYGB", "SG"), automatically excluding "ReDo" and "Unknown" rows.  
   *Limitation:* Prior bariatric procedures performed before DBSO's 2010 start or carried out abroad cannot be identified through this flag alone.  
   *[Protocol reviewer comment: confirm proportion of re-operations]*

2. **Dementia diagnosis** (ICD-10: F00–F03, G30–G31) at any time before index — from DNPR (somatic) AND DCPRR (psychiatric).

3. **Antidementia medication (ATC N06D) dispensed before index date.**  
   ATC class N06D comprises all licensed pharmacological treatments for dementia: the cholinesterase inhibitors donepezil, rivastigmine, and galantamine (ATC N06DA), and the NMDA receptor antagonist memantine (ATC N06DX). In Denmark these agents are prescribed exclusively for patients with established or strongly suspected dementia — they have no other clinical indication. A dispensing recorded before the index date therefore indicates that the patient already had clinical or prodromal dementia prior to surgery. Including these patients would introduce prevalent disease at baseline and bias the incidence estimate toward the null. This criterion is applied symmetrically to all three cohorts (BS, GP, obesity). The symmetry is important: patients in the GP comparator and obesity comparator who are managed entirely in primary care may receive N06D prescriptions without ever receiving a hospital-based ICD-10 dementia code (criterion 2 captures hospital contacts only). N06D dispensing therefore serves as a complementary and necessary exclusion that captures primary-care-diagnosed dementia cases that criterion 2 alone would miss.

4. **Death within 30 days of surgery**
5. **Fewer than 5 years of registry history before index date**

> **Note on healthy user / surveillance bias** *(Protocol comment s):* Patients with incipient cognitive decline are likely excluded from BS eligibility at the preoperative assessment. This could artefactually lower dementia rates post-surgery and must be addressed in limitations and in the sensitivity analysis (exclusion of early events, criterion 7g.2).

### 3b. Comparison Cohort 1 — General Population (GP)

Risk-set matched **1:25** to each BS patient on sex and birth year (± 1 year), sampled from BEF (annual January 1 population snapshots).

#### Matching Procedure

For each BS patient, eligible GP candidates must satisfy all of the following at the BS patient's surgery date (= the candidate's assigned index date):

- (a) Not be a BS patient themselves
- (b) Same sex as the BS patient
- (c) Birth year within ± 1 year of the BS patient
- (d) Alive on the exact surgery date (verified via dodsaars death register — BEF is an annual January 1 snapshot so mid-year death is not captured without this check)
- (e) No prior bariatric surgery: absent from DBSO, or earliest DBSO surgery date strictly after the BS patient's index date
- (f) Age ≥ 18 years at the index date

N = 25 candidates are drawn at random (without replacement) from the eligible pool. Each person can be matched to at most one BS patient.

#### Pool Depletion and Temporal Ordering

Each sampled comparator is immediately removed from the eligibility pool (sampling without replacement). The BS cohort is sorted by surgery date (ascending) before the matching loop begins, mirroring the natural temporal precedence of incidence density sampling. A match-rate audit runs after each matching loop; patients who receive fewer than the target number of controls are flagged.

#### Bariatric Surgery Crossover

Pool members who have a DBSO surgery date *after* a candidate's potential index date are eligible controls at enrolment — they were unexposed at baseline. If sampled, they are enrolled and assigned `bs_crossover_date` (= their own surgery date). In the survival analysis they contribute unexposed person-time from index date until `bs_crossover_date`, at which point they are censored. Excluding them entirely would condition on a future event and introduce selection bias.

#### Exclusions Applied After Matching

- Pre-index dementia (F00–F03, G30–G31) from LPR2 somatic, LPR2 psychiatric, and LPR3
- Pre-index N06D dispensing (same criterion as BS cohort exclusion 3a.3)

**Index date** = surgery date of the matched BS patient.

> **Methodological note — GP comparator cannot isolate the surgical effect from obesity:** The GP comparator is drawn from the full general population and therefore includes persons without severe obesity. The BS vs GP comparison estimates the combined effect of bariatric surgery AND the long-term consequences of not having had severe obesity — it does not isolate the surgical procedure as the causal agent. This comparison is most useful for quantifying absolute dementia risk relative to an average population control and for benchmarking against prior literature.
>
> *The causally targeted comparison is BS vs obesity comparator (Section 3c), which holds obesity status approximately constant.* Suggested framing for the manuscript: state explicitly that the GP comparator addresses "what is the dementia risk for a BS patient relative to a comparable person in the general population" while the obesity comparator addresses "does bariatric surgery change dementia risk relative to living with untreated severe obesity." Present BS vs obesity as the primary causal result; BS vs GP as the secondary descriptive result. Acknowledge the limitation in the methods section and again in the discussion.

### 3c. Comparison Cohort 2 — Obesity Cohort

Individuals identified by ICD-10 **E66** (obesity) in DNPR (LPR2 or LPR3) at any time before the BS patient's index date. Risk-set matched **1:5** using the same procedure as the GP comparator (see 3b), with one additional eligibility requirement.

**Additional eligibility criterion:** At least one recorded E66 diagnosis with a contact date strictly before the BS patient's index date. The presence of any prior E66 record is a binary gate — the specific date has no further role in eligibility or analysis.

**Assumption — obesity as a chronic condition:** Obesity (E66) is treated as a chronic, persistent disorder. A person who received an E66 diagnosis at any point before the index date is assumed to still be obese at that date. This assumption is supported by clinical literature showing that body weight at the level qualifying for an E66 code does not normalise spontaneously or durably without major intervention. A recency requirement is not imposed to avoid differential exclusion across calendar periods (E66 coding practices changed over time).

*References: Gribsholt SB et al. Clin Epidemiol 2019;11:845–54; Sjostrom L et al. N Engl J Med 2007;357:741–52.*

> **Note:** E66 has low sensitivity for overweight; it captures primarily the more severely obese end of the weight spectrum. This is acceptable because BS eligibility itself requires severe obesity (BMI ≥ 40 or ≥ 35 with comorbidity).

#### GLP-1 Receptor Agonist Use in the Obesity Comparator — DECISION MADE

GLP-1 receptor agonist (ATC A10BJ) use by obesity comparators is **not** an exclusion criterion and is **not** used as a censoring event in the main analysis. GLP-1 RAs were rare as obesity treatment before approximately 2021; excluding or censoring users in the main analysis would create calendar-period imbalance and disproportionately reduce the comparator pool in recent years.

**Pre-specified sensitivity analysis (SA5):** The BS versus obesity comparison is repeated after censoring obesity comparators at the date of first dispensing of a GLP-1 RA at obesity-indicated dose (liraglutide ≥ 2.4 mg or semaglutide ≥ 1 mg) during follow-up. This quantifies the potential influence of GLP-1 RA use on the main estimate.

---

## 4. Outcomes

**Primary outcome:** Incident all-cause dementia — first diagnosis of F00, F01, F02, F03, G30, or G31 in DNPR (somatic) or DCPRR (psychiatric) after index date. PPV: 86% for all-cause dementia in Danish hospital registers. *Reference: Phung TK et al. Dement Geriatr Cogn Disord 2007;24(3):220–8.*

**Secondary outcomes:**

- Alzheimer's disease: G30 or F00 (PPV ~81%; Phung 2007)
- Vascular dementia: F01. Note: PPV for vascular dementia and other subtypes is lower; diagnostic sensitivity of registry-based dementia is unknown.

**Ascertainment:** Primary (A) and secondary (B) diagnosis codes from DNPR (LPR2 + LPR3) and DCPRR. Date of first relevant code after index = event date. G (grundmorbus) codes are **not** used for outcome ascertainment.

---

## 5. Covariates

Lookback windows follow the NMI algorithm (Kristensen 2022): ICD-10 diagnosis codes use a **5-year** lookback; ATC prescription-based predictors use a **6-month** lookback.

### Demographics
- Age at surgery (continuous)
- Sex (male / female)

### Surgery-Related
- Surgery type (RYGB / SG)
- Calendar year of surgery (period: 2010–2014 / 2015–2019 / 2020–2024)

### Comorbidities — Nordic Multimorbidity Index (NMI)

Conditions ascertained through ICD-10 diagnosis codes (diagtypes A, B, G) AND dispensed prescriptions (DNPD/LMDB). For hypertension, dyslipidaemia, and diabetes: defined as ICD-10 code OR relevant prescription within the lookback window (GMC algorithm). All other NMI conditions: ICD-10 diagnosis only.

*NMI reference: Kristensen KB, Lund LC, Jensen PB, et al. Clin Epidemiol 2022;14:567–79.*

**Modified NMI for Study 1 (pre-specified):** The original NMI includes two dementia-related predictors: hospital-coded dementia diagnoses F00–F03/G30 (ICD weight = 9) and dispensed antidementia prescriptions ATC N06D (prescription weight = 11). Retaining these predictors would introduce circular confounding — persons who later develop dementia are more likely to have pre-index register evidence of early dementia, the very diagnoses and prescriptions captured by these two predictors. For Study 1, a modified NMI is therefore pre-specified that excludes dx\_F00\_G30 and rx\_N06D, yielding a **48-predictor score**. The modified score retains full validity as a baseline comorbidity summary for all non-dementia conditions.

**Condition categories:**

| Domain | Conditions |
|--------|-----------|
| Cardiovascular | MI, stroke/TIA, PAD, IHD, heart failure, AF, hypertension |
| Metabolic | Diabetes (any type), dyslipidaemia, thyroid, gout |
| Respiratory | COPD, asthma |
| Gastrointestinal | Liver disease, peptic ulcer, IBD, diverticular disease |
| Renal | Chronic kidney disease |
| Urological | Prostate disorders (men only) |
| Musculoskeletal | Connective tissue disease, osteoporosis |
| Mental health | Depression, bipolar disorder |
| Neurological | Parkinson's, epilepsy, MS, migraine, peripheral neuropathy |
| Oncological | Cancer, anaemia, HIV |
| Sensory | Vision disorders, hearing disorders |

- **nmi\_count** (for Table 1 descriptives): number of conditions present — 0 / 1 / 2 / 3+
- **nmi\_score** (for Cox models): Kristensen 2022 weighted continuous index — sum of component weights across the 48 active predictors

### Medications (any dispensing in lookback window)

- Antihypertensive: ATC C02, C03, C07–C09
- Lipid-lowering: C10
- Antidiabetic: A10 (A10A = insulin only)
- Antidepressant: N06A
- Antidementia: N06D (pre-surgery dispensing is an exclusion criterion; antidementia flag also extracted for Table 1 baseline characterisation)

### Socioeconomic Position (SEP)

*[Not in protocol draft 1; added per reviewer comment p and SEPLINE guideline.]*  
Measured in the year before surgery. *Reference: Hjorth CF et al. SEPLINE. Clin Epidemiol 2025;17:593–624.*

Three separate dimensions are entered as covariates. No composite SEP variable is used; SEPLINE explicitly advises against composites because education, income, and occupation represent distinct causal pathways.

- **Education:** HFAUDD from UDDA — highest attained qualification, most recent record up to the year before surgery. Categories: Short (HFAUDD 10, 15) / Medium (20, 30, 35) / Long (40–80) / Unknown (90)

- **Household income:** FAMAEKVIVADISP\_13 from FAIK, linked via FAMILIE\_ID in BEF. 3-year average equivalised disposable household income (years −1, −2, −3 before surgery). Quintile assignment uses population-level cutpoints computed from the full Danish population, stratified by sex and 5-year age group. Categories: Low (Q1) / Medium (Q2–Q4) / High (Q5) / Unknown

- **Occupation:** SOCIO13 from AKM, year before surgery. Categories: Working / Unemployed / Outside workforce / Retired / Student / Unknown

SEP is a known dementia risk factor (education in particular: lower education is consistently associated with higher dementia incidence) and a potential confounder for the BS–dementia association. Its inclusion is consistent with SEPLINE recommendations for Danish register epidemiology studies.

---

## 6. Follow-Up and Censoring

Time scale: days from index date. Each individual followed from index date until the **first** of:

- Dementia event (primary outcome)
- Death (competing event)
- Emigration from Denmark
- Comparator undergoes bariatric surgery (censored at surgery date)
- December 31, 2025 (administrative end of follow-up)

---

## Statistical Power and Expected Event Counts

Formal power calculations for cohort studies using total national registers are of limited utility because the denominator (number of eligible BS patients) is defined by the data, not by design. Power depends on observed cohort size, mean follow-up time, dementia incidence in the comparator population, and the true hazard ratio — none of which are known before data access. This section documents expected event counts derived from published literature to assess rough feasibility.

**Danish bariatric surgery volume:** The DBSO has registered procedures since 2010. Winckelmann et al. (2022) report procedure volumes from the DBSO and describe its coverage and data quality; approximately 2,000–3,000 procedures have been performed annually in recent years *(Winckelmann LA et al. Surg Obes Relat Dis 2022;18(4):511–9. DOI: 10.1016/j.soard.2021.11.005)*. For the study period 2010–2024 this implies a BS cohort on the order of 20,000–35,000 persons, though early years (2010–2012) had lower and potentially incomplete DBSO registration. *[Action: confirm actual cohort size from first run of 01\_build\_cohorts.R]*

**Dementia incidence in the Danish register:** Phung et al. (2007) validated dementia diagnosis codes in Danish registers against clinical records (PPV ~86% all-cause dementia, ~81% Alzheimer's, lower for vascular dementia subtypes). They do not report incidence rates but confirm ascertainment validity *(Phung TK et al. Dement Geriatr Cogn Disord 2007;24(3):220–8. DOI: 10.1159/000107084)*. *[Action: for incidence rates, consider citing Danish register incidence data from Waldemar G et al. or equivalent; verify DOI before submission]*

The Lancet Commission on dementia (Livingston et al. Lancet 2020, DOI: 10.1016/S0140-6736(20)30367-6) reports global dementia incidence but not Danish-specific rates. Reported EU incidence is approximately 10–15 per 1,000 person-years in persons aged 70+, and 3–5 per 1,000 PY across the 50+ age range. For a BS population (mean surgery age ~40–45, follow-up extending to age ~55–65), the relevant incidence is likely at the lower end of this range. *[Flag for verification: confirm Livingston 2020 as the intended citation]*

**Rough expected event count for the primary outcome (all-cause dementia):**

Assuming:
- BS cohort n = 20,000
- Mean follow-up ~6 years (wide range: patients in 2010 have 15 years, patients in 2024 have <1 year)
- Total person-time ~100,000–120,000 person-years
- Crude dementia incidence in the BS population ~2–4 per 1,000 PY (lower than general population because BS patients are younger and selected for surgical fitness)

**Expected dementia events in BS cohort: approximately 200–480.** This is sufficient power for the primary Cox analysis.

**Anticipated underpowered subanalyses:**

- *Vascular dementia:* accounts for approximately 15–20% of all dementia events, yielding an estimated 30–100 events in the BS cohort. Hazard ratio estimates will be imprecise; interpret with caution.
- *Age < 50 subgroup:* most dementia occurs after age 60. The <50 subgroup at baseline will have low absolute dementia incidence, likely fewer than 50 events. This subgroup analysis is exploratory and not powered for a definitive estimate.
- Both underpowered analyses will be reported with wide confidence intervals and noted as exploratory in the manuscript.

---

## 7. Statistical Analyses

### 7a. Baseline Characteristics (Table 1)

By cohort: BS total / RYGB / SG / GP comparator / Obesity comparator.
- Continuous: median (IQR)
- Categorical: n (%)
- Standardised mean differences (SMD) — no p-values in Table 1

### 7b. Incidence Rates

Crude IR per 100 person-years (95% CI, exact Poisson method). Reported by: cohort, outcome type, sex, age group (<50 / ≥50), diabetes status. Also: 1-year and 5-year IRs separately (landmark approach).

### 7c. Main Survival Analysis — Cox Proportional Hazards Regression

Time = days since index date.

**Three primary comparisons:**

1. BS total vs GP comparator
2. BS total vs obesity comparator
3. RYGB vs SG (within BS cohort; SG as reference)

**Adjustment models:**

| Model | Covariates |
|-------|-----------|
| Model 1 | Unadjusted |
| Model 2 | Age (continuous) + sex |
| Model 3 | Model 2 + nmi\_score (48-predictor) + SEP (education\_cat, income\_cat, occupation\_cat) + surgery year period |

**Proportional hazards (PH) assumption:** Assessed by log-log plots and Schoenfeld residuals. Since the PH assumption may not hold over the full follow-up, HRs are reported as weighted averages of time-varying hazard rate ratios. *Reference: Stensrud MJ, Hernán MA. JAMA 2020;323(14):1401–2.*

### 7d. Competing Risk Analysis — Pre-Specified Framework

Death is a competing event for dementia: a person who dies before developing dementia can never be observed to do so, but their death is not statistically independent of their dementia risk. Treating death as independent censoring is therefore an assumption that requires scrutiny, especially because BS may substantially reduce competing mortality, which would differentially remove high-risk individuals from comparator groups.

**Two complementary approaches are pre-specified:**

**PRIMARY — Cause-specific hazard model** (standard Cox, treating death as censoring): Estimates the instantaneous rate of dementia among persons who are still alive and dementia-free at each moment — the aetiologic question: does BS change the biological process leading to dementia? This approach is the standard in the dementia register literature and facilitates direct comparison with prior studies.  
*Limitation:* If BS markedly reduces competing mortality, survivors in the BS group at late time points may be a selected healthy subgroup, potentially underestimating the true preventive effect.

**SECONDARY — Subdistribution hazard model (Fine-Gray):** Estimates the effect of BS on the cumulative incidence of dementia in the full at-risk population, keeping deceased persons in the risk set. Addresses the public health question: does BS reduce the absolute population burden of dementia, accounting for competing mortality? The Fine-Gray subdistribution HR will diverge from the cause-specific HR when BS materially affects competing mortality.  
*References: Fine JP, Gray RJ. J Am Stat Assoc 1999;94:496–509; Lau B et al. Epidemiology 2009;20:521–525.*

**Graphical summary:** Cumulative incidence functions (CIF) plotted using the Aalen-Johansen estimator for all three comparisons. The Aalen-Johansen CIF is the correct non-parametric curve under competing risks; 1 − Kaplan-Meier overstates cumulative incidence when competing events are present *(Gooley TA et al. Stat Med 1999;18:695–706)*.

**Reporting:** Table 3 presents both cause-specific HR (Cox) and subdistribution HR (Fine-Gray) side-by-side. Large divergence between the two estimates would indicate that competing mortality materially confounds the dementia comparison.

### 7e. Time-Period Analyses

Landmark analyses at 1 year and 5 years post-surgery:

- **[0, 1 year]:** early post-surgical period
- **(1 year, end of follow-up]:** long-term period

These assess whether the BS–dementia association changes over time, as early events may reflect unmasking of pre-existing dementia (surveillance bias), while later events reflect true incident disease.

### 7f. Subgroup (Stratified) Analyses

Primary outcome vs GP comparator. Pre-specified:

- Sex (male / female)
- Age at surgery (<50 / ≥50)
- Baseline diabetes status (T1D / T2D / No diabetes)
- Surgery type (RYGB / SG, within BS vs GP comparison)

Report interaction p-values for each modifier. Forest plot of fully adjusted HRs by subgroup.

### 7g. Sensitivity Analyses

**1. Restrict dementia ascertainment to primary (A) diagnosis codes only** (more specific, less sensitive).  
*IMPLEMENTED:* `date_dementia_primary` extracted in 02 (A-code-only LPR query); `dementia_event_primary` and `follow_up_days_primary` computed in 04. Note: "primary" here refers to diagnosis type A (LPR A-code / *hoveddiagnose*), not the primary study outcome.  
Analysis-time: re-run Cox models substituting `dementia_event_primary` and `follow_up_days_primary` for the main outcome variables.

**2. Exclude dementia events within first 12 months of surgery** (addresses surveillance bias / unmasking of pre-existing dementia).  
Analysis-time: `filter(follow_up_days > 365 | dementia_event == 0)` before running Cox. No new data extraction needed.

**3. [NOT FEASIBLE — moved to limitations]** Restrict BS cohort to public-hospital procedures only. The DBSO data delivered by SunDK does not include a hospital sector indicator. This sensitivity analysis cannot be performed. See Section 10, Limitations.

**4. Censor comparators at time of bariatric surgery** (already in main analysis; report results without this censoring as sensitivity check).  
Analysis-time: recompute `censor_date` omitting `bs_crossover_date`. No new data extraction needed.

**5. [NOT TRIGGERED]** Index date source: DatoPER\_prim vs OpDateLPR. Date quality check performed — distribution of (DatoPER\_prim − OpDateLPR) showed no systematic discrepancy (≥95% of patients within 7 days). DatoPER\_prim is used as index date; sensitivity analysis 7g.5 is removed from the pre-specified analysis plan.

**6. Negative control outcome — cataract** *(Protocol reviewer comment v)*  
*IMPLEMENTED:* `date_cataract` extracted in 02 (`extract_negative_controls()`); `cataract_event` and `follow_up_days_cataract` computed in 04.

Outcome: incident cataract (ICD-10 H25: age-related cataract; H26: other cataract). Diagnosed in hospital register (LPR2 + LPR3), diagtypes A+B, first contact after index date per person. H27 (other lens disorders) and H28 (cataract in diseases classified elsewhere, typically diabetic cataract) are **excluded** — H28 lies on a metabolic pathway shared with obesity and could be affected by BS.

*Rationale for cataract:* Lens opacification has no biologically plausible pathway from bariatric surgery. The established risk factors for cataract — age, cumulative UV exposure, smoking history, and genetic predisposition — are not materially altered by bariatric surgery or the weight loss it produces. An HR near 1.0 for cataract supports that the main dementia estimate is not substantially driven by unmeasured confounding or surveillance bias.

*Why fracture was considered and rejected:* RYGB specifically and substantially increases fracture risk through calcium and Vitamin D malabsorption, secondary hyperparathyroidism, and accelerated bone loss following rapid weight loss. This is a recognised complication of RYGB in clinical guidelines. Because bariatric surgery has a true biological effect on fracture risk, a non-null HR for fracture cannot be interpreted as evidence of bias — it would be uninterpretable as a negative control result. Fracture was therefore excluded.

*Interpretation:* HR ≈ 1.0 for cataract supports internal validity of the main dementia analysis. HR ≠ 1.0 would prompt investigation of confounding or surveillance differential.

#### Removed Pre-Specified Sensitivity Analyses

- *N06D exclusion at baseline:* This is now a main-analysis exclusion criterion. A sensitivity analysis on top of an exclusion criterion would have no comparison group.
- *Population income quintiles:* This is now the main analysis (SEPLINE approach in 03\_extract\_ses.R).
- *7g.5 (OpDateLPR index date):* Not triggered — date quality check showed no systematic discrepancy.

#### Implementation Note

Use `lapply()` + `data.table::rbindlist()` to loop across outcomes/models rather than copy-pasting analysis blocks:

```r
results <- rbindlist(lapply(outcomes, function(outcome) {
  fit <- coxph(Surv(time, event) ~ exposure + covariates, data = df)
  tidy_result(fit, outcome_label = outcome)
}))
```

Apply to: all 6 sensitivity analyses, all 3 comparison pairs, secondary outcomes.

**Software:** R (≥ 4.3). Key packages: survival, cmprsk, ggplot2, tableone, Publish.  
**Significance:** α = 0.05 two-sided. No correction for multiple comparisons across pre-specified secondary outcomes.

---

## 8. Manuscript Figures — Plan

**Figure 1:** Cohort selection flow diagram (CONSORT-style). Boxes for each exclusion step with n removed. Final: BS cohort (n RYGB, n SG) → GP comparator (n, matched 1:25) → Obesity comparator (n, matched 1:5). Include person-years of follow-up and n dementia events per group. *Tool: DiagrammeR or ggplot2*

**Figure 2:** Cumulative incidence of all-cause dementia — main result. Aalen-Johansen estimator. Panel A: BS vs GP; Panel B: BS vs obesity; Panel C: RYGB vs SG. X-axis: years since index date. Shaded 95% CI with number-at-risk table. *Tool: ggplot2 + survminer*

**Figure 3:** Forest plot — main Cox results for all outcomes. Rows: All-cause dementia / Alzheimer's disease / Vascular dementia. Grouped by comparison pair. Adjusted HR (95% CI). *Tool: ggplot2*

**Figure 4:** Forest plot — subgroup analysis. Primary outcome, BS vs GP comparator. Rows: Overall / Sex / Age / Diabetes status / Surgery type. Fully adjusted HR (95% CI) + p-interaction. *Tool: ggplot2*

**Figure 5:** Time-varying hazard ratio. Smoothed log HR over time since surgery, with 95% CI shading. RYGB and SG shown as separate lines vs GP comparator as reference. *Tool: ggplot2 with Royston-Parmar or spline Cox output*

**Figure 6 (optional):** Competing risk — dementia vs death. Dual CIF curves by cohort. *Tool: ggplot2 / cmprsk*

**Supplementary figures:**
- S1: Schoenfeld residuals / log-log plots (PH assumption check)
- S2: Sensitivity analyses forest plot (all 6 sensitivity analyses combined)
- S3: CIF curves for Alzheimer's disease and vascular dementia separately

---

## 9. Manuscript Tables — Plan

**Table 1:** Baseline characteristics. Columns: BS total / RYGB / SG / GP comparator / Obesity comparator. Rows: n, follow-up time, age, sex, NMI conditions, nmi\_count category (0/1/2/3+), medications, education, income, occupation. Include SMD (BS vs GP and BS vs obesity). *Note: nmi\_score (continuous) is used in Cox models (Model 3), not displayed in Table 1.*

**Table 2:** Person-time and crude incidence rates. Rows: All-cause dementia / Alzheimer's / Vascular dementia, by cohort. Columns: n events / person-years / IR per 100 PY (95% CI). Also stratified by sex, age group, diabetes status. Separate sub-tables for 1-year and 5-year landmark periods.

**Table 3:** Main Cox regression results. Rows: Model 1 / Model 2 / Model 3 for each comparison pair. Columns: BS vs GP / BS vs obesity / RYGB vs SG. Includes cause-specific HR and Fine-Gray subdistribution HR.

**Table 4:** Subgroup analysis. Rows: subgroup strata. Columns: n events / n at risk / fully adjusted HR (95% CI) / p-interaction.

---

## 10. Open Issues / Decisions Needed

### Protocol Decisions

- **GLP-1 receptor agonist use in the obesity comparator** *(DECIDED)*: Main analysis: include GLP-1 users without exclusion or censoring. Pre-specified sensitivity analysis (SA5): repeat BS vs obesity comparison after censoring obesity comparators at first dispensing of a GLP-1 RA at obesity-indicated dose (liraglutide ≥ 2.4 mg or semaglutide ≥ 1 mg) during follow-up. See section 3c.
- Confirm whether NMI individual conditions or only the composite score is reported in Table 1 and used as covariate.
- SEP not in original protocol draft — confirm with co-authors that including education, income, and occupation in Model 3 is agreed.
- Censoring of comparators at time of BS: confirmed as main analysis. Implemented via `bs_crossover_date`. Pre-index BS → excluded from pool; post-index BS → enrolled then censored.
- Study period: patients operated in 2024 contribute <1 year by follow-up end. These patients can only contribute to 1-year landmark analysis. This is expected and acceptable.

### Data Management

- Confirm DBSO file location and column names (see TODO.txt)
- Confirm LPR2 psychiatric register folder name (see TODO.txt)
- Confirm revision surgery exclusion: what procedure code identifies a revision vs primary bariatric surgery?
- Run date quality check: tabulate distribution of (DatoPER\_prim − OpDateLPR) — check completed, no systematic discrepancy found (≥95% within 7 days).

### Limitations to Discuss in Paper

- **No hospital sector stratification:** Approximately 50% of Danish bariatric surgery is performed in private hospitals. Private patients tend to differ from public patients in socioeconomic position. A pre-specified sensitivity analysis restricting to public-hospital procedures (7g.3) was planned but could not be performed because the DBSO data delivered by SunDK does not include a hospital sector indicator. The impact of this is likely limited, as all Cox models adjust for three dimensions of SES (education, income, and occupation per SEPLINE), which accounts for much of the systematic difference between private and public patients.
- **Surveillance bias (differential hospital follow-up):** BS patients receive structured post-operative follow-up throughout the observation period — DBSO registry visits, nutritional monitoring, endoscopic surveillance — that GP and obesity comparators do not. Dementia suspects encountered during these contacts may be referred to specialist memory clinics at higher rates simply because BS patients are already in active hospital contact. Direction of bias: biases toward finding more dementia, or finding it earlier, in the BS cohort, which would attenuate an apparent protective effect or produce a spurious null result. Sensitivity analysis 7g.2 (exclude events within the first 12 months) addresses early unmasking but does not eliminate later differential ascertainment from ongoing structured follow-up. An additional negative control outcome with no plausible BS pathway but requiring hospital coding — for example, hip or knee osteoarthritis (ICD-10 M16–M17) — could be used as an internal validity check: a non-null HR for osteoarthritis would flag residual differential ascertainment. Cataract (already pre-specified, 7g.6) addresses confounding but not differential ascertainment to the same degree, as cataract is typically managed in ophthalmology rather than in the hospital contacts that form the BS follow-up pathway.

- **Healthy user bias:** BS patients undergo a structured multi-disciplinary pre-operative programme that typically includes smoking cessation, reduction in alcohol intake, and increased physical activity. All three are independent dementia risk factors. Post-surgery lifestyle improvements are likely sustained in at least a subset of patients and represent confounding along a pathway distinct from any direct biological effect of BS on the brain. Direction of bias: biases toward finding less dementia in BS patients regardless of any true surgical effect. Register data do not capture smoking status, alcohol use, or physical activity longitudinally, so this confounding cannot be fully adjusted for in the main analysis. This should be acknowledged explicitly in the discussion; it is not addressed by any current sensitivity analysis.

- **Prodromal dementia selection (surgery eligibility screening):** Pre-operative assessment for BS routinely evaluates cognitive function; patients with overt or suspected early cognitive impairment are typically not offered surgery. Pre-clinical Alzheimer's disease can begin 10–15 years before clinical diagnosis. Some patients who are biologically destined to develop dementia will be identified at assessment and declined — systematically depleting the BS cohort of individuals at the highest underlying dementia risk. Direction of bias: biases toward finding less dementia in BS patients, the same direction as healthy user bias. Together, these two biases may substantially inflate an apparent protective effect and both should be discussed in the limitations. Sensitivity analysis 7g.2 (exclude first 12 months) partially addresses prevalent undiagnosed dementia present at the time of surgery but does not remove the systematic screening effect for pre-clinical disease.
- **Obesity comparator selection bias (E66 definition):** The obesity comparator is defined by a recorded ICD-10 E66 diagnosis in the hospital register, creating two layers of selection bias. First, E66 has low sensitivity for overweight and predominantly captures patients with BMI ≥ 35–40, which is broadly appropriate because BS eligibility also requires severe obesity. Second, E66 is coded only when a patient presents to hospital for a reason where obesity is recorded — it is not coded at every contact. The obesity comparator therefore overrepresents patients who are symptomatic, actively seeking care, or have comorbidities warranting hospital contact, and underrepresents persons who are severely obese but clinically quiescent. Direction of bias: if E66-coded patients have higher baseline comorbidity and thereby higher dementia risk than the true population of severely obese individuals, the BS vs obesity HR will be biased toward a larger apparent protective effect of BS. This cannot be fully resolved without individual-level BMI data from a population survey or screening programme. Partially addressed by NMI adjustment (Model 3); acknowledged as a limitation in the manuscript.
- **Register-based dementia ascertainment:** PPV 86% for all-cause dementia, 81% for Alzheimer's disease, lower for vascular dementia subtypes (Phung 2007). Sensitivity (proportion of true dementia cases captured in LPR) is not well established. An important Denmark-specific feature: dementia is formally diagnosed in specialist memory clinics and hospital neurology/geriatrics departments — general practitioners can suspect dementia and refer patients, but cannot issue a formal ICD-10 dementia code. All formal diagnoses therefore flow through the hospital system and are captured in LPR. This makes LPR capture more complete than it would be in a system where primary care can formally code the condition. Unascertained cases are primarily persons who die before completing the diagnostic work-up, or who have very mild or early-stage disease and have not yet been referred. Sensitivity is expected to be higher for moderate-to-severe dementia than for mild or pre-clinical stages.
- **Unmeasured confounders:** Several established dementia risk factors cannot be ascertained from Danish register data and therefore cannot be adjusted for in any model. (1) **BMI** — individual-level BMI is available for BS patients from DBSO but not for GP or obesity comparators; residual confounding by severity of obesity within the comparator groups cannot be removed. (2) **Physical activity** — not recorded in any Danish health register; BS patients may increase physical activity post-surgery, and physical activity is an independent dementia risk factor. (3) **Diet quality** — not recorded; pre-operative dietary counselling and post-surgical dietary changes represent uncontrolled exposure differences. (4) **APOE ε4 genotype** — the strongest single genetic risk factor for Alzheimer's disease is not available in register data and cannot be adjusted for; if APOE ε4 frequency differs between persons who undergo BS and comparators (plausible if APOE ε4 carriers have higher rates of metabolic disease driving BS eligibility), this introduces residual confounding. (5) **Family history of dementia** — first-degree relatives' diagnoses are not systematically linkable to index persons for this purpose. Residual confounding from these variables is unavoidable. Direction of bias is uncertain and will depend on the distribution of each factor between the BS and comparator groups.
- **Income quintiles** are population-standardised (SEPLINE approach): 3-year average compared against general-population cutpoints. This does not remove residual confounding by unmeasured aspects of SES, but the relative position is calibrated to the general population.
- **OSDC diabetes file covers to 2022;** patients with diabetes onset 2023–2024 may be misclassified.
- **Modified NMI (48 predictors):** dementia predictors dx\_F00\_G30 (weight 9) and rx\_N06D (weight 11) are excluded from nmi\_score in Study 1 to avoid circular adjustment. This modified version has not been externally validated.

### References to Include in Paper

| Reference | Citation |
|-----------|---------|
| NMI | Kristensen KB et al. *Clin Epidemiol* 2022;14:567–79 |
| DCPRR | Mors O et al. *Scand J Public Health* 2011;39(7 Suppl):54–7 |
| CRS | Schmidt M et al. *Eur J Epidemiol* 2014;29(8):541–9 |
| DNPR | Schmidt M et al. *Clin Epidemiol* 2015;7:449–90 |
| DNPD | Johannesdottir SA et al. *Clin Epidemiol* 2012;4:303–13 |
| DBSO | Winckelmann LA et al. *Surg Obes Relat Dis* 2022;18(4):511–9 |
| Dementia PPV | Phung TK et al. *Dement Geriatr Cogn Disord* 2007;24(3):220–8 |
| PH/HR | Stensrud MJ, Hernán MA. *JAMA* 2020;323(14):1401–2 |
| E66 validity | Gribsholt SB et al. *Clin Epidemiol* 2019;11:845–54 |
| SEPLINE | Hjorth CF et al. *Clin Epidemiol* 2025;17:593–624 |

---

## 11. Discuss with Supervisors — Decisions Before Analysis

This section collects open analytical decisions that require supervisor or co-author input before the analysis scripts are finalised.

### A. Study Population and Design

#### [A1] Study Period: 2010–2024 — Pros, Cons, and Possible Restriction

**Current plan:** Include all first bariatric procedures from January 1, 2010 (DBSO mandatory start) through December 31, 2024.

**Arguments FOR keeping 2010–2024:**
- Maximises sample size and person-time, critical given the relatively low absolute incidence of dementia in a surgical population
- Covers two distinct eras of bariatric practice (RYGB-dominant 2010–2015; SG-dominant 2015–2024), allowing the RYGB vs SG analysis to have adequate numbers in both groups
- Full 15-year window maximises events in the long-term landmark analysis

**Arguments AGAINST (or for restriction):**
- Patients operated in 2024 contribute less than 1 year of follow-up by December 31, 2025 — they can only appear in the 0–1 year landmark stratum, creating imbalance across landmark periods
- DBSO completeness in 2010–2012 may have been lower, potentially underestimating the true BS cohort size and biasing the person-time denominator
- Late-2024 entrants create the most informative-censoring concern: persons who survive to receive surgery in 2024 are already a positively selected group

**Options:**
- *Option A:* Keep 2010–2024 (current plan). Note 2024 asymmetry in the methods and check whether results change materially in a sensitivity analysis restricted to 2010–2023.
- *Option B:* Restrict main analysis to 2010–2022 or 2010–2023, preserving at least 2–3 years minimum follow-up for all patients. Report 2010–2024 as a supplementary sensitivity analysis.
- *Option C:* Keep 2010–2024 but apply a 12-month minimum follow-up requirement. This would overlap with sensitivity analysis 7g.2.

*Question for supervisors:* Is the power gain from including 2024 patients worth the methodological complication? What is SDS/DST policy on using the most recent data year?

#### [A2] Primary Comparison — BS vs Obesity or BS vs GP as the Headline Result? *(Protocol item k)*

Both comparisons are pre-specified and will be reported. The question is which should be presented as the primary result in the abstract.

**Arguments for BS vs GP as headline:**
- More clinically interpretable: estimates the absolute risk reduction in dementia relative to a comparable person who did not have BS
- Consistent with most prior bariatric surgery outcome literature, facilitating direct comparison with existing studies
- GP comparator is larger (1:25), so estimates will be more precise

**Arguments for BS vs obesity as headline:**
- The obesity comparator controls for severe obesity as a shared risk factor. The GP comparator does not — the BS vs GP HR partially reflects the effect of severe obesity itself, not BS specifically
- BS vs obesity comparison disentangles the surgical effect from the obesity effect: the more aetiologically focused comparison and the stronger causal argument for a BS effect
- Pre-surgical weight loss programmes and bariatric team monitoring differ from usual GP care, making the GP comparison susceptible to residual confounding

*Suggested approach:* Present both as co-primary comparisons, with the BS vs obesity result featured in the abstract as the more causally targeted estimate. Confirm framing with all co-authors.

#### [A3] Comparator Eligibility — Should Comparators Be Restricted to BS-Eligible Patients? *(Protocol item m)*

**Current plan:** GP comparator drawn from all BEF residents matching on sex and birth year; obesity comparator drawn from all persons with E66 in LPR.

*The concern:* BS patients are a selected population (severe obesity, surgical fitness, motivated for intervention). GP comparators include many persons who would never be eligible for BS. This makes the GP comparator healthier than the counterfactual "same patient without BS."

**Arguments for NOT restricting comparators:**
- Restricting GP comparators to "BS-eligible" persons would require applying complex BMI thresholds and comorbidity criteria — operationally difficult and prone to misclassification
- The E66 obesity comparator already partially addresses this by selecting persons with a recorded obesity diagnosis
- Age, sex, and NMI adjustment (Model 3) accounts for much of the systematic health difference between groups

*Recommendation:* Keep current approach. Address as a limitation. Sensitivity analysis option: restrict GP comparator to persons with at least one E66 code recorded before index date. Discuss feasibility.

#### [A4] Matching Ratios and Matching Variables — Confirm Before Running Cohort Build

**Current plan:** GP comparator matched 1:25; obesity comparator matched 1:5. Matching variables: sex (exact) and birth year (±1 year). Index date is assigned as the BS patient's surgery date.

*Questions for supervisors:*

- **Matching ratios:** Are 1:25 (GP) and 1:5 (obesity) the agreed ratios? Higher ratios increase power but also computational load and pool depletion risk (especially for the obesity comparator, where the eligible pool is smaller). If pool depletion is severe for rare birth-year/sex strata, fewer controls than the target ratio will be available; the code logs a warning for affected patients.

- **Calendar month matching:** Should the matching include calendar month of index date in addition to birth year? Arguments for: reduces confounding by secular trends in dementia ascertainment and BS practice within a year. Arguments against: tightens the pool further, increases the risk of zero matches for 2010–2012 when DBSO registration was less complete. Currently not implemented; would require code changes in `build_cohorts.R` (N\_GP\_PER\_BS and N\_OBESITY\_PER\_BS constants and matching loop).

- **Birth year window:** ±1 year is the current tolerance. A narrower window (exact birth year) would improve matching balance on age but further deplete the pool; a wider window (±2 years) would ease matching at the cost of greater age imbalance. Confirm ±1 year is acceptable.

*Note:* DBSO underreporting in 2010–2012 (MINOR-16 in TODO.txt) may cause zero-match warnings for early-index-date BS patients in the obesity comparator. If ≥5% of 2010–2012 patients receive zero obesity comparator matches, a sensitivity analysis restricting to index dates from 2013 onwards will be added. This is linked to the study period decision in [A1].

#### [A5] Comparator Sampling Strategy — With vs Without Replacement, and Matching Ratio

**Background:** Heide-Jørgensen et al. (2018) compared three strategies for sampling general population comparison cohorts from Danish register data (matching on sex, birth year, and calendar period — identical to our approach). *(Heide-Jørgensen U et al. Clin Epidemiol. 2018;10:1325–1337. DOI: 10.2147/CLEP.S164456)*

Their empirical findings at a 5:1 matching ratio:

| Strategy | Bias direction | Key finding |
|---|---|---|
| Without replacement, random order | Upward (comparators look sicker) | Immortal time bias; substantial when index persons aged >50 |
| Without replacement, chronological order | Downward (comparators look healthier) + match failure for late patients | Up to 20% of heart failure patients received zero matches; comparison cohort skewed younger than index cohort |
| With replacement | None detected | Unbiased across all settings tested |

**Current implementation:** Sampling without replacement in chronological order (BS cohort sorted ascending by surgery date before the matching loop). This avoids the worst immortal time bias from random order, but the paper shows chronological order introduces its own downward bias in outcome rates and match failure for late/older cases — especially at ratios beyond 1:1.

**Why this is probably not a serious problem for our cohort:**
The paper's concerning findings were driven by high outcome rates in the comparison pool (heart failure cohort, median age 77 years; mortality ~228/1,000 person-years). Our BS cohort has a mean surgery age of approximately 38–48 years. Dementia incidence in this age group is very low (~2–5/1,000 person-years), leaving little signal for pool depletion bias to distort. The paper explicitly notes the effect was "minuscule" in general population analyses unless index persons were aged >50. However, the concern is not zero — older BS patients (operated at 55–65) and the later study years (2020–2024, where pool depletion is largest) represent the highest-risk combination.

**The 1:25 ratio itself:** The paper (citing Daly et al. 2000) notes: *"it is questionable if there is much to gain in statistical power when the sampling ratio exceeds four."* Statistical power for a Cox model saturates rapidly beyond 1:4–1:5; increasing from 1:10 to 1:25 provides negligible additional precision. The 1:25 ratio increases computational burden, pool depletion, and the complexity of any switch to with-replacement sampling, for minimal methodological return.

**If we switch to sampling with replacement — expected duplication rate:**

With 23,700 BS patients at a 1:25 ratio, 592,500 GP comparator draws are needed. For a representative sex × birth-year stratum (women born ~1975, pool ≈ 60,000–90,000 eligible women), approximately 8,000–15,000 draws come from that stratum across the full study period. Using the coupon-collector approximation for expected unique draws:

E[unique] = N × (1 − e^(−n/N))

For n = 12,500 draws from N = 75,000: E[unique] ≈ 75,000 × (1 − e^(−0.167)) ≈ 11,600 unique persons out of 12,500 total draws → approximately 7% duplicate comparator-observations in the most common strata. Averaged across all strata (including smaller, less-depleted ones), a realistic overall duplication rate is **5–10% of GP comparator-observations**. For the obesity comparator (smaller eligible pool), the duplication rate would be higher.

This level of duplication is operationally manageable but requires an analytical change.

**Analytical changes required if sampling with replacement:**

With replacement, the same person can appear as a comparator for multiple BS patients — once as a comparator for a 2012 surgery and again for a 2018 surgery, each time with a different assigned index date and a different follow-up window. These are not independent observations.

The Cox model must account for this non-independence. Two options:

1. *`cluster(pnr)` in `coxph()`* — robust sandwich variance estimator, treating each unique person as a cluster. This corrects standard errors and confidence intervals; point estimates are unchanged. This is in addition to any `cluster(matched_pnr)` term for the matched design (see decision B1). In practice, `cluster(pnr)` subsumes the matched-set clustering because pnr is a finer grouping than matched set when with-replacement allows a person to appear in multiple matched sets.

2. *Explicit duplicate indicator* — flag duplicated pnrs, report the proportion, and run a sensitivity analysis excluding second (and third) appearances. If the sensitivity analysis gives similar estimates, duplicates have not materially influenced the results.

**Questions for supervisors:**

1. Should we switch the GP comparator from 1:25 to a lower ratio (e.g., 1:10 or 1:5), given the negligible power gain beyond 1:4?
2. Should we switch to sampling with replacement (accepting the `cluster(pnr)` adjustment in Cox models) to eliminate the chronological-order downward bias, even if it is likely small for our age group?
3. If we keep 1:25 without replacement in chronological order, should we add a sentence in the methods section explicitly citing Heide-Jørgensen 2018 and justifying the approach by the low dementia incidence rate in our age group?

*References:*
- Heide-Jørgensen U et al. Sampling strategies for selecting general population comparison cohorts. *Clin Epidemiol.* 2018;10:1325–1337. DOI: 10.2147/CLEP.S164456
- Miettinen OS. Estimability and estimation in case-referent studies. *Am J Epidemiol.* 1976;103(2):226–235. DOI: 10.1093/oxfordjournals.aje.a112220

---

### B. Analysis Methods

#### [B1] Clustering in Cox Models — Robust SE vs Stratified Cox — TBD

Matched cohort designs require accounting for within-cluster correlation (BS patient and their matched comparators share the same index date and matching variables).

- *Option A:* `cluster(matched_pnr)` in `coxph()` — adds a robust sandwich variance estimator. Standard errors are corrected for clustering; point estimates are the same as a naive Cox. Simpler to implement and interpret.
- *Option B:* `strata(matched_pnr)` — fully stratifies the baseline hazard by cluster. Only within-cluster comparisons contribute to the likelihood. More conservative; estimates can be unstable if clusters are small (1:5 obesity comparator may have too few per stratum).

Implication: this must be pre-specified. The two approaches can give different point estimates in addition to different standard errors.

**STATUS: TBD.** Must be agreed with co-authors and pre-specified before analysis begins. Confirm which approach is standard in the group and consistent with prior published analyses from this data environment.

#### [B2] Landmark Analysis Method — Landmark Restriction vs Time-Split Approach

Section 7e pre-specifies landmark analyses at 1 year and 5 years. Two methodologically distinct approaches exist:

- *Option A: Landmark restriction.* Restrict the analysis dataset to persons who survived dementia-free to the landmark time, then start follow-up from that landmark. This answers: "Among persons who survived to 1 year without dementia, what is the long-term risk thereafter?" The restriction changes the study population at each landmark. Standard for assessing whether early events (surveillance bias) explain an association.
- *Option B: Time-split (piece-wise) approach.* Split each person's follow-up at the landmark time points and model the period-specific hazard using an interaction term (time-period × exposure). Keeps the full cohort but allows the HR to differ by period. Better for testing time-varying effects.

The two approaches answer different questions and are not interchangeable.

*Question for supervisors:* Which is the intended approach for the 7e analysis? Should both be reported, or one as main and one as supplement?

#### [B3] Age Cutoff for Subgroup Analysis — <50/≥50 or Alternative Threshold? *(Protocol item t)*

**Current plan:** Stratify by age at surgery < 50 years vs ≥ 50 years (section 7f).

*Considerations:*
- Most dementia events will occur in persons who were ≥ 50 at surgery and have reached age 60–70+ during follow-up. The < 50 group will have very few dementia events (likely underpowered — see power section).
- Clinical rationale for <50: this defines the group where BS is being used for metabolic rather than primarily weight-loss reasons, and where a dementia-preventive effect over a lifetime horizon would be most meaningful.
- Alternative thresholds: <55/≥55 gives more events in the younger group but reduces the contrast; <60/≥60 captures the clinically important late-onset dementia age range but the older group becomes the majority.

**STATUS: TBD.** <50/≥50 is the current pre-specified threshold. Will be reviewed once observed event counts are available from the first cohort build. If fewer than 20–30 dementia events are observed in the <50 stratum, an alternative threshold will be considered and documented as a protocol amendment.

#### [B4] Multiple Testing — No Correction Across Pre-Specified Analyses

**Current plan:** α = 0.05 two-sided. No correction for multiple comparisons across pre-specified secondary outcomes.

*Justification:* All analyses are pre-specified (not data-driven). Each comparison addresses a distinct scientific question. Blanket Bonferroni correction would be overly conservative and is not standard in register epidemiology.

*However:* The large number of analyses (3 comparisons × 3 models × 3 outcomes + 6 sensitivity analyses + 4 subgroups) increases the probability of at least one spurious significant result. This should be addressed in the discussion section of the paper.

*Question for supervisors:* Is the no-correction approach accepted by all co-authors? Should we pre-register the analysis plan (e.g., OSF) to strengthen this argument?

#### [B5] GLP-1 Receptor Agonists — DECIDED

**Decision:** GLP-1 RA use is not an exclusion criterion and is not used as a censoring event in the main analysis. A pre-specified sensitivity analysis (SA5) repeats the BS vs obesity comparison after censoring obesity comparators at first dispensing of a GLP-1 RA at obesity-indicated dose (liraglutide ≥ 2.4 mg or semaglutide ≥ 1 mg, ATC A10BJ) during follow-up. The BS cohort is not modified in this sensitivity analysis, as GLP-1 use after bariatric surgery is rare and would in any case represent post-index exposure. See section 3c for full rationale.

#### [B6] Calendar Period Confounding in RYGB vs SG Comparison

RYGB was dominant in Denmark approximately 2010–2015; SG became dominant from approximately 2015 onwards. Persons who had RYGB therefore tend to have earlier index dates and longer follow-up than persons who had SG, independently of any surgical effect on dementia.

*Current mitigation:* Surgery year period included as a covariate in Model 3 (3 periods: 2010–2014, 2015–2019, 2020–2024).

*Residual concern:* Period adjustment may not fully remove the calendar confounding because the RYGB-to-SG transition happened at different times in different hospital centres, and patient selection for RYGB vs SG changed over the period.

*Question for supervisors:* Is period adjustment in Model 3 considered sufficient, or should we add a sensitivity analysis restricted to the period of SG equipoise (approximately 2013–2018, when both procedures were in widespread use)?

---

### C. Potential Additional Analyses

#### [C1] BMI as a Subanalysis Within the BS Cohort *(Protocol item u)*

Individual baseline BMI (`bmi_preop` from DBSO) is available for BS patients only. Comparators have no linked BMI; this variable cannot be included in the main Cox models.

**Potential uses within the BS cohort:**

1. BMI as a covariate in the RYGB vs SG model: does the RYGB vs SG HR attenuate after adjusting for baseline BMI?
2. Effect modification by baseline BMI quartile within the BS cohort: is the dementia hazard for RYGB vs SG modified by how obese the patient was at baseline?
3. BMI category (30–35 / 35–40 / 40–50 / ≥50 kg/m²) as a stratification variable in the BS vs GP comparison: shows heterogeneity of effect by severity of obesity at surgery.

These are secondary exploratory analyses and should be labelled as such.

*Question for supervisors:* Are analyses (1) and (2) considered worth including in the pre-specified analysis plan, or should they be deferred to a separate paper?

#### [C2] SEP in Model 3 — Confirm with All Co-Authors

Model 3 includes education, income, and occupation as confounders per SEPLINE. This was not in the original protocol draft but was added based on SEPLINE recommendations *(Hjorth et al. Clin Epidemiol 2025)*.

SEP is a well-established dementia risk factor. Including it in Model 3 reduces residual confounding by SES — particularly relevant for the BS vs GP comparison.

*Question for co-authors:* Is there agreement on the SEPLINE approach? Should it be included in the pre-specified plan and noted in any pre-registration?



DISCUSS-1] Public vs private hospital — sensitivity analysis not feasible
  Background: ~50% of Danish BS is private. Private patients differ
              systematically in SES, which is a potential residual confounder
              for dementia risk. A sensitivity analysis restricting to
              public-hospital procedures (pre-specified as 7g.3) was intended
              to test robustness to this heterogeneity.
  Problem:    DBSO data from SunDK does not include a hospital sector
              indicator. We cannot distinguish public from private procedures
              in the current dataset.
  Options to discuss with supervisors:
    A) Accept as a limitation (current approach — documented in methods plan
       section 10 and TODO). No further action needed.
    B) Contact SunDK to request a hospital sector variable or institution
       code for the delivered DBSO file (dfr_2025_10_31.sas7bdat). If
       available, add to 00_prepare_dbso.R and re-run sensitivity analysis.
    C) Use LPR as a proxy: if a patient's surgery date (datoper_prim) matches
       an LPR procedure record, they were likely in an LPR-reporting hospital
       (predominantly public). Imperfect — private clinics are required to
       report to LPR3 but compliance varies.
  Current status: treated as a limitation. Sensitivity analysis 7g.3 removed
                  from analysis plan. Discuss whether option B or C is
                  worth pursuing before manuscript submission.
