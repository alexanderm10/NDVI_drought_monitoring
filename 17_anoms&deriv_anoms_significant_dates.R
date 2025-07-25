library(ggplot2)
library(cowplot)
library(dplyr)
library(tidyverse)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/figures")
pathShare2 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/tables")

# load data ---------------------------------------------------------------

yrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_individual_years_post_GAM_with_forest-wet.csv")) #individual years
yrs <- yrs[yrs$type!="forest",]
yrs$type[yrs$type=="forest-wet"] <- "forest"
yrs$type <- factor(yrs$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_norms_all_LC_types_with_wet-forest.csv")) #normals
norms <- norms[norms$type!="forest",]
norms$type[norms$type=="forest-wet"] <- "forest"
norms$type <- factor(norms$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

yrsderivs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_individual_years_derivs_GAM_with_forest-wet.csv")) #individual years derivatives
yrsderivs <- yrsderivs[yrsderivs$type!="forest",]
yrsderivs$type[yrsderivs$type=="forest-wet"] <- "forest"
yrsderivs$type <- factor(yrsderivs$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

normsderivs <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_norms_derivatives_with_forest-wet.csv")) #normals derivatives
normsderivs <- normsderivs[normsderivs$type!="forest",]
normsderivs$type[normsderivs$type=="forest-wet"] <- "forest"
normsderivs$type <- factor(normsderivs$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

yrs_merge <- yrs %>% inner_join(norms, by= c("type", "yday"), suffix = c("_yrs", "_norm")) 
yrs_merge$mean_anoms <- yrs_merge$mean_yrs - yrs_merge$mean_norm
yrs_merge$upr_anoms <- yrs_merge$upr_yrs - yrs_merge$mean_norm
yrs_merge$lwr_anoms <- yrs_merge$lwr_yrs - yrs_merge$mean_norm
#yrs_merge <- yrs_merge %>% pivot_longer(cols=c("mean_yrs","mean_anoms"), names_to =("graph type"), values_to = "mean")

yrsderivs_merge <- yrsderivs %>% inner_join(normsderivs, by= c("type", "yday"), suffix = c("_yrs", "_norm")) 
yrsderivs_merge$mean_anoms <- yrsderivs_merge$mean_yrs - yrsderivs_merge$mean_norm
yrsderivs_merge$upr_anoms <- yrsderivs_merge$upr_yrs - yrsderivs_merge$mean_norm
yrsderivs_merge$lwr_anoms <- yrsderivs_merge$lwr_yrs - yrsderivs_merge$mean_norm
yrsderivs_merge <- yrsderivs_merge[, !names(yrsderivs_merge) %in% c("sig_yrs", "var_yrs", "sig_norm", "var_norm", "mean_yrs", "upr_yrs","lwr_yrs")]

growing_szn <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_growing_season_norms_with_forest-wet.csv"))

# cut to case study years and add date ------------------------------------

yrs_merge <- yrs_merge[yrs_merge$year %in% c(2005,2012,2023),]
yrs_merge$date <- as.Date(yrs_merge$yday, origin = paste0(yrs_merge$year - 1, "-12-31"))
yrs_merge <- yrs_merge %>% arrange(type,year,date)

yrsderivs_merge <- yrsderivs_merge[yrsderivs_merge$year %in% c(2005,2012,2023),]
yrsderivs_merge$date <- as.Date(yrsderivs_merge$yday, origin = paste0(yrsderivs_merge$year - 1, "-12-31"))
yrsderivs_merge <- yrsderivs_merge %>% arrange(type,year,date)

# find significant event dates --------------------------------------------
USDM_dates <- data.frame(USDM_start = as.Date(c("2005-04-26","2012-06-12","2023-05-23")),
                         USDM_end = as.Date(c("2005-12-31", "2012-12-31", "2023-09-26")),
                         year = c(2005,2012,2023))
                              

anoms_dates <- data.frame(type = character(),
                          year = numeric(),
                          start_date = as.Date(character()),
                          recovery_date = character())

for (LC in unique(yrs_merge$type)){
  for (yr in unique(yrs_merge$year)){
    growLC <- growing_szn[growing_szn$type==LC,]
    df_sub <- yrs_merge[yrs_merge$type==LC & yrs_merge$year==yr & yrs_merge$yday %in% growLC$yday,]
    
    df_sub <- df_sub %>% mutate(upper_negative = upr_anoms <0,
                                start_flag = upper_negative & !lag(upper_negative, default=FALSE))
    event_dates <- df_sub$date[df_sub$start_flag]
    last_recovery <- as.Date("2000-01-01")
    for (event in event_dates){
      if (event <= last_recovery | is.na(last_recovery)) next
      rebound <- df_sub[df_sub$date > event & df_sub$upr_anoms >0,]
      if (nrow(rebound) >0) {
        recovery_date <- rebound$date[1]
        last_recovery <- recovery_date
      } else {
        recovery_date <- NA
        last_recovery <- NA
      }
      anoms_dates <- rbind(anoms_dates,
                           data.frame(type = LC, 
                                      start_date = as.Date(event), 
                                      recovery_date = recovery_date))
    }
  }
}

anoms_dates <- anoms_dates %>% mutate(year = year(start_date))
anoms_dates <- anoms_dates %>% left_join(USDM_dates, by="year")
anoms_dates$onset_difference <- anoms_dates$start_date - anoms_dates$USDM_start 

write.csv(anoms_dates, file.path(pathShare2, "significant_negative_anoms_dates.csv"), row.names=F)

deriv_anoms_dates <- data.frame(type = character(),
                          year = numeric(),
                          start_date = as.Date(character()),
                          recovery_date = character())

for (LC in unique(yrsderivs_merge$type)){
  for (yr in unique(yrsderivs_merge$year)){
    growLC <- growing_szn[growing_szn$type==LC,]
    df_sub <- yrsderivs_merge[yrsderivs_merge$type==LC & yrsderivs_merge$year==yr & yrsderivs_merge$yday %in% growLC$yday,]
    
    df_sub <- df_sub %>% mutate(upper_negative = upr_anoms <0,
                                start_flag = upper_negative & !lag(upper_negative, default=FALSE))
    event_dates <- df_sub$date[df_sub$start_flag]
    last_recovery <- as.Date("2000-01-01")
    for (event in event_dates){
      if (event <= last_recovery | is.na(last_recovery)) next
      rebound <- df_sub[df_sub$date > event & df_sub$upr_anoms >0,]
      if (nrow(rebound) >0) {
        recovery_date <- rebound$date[1]
        last_recovery <- recovery_date
      } else {
        recovery_date <- NA
        last_recovery <- NA
      }
      deriv_anoms_dates <- rbind(deriv_anoms_dates,
                           data.frame(type = LC, 
                                      start_date = as.Date(event), 
                                      recovery_date = recovery_date))
    }
  }
}

deriv_anoms_dates <- deriv_anoms_dates %>% mutate(year = year(start_date))
deriv_anoms_dates <- deriv_anoms_dates %>% left_join(USDM_dates, by="year")
deriv_anoms_dates$onset_difference <- deriv_anoms_dates$start_date - deriv_anoms_dates$USDM_start

write.csv(deriv_anoms_dates, file.path(pathShare2, "significant_negative_deriv_anoms_dates.csv"), row.names=F)
