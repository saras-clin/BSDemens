##########################
##########################
#### psyc_atlas2021
##########################
##########################

rm(list = ls())
library(dplyr)
library(tidyr)

##########################
#### Input data
load(file = "E:/workdata/708614/Datasets/psyc2021.RData")
##########################

##########################
#### Output data
folder_output <- "E:/workdata/708614/Datasets/"
##########################

#### First, we keep all diagnsoses of mental disorders after age 1 year
psyc <- psyc %>%
  filter(lubridate::time_length(difftime(date_dx, birth_d), "years") >=1)

## Now we create a function to keep diagnosis within two reference codes
diag_classify <- function(data, diag_low, diag_high) {
  data2 <- data %>%
    filter(
      ((diag_low <= toupper(diag)) & (toupper(diag) <= diag_high))
    )
  return(data2)
}


## And now a function to take the first appearance and give a name to that
disease_first <- function(data, label, min_age) {
  data2 <- data %>%
    filter(lubridate::time_length(difftime(date_dx, birth_d), "years") >= min_age) %>%
    group_by(pnr) %>%
    arrange(date_dx) %>%
    filter(row_number()==1) %>%
    select(pnr, date_dx)
  
  colnames(data2)[colnames(data2)=="date_dx"] <- label
  
  return(data2)
}



#################################################
##### We now prepare a dataset including any mental disorder
data_master <- psyc %>%
  group_by(pnr) %>%
  arrange(date_dx) %>%
  filter(row_number()==1) %>%
  select(pnr, birth_d, sex, Dxx = date_dx)

###################
### D00: F00-F09 

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF00", "DF0999"), 
  diag_classify(psyc, "29009", "29009"),
  diag_classify(psyc, "29010", "29010"),
  diag_classify(psyc, "29011", "29011"),
  diag_classify(psyc, "29018", "29018"),
  diag_classify(psyc, "29019", "29019"),
  diag_classify(psyc, "29209", "29299"),
  diag_classify(psyc, "29309", "29399"),
  diag_classify(psyc, "29409", "29429"),   #294.x9 part 1
  diag_classify(psyc, "29449", "29499"),   #294.x9 part 2
  diag_classify(psyc, "30909", "30949"),   #309.x9 part 1
  diag_classify(psyc, "30959", "30999")    #309.x9 part 2
)

## We select only the first appearance (minimum age: 35 for organic disorders)
x <- data_disorder %>% 
  disease_first(label = "D00", min_age = 35)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D01: F00

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF00", "DF0099"), 
  diag_classify(psyc, "29009", "29009"),
  diag_classify(psyc, "29010", "29010"),
  diag_classify(psyc, "29019", "29019")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D01", min_age = 35)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D02: F01

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF01", "DF0199"), 
  diag_classify(psyc, "29309", "29309"),
  diag_classify(psyc, "29319", "29319")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D02", min_age = 35)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D10: F10-F19

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF10", "DF1999"), 
  diag_classify(psyc, "29109", "29199"),
  diag_classify(psyc, "29439", "29439"),
  diag_classify(psyc, "30309", "30390"),   # 303.x9 part 1, 303.20, 303.28, 303.90
  diag_classify(psyc, "30399", "30399"),   # 303.x9 part 2
  diag_classify(psyc, "30409", "30499")   # 304.x9 
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D10", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)



###################
### D11: F10

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF10", "DF1099"), 
  diag_classify(psyc, "29109", "29199"),
  diag_classify(psyc, "30309", "30390"),   # 303.x9 part 1, 303.20, 303.28, 303.90
  diag_classify(psyc, "30399", "30399")   # 303.x9 part 2
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D11", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D12: F12

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF12", "DF1299"), 
  diag_classify(psyc, "30459", "30459") 
  
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D12", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)




###################
### D20: F20-F29

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF20", "DF2999"), 
  diag_classify(psyc, "29509", "29599"),
  diag_classify(psyc, "29689", "29689"),
  diag_classify(psyc, "29709", "29799"),
  diag_classify(psyc, "29829", "29899"),
  diag_classify(psyc, "29904", "29905"),
  diag_classify(psyc, "29909", "29909"),
  diag_classify(psyc, "30183", "30183")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D20", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D21: F20

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF20", "DF2099"), 
  diag_classify(psyc, "29509", "29569"),
  diag_classify(psyc, "29589", "29599")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D21", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D22: F25

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF25", "DF2599"), 
  diag_classify(psyc, "29579", "29579"),
  diag_classify(psyc, "29689", "29689")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D22", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D30: F30-39

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF30", "DF3999"), 
  diag_classify(psyc, "29609", "29679"),
  diag_classify(psyc, "29699", "29699"),
  diag_classify(psyc, "29809", "29809"),
  diag_classify(psyc, "29819", "29819"),
  diag_classify(psyc, "30049", "30049"),
  diag_classify(psyc, "30119", "30119")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D30", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)



###################
### D31: F30-31

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF30", "DF3199"), 
  diag_classify(psyc, "29619", "29619"),
  diag_classify(psyc, "29639", "29639"),
  diag_classify(psyc, "29819", "29819")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D31", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)



###################
### D32: F33

## We select all diagnosis of interest

# For recurrent depression onset was defined as the second admission that occurred at least 8 weeks after last discharge with these ICD-8 codes.
# Not enough to compare to previous admission, because one of the previous could be have a later date of discharge

data_disorder_aux <- bind_rows(
  diag_classify(psyc, "29609", "29609"),
  diag_classify(psyc, "29629", "29629"),
  diag_classify(psyc, "29809", "29809"),
  diag_classify(psyc, "30049", "30049")
) %>% 
  group_by(pnr) %>%
  arrange(date_dx) %>%
  mutate(
    max_disc = cummax(as.numeric(date_ending)),
    time = as.numeric(date_dx) - lag(max_disc)
  ) %>%
  filter(time > 8*7) %>% ungroup()

data_disorder <- bind_rows(
  diag_classify(psyc, "DF33", "DF3399"), 
  data_disorder_aux
)
rm(data_disorder_aux)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D32", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)




###################
### D33: F32-F33

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF32", "DF3399"), 
  diag_classify(psyc, "29609", "29609"),
  diag_classify(psyc, "29629", "29629"),
  diag_classify(psyc, "29809", "29809"),
  diag_classify(psyc, "30049", "30049")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D33", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)






###################
### D41: F40-48


## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF40", "DF4899"), 
  diag_classify(psyc, "30009", "30039"),
  diag_classify(psyc, "30059", "30099"),
  diag_classify(psyc, "30509", "30559"),
  diag_classify(psyc, "30569", "30599"),
  diag_classify(psyc, "30568", "30568"),
  diag_classify(psyc, "30799", "30799")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D41", min_age = 5)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D42: F42

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF42", "DF4299"), 
  diag_classify(psyc, "30039", "30039")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D42", min_age = 5)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D51: F50

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF50", "DF5099"), 
  diag_classify(psyc, "30650", "30650"),
  diag_classify(psyc, "30658", "30658"),
  diag_classify(psyc, "30659", "30659")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D51", min_age = 1)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D52: F50.0

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF500", "DF5009"), 
  diag_classify(psyc, "30650", "30650")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D52", min_age = 1)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)



###################
### D61: F60

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF60", "DF6099"), 
  diag_classify(psyc, "30109", "30109"),
  diag_classify(psyc, "30129", "30179"),
  diag_classify(psyc, "30189", "30199"),
  diag_classify(psyc, "30180", "30182"),
  diag_classify(psyc, "30184", "30184")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D61", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)

###################
### D62: F60.31

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF6031", "DF6031"), 
  diag_classify(psyc, "30184", "30184")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D62", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D63: F60.2

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF602", "DF6029"), 
  diag_classify(psyc, "30179", "30179"),
  diag_classify(psyc, "30182", "30182")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D63", min_age = 10)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)



###################
### D70: F70-F79

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF70", "DF7999"), 
  diag_classify(psyc, "31100", "31199"),
  diag_classify(psyc, "31200", "31299"),
  diag_classify(psyc, "31300", "31399"),
  diag_classify(psyc, "31400", "31499"),
  diag_classify(psyc, "31500", "31599")
)


## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D70", min_age = 1)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D81: F84

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF84", "DF8499"), 
  diag_classify(psyc, "29900", "29903")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D81", min_age = 1)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D82: F84.0

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF840", "DF8409"), 
  diag_classify(psyc, "29900", "29900")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D82", min_age = 1)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


###################
### D91: F90-F98

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF90", "DF9899"), 
  diag_classify(psyc, "30609", "30609"),
  diag_classify(psyc, "30619", "30649"),
  diag_classify(psyc, "30669", "30699"),
  diag_classify(psyc, "30800", "30809")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D91", min_age = 1)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)



###################
### D92: F90

## We select all diagnosis of interest
data_disorder <- bind_rows(
  diag_classify(psyc, "DF90", "DF9099"), 
  diag_classify(psyc, "30801", "30801")
)

## We select only the first appearance
x <- data_disorder %>%
  disease_first(label = "D92", min_age = 1)
data_master <- data_master %>% left_join(x, by = "pnr")
rm(x)


#################################################
##### Now the dataset is saved in wide format
psyc <- data_master %>% arrange(pnr) %>% ungroup()

nrow(psyc)
length(unique(psyc$pnr))

save(psyc, file=paste0(folder_output, "psyc_atlas2021.RData"))
haven::write_dta(psyc, path=paste0(folder_output, "Stata/psyc_atlas2021.dta"), label = NULL)