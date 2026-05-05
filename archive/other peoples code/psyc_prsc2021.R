##########################
##########################
#### psyc_prsc2021
##########################
##########################

rm(list = ls())
library(dplyr)
library(tidyr)

##########################
#### Input data
load(file = "E:/workdata/708614/Datasets/population1986_2021.RData")
folder_input_LMDB <- "E:/rawdata/708614/grunddata/LMDB/"
##########################

##########################
#### Output data
folder_output <- "E:/workdata/708614/Datasets/"
##########################

##########################
#### We take all prescriptions and consider only those of interest

prescriptions <- data.frame()

# First, we combine all yearly data sets, creating the new variable "year",
# only keeping prescriptions with ATC codes N01-N07
for(year in 1995:2021) {
  print(year)
  px_year <- haven::read_sas(paste0(folder_input_LMDB, "lmdb", year, ".sas7bdat"))
  
  colnames(px_year) <- tolower(colnames(px_year))
  
  px_year <- px_year %>% 
    select(pnr, atc, eksd, indo) %>%
    mutate(
      atc3 = substr(atc,1,3),
      date = eksd,
      indication = indo
    )

  px_year <- px_year %>%
    filter((atc3 %in% c("N01", "N02", "N03", "N04", "N05", "N06", "N07"))) %>%
    select(pnr, atc, date, indication)
  
  prescriptions <- prescriptions %>%
    bind_rows(px_year %>% mutate(year = !!year))
}

rm(px_year)

# Then we merge with the population data
prescriptions <- prescriptions %>%
  left_join(population %>% select(pnr, sex, birth_d, death_d)) %>%
  filter(
    date >= birth_d,
    is.na(death_d) | date <= death_d,
    date < '2022-01-01' & date > '1994-12-31')
  
# Check
nrow(prescriptions)
length(unique(prescriptions$pnr))

# We keep the relevant variables and save the data
prescriptions <- prescriptions %>% 
  select(pnr, sex, birth_d, atc, date, indication)

save(prescriptions, file=paste0(folder_output, "psyc_prsc2021.RData"))
haven::write_dta(prescriptions, path=paste0(folder_output, "Stata/psyc_prsc2021.dta"), label = NULL)
data.table::fwrite(prescriptions,file=paste0(folder_output, "csv/psyc_prsc2021.csv"))