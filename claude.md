# Claude Context - BS & Dementia Project

## Overview
Research investigating associations between bariatric surgery (BS) and dementia, and separately, BS outcomes in patients with Type 1 Diabetes (T1D).

---

## Study 1: Bariatric Surgery and Dementia

### Research Questions
1. What is the association between bariatric surgery (RYGB and SG) and all-cause dementia, Alzheimer's disease, and vascular dementia?
2. Does the association differ between RYGB and SG?
3. Does risk vary by age, sex, and baseline diabetes status?
4. How much do baseline comorbidities and metabolic factors explain differences?
5. How do time-dependent risk patterns develop (1 year vs. 5 years post-surgery)?

### Study Design
- **Type:** Retrospective cohort study using nationwide register data
- **Setting:** Denmark (tax-funded and private bariatric surgery)
- **Period:** January 1, 2010 - December 31, 2024
- **Inclusion:** Patients with 5 years of lookback before surgery

### Cohorts
- **Bariatric surgery cohort:** All BS patients in Denmark (2010-2024)
  - Divided into: RYGB cohort and SG cohort
- **Comparison cohorts:**
  - General population (1:25 matching on age, sex, index date)
  - Obesity cohort with BMI >25 kg/m² (1:5 matching)

### Primary Outcome
- Incident all-cause dementia (ICD-10 diagnosis codes)

### Secondary Outcomes
- Alzheimer's disease
- Vascular dementia
- Positive predictive value: 86% for all-cause dementia, 81% for Alzheimer's disease

### Data Sources
1. **Danish Civil Registration System (CRS):** Age, sex, birth date, vital status (1968+)
2. **Danish National Patient Registry (DNPR):** Hospital contacts (inpatient, outpatient, ER) since 1995
3. **Danish National Prescription Database (DNPD):** Prescription data since 1994
4. **Danish Central Psychiatric Research Registry (DCPRR):** Psychiatric hospital/clinic contacts since 1970
5. **Danish Quality Registry for Treatment of Severe Obesity (DBSO):** Surgical data (mandatory since 2010)
6. **Integrated Database for Labour Market Research (IDLMR):** Education and income since 1980

### Covariates
- Baseline comorbidities (Nordic Multimorbidity Index - NMI)
- Education level
- ICD-10 diagnosis codes and medication use

### Statistical Analyses
- **Follow-up:** Index date until outcome, death, or December 31, 2025
- **Incidence rates (IR)** per 100 person-years
- **Cox proportional hazards regression** (HR with 95% CI)
- Time periods: 1-year and 5-year analyses
- **Stratified analyses:** Sex (male/female), age (<50, ≥50), baseline diabetes status
- **Competing risk:** Death considered as competing risk for cumulative incidence

### Key Mechanisms
**Potential protective effects of BS:**
- Weight loss reduces systemic inflammation and oxidative stress
- Improved glycemic control, reduced neuroinflammation
- Favorable changes in appetite-regulating hormones (ghrelin, leptin, adiponectin)

**Potential harmful effects of BS:**
- Vitamin B deficiencies → impaired neurotransmitter synthesis
- Decreased circulating estrogen → loss of neuroprotective effects

---

## Study 2: Type 1 Diabetes and Bariatric Surgery

### Research Question
What are the outcomes of metabolic bariatric surgery (MBS) in patients with T1D compared to T2D and non-diabetes patients?

### Knowledge Gap
- Very few studies exist (only 5-10 patients in most)
- Limited data on surgical safety, complications, insulin requirements, long-term glycemic control
- Mixed findings on insulin requirements post-surgery

### Study Design
- **Type:** Retrospective cohort study using nationwide register data
- **Period:** January 1, 2010 - December 31, 2024
- **Inclusion:** Patients with 5 years of lookback before surgery

### Cohorts (3 groups)
1. **T1D cohort:** Insulin purchase OR T1D diagnosis (most recent type-specific)
   - Exclusions: GDM-related metformin use, no T1D purchases last 10 years, T2D classified patients
2. **T2D comparison cohort:** Non-insulin GLD OR T2D diagnosis (most recent type-specific)
   - Exclusions: Women with only metformin + PCOS, single inclusion event
3. **Non-diabetes comparison cohort:** No diabetes classification

### Data Sources
- Danish Civil Registration System (CRS)
- Danish National Patient Registry (DNPR)
- Danish National Prescription Database (DNPD)
- Danish Quality Registry for Treatment of Severe Obesity (DBSO)

### Outcomes
**Weight outcomes:**
- Total weight loss (TWL) at 1 and 2 years
- Percentage total weight loss (%TWL)
- Percentage excess weight loss (%EWL)

**Metabolic outcomes:**
- Daily insulin dose (baseline, 3 months, 6 months, 12 months)

**Hospital contacts due to:**
- Hyperglycemia
- Hypoglycemia
- Self-harm
- Substance abuse
- Trauma
- Surgical complications

**Mortality:**
- 90-day mortality
- 5-year mortality

### Statistical Analyses
- **Baseline characteristics:** Medians with IQR (numeric), counts with % (categorical)
- **Prevalence ratios (PRs):** Weight loss and BMI changes between follow-up visits
- **Insulin dose:** Assessed at baseline, 3, 6, and 12 months post-op
- **Cumulative incidence rates (IRs):** First-time acute admissions per 100 person-years
- **Cox proportional hazards:** HR as incidence rate ratio (RR) with 95% CI
- **Stratification:** Age and sex
- **Competing risk:** Considered

### Weight Loss Definitions
- **Preoperative:** First preoperative exam to surgery date
- **Postoperative:** Surgery date to follow-up exam
- **Total:** Pre + Post combined
- **Target BMI:** 25 kg/m²
- **Excess weight:** Preoperative weight - target weight

### Reoperation
- Defined as any surgery for surgical complications (gastroscopy excluded)

---

## General Notes

### Surgery Codes (from DNPR)
- **RYGB:** KJDF10/11
- **SG:** KJDF40/41/96/97

### Diabetes Definitions
- Based on Open Source Diabetes Classifier algorithm
- Classification uses ICD-10 codes (E66 for obesity) and medication profiles

### Important Considerations
- Danish BMI ≥40 kg/m² OR ≥35 kg/m² with obesity-related comorbidity required for BS
- Approximately 50% of Danish BS procedures are at private hospitals (self-paid)
- All procedures reported to DBSO (mandatory since 2010)

---

## STUDY 1: BARIATRIC SURGERY & DEMENTIA - ALL VARIABLES NEEDED

### Exposure (NOT EXTRACTING - already have BS cohort)
- Bariatric surgery procedure date (index date)
- Surgery type (RYGB vs SG)

### Primary Outcome
- **Dementia (all-cause):** ICD-10 codes from DNPR/DCPRR
- **Alzheimer's disease:** ICD-10 codes from DNPR/DCPRR
- **Vascular dementia:** ICD-10 codes from DNPR/DCPRR
- Date of first diagnosis

### Covariates - Baseline (5 years before surgery)
1. **Demographics:**
   - Age (at surgery)
   - Sex (from CRS)
   - Birth date (from CRS)

2. **Nordic Multimorbidity Index (NMI) Conditions:**
   - Myocardial infarction
   - Stroke/TIA
   - Peripheral arterial disease
   - Diabetes mellitus
   - Chronic lung disease
   - Liver disease
   - Kidney disease
   - Cancer
   - Mental disorders (depression, bipolar)
   - Other chronic conditions

3. **Education Level (from IDLMR):**
   - Highest education achieved

4. **Baseline Medications (5 years before surgery):**
   - Antihypertensive drugs
   - Lipid-lowering drugs
   - Antidiabetic drugs
   - Antidepressants
   - Other relevant medications

5. **Obesity-related Comorbidities:**
   - Hypertension
   - Type 2 Diabetes
   - Dyslipidemia

### Follow-up Data
- Death date (from CRS)
- End of follow-up: December 31, 2025

---

## STUDY 2: TYPE 1 DIABETES & BARIATRIC SURGERY - ALL VARIABLES NEEDED

### Exposure (NOT EXTRACTING - already have BS cohort)
- Bariatric surgery procedure date (index date)
- Surgery type (RYGB vs SG)

### Primary Outcomes - Weight

**Baseline (preoperative):**
- Weight (kg) at first preoperative exam
- BMI (kg/m²) at first preoperative exam
- Date of first preoperative exam

**Postoperative:**
- Weight (kg) at 3 months, 6 months, 12 months, 1-year, 2-years post-op
- BMI (kg/m²) at same timepoints
- Date of each exam

**Calculated:**
- Total weight loss (TWL) = Preop weight - Post-op weight
- % TWL = (TWL / Preop weight) × 100
- Excess weight = Preop weight - Target BMI 25 weight
- % EWL = (Post-op weight loss / Excess weight) × 100

### Primary Outcomes - Metabolic

**Insulin dose:**
- Daily insulin requirement (units/day)
  - Baseline (at surgery)
  - 3 months post-op
  - 6 months post-op
  - 12 months post-op

### Primary Outcomes - Hospital Contacts

**First-time admissions per 100 person-years for:**
- Any hyperglycemia admission
- Any hypoglycemia admission
- Any self-harm admission
- Any substance abuse admission
- Any trauma admission
- Any surgical complication admission

### Secondary Outcomes
- 90-day mortality
- 5-year mortality
- Any reoperation (defined as any surgery for complications, excluding gastroscopy)

### Covariates - Baseline

1. **Demographics:**
   - Age (at surgery)
   - Sex (from CRS)
   - Birth date (from CRS)

2. **Diabetes Classification:**
   - Type (T1D, T2D, or non-diabetes) - using Open Source Diabetes Classifier
   - Date of diabetes diagnosis (if applicable)

3. **Baseline Comorbidities (5 years before surgery):**
   - Hypertension
   - Cardiovascular disease
   - Chronic kidney disease
   - Other obesity-related conditions

4. **Baseline Medications:**
   - Insulin (for T1D)
   - Other glucose-lowering drugs (for T2D)
   - Cardiovascular medications
   - Other relevant medications

5. **Baseline Anthropometry (from DBSO):**
   - Weight (kg)
   - Height (cm) if available
   - BMI (kg/m²)

### Follow-up Data
- Death date (from CRS)
- End of follow-up: December 31, 2024 (or when followed up in DBSO)


## Behavioral Guidelines

Derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM coding pitfalls.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
