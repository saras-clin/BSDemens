##########################
##########################
#### psyc2021 (version 1)
##########################
##########################

rm(list = ls())
library(dplyr)
library(tidyr)

##########################
#### Input data
psyc_adm1968 <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/patient_icd8.sas7bdat")
psyc_adm1994 <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/patient_icd10.sas7bdat")
psyc_diag1994 <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/diag_icd10.sas7bdat")
psyc_adm1995 <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/t_psyk_adm.sas7bdat")
psyc_diag1995 <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/t_psyk_diag.sas7bdat")
psyc_adm2019 <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/kontakter.sas7bdat")
psyc_diag2019 <- haven::read_sas("E:/rawdata/708614/Eksterne data/20220908_FraSDS/diagnoser.sas7bdat")
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


##########################
#### Combine all LPR2 datasets (1968 - March 2019)
psyc_adm_LPR2 <- psyc_adm1968 %>%
  mutate(icd = 8) %>%
  select(pnr = cprnr, recnum = pat_seq, d_inddto = indldato, d_uddto = udskdato, pattype = pttype, c_indm = indlmade, c_adiag = hoveddiag, icd) %>%
  bind_rows(
    psyc_adm1994 %>%
      mutate(icd = 10) %>%
      select(pnr = cprnr, recnum = pat_seq, d_inddto = indldato, d_uddto = udskdato, pattype = pttype, c_indm = indlmade, c_adiag, icd)
  ) %>%
  bind_rows(
    psyc_adm1995 %>%
      mutate(
        icd = 10,
        c_pattype = as.numeric(c_pattype),
        c_indm = as.numeric(c_indm)) %>%
      select(pnr = v_cpr, recnum = k_recnum, d_inddto, d_uddto, pattype = c_pattype, c_indm, c_adiag, icd)
  )
rm(psyc_adm1968, psyc_adm1994, psyc_adm1995)

psyc_diag_LPR2 <- psyc_diag1968 %>%
  bind_rows(psyc_diag1994 %>% select(recnum = pat_seq, c_diag = diag, c_diagtype = dart, c_tildiag = tdiag1)) %>%
  bind_rows(psyc_diag1995 %>% select(recnum = v_recnum, c_diag, c_diagtype, c_tildiag))
rm(psyc_diag1968, psyc_diag1994, psyc_diag1995)




##########################
#### Psychiatric register March 2019 - onwards (ICD-10 / inpatients, outpatients, emergency rooms / LPR3)
colnames(psyc_adm2019) <- tolower(colnames(psyc_adm2019))
colnames(psyc_diag2019) <- tolower(colnames(psyc_diag2019))

### We keep only physical contacts from psychiatric departments
psyc_adm_LPR3 <- psyc_adm2019 %>%
  filter(
    hovedspeciale_ans %in% c("psykiatri", "børne- og ungdomspsykiatri"),
    kontakttype == "ALCA00") %>%
  mutate(icd = 10) %>%
  select(pnr = cpr, recnum = dw_ek_kontakt, d_inddto = dato_start, d_uddto = dato_slut, 
         enhedstype_ans, prioritet,
         c_adiag = aktionsdiagnose, time0 = tidspunkt_start, time1 = tidspunkt_slut, icd)
rm(psyc_adm2019)

### To have the same structure as LPR2, we keep additional diagnoses in c_tildiag and other diagnoses in c_diag
psyc_diag_LPR3 <- psyc_diag2019 %>%
  select(recnum = dw_ek_kontakt, c_diag = diagnosekode, c_diagtype = diagnosetype, parent = diagnosekode_parent) %>%
  inner_join(psyc_adm_LPR3 %>% select(recnum)) %>%
  mutate(
    c_tildiag = ifelse(c_diagtype == "+", c_diag, ""),
    c_diag = ifelse(c_diagtype == "+", parent, c_diag)
  ) %>%
  select(recnum, c_diag, c_diagtype, c_tildiag)
rm(psyc_diag2019)






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

psyc_adm_LPR2 <- psyc_adm_LPR2 %>%
  mutate(type_patient = ifelse(pattype %in% c(0, 1, 4, 5), 1, 
                               ifelse(pattype==3, 3,
                                      ifelse(!is.na(c_indm) & c_indm==1, 3, 2)))) %>%
  select(pnr, recnum, d_inddto, d_uddto, c_adiag, type_patient, icd)
# 1: inpatient
# 2: outpatient
# 3: emergency


#### LPR3 (2019-onward)
# 1: inpatient (if in the hospital for 8 hours or more)
# 3: emergency (if attended in ER and priority == "ATA1")
# 2: oupatient (all other options)

psyc_adm_LPR3 <- psyc_adm_LPR3 %>%
  mutate(
    length_days = as.numeric(d_uddto - d_inddto),
    length_hours_aux = as.numeric(time1 - time0)/(60*60),
    length_hours = 24*length_days + length_hours_aux,
    type_patient = case_when(
      length_hours >= 8 ~ 1,
      length_hours < 8 & enhedstype_ans == "skadestue" & prioritet == "ATA1" ~ 3,
      TRUE ~ 2
    )
  ) %>% select(pnr, recnum, d_inddto, d_uddto, c_adiag, type_patient, icd)





##########################
#### Combination of LPR2 and LPR3
psyc_adm <- psyc_adm_LPR2 %>%
  mutate(lpr = 2) %>%
  bind_rows(
    psyc_adm_LPR3 %>%
      mutate(lpr = 3)
  )


psyc_diag <- psyc_diag_LPR2 %>%
  mutate(lpr = 2) %>%
  bind_rows(
    psyc_diag_LPR3 %>%
      mutate(lpr = 3)
  )

rm(psyc_adm_LPR2, psyc_diag_LPR2, psyc_adm_LPR3, psyc_diag_LPR3)
##########################


##########################
#### Include information on birth date and sex
psyc_adm <- psyc_adm %>%
  inner_join(population, by = "pnr") %>%
  select(pnr, sex, birth_d, death_d, recnum, d_inddto, d_uddto, c_adiag, type_patient, lpr, icd)
rm(population)

##########################
#### Remove contacts happening before birth date and with main diagnosis "rask ledsager" or "diagnosis not found"
psyc_adm <- psyc_adm %>%
  filter(
    d_inddto >= birth_d,
    is.na(death_d) | (!is.na(death_d) & d_inddto <= death_d),
    substr(toupper(c_adiag), 1, 4) != "Y719",  # ICD-8
    !(substr(toupper(c_adiag), 1, 5) %in% c("DZ763", "DZ032", "DZ038", "DZ039"))   #ICD-10
  )

##########################
#### Include diagnosis information and remove associated diagnoses with main diagnosis "rask ledsager" or "diagnosis not found"
psyc <- psyc_adm %>%
  left_join(psyc_diag, by = c("recnum", "lpr")) %>%
  filter(
    (c_diagtype != "+") | (!(substr(toupper(c_diag), 1, 5) %in% c("DZ763", "DZ032", "DZ038", "DZ039")) & (substr(toupper(c_diag), 1, 4) != "Y719"))
  )
rm(psyc_adm, psyc_diag)

##########################
#### Remove referral diagnoses and complications
psyc <- psyc %>%
  filter(c_diagtype %in% c("A", "B", "G", "+"))

##########################
#### For additional diagnoses (diagtype = "+"), we need to keep both the main diagnoses
###  (diag) and additional diagnoses (tildiag)
psyc <- psyc %>%
  bind_rows(
    psyc %>%
      filter(c_diagtype == "+") %>%
      mutate(c_diag = c_tildiag)
  ) %>%
  select(-c_tildiag) %>%
  distinct()

##########################
#### We keep only mental disorders and save the dataset with all diagnoses in psychiatric departments
psyc <- psyc %>%
  filter(
    (("DF00" <= toupper(c_diag)) & (toupper(c_diag) <= "DF9999")) | (("290" <= c_diag) & (c_diag <= "31599"))
  ) %>%
  select(-death_d)

head(psyc)
table(psyc$lpr)
summary(psyc$d_inddto)

## Classify 10 subgroups
psyc$MDatlas10 <- NA

classify_atlas <- function(data, diag_low, diag_high, label) {
  data <- data %>%
    mutate(
      MDatlas10 = ifelse(((diag_low <= toupper(c_diag)) & (toupper(c_diag) <= diag_high)), label, MDatlas10)
    )
  return(data)
}

# D00: F00-F09
psyc <- classify_atlas(psyc, "DF00", "DF0999", "D00")
psyc <- classify_atlas(psyc, "29009", "29009", "D00")
psyc <- classify_atlas(psyc, "29010", "29010", "D00")
psyc <- classify_atlas(psyc, "29011", "29011", "D00")
psyc <- classify_atlas(psyc, "29018", "29018", "D00")
psyc <- classify_atlas(psyc, "29019", "29019", "D00")
psyc <- classify_atlas(psyc, "29209", "29299", "D00")
psyc <- classify_atlas(psyc, "29309", "29399", "D00")
psyc <- classify_atlas(psyc, "29409", "29429", "D00")     
psyc <- classify_atlas(psyc, "29439", "29499", "D00")     
psyc <- classify_atlas(psyc, "30909", "30949", "D00")     
psyc <- classify_atlas(psyc, "30959", "30999", "D00")    

#D10: F10-F19
psyc <- classify_atlas(psyc, "DF10", "DF1999", "D10")
psyc <- classify_atlas(psyc, "29109", "29199", "D10")
psyc <- classify_atlas(psyc, "29439", "29439", "D10")
psyc <- classify_atlas(psyc, "30309", "30390", "D10")      
psyc <- classify_atlas(psyc, "30399", "30399", "D10")      
psyc <- classify_atlas(psyc, "30409", "30499", "D10")      

#D20: F20-F29
psyc <- classify_atlas(psyc, "DF20", "DF2999", "D20")
psyc <- classify_atlas(psyc, "29509", "29599", "D20")
psyc <- classify_atlas(psyc, "29689", "29689", "D20")
psyc <- classify_atlas(psyc, "29709", "29799", "D20")
psyc <- classify_atlas(psyc, "29829", "29899", "D20")
psyc <- classify_atlas(psyc, "29904", "29905", "D20")
psyc <- classify_atlas(psyc, "29909", "29909", "D20")
psyc <- classify_atlas(psyc, "30183", "30183", "D20")

#D30: F30-F39
psyc <- classify_atlas(psyc, "DF30", "DF3999", "D30")
psyc <- classify_atlas(psyc, "29609", "29679", "D30")
psyc <- classify_atlas(psyc, "29699", "29699", "D30")
psyc <- classify_atlas(psyc, "29809", "29809", "D30")
psyc <- classify_atlas(psyc, "29819", "29819", "D30")
psyc <- classify_atlas(psyc, "30049", "30049", "D30")
psyc <- classify_atlas(psyc, "30119", "30119", "D30")

#D41: F40-48
psyc <- classify_atlas(psyc, "DF40", "DF4899", "D41")
psyc <- classify_atlas(psyc, "30009", "30039", "D41")
psyc <- classify_atlas(psyc, "30059", "30099", "D41")
psyc <- classify_atlas(psyc, "30509", "30559", "D41")
psyc <- classify_atlas(psyc, "30569", "30599", "D41")
psyc <- classify_atlas(psyc, "30568", "30568", "D41")
psyc <- classify_atlas(psyc, "30799", "30799", "D41")

#D51: F50
psyc <- classify_atlas(psyc, "DF50", "DF5099", "D51")
psyc <- classify_atlas(psyc, "30650", "30650", "D51")
psyc <- classify_atlas(psyc, "30658", "30658", "D51")
psyc <- classify_atlas(psyc, "30659", "30659", "D51")

#D61: F60
psyc <- classify_atlas(psyc, "DF60", "DF6099", "D61")
psyc <- classify_atlas(psyc, "30109", "30109", "D61")
psyc <- classify_atlas(psyc, "30129", "30179", "D61")
psyc <- classify_atlas(psyc, "30189", "30199", "D61")
psyc <- classify_atlas(psyc, "30180", "30182", "D61")
psyc <- classify_atlas(psyc, "30184", "30184", "D61")

#D70: F70-F79
psyc <- classify_atlas(psyc, "DF70", "DF7999", "D70")
psyc <- classify_atlas(psyc, "31100", "31199", "D70")
psyc <- classify_atlas(psyc, "31200", "31299", "D70")
psyc <- classify_atlas(psyc, "31300", "31399", "D70")
psyc <- classify_atlas(psyc, "31400", "31499", "D70")
psyc <- classify_atlas(psyc, "31500", "31599", "D70")

#D81: F84
psyc <- classify_atlas(psyc, "DF84", "DF8499", "D81")
psyc <- classify_atlas(psyc, "29900", "29903", "D81")

#D91: F90-F98
psyc <- classify_atlas(psyc, "DF90", "DF9899", "D91")
psyc <- classify_atlas(psyc, "30609", "30609", "D91")
psyc <- classify_atlas(psyc, "30619", "30649", "D91")
psyc <- classify_atlas(psyc, "30659", "30699", "D91")
psyc <- classify_atlas(psyc, "30800", "30809", "D91")

table(psyc$MDatlas10, useNA = "always")
head(psyc)

psyc <- psyc %>%
  select(pnr, sex, birth_d, date_dx = d_inddto, date_ending = d_uddto, type_patient, diag = c_diag, type_diag = c_diagtype, MDatlas10, recnum, lpr, icd)

nrow(psyc)
length(unique(psyc$pnr))

save(psyc, file=paste0(folder_output, "psyc2021.RData"))
haven::write_dta(psyc, path=paste0(folder_output, "Stata/psyc2021.dta"), label = NULL)