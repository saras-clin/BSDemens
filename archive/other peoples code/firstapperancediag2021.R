##########################
##########################
#### gmc2021
##########################
##########################

rm(list = ls())
library(dplyr)
library(tidyr)

##########################
#### Input data
load(file = "E:/workdata/708614/Datasets/population1986_2021.RData")
load(file = "E:/workdata/708614/Datasets/hospital2021.RData")
folder_input_LMDB <- "E:/rawdata/708614/grunddata/LMDB/"
##########################

##########################
#### Output data
folder_output <- "E:/workdata/708614/Datasets/"
##########################



##########################
#### First, we take all diagnoses and consider only those of interest
hospital <- hospital %>%
  filter(
    date_dx >= as.Date("1995-01-01") & date_dx <= as.Date("2021-12-31"),
    type_diag != "+"  # Remove additional diagnoses
    ) %>%   
  select(pnr, recnum, date_dx, diag)

hospital <- hospital %>%
  mutate(
    icd3 = substr(diag, 2, 4),
    icd4 = substr(diag, 2, 5)
  ) %>%
  mutate(
    disease = case_when(
      (icd3 >= "I10" & icd3 <= "I13") | icd3 == "I15" ~ 1,
      icd3 == "E78" ~ 2,
      (icd3 >= "I20" & icd3 <= "I25") ~ 3,
      icd3 == "I48" ~ 4,
      icd3 == "I50" ~ 5,
      (icd3 >= "I70" & icd3 <= "I74") ~ 6,
      (icd3 >= "I60" & icd3 <= "I64") | icd3 == "I69" ~ 7,
      (icd3 >= "E10" & icd3 <= "E14") ~ 8,
      (icd3 >= "E00" & icd3 <= "E05") | (icd4 >= "E061" & icd4 <= "E069") | icd3=="E07" ~ 9,
      icd3 == "E79" | icd3 == "M10" ~ 10,
      (icd3 >= "J40" & icd3 <= "J47") ~ 11,
      (icd4 >= "J301" & icd4 <= "J304") | icd3 == "L23" | icd4 == "L500" | icd4 == "T780" | icd4 == "T782" | icd4 == "T784" ~ 12,
      icd4 == "K221" | (icd3 >= "K25" & icd3 <= "K28") | (icd4 >= "K293" & icd4 <= "K295") ~ 13,
#      (icd3 >= "B16" & icd3 <= "B19") | icd3 == "K70" | icd3 == "K74" | icd4 == "K766" | icd3 == "I85" ~ 14,     
      (icd3 >= "B16" & icd3 <= "B19") | (icd3 >= "K70" & icd3 <= "K74") | icd4 == "K766" | icd3 == "I85" ~ 14,    ## fixed from previous version
      (icd3 >= "K50" & icd3 <= "K51") ~ 15,
      icd3 == "K57" ~ 16,
      icd3 == "N03" | icd3 == "N11" | icd3 == "N18" | icd3 == "N19" ~ 17,
      icd3 == "N40" ~ 18,
      (icd3 >= "M05" & icd3 <= "M06") | (icd3 >= "M08" & icd3 <= "M09") | (icd3 >= "M30" & icd3 <= "M36") | icd3 == "D86" ~ 19,
      (icd3 >= "M80" & icd3 <= "M82") ~ 20,
      (icd3 >= "B20" & icd3 <= "B24") ~ 22,
      (icd3 >= "D50" & icd3 <= "D53") | (icd3 >= "D55" & icd3 <= "D59") | (icd3 >= "D60" & icd3 <= "D61") | (icd3 >= "D63" & icd3 <= "D64") ~ 23,
      (icd3 >= "C00" & icd3 <= "C43") | (icd3 >= "C45" & icd3 <= "C97") ~ 24,
      icd3 == "H40" | icd3 == "H25" | icd3 == "H54" ~ 25,
      (icd3 >= "H90" & icd3 <= "H91") | icd4 == "H931" ~ 26,
      icd3 == "G43" ~ 27,
      (icd3 >= "G40" & icd3 <= "G41") ~ 28,
      (icd3 >= "G20" & icd3 <= "G22") ~ 29,
      icd3 == "G35" ~ 30,
      (icd3 >= "G50" & icd3 <= "G64") ~ 31
    )
  )

table(hospital$disease, useNA = "always")

## Add COPD/Asthma
copd_asthma <- hospital %>%
  filter(disease == 11) %>%
  mutate(
    disease = case_when(
      (icd3 >= "J40" & icd3 <= "J44") | (icd3 == "J47") ~ 1101,
      (icd3 >= "J45" & icd3 <= "J46") ~ 1102
    )
  )
table(copd_asthma$disease, useNA = "always")

hospital <- hospital %>%
  bind_rows(copd_asthma)
rm(copd_asthma)
table(hospital$disease, useNA = "always")

hospital <- hospital %>%
  filter(!is.na(disease)) %>%
  group_by(pnr, disease) %>%
  arrange(date_dx) %>%
  slice(1) %>%
  select(pnr, disease, date_dx) %>%
  ungroup()
table(hospital$disease, useNA = "always")

  


##########################
#### Second, we take all prescriptions and consider only those of interest

prescriptions <- data.frame()

for(year in 1995:2021) {
  print(year)
  px_year <- haven::read_sas(paste0(folder_input_LMDB, "lmdb", year, ".sas7bdat"))
  colnames(px_year) <- tolower(colnames(px_year))
  
  px_year <- px_year %>% 
    select(pnr, atc, eksd) %>%
    mutate(
      atc3 = substr(atc,1,3),
      atc4 = substr(atc,1,4),
      atc5 = substr(atc,1,5),
      atc7 = substr(atc,1,7)
    )
  
  px_year <- px_year %>%
    filter(
      (atc3 %in% c("C02", "C03", "C04", "C07", "C08", "C09", "C10", "H03", "N03", "R03")) |
        (atc4 %in% c("A10A", "A10B", "G04C", "M01A", "M02A", "M05B", "N02A", "N02C")) |
        (atc5 %in% c("C01DA", "C02CA", "H05AA", "N02BE", "R01AC", "R01AD", "R06AX")) |
        (atc7 %in% c("G03XC01", "N02BA51", "R06AE07", "R06AE09"))
    )
  
  prescriptions <- prescriptions %>%
    bind_rows(px_year %>% mutate(year = !!year))
  
}
rm(px_year)

# generate variable indicating which GMC drug meets criteria for
prescriptions <- prescriptions %>%
  mutate(
    disease = case_when(
      atc3 %in% c("C02", "C03", "C04", "C07", "C08", "C09") ~ 1,
      atc3 == "C10" ~ 2,
      atc5 == "C01DA" ~ 3,
      atc4 %in% c("A10A", "A10B") ~ 8,
      atc3 == "H03" ~ 9,
      atc3 == "R03" ~ 11,
      (atc5 %in% c("R06AX", "R01AC", "R01AD")) | (atc7 %in% c("R06AE07", "R06AE09")) ~ 12,
      atc4 == "G04C" | atc5 == "C02CA" ~ 18,
      atc4 == "M05B" | atc5 == "H05AA" | atc7 == "G03XC01" ~ 20,
      atc4 %in% c("N02A", "M01A", "M02A") | atc5 == "N02BE" | atc7 == "N02BA51" ~ 21,
      atc4 == "N02C" ~ 27,
      atc3 == "N03" ~ 28
    )
  )
table(prescriptions$disease, useNA = "always")
table(prescriptions$year, useNA = "always")

prescriptions <- prescriptions %>%
  filter(eksd >= as.Date("1995-01-01") & eksd <= as.Date("2021-12-31"))

prescriptions <- prescriptions %>%
  inner_join(population %>% select(pnr, birth_d, death_d)) %>%
  filter(
    eksd >= birth_d,
    is.na(death_d) | eksd <= death_d)

# For hypertension (disease = 1), diuretic presriptions (ATC C03) are not used if the person has a
# previous diagnosis of kidney disease. Thus, we keep non-diuretic prescriptions for later use
nondiuretics <- prescriptions %>%
  filter(
    disease == 1,
    atc3 != "C03"
    )

# Create variable looking at time between prescriptions. All drugs require at least two prescriptions
# within a year (except for painful condition [disease = 21] that it requires at least 4 prescriptions within a year)
prescriptions <- prescriptions %>%
  group_by(pnr, disease) %>%
  arrange(eksd) %>%
  mutate(
    time_prev = lubridate::time_length(difftime(eksd, lag(eksd, n = 1)), "years"),
    time_3prev = lubridate::time_length(difftime(eksd, lag(eksd, n = 3)), "years")
  ) %>%
  filter(
    !is.na(time_prev) & time_prev < 1,
    (disease != 21) | (!is.na(time_3prev) & time_3prev < 1)
  ) %>%
  arrange(eksd) %>%
  slice(1) %>%
  ungroup() %>%
  select(pnr, disease, date_px = eksd)

## Add COPD/Asthma
copd_asthma <- prescriptions %>%
  filter(disease == 11) %>%
  left_join(population %>% select(pnr, birth_d)) %>%
  mutate(
    age = lubridate::time_length(difftime(date_px, birth_d), "years"),
    asthma = age < median(age),
    disease = ifelse(asthma, 1102, 1101)
    ) %>%
  select(pnr, disease, date_px)

prescriptions <- prescriptions %>%
  bind_rows(copd_asthma)
rm(copd_asthma)

nondiuretics <- nondiuretics %>%
  group_by(pnr) %>%
  arrange(eksd) %>%
  mutate(
    time_prev = lubridate::time_length(difftime(eksd, lag(eksd, n = 1)), "years"),
  ) %>%
  filter(
    !is.na(time_prev) & time_prev < 1
  ) %>%
  arrange(eksd) %>%
  slice(1) %>%
  ungroup() %>%
  select(pnr, nondiuretic = eksd)


##########################
#### Merge the two data sources
gmc <- hospital %>% full_join(prescriptions) %>%
  left_join(nondiuretics)
head(gmc)

rm(hospital, prescriptions, nondiuretics)


# We now take the first between prescription or diagnosis, except epilepsy (disease = 28) that needs both
gmc <- gmc %>%
  mutate(
    date_disease = as.Date(ifelse(disease != 28, pmin(date_dx, date_px, na.rm = T), pmax(date_dx, date_px, na.rm = F)), origin = "1970-01-01")
  )

# Hypertension (1) depends on IHD (3), heart failure (5), and kidney disease (17), so we will need to save those conditions
dx_wide <- gmc %>%
  filter(disease %in% c(3, 5, 17)) %>%
  select(pnr, disease, date_disease) %>%
  mutate(
    disease = paste0("dis", disease)
  ) %>%
  pivot_wider(names_from = disease, values_from = date_disease)

gmc <- gmc %>%
  left_join(dx_wide)
rm(dx_wide)

####### Generate exclusion codes

# Prescriptions for HT (1) include only non-diuretic antihypertensives if previous CKD (17)
gmc <- gmc %>%
  mutate(
#    date_px = as.Date(ifelse(disease == 1 & dis17 <= date_px, nondiuretic, date_px), origin = "1970-01-01")
    date_px = as.Date(ifelse(disease == 1 & !is.na(dis17) & dis17 <= date_px, nondiuretic, date_px), origin = "1970-01-01")  ## fixed from previous version
  )

# Prescriptions for HT (1) are only considered if no previous IHD (3) or HF (5)
gmc <- gmc %>%
  mutate(
#    date_px = as.Date(ifelse(disease == 1 & (dis3 <= date_px | dis5 <= date_px), NA, date_px), origin = "1970-01-01")
    date_px = as.Date(ifelse(disease == 1 & ((!is.na(dis3) & dis3 <= date_px) | (!is.na(dis5) & dis5 <= date_px)), NA, date_px), origin = "1970-01-01")  ## fixed from previous version
  )

# We now calculate new date for HT (1) based on new prescriptions
gmc <- gmc %>%
  mutate(
    date_disease = as.Date(ifelse(disease == 1, pmin(date_dx, date_px, na.rm = T), date_disease), origin = "1970-01-01")
  )


# Prescriptions for Dyslipidemia (2) are only considered if no previous IHD (3) 
gmc <- gmc %>%
  mutate(
#    date_px = as.Date(ifelse(disease == 2 & dis3 <= date_px, NA, date_px), origin = "1970-01-01")
    date_px = as.Date(ifelse(disease == 2 & !is.na(dis3) & dis3 <= date_px, NA, date_px), origin = "1970-01-01") ## fixed from previous version
  )
gmc <- gmc %>%
  mutate(
    date_disease = as.Date(ifelse(disease == 2, pmin(date_dx, date_px, na.rm = T), date_disease), origin = "1970-01-01")
  )


# Prostate disorders (18) only for men
gmc <- gmc %>%
  left_join(population %>% select(pnr, sex)) %>%
  filter(disease != 18 | sex == 1)
rm(population)

# We select the final dataset
gmc <- gmc %>%
  filter(!is.na(date_disease)) %>%
  select(pnr, disease, date_disease)

gmc_broad <- gmc %>%
  mutate(
    broad_category = case_when(
      disease >= 1 & disease <= 7 ~ 101,
      disease >= 8 & disease <= 10 ~ 102,
      disease >= 11 & disease <= 12 ~ 103,
      disease >= 13 & disease <= 16 ~ 104,
      disease >= 17 & disease <= 18 ~ 105,
      disease >= 19 & disease <= 21 ~ 106,
      disease >= 22 & disease <= 23 ~ 107,
      disease == 24 ~ 108,
      disease >= 25 & disease <= 31 ~ 109,
      disease >= 1101 & disease <= 1102 ~ 103
    )
  ) %>%
  group_by(pnr, broad_category) %>%
  arrange(date_disease) %>%
  slice(1) %>%
  ungroup() %>%
  select(pnr, disease = broad_category, date_disease)
head(gmc_broad)



gmc <- gmc %>%
  bind_rows(gmc_broad) %>%
  mutate(
    disease_label = factor(
      disease,
      levels = c(1:31, 101:109, 1101, 1102),
      labels = c(
        "hypertension", "dyslipidemia", "ihd", "af", "hf", "paod", "stroke",
        "dm", "thyroid", "gout",
        "pulmonary", "allergy",
        "gastritis", "liver", "ibd", "diverticular",
        "kidney", "prostate",
        "connective", "osteoporosis", "painful",
        "hiv", "anemia",
        "cancer",
        "vision", "hearing", "migraine", "epilepsy", "parkinsons", "ms", "neuropathies",
        "CIRC",
        "ENDO",
        "PULMO",
        "GASTRO", 
        "URO",
        "MUSCULO",
        "HEMATO", 
        "CANCER", 
        "NEURO",
        "copd", "asthma"
      )
    )
  )

table(gmc$disease_label, useNA = "always")
rm(gmc_broad)

gmc <- gmc %>%
  select(pnr, disease, disease_label, date_disease)

nrow(gmc)
length(unique(gmc$pnr))

save(gmc, file=paste0(folder_output, "gmc2021.RData"))
haven::write_dta(gmc, path=paste0(folder_output, "Stata/gmc2021.dta"), label = NULL)
data.table::fwrite(gmc, file=paste0(folder_output, "csv/gmc2021.csv"))

### Now transform to wide format

gmc <- gmc %>%
  select(pnr, disease, date_disease) %>%
  mutate(disease = paste0("gmc", disease)) %>%
  pivot_wider(names_from = disease, values_from = date_disease)

gmc <- gmc[, c("pnr", paste0("gmc", c(1:31, 101:109, 1101, 1102)))]

head(gmc)

nrow(gmc)
length(unique(gmc$pnr))

save(gmc, file=paste0(folder_output, "gmc2021_wide.RData"))
haven::write_dta(gmc, path=paste0(folder_output, "Stata/gmc2021_wide.dta"), label = NULL)
data.table::fwrite(gmc, file=paste0(folder_output, "csv/gmc2021_wide.csv"))