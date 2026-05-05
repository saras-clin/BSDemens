##########################
##########################
#### costs2007_2020
##########################
##########################

rm(list = ls())
library(dplyr)
library(tidyr)

##########################
#### Input data
folder_input <- "E:/rawdata/708614/grunddata/"
load("E:/workdata/708614/Datasets/population1986_2021.RData")
load("E:/workdata/708614/Datasets/LifeLines1986_2021.RData")
##########################

##########################
#### Output data
folder_output <- "E:/workdata/708614/Datasets/"
##########################

##########################
#### Data management

costs <- data.frame()

for(year in 2007:2020) {
  print(year)
  bef_year <- haven::read_sas(paste0(folder_input, "bef", year, "12.sas7bdat"))
  colnames(bef_year) <- tolower(colnames(bef_year))
  
  ## Population
  costs_year <- bef_year %>%
    select(pnr, sex = koen, birth_d = foed_dag) %>%
    distinct()
  rm(bef_year)
  
  ## Number of days registered
  migrations_year <- migrations %>%
    filter(
      entry_d <= as.Date(paste0(year, "-12-31")),
      exit_d >= as.Date(paste0(year, "-01-01"))
    ) %>%
    mutate(
      entry_d = pmax(entry_d, as.Date(paste0(year, "-01-01"))),
      exit_d = pmin(exit_d, as.Date(paste0(year, "-12-31")))
    ) %>%
    mutate(bef_days = as.numeric(exit_d - entry_d + 1)) %>%
    group_by(pnr) %>%
    summarise(bef_days = sum(bef_days)) %>%
    ungroup()
  
  costs_year <- costs_year %>%
    left_join(migrations_year) %>%
    mutate(bef_days = ifelse(is.na(bef_days), 0, bef_days))
  rm(migrations_year)

  ## Primary care costs
  primary <- haven::read_sas(paste0(folder_input, "sssy", year, ".sas7bdat"))
  colnames(primary) <- tolower(colnames(primary))
  
  primary <- primary %>%
    mutate(
      provider = case_when(
        ydtyp >= "01" & ydtyp <= "10" ~ "gp",
        ydtyp >= "11" & ydtyp <= "35" ~ "spec")) %>%
    filter(!is.na(provider)) %>%
    select(pnr, bruhon, provider) %>%
    group_by(pnr, provider) %>%
    summarise(hcosts = sum(bruhon)) %>%
    ungroup()
  
  primarysum <- spread(primary,provider,hcosts)
   
  costs_year <- costs_year %>%
    left_join(primarysum %>% select(pnr, gp, spec), by = "pnr")

  ## Prescription costs
  prescriptions <- haven::read_sas(paste0(folder_input, "LMDB/lmdb", year, ".sas7bdat"))
  colnames(prescriptions) <- tolower(colnames(prescriptions))
  
  prescriptions <- prescriptions %>% 
    select(pnr, eksp, ptp) %>%
    group_by(pnr) %>%
    summarise(prsc = sum(eksp) - sum(ptp)) %>%
    ungroup()
  
  costs_year <- costs_year %>%
    left_join(prescriptions %>% select(pnr, prsc), by = "pnr")
  
  ## Somatic hospital costs
  if (year >= 2019) {
    #Data is not available
  }
  else {
    if (year <= 2017) {
      #DRG costs
      somatic_drg <- haven::read_sas(paste0(folder_input, "drgsoma_hel", year, ".sas7bdat"))
      colnames(somatic_drg) <- tolower(colnames(somatic_drg))
      
      somatic_drg <- somatic_drg %>%
        mutate(hcosts = v_totpris_genop * 1000) %>%
        select(pnr, hcosts) %>%
        filter(hcosts != 0) %>%
        group_by(pnr) %>%
        summarise(som_drg = sum(hcosts)) %>%
        ungroup()
      
      #DAG costs
      somatic_dag <- haven::read_sas(paste0(folder_input, "drgsoma_amb", year, ".sas7bdat"))
      colnames(somatic_dag) <- tolower(colnames(somatic_dag))
      
      somatic_dag <- somatic_dag %>%
        mutate(hcosts = v_pris_genop * 1000) %>%
        select(pnr, hcosts) %>%
        filter(hcosts != 0) %>%
        group_by(pnr) %>%
        summarise(som_dag = sum(hcosts)) %>%
        ungroup()
      
      #Combined
      somatic <- somatic_drg %>%
        full_join(somatic_dag %>% select(pnr, som_dag), by = "pnr")
    
      } else {
        
        #DAG & DRG
        somatic <- haven::read_sas(paste0(folder_input, "drgsoma_kontakt", year, ".sas7bdat"))
        colnames(somatic) <- tolower(colnames(somatic))
      
        somatic <- somatic %>%
          mutate(
            type = case_when(
              is.na(ambulant_dato) ~ "som_drg",
              !is.na(ambulant_dato) ~ "som_dag")) %>%
          select(pnr, totalpris_drg, type) %>%
          filter(totalpris_drg != 0) %>%
          group_by(pnr, type) %>%
          summarise(hcosts = sum(totalpris_drg)) %>%
          ungroup()
      
        somatic <- spread(somatic,type,hcosts)
      }
    
    costs_year <- costs_year %>%
      left_join(somatic %>% select(pnr, som_drg, som_dag), by = "pnr")
  }
  
  ## Psychiatric hospital costs
  if (year >= 2019) {
    #Data is not available
  }
  else {
    
    #DRG costs
    psychiatric_drg <- haven::read_sas(paste0(folder_input, "drgpsyk_hel", year, ".sas7bdat"))
    colnames(psychiatric_drg) <- tolower(colnames(psychiatric_drg))
    psychiatric_drg <- psychiatric_drg %>%
      mutate(hcosts = v_totpris * 1000) %>%
      select(pnr, hcosts) %>%
      filter(hcosts != 0) %>%
      group_by(pnr) %>%
      summarise(psyc_drg = sum(hcosts)) %>%
      ungroup()
      
    #DAG costs
    psychiatric_dag <- haven::read_sas(paste0(folder_input, "drgpsyk_amb", year, ".sas7bdat"))
    colnames(psychiatric_dag) <- tolower(colnames(psychiatric_dag))
    psychiatric_dag <- psychiatric_dag %>%
      mutate(hcosts = v_pris * 1000) %>%
      select(pnr, hcosts) %>%
      filter(hcosts != 0) %>%
      group_by(pnr) %>%
      summarise(psyc_dag = sum(hcosts)) %>%
      ungroup()
      
    #Combined
    psychiatric <- psychiatric_drg %>%
      full_join(psychiatric_dag %>% select(pnr, psyc_dag), by = "pnr")
    
    costs_year <- costs_year %>%
      left_join(psychiatric %>% select(pnr, psyc_drg, psyc_dag), by = "pnr")
  }
  
  ## Primary wage income and transfers
  wage <- haven::read_sas(paste0(folder_input, "ind", year, ".sas7bdat"))
  colnames(wage) <- tolower(colnames(wage))

  costs_year <- costs_year %>%
    left_join(wage %>% select(pnr, wage = aindk94, transfers = off_overforsel_13) %>% distinct(), by = "pnr") 

  ### Restrict to our study population
  costs_year <- costs_year %>%
    filter(pnr %in% population$pnr)

  ## We save the data from each year
  costs_year <- costs_year %>%
    mutate(year = !!year)
  costs <- costs %>% bind_rows(costs_year)
  rm(costs_year)
}

## Replace NA values with 0 for healthcare costs
costs <- costs %>%
  mutate_at(c('gp','spec','prsc','som_drg','som_dag','psyc_drg','psyc_dag'), ~replace_na(.,0))

## Order the variables and get summary statistics
costs <- costs[,c(1,14,2,3,4,5,6,7,8,9,10,11,12,13)]
nrow(costs)
length(unique(costs$pnr))

save(costs, file=paste0(folder_output, "costs2007_2020.RData"))
haven::write_dta(costs, path=paste0(folder_output, "Stata/costs2007_2020.dta"))
data.table::fwrite(costs,file=paste0(folder_output, "csv/costs2007_2020.csv"))