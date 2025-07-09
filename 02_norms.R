# Post GAMs creating a data frame for the norms of each LC type

library(mgcv) #load packages
library(ggplot2)
library(tibble)
library(dplyr)
library(MASS)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/")

source("~/Documents/GitHub/NDVI_drought_monitoring/0_Calculate_GAMM_Posteriors_Updated_Copy.R")

######################
#loading in and formatting raw data from 01_raw_data.R
######################

#raw.data <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/raw_data_k=12.csv"))

raw.data <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/raw_data_k=12_with_wet-forest.csv"))

newDF <- data.frame(yday=seq(1:365)) #create new data frame with column to represent day of year sequence

######################
#loop through each LC
######################
df <- data.frame()

for (LC in unique(raw.data$type)){
  datLC <- raw.data[raw.data$type==LC,]
  
  gam_norm <- gam(NDVIReprojected ~ s(yday, k=12, bs="cc"), data=datLC) #cyclic cubic spline for norm
  norm_post <- post.distns(model.gam=gam_norm, newdata=newDF, vars="yday")
  norm_post$type <- LC
  df <- rbind(df,norm_post)
}

write.csv(df, file.path(pathShare, "k=12_norms_all_LC_types_with_wet-forest.csv"), row.names=F)

######################