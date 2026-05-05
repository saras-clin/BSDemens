##########################
##########################
#### hospital2021
##########################
##########################

rm(list = ls())
library(dplyr)
library(tidyr)

##########################
#### Input data
lpr2_adm <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/t_adm.sas7bdat")
lpr2_diag <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/t_diag.sas7bdat")
psyc_adm1968 <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/patient_icd8.sas7bdat")
psyc_adm1994 <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/patient_icd10.sas7bdat")
psyc_diag1994 <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/diag_icd10.sas7bdat")
psyc_adm1995 <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/t_psyk_adm.sas7bdat")
psyc_diag1995 <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/t_psyk_diag.sas7bdat")
lpr3_adm <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/kontakter.sas7bdat")
lpr3_diag <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/diagnoser.sas7bdat")
load(file = "E:/workdata/708614/Datasets/population1986_2021.RData")
##########################

##########################
#### Output data
folder_output <- "E:/workdata/708614/Datasets/"
##########################


##########################
#### Harmonize all data periods to have two registers:
#### - ADM: with each contact with date and type of patient (and main diagnosis)
#### - DIAG: with all diagnoses from that contact

#### Psychiatric register 1968-1993 (ICD-8 / only inpatients). All data is in one
#### ADM dataset, so we need to create a DIAG dataset
colnames(psyc_adm1968) <- tolower(colnames(psyc_adm1968))
psyc_diag1968 <- psyc_adm1968 %>%
  select(recnum = pat_seq, c_diagA = hoveddiag, c_diagB1 = b1diag, c_diagB2 = b2diag, c_diagB3 = b3diag) %>%
  pivot_longer(!recnum, names_to = "c_diagtype", values_to = "c_diag") %>%
  mutate(
    c_diagtype = substr(c_diagtype, 7, 7)
  ) %>%
  filter(c_diag != "")


#### Psychiatric register 1994 (ICD-10 / only inpatients)
colnames(psyc_adm1994) <- tolower(colnames(psyc_adm1994))
colnames(psyc_diag1994) <- tolower(colnames(psyc_diag1994))

# Data from 1994 does not include main diagnosis in ADM, we add it
psyc_adm1994 <- psyc_adm1994 %>%
  left_join(
    psyc_diag1994 %>% filter(dart == "A") %>% select(pat_seq, c_adiag = diag)
  )

# Data from 1994 does not have a specific row for additional diagnoses
psyc_diag1994b <- psyc_diag1994 %>%
  select(pat_seq, diag, dart, tdiag1)

psyc_diag1994c <- psyc_diag1994b %>%
  mutate(tdiag1 = "") %>%
  bind_rows(
    psyc_diag1994c <- psyc_diag1994b %>%
      filter(tdiag1 != "") %>%
      mutate(
        dart = "+"
      )
  )
psyc_diag1994 <- psyc_diag1994c
rm(psyc_diag1994b, psyc_diag1994c)


#### Psychiatric register 1995-March 2019 (ICD-10 / inpatients, outpatients, emergency rooms / LPR2)
colnames(psyc_adm1995) <- tolower(colnames(psyc_adm1995))
colnames(psyc_diag1995) <- tolower(colnames(psyc_diag1995))

#### Hospital register 1977-March 2019
colnames(lpr2_adm) <- tolower(colnames(lpr2_adm))
colnames(lpr2_diag) <- tolower(colnames(lpr2_diag))


##########################
#### Combine all LPR2 datasets (1968/1977 - March 2019)
hosp_adm_LPR2 <- psyc_adm1968 %>%
  select(pnr = cprnr, recnum = pat_seq, d_inddto = indldato, d_uddto = udskdato, pattype = pttype, c_indm = indlmade, c_adiag = hoveddiag) %>%
  bind_rows(
    psyc_adm1994 %>%
      select(pnr = cprnr, recnum = pat_seq, d_inddto = indldato, d_uddto = udskdato, pattype = pttype, c_indm = indlmade, c_adiag)
  ) %>%
  bind_rows(
    psyc_adm1995 %>%
      mutate(
        c_pattype = as.numeric(c_pattype),
        c_indm = as.numeric(c_indm)) %>%
      select(pnr = v_cpr, recnum = k_recnum, d_inddto, d_uddto, pattype = c_pattype, c_indm, c_adiag)
  ) %>%
  mutate(lpr = "psychiatric") %>%
  bind_rows(
    lpr2_adm %>%
      mutate(
        c_pattype = as.numeric(c_pattype),
        c_indm = as.numeric(c_indm),
        lpr = "somatic") %>%
      select(pnr = v_cpr, recnum = k_recnum, d_inddto, d_uddto, pattype = c_pattype, c_indm, c_adiag, lpr)
  )

rm(psyc_adm1968, psyc_adm1994, psyc_adm1995, lpr2_adm)

hosp_diag_LPR2 <- psyc_diag1968 %>%
  bind_rows(psyc_diag1994 %>% select(recnum = pat_seq, c_diag = diag, c_diagtype = dart, c_tildiag = tdiag1)) %>%
  bind_rows(psyc_diag1995 %>% select(recnum = v_recnum, c_diag, c_diagtype, c_tildiag)) %>%
  bind_rows(lpr2_diag %>% select(recnum = v_recnum, c_diag, c_diagtype, c_tildiag))

rm(psyc_diag1968, psyc_diag1994, psyc_diag1995, lpr2_diag)



##########################
#### Hospital register March 2019 - onwards (LPR3)
colnames(lpr3_adm) <- tolower(colnames(lpr3_adm))
colnames(lpr3_diag) <- tolower(colnames(lpr3_diag))

### We keep only physical contacts 
hosp_adm_LPR3 <- lpr3_adm %>%
  filter(
    kontakttype == "ALCA00") %>%
  mutate(
    lpr = ifelse(hovedspeciale_ans %in% c("psykiatri", "b?rne- og ungdomspsykiatri"), "psychiatric", "somatic")
    ) %>%
  select(pnr = cpr, recnum = dw_ek_kontakt, d_inddto = dato_start, d_uddto = dato_slut, 
         enhedstype_ans, prioritet,
         c_adiag = aktionsdiagnose, time0 = tidspunkt_start, time1 = tidspunkt_slut, lpr)
rm(lpr3_adm)

### To have the same structure as LPR2, we keep additional diagnoses in c_tildiag and other diagnoses in c_diag
hosp_diag_LPR3 <- lpr3_diag %>%
  select(recnum = dw_ek_kontakt, c_diag = diagnosekode, c_diagtype = diagnosetype, parent = diagnosekode_parent) %>%
  inner_join(hosp_adm_LPR3 %>% select(recnum)) %>%
  mutate(
    c_tildiag = ifelse(c_diagtype == "+", c_diag, ""),
    c_diag = ifelse(c_diagtype == "+", parent, c_diag)
  ) %>%
  select(recnum, c_diag, c_diagtype, c_tildiag)
rm(lpr3_diag)





##########################
#### Determine patient type:
#### - inpatient
#### - outpatient
#### - emergency room visits


#### LPR2 (1968-2019)
# 1977-2019
# 0: Held?gnspatient/indlagt patient
# 
# 1994-2001
# 1: Deld?gnspatient
# 
# 1994-2019
# 2: Ambulant patient
# 
# 1994-2013
# 3: Skadestuepatient
# In 2014, or later, emergency visit --> c_pattype==2 and c_indm==1
#
#1974-1994
# 4: daypatient
# 5: nightpatient

table(lubridate::year(hosp_adm_LPR2$d_inddto), hosp_adm_LPR2$pattype)
table(lubridate::year(hosp_adm_LPR2$d_inddto), hosp_adm_LPR2$c_indm)

hosp_adm_LPR2 <- hosp_adm_LPR2 %>%
  mutate(type_patient = ifelse(pattype %in% c(0, 1, 4, 5), 1, 
                               ifelse(pattype==3, 3,
                                      ifelse(!is.na(c_indm) & c_indm==1, 3, 2)))) %>%
  select(pnr, recnum, d_inddto, d_uddto, c_adiag, type_patient, lpr)
# 1: inpatient
# 2: outpatient
# 3: emergency


#### LPR3 (2019-onward)
# 1: inpatient (if in the hospital for 8 hours or more)
# 3: emergency (if attended in ER and priority == "ATA1")
# 2: oupatient (all other options)

hosp_adm_LPR3 <- hosp_adm_LPR3 %>%
  mutate(
    length_days = as.numeric(d_uddto - d_inddto),
    length_hours = case_when(
      length_days == 0 ~ as.numeric(time1-time0)/(60*60),
      length_days != 0 & time0 <= time1 ~ (length_days-1)*24 + as.numeric(time1-time0)/(60*60),
      length_days != 0 & time0 > time1 ~ (length_days-1)*24 + (24-as.numeric(time0)/(60*60)) + as.numeric(time1)/(60*60)
    ),
    type_patient = case_when(
      length_hours >= 8 ~ 1,
      length_hours < 8 & enhedstype_ans == "skadestue" & prioritet == "ATA1" ~ 3,
      TRUE ~ 2
    )
  ) %>% select(pnr, recnum, d_inddto, d_uddto, c_adiag, type_patient, length_hours, lpr)





##########################
#### Combination of LPR2 and LPR3
hosp_adm <- hosp_adm_LPR2 %>%
  rename(hosp_type = lpr) %>%
  mutate(lpr = 2) %>%
  bind_rows(
    hosp_adm_LPR3 %>%
      rename(hosp_type = lpr) %>%
      mutate(lpr = 3)
  )


hosp_diag <- hosp_diag_LPR2 %>%
  mutate(lpr = 2) %>%
  bind_rows(
    hosp_diag_LPR3 %>%
      mutate(lpr = 3)
  )

rm(hosp_adm_LPR2, hosp_diag_LPR2, hosp_adm_LPR3, hosp_diag_LPR3)
##########################


##########################
#### Include information on birth date and sex
hosp_adm <- hosp_adm %>%
  inner_join(population, by = "pnr") %>%
  select(pnr, sex, birth_d, death_d, recnum, d_inddto, d_uddto, c_adiag, type_patient, length_hours, hosp_type, lpr)
rm(population)

##########################
#### Remove contacts happening before birth or after death
hosp_adm <- hosp_adm %>%
  filter(
    d_inddto >= birth_d,
    is.na(death_d) | (!is.na(death_d) & d_inddto <= death_d)
  )


##########################
#### Remove contacts with main diagnosis "rask ledsager" or "diagnosis not found"
hosp_adm <- hosp_adm %>%
  filter(
    substr(toupper(c_adiag), 1, 4) != "Y719",  # ICD-8
    !(substr(toupper(c_adiag), 1, 5) %in% c("DZ763", "DZ032", "DZ038", "DZ039"))   #ICD-10
  )


##########################
#### Include diagnosis information and remove associated diagnoses with main diagnosis "rask ledsager" or "diagnosis not found"
hospital <- hosp_adm %>%
  left_join(hosp_diag, by = c("recnum", "lpr")) %>%
  filter(
    (c_diagtype != "+") | (!(substr(toupper(c_diag), 1, 5) %in% c("DZ763", "DZ032", "DZ038", "DZ039")) & (substr(toupper(c_diag), 1, 4) != "Y719"))
  )
rm(hosp_adm, hosp_diag)

##########################
#### Remove referral diagnoses and complications
table(hospital$c_diagtype, useNA = "always")
hospital <- hospital %>%
  filter(c_diagtype %in% c("A", "B", "G", "+"))


##########################
#### For additional diagnoses (diagtype = "+"), we need to keep both the main diagnoses
###  (diag) and additional diagnoses (tildiag)
hospital <- hospital %>%
  bind_rows(
    hospital %>%
      filter(c_diagtype == "+") %>%
      mutate(c_diag = c_tildiag)
  ) %>%
  select(-c_tildiag) %>%
  distinct()


head(hospital)

hospital <- hospital %>%
  select(pnr, sex, birth_d, date_dx = d_inddto, date_ending = d_uddto, type_patient, length_hours, diag = c_diag, type_diag = c_diagtype, recnum, lpr, hosp_type)

nrow(hospital)
length(unique(hospital$pnr))

save(hospital, file=paste0(folder_output, "hospital2021.RData"))
haven::write_dta(hospital, path=paste0(folder_output, "Stata/hospital2021.dta"), label = NULL)