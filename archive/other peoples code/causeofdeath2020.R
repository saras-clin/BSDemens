##########################
##########################
#### cod2020
##########################
##########################

rm(list = ls())
library(dplyr)
library(tidyr)

##########################
#### Input data
cod_date <- haven::read_sas("E:/rawdata/708614/grunddata/dod2021.sas7bdat")
cod2001 <- haven::read_sas("E:/rawdata/708614/grunddata/dodsaars2001.sas7bdat")
cod2020 <- haven::read_sas("E:/rawdata/708614/grunddata/dodsaasg2020.sas7bdat")
load(file = "E:/workdata/708614/Datasets/population1986_2021.RData")
##########################

##########################
#### Output data
folder_output <- "E:/workdata/708614/Datasets/"
##########################


##########################
#### Combine datasets
colnames(cod_date) <- tolower(colnames(cod_date))
colnames(cod2001) <- tolower(colnames(cod2001))
colnames(cod2020) <- tolower(colnames(cod2020))

cod <- population %>% select(pnr) %>%
  left_join(
    cod_date %>%
  select(pnr, death_d = doddato)
  )%>%
  filter(!is.na(death_d)) %>%
  left_join(
    cod2001 %>%
      select(pnr, cod = c_dod1, cod14 = c_liste_14) %>%
      bind_rows(
        cod2020 %>%
          select(pnr, cod = c_dodtilgrundl_acme, cod14 = c_liste14)
      ),
    by = "pnr"
  )

rm(population, cod_date, cod2001, cod2020)

head(cod)
table(cod$cod14, useNA = "always")

cod <- cod %>%
  mutate(
    year = lubridate::year(death_d),
    cod11 = case_when(
      year >= 1994 & substr(cod, 1, 3) >= "A15" & substr(cod, 1, 3) <= "A99" ~ 1,
      year >= 1994 & substr(cod, 1, 3) >= "B00" & substr(cod, 1, 3) <= "B99" ~ 1,
      year >= 1994 & substr(cod, 1, 3) >= "A00" & substr(cod, 1, 3) <= "A09" ~ 1,
      year >= 1994 & substr(cod, 1, 3) >= "C00" & substr(cod, 1, 3) <= "D09" ~ 2,
      year >= 1994 & substr(cod, 1, 3) >= "E10" & substr(cod, 1, 3) <= "E14" ~ 3,
      year >= 1994 & substr(cod, 1, 4) == "F039" ~ 4,
      year >= 1994 & substr(cod, 1, 3) >= "I00" & substr(cod, 1, 3) <= "I25" ~ 4,
      year >= 1994 & substr(cod, 1, 3) == "I27" ~ 4,
      year >= 1994 & substr(cod, 1, 3) >= "I30" & substr(cod, 1, 3) <= "I52" ~ 4,
      year >= 1994 & substr(cod, 1, 3) >= "I60" & substr(cod, 1, 3) <= "I84" ~ 4,
      year >= 1994 & substr(cod, 1, 3) >= "I86" & substr(cod, 1, 3) <= "I99" ~ 4,
      year >= 1994 & substr(cod, 1, 3) == "R54" ~ 4,
      year >= 1994 & substr(cod, 1, 3) >= "J00" & substr(cod, 1, 3) <= "J99" ~ 5,
      year >= 1994 & substr(cod, 1, 3) >= "K00" & substr(cod, 1, 3) <= "K69" ~ 6,
      year >= 1994 & substr(cod, 1, 3) >= "K71" & substr(cod, 1, 3) <= "K93" ~ 6,
      year >= 1994 & substr(cod, 1, 3) == "F10" ~ 7,
      year >= 1994 & substr(cod, 1, 3) == "I85" ~ 7,
      year >= 1994 & substr(cod, 1, 3) == "K70" ~ 7,
      year >= 1994 & substr(cod, 1, 3) >= "X60" & substr(cod, 1, 3) <= "X84" ~ 8,
      year >= 1994 & substr(cod, 1, 4) == "Y870" ~ 8,
      year >= 1994 & substr(cod, 1, 3) >= "V01" & substr(cod, 1, 3) <= "X59" ~ 9,
      year >= 1994 & substr(cod, 1, 3) >= "Y10" & substr(cod, 1, 3) <= "Y86" ~ 9,
      year >= 1994 & substr(cod, 1, 4) == "Y872" ~ 9,
      year >= 1994 & substr(cod, 1, 3) >= "Y88" & substr(cod, 1, 3) <= "Y89" ~ 9,
      year >= 1994 & substr(cod, 1, 3) >= "X85" & substr(cod, 1, 3) <= "Y09" ~ 10,
      year >= 1994 & substr(cod, 1, 4) == "Y871" ~ 10,
      year >= 1994 & year <= 2020 ~ 11
    ),
    cod11_label = factor(
      cod11,
      levels = 1:11,
      labels = c(
        "Infectious diseases", 
        "Cancer", 
        "Diabetes Mellitus", 
        "Diseases circulatory system", 
        "Respiratory diseases", 
        "Digestive diseases", 
        "Alcohol misuse", 
        "Suicide", 
        "Accidents", 
        "Homicide", 
        "Others"
      )
    )
  )

table(cod$year, cod$cod11, useNA="always")
table(cod$year, cod$cod11_label, useNA="always")
head(cod)

cod <- cod %>%
  select(pnr, death_d, cod, cod14, cod11, cod11_label)

save(cod, file=paste0(folder_output, "cod2020.RData"))
haven::write_dta(cod, path=paste0(folder_output, "Stata/cod2020.dta"), label = NULL)