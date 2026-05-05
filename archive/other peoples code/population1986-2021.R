##########################
##########################
#### population1986_2021
##########################
##########################

rm(list = ls())
library(dplyr)

##########################
#### Input data
folder_input_DST <- "E:/rawdata/708614/grunddata/"
bef_bop <- haven::read_sas("E:/rawdata/708614/grunddata/befbop202112.sas7bdat")
bef_adr <- haven::read_sas("E:/rawdata/708614/grunddata/befadr202203.sas7bdat")
colnames(bef_bop) <- tolower(colnames(bef_bop))
colnames(bef_adr) <- tolower(colnames(bef_adr))
municipalities <- readxl::read_excel("E:/workdata/708614/Datasets/municipalities.xlsx")
##########################

##########################
#### Output data
folder_output <- "E:/workdata/708614/Datasets/"
##########################


# The population is selected from the BEF registers. Those of the last year with data available (2021) 
# are selected and information on parents, sex, origin, birthdate and birth place is kept
# Then going back in time, the population at each given year is appended (if the person had not been included before)

pop <- data.frame()

for(year in 2021:1985) {
  print(year)
  bef_year <- haven::read_sas(paste0(folder_input_DST, "bef", year, "12.sas7bdat"))
  colnames(bef_year) <- tolower(colnames(bef_year))
  
  bef <- bef_year %>%
    select(pnr, pnrm = mor_id, pnrf = far_id, birth_d = foed_dag, ie_type, sex = koen, birth_place = foedreg_kode)
  
  pop <- pop %>% bind_rows(bef %>% filter(!(pnr %in% pop$pnr)))
  rm(bef)
  
}

# The municipality is transformed into country (Denmark, Greenland, Abroad, Unknown)
country <- function(x) {
  return(case_when(
    x == 0 ~ 'Unknown',
    x >= 101 & x <= 900 ~ 'Denmark',
    x >= 901 & x <= 961 ~ 'Greenland',
    x == 3999 ~ 'Greenland',
    x >= 2401 & x <= 2599 ~ 'Denmark',
    x >= 4001 & x <= 4007 ~ 'Denmark',
    x >= 4301 & x <= 4499 ~ 'Denmark',
    x >= 4501 & x <= 4599 ~ 'Denmark',
    x >= 4601 & x <= 4687 ~ 'Denmark',
    x >= 4688 & x <= 4799 ~ 'Denmark',
    x >= 4801 & x <= 4989 ~ 'Denmark',
    x == 4998 ~ 'Denmark',
    x == 4999 ~ 'Unknown',
    x == 5001 ~ 'Unknown',
    x == 5100 ~ 'Denmark',
    x == 5101 ~ 'Greenland',
    x == 5102 ~ 'Abroad',
    x == 5103 ~ 'Unknown',
    x >= 5104 & x <= 5902 ~ 'Abroad',
    x == 5999 ~ 'Abroad',
    x >= 7001 & x <= 9348 ~ 'Denmark',
    x >= 9501 & x <= 9599 ~ 'Greenland',
    x == 9999 ~ 'Denmark',
    TRUE  ~ 'Unknown'
  ))
}

pop$birth_country <- country(pop$birth_place)

### Death dates are now included from the DOD register
dod <- haven::read_sas(paste0(folder_input_DST, "dod2021.sas7bdat"))
colnames(dod) <- tolower(colnames(dod))

pop <- pop %>%
  left_join(dod %>% select(pnr, death_d = doddato), by = "pnr") %>%
  filter(is.na(death_d) | (!is.na(death_d) & death_d >= as.Date("1986-01-01")))

### Some individuals are registered in the CPR register for tax reasons, but they
### do not live in Denmark. They should be excluded

# First we keep only residences in Denmark (excluding Greenland)
municipalities_DK <- unique(c(municipalities$OldCommunityCode, municipalities$NewCommunityCode))
                            
bef_adr <- bef_adr %>%
  filter(kom %in% municipalities_DK) 
  
bef_bop <- bef_bop %>%
  filter(adresse_id %in% unique(bef_adr$adresse_id))

bef_bop <- bef_bop %>%
  group_by(pnr) %>%
  summarise(
    max_date = max(bop_vtil)
  ) %>%
  ungroup()

pop <- pop %>%
  inner_join(bef_bop) %>%
  filter(
    (max_date >= as.Date("1986-01-01")) | ((max_date == as.Date("1985-12-31") & (death_d == as.Date("1986-01-01"))))
  )

population <- pop %>%
  select(pnr, sex, birth_d, birth_place, birth_country, ie_type, death_d, pnrm, pnrf)

nrow(population)

save(population, file=paste0(folder_output, "population1986_2021.RData"))
haven::write_dta(population, path=paste0(folder_output, "Stata/population1986_2021.dta"))