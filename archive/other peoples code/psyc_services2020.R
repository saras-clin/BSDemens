##########################
##########################
#### psych_services2020
##########################
##########################

rm(list = ls())
library(dplyr)
library(tidyr)

##########################
#### Input data
load(file = "E:/workdata/708614/Datasets/population1986_2021.RData")
folder_input <- "E:/rawdata/708614/grunddata/"
##########################

##########################
#### Output data
folder_output <- "E:/workdata/708614/Datasets/"
##########################

##########################
#### We take all registered healthcare services and consider only those of interest

services <- data.frame()
sssy <- data.frame()
sysi <- data.frame()

# First, we combine all yearly SSSY data sets,
# only keeping healthcare services with private practicing psychiatrists
for(ryear in 2006:2020) {
  print(ryear)
  px_ryear <- haven::read_sas(paste0(folder_input, "sssy", ryear, ".sas7bdat"))

  colnames(px_ryear) <- tolower(colnames(px_ryear))
  
  px_ryear <- px_ryear %>% 
    select(pnr, speciale, ydlant, honuge) %>%
    mutate(
      spec2 = substr(speciale,1,2),
      no_services = ydlant,
      type_service = as.numeric(speciale),
      register = "SSSY"
    )
  
  px_ryear <- px_ryear %>%
    mutate(
      type_prof = case_when(
        spec2 == "24" ~ "24",
        spec2 == "26" ~ "26",
        spec2 == "35" ~ "35",
      )
    )
  
  px_ryear <- px_ryear %>%
    filter(!is.na(type_prof)) %>%
    select(pnr, type_prof, type_service, no_services, honuge, register) %>%
    mutate(type_prof = as.numeric(type_prof))
  
  sssy <- sssy %>%
    bind_rows(px_ryear %>% mutate(ryear = !!ryear))
}

rm(px_ryear)

# Second, we combine all yearly SYSI data sets,
# only keeping healthcare services with private practicing psychiatrists
for(ryear in 1990:2005) {
  print(ryear)
  px_ryear <- haven::read_sas(paste0(folder_input, "sysi", ryear, ".sas7bdat"))
  
  colnames(px_ryear) <- tolower(colnames(px_ryear))
  
  px_ryear <- px_ryear %>% 
    select(pnr, speciale, ydlant, honuge) %>%
    mutate(
      spec2 = substr(speciale,1,2),
      no_services = ydlant,
      type_service = as.numeric(speciale),
      register = "SYSI"
    )
  
  px_ryear <- px_ryear %>%
    mutate(
      type_prof = case_when(
        spec2 == "24" ~ "24",
        spec2 == "26" ~ "26",
        spec2 == "35" ~ "35",
        )
    )
  
  px_ryear <- px_ryear %>%
    filter(!is.na(type_prof)) %>%
    select(pnr, type_prof, type_service, no_services, honuge, register) %>%
    mutate(type_prof = as.numeric(type_prof))
  
  sysi <- sysi %>%
    bind_rows(px_ryear %>% mutate(ryear = !!ryear))
}

rm(px_ryear)

# Then we merge the two data sets
services <- sssy %>%
  bind_rows(sysi) %>%
  select(pnr, type_prof, type_service, no_services, honuge, register, ryear)

# We convert "honuge" to an approximate date, choosing the first day of the week
services <- services %>%
  mutate(
    yeardigits = substr(honuge,1,2),
    weekdigits =  substr(honuge,3,4)
  )

services <- services %>%
  mutate(
    century = case_when(
      yeardigits >= "90" & yeardigits <= "99" ~ "19",
      yeardigits >= "00" & yeardigits <= "20" ~ "20"
      )
  )

services <- services %>%
  transform(year = as.numeric(paste0(century, yeardigits)),
            week = as.numeric(weekdigits))

services <- services %>%
  transform(date = as.Date(paste(year,weekdigits,1,sep=""), "%Y%U%u"))

# Not all health services are registered in the correct year around the year-end - but this is expected
View(services[services$year==2004 & services$ryear==2005,])

services <- services %>%
  mutate(
    unequal = case_when(
      year != ryear ~ "1"
    ),
  )

services %>% count(unequal)

# Then we merge with the population data and filter the data
services <- services %>%
  left_join(population %>% select(pnr, sex, birth_d, death_d)) %>%
  filter(
    date >= birth_d,
    is.na(death_d) | date <= death_d,
    yeardigits >= 90 | yeardigits <= 20)
              
# We keep the relevant variables and save the data
services <- services %>%
  select(pnr, sex, birth_d, type_prof, type_service, no_services, year, week, date, register)

save(services, file=paste0(folder_output, "psyc_services2020.RData"))
haven::write_dta(services, path=paste0(folder_output, "Stata/psyc_services2020.dta"), label = NULL)
data.table::fwrite(services,file=paste0(folder_output, "csv/psyc_services2020.csv"))