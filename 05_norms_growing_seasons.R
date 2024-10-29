# code for finding growing season of each LC type based on normal

library(spatialEco)
library(ggplot2)
library(tidyr)
library(dplyr)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/")

######################
#usdmcat <- read.csv("~/Downloads/dm_export_20000101_20241017.csv") #usdm chicago region categorical data
#usdmcum <- read.csv("~/Downloads/dm_export_20000101_20241024.csv") #usdm chicago region cumulative data
#yrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/individual_years_post_GAM.csv")) #individual years
norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/norms_all_LC_types.csv")) #normals

######################
#loops to find growing season
######################

#find 15% of the way between max and min --> start of growing season
#find 95% of upper max --> end of growing season

for (LC in unique(norms$type)){
  if (LC=="urban-high"){                 #doing urban-high out of loop b/c too wiggly
    next
  }
  df <- norms[norms$type==LC,] #subset normal data
  
  LCmax <- max(df$mean) #max mean NDVI
  LCmin <- min(df$mean) #min mean NDVI
  
  maxday <- df[df$mean==LCmax,"yday"] #find yday associated with max/min
  minday <- df[df$mean==LCmin,"yday"]
  
  lower_thresh <- (LCmax-LCmin)*.15 + LCmin #calculate the threshold for growing season
  upper_thresh <- .95*LCmax
  
  subset_end <- df[df$yday > maxday,] #making two chunks of the dataframe to find threshold
  subset_start <- df[df$yday > minday & df$yday<maxday,]
  
  season_end <- subset_end[which.min(abs(subset_end$mean-upper_thresh)),"yday"] #finding closest data point to threshold
  season_start <- subset_start[which.min(abs(subset_start$mean-lower_thresh)),"yday"]
  
  growing_season <- df[df$yday >= season_start & df$yday <= season_end,] #define range of growing season
  assign(paste0("grow",LC),growing_season)
}

######################
#doing urban-high separately since it's a bit funky
######################

urbhigh <- norms[norms$type=="urban-high",]

maxmin <- local.min.max(urbhigh$mean) #this function finds local max & min
localmax <- maxmin$maxima[3] #this is the local maximum we are basing the threshold off of

maxday <- urbhigh[urbhigh$mean==localmax,"yday"]
localminday <- urbhigh[urbhigh$mean==maxmin$minima[3],"yday"]

urbhigh_min <- min(urbhigh$mean)
minday <- urbhigh[urbhigh$mean==urbhigh_min, "yday"]

lower_thresh <- (localmax-urbhigh_min)*.15 + urbhigh_min
upper_thresh <- .95*localmax

urbstart <- urbhigh[urbhigh$yday>=minday & urbhigh$yday<=maxday,]
season_start <- urbstart[which.min(abs(urbstart$mean-lower_thresh)),"yday"]
urbend <- urbhigh[urbhigh$yday>=maxday & urbhigh$yday<=localminday,]
season_end <- urbend[which.min(abs(urbend$mean-upper_thresh)),"yday"]
urban_high_grow <- urbhigh[urbhigh$yday >= season_start & urbhigh$yday <= season_end,]

######################
#saving as separate df just to be safe
######################

grow_norms <- rbind(growcrop, growforest, growgrassland, `growurban-low`, `growurban-medium`, `growurban-open`, urban_high_grow)
write.csv(grow_norms, file.path(pathShare, "growing_season_norms.csv"), row.names =F)

######################