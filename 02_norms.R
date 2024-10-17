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

raw.data <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/raw_data.csv"))
newDF <- data.frame(yday=seq(1:365)) #create new data frame with column to represent day of year sequence

######################
#crop
######################

gamcrop_norm <- gam(NDVIReprojected ~ s(yday, k=18), data=raw.data[raw.data$type=="crop",])
NDVIcrop_norm <- predict(gamcrop_norm, newdata=newDF) #normal crop values for a year
crop_norm <- post.distns(model.gam=gamcrop_norm, newdata=newDF, vars="yday")
crop_norm$type <- "crop"
#crop_norm$NDVIpred <- NDVIcrop_norm

######################
#forest
######################

gamforest_norm <- gam(NDVIReprojected ~ s(yday, k=18), data=raw.data[raw.data$type=="forest",])
NDVIforest_norm <- predict(gamforest_norm, newdata=newDF)
forest_norm <- post.distns(model.gam = gamforest_norm, newdata = newDF, vars="yday")
forest_norm$type <- "forest"
#forest_norm$NDVIpred <- NDVIforest_norm

######################
#grassland
######################

gamgrass_norm <- gam(NDVIReprojected ~ s(yday, k=18), data=raw.data[raw.data$type=="grassland",])
NDVIgrass_norm <- predict(gamgrass_norm, newdata=newDF)
grass_norm <- post.distns(model.gam = gamgrass_norm, newdata = newDF, vars="yday")
grass_norm$type <- "grassland"
#grass_norm$NDVIpred <- NDVIgrass_norm

######################
#urban-high
######################

gamUrbHigh_norm <- gam(NDVIReprojected ~ s(yday, k=18), data=raw.data[raw.data$type=="urban-high",])
NDVIUrbHigh_norm <- predict(gamUrbHigh_norm, newdata=newDF)
UrbHigh_norm <- post.distns(model.gam = gamUrbHigh_norm, newdata = newDF, vars="yday")
UrbHigh_norm$type <- "urban-high"
#UrbHigh_norm$NDVIpred <- NDVIUrbHigh_norm

######################
#urban-medium
######################

gamUrbMed_norm <- gam(NDVIReprojected ~ s(yday, k=18), data=raw.data[raw.data$type=="urban-medium",])
NDVIUrbMed_norm <- predict(gamUrbMed_norm, newdata=newDF)
UrbMed_norm <- post.distns(model.gam = gamUrbMed_norm, newdata = newDF, vars="yday")
UrbMed_norm$type <- "urban-medium"
#UrbMed_norm$NDVIpred <- NDVIUrbMed_norm

######################
#urban-low
######################

gamUrbLow_norm <- gam(NDVIReprojected ~ s(yday, k=18), data=raw.data[raw.data$type=="urban-low",])
NDVIUrbLow_norm <- predict(gamUrbLow_norm, newdata=newDF)
UrbLow_norm <- post.distns(model.gam = gamUrbLow_norm, newdata = newDF, vars="yday")
UrbLow_norm$type <- "urban-low"
#UrbLow_norm$NDVIpred <- NDVIUrbLow_norm

######################
#urban-open
######################

gamUrbOpen_norm <- gam(NDVIReprojected ~ s(yday, k=18), data=raw.data[raw.data$type=="urban-open",])
NDVIUrbOpen_norm <- predict(gamUrbOpen_norm, newdata=newDF)
UrbOpen_norm <- post.distns(model.gam = gamUrbOpen_norm, newdata = newDF, vars="yday")
UrbOpen_norm$type <- "urban-open"
#UrbOpen_norm$NDVIpred <- NDVIUrbOpen_norm

######################
#combine into one large dataframe & save
######################

norms <- rbind(crop_norm, forest_norm, grass_norm, UrbHigh_norm, UrbMed_norm, UrbLow_norm, UrbOpen_norm)
write.csv(norms, file.path(pathShare, "norms_all_LC_types.csv"), row.names=F)

######################