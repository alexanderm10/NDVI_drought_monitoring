#boxplots, raincloud plots, anovas, etc for DERIVATIVES.

library(ggplot2)
library(tidyr)
library(dplyr)
library(tidyverse)
library(lubridate)
library(cowplot)
library(ggdist)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring")

######################

usdmcat <- read.csv("~/Downloads/dm_export_20000101_20241017.csv") #usdm chicago region categorical data
usdmcum <- read.csv("~/Downloads/dm_export_20000101_20241024.csv") #usdm chicago region cumulative data
grow_norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/growing_season_norms.csv")) #normals
growyrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/growing_season_yrs.csv")) #individual years

yrsderivs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/individual_years_derivs_GAM.csv")) #individual years derivatives
normsderivs <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/norms_derivatives.csv")) #normals derivatives

######################
#loop to find matching growing season dates for norms dataframes
######################

for (LC in unique(normsderivs$type)){
  df <- normsderivs[normsderivs$type==LC,]
  grownormsLC <- grow_norms[grow_norms$type==LC,]
  df <- df[df$yday %in% grownormsLC$yday,]
  LC <- gsub("-","",LC)
  assign(paste0("grownormsderivs",LC),df)
}

grownormsderivs <- rbind(grownormsderivscrop, grownormsderivsforest, grownormsderivsgrassland, grownormsderivsurbanlow, grownormsderivsurbanmedium, grownormsderivsurbanopen, grownormsderivsurbanhigh)
write.csv(grownormsderivs, file.path(pathShare, "growing_season_norms_derivatives.csv"), row.names=F)

######################
#do the same thing but for the individual years derivatives
######################

for (LC in unique(yrsderivs$type)){
  df <- yrsderivs[yrsderivs$type==LC,]
  grownormsLC <- grow_norms[grow_norms$type==LC,]
  df <- df[df$yday %in% grownormsLC$yday,]
  LC <- gsub("-","",LC)
  assign(paste0("growyrsderivs",LC),df)
}

growyrsderivs <- rbind(growyrsderivscrop, growyrsderivsforest, growyrsderivsgrassland, growyrsderivsurbanlow, growyrsderivsurbanmedium, growyrsderivsurbanopen, growyrsderivsurbanhigh)
write.csv(growyrsderivs, file.path(pathShare, "growing_season_yrs_derivatives.csv"), row.names=F)

######################
