# code for finding growing season of each LC type based on normal

library(spatialEco)
library(ggplot2)
library(tidyr)
library(dplyr)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/")
pathShare2 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/tables")

######################
#usdmcat <- read.csv("~/Downloads/dm_export_20000101_20241017.csv") #usdm chicago region categorical data
#usdmcum <- read.csv("~/Downloads/dm_export_20000101_20241024.csv") #usdm chicago region cumulative data

#yrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_individual_years_post_GAM.csv")) #individual years
#norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_norms_all_LC_types.csv")) #normals

yrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_individual_years_post_GAM_with_forest-wet.csv")) #individual years
norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_norms_all_LC_types_with_wet-forest.csv")) #normals
######################
#loops to find growing season
######################

#find 15% of the way between max and min --> start of growing season
#find 95% of upper max --> end of growing season

for (LC in unique(norms$type)){
  #if (LC=="urban-high"){                 #doing urban-high out of loop b/c too wiggly
    #next
  #}
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

#urbhigh <- norms[norms$type=="urban-high",]

#maxmin <- local.min.max(urbhigh$mean) #this function finds local max & min
#localmax <- maxmin$maxima[3] #this is the local maximum we are basing the threshold off of

#maxday <- urbhigh[urbhigh$mean==localmax,"yday"]
#localminday <- urbhigh[urbhigh$mean==maxmin$minima[3],"yday"]

#urbhigh_min <- min(urbhigh$mean)
#minday <- urbhigh[urbhigh$mean==urbhigh_min, "yday"]

#lower_thresh <- (localmax-urbhigh_min)*.15 + urbhigh_min
#upper_thresh <- .95*localmax

#urbstart <- urbhigh[urbhigh$yday>=minday & urbhigh$yday<=maxday,]
#season_start <- urbstart[which.min(abs(urbstart$mean-lower_thresh)),"yday"]
#urbend <- urbhigh[urbhigh$yday>=maxday & urbhigh$yday<=localminday,]
#season_end <- urbend[which.min(abs(urbend$mean-upper_thresh)),"yday"]
#urban_high_grow <- urbhigh[urbhigh$yday >= season_start & urbhigh$yday <= season_end,]

######################
#saving as separate df
######################

#grow_norms <- rbind(growcrop, growforest, growgrassland, `growurban-low`, `growurban-medium`, `growurban-open`, `growurban-high`)
#write.csv(grow_norms, file.path(pathShare, "k=12_growing_season_norms.csv"), row.names =F)

grow_norms <- rbind(growcrop, growforest, `growforest-wet`, growgrassland, `growurban-low`, `growurban-medium`, `growurban-open`, `growurban-high`)
write.csv(grow_norms, file.path(pathShare, "k=12_growing_season_norms_with_forest-wet.csv"), row.names =F)
######################
#loop to make a dataset of growing season for the years dataset
######################

for (LC in unique(yrs$type)){
  df <- yrs[yrs$type==LC,]
  growLC <- grow_norms[grow_norms$type==LC,]
  df <- df[df$yday %in% growLC$yday,]
  LC <- gsub("-","",LC)
  assign(paste0("growyrs",LC),df)
}

#growyrs <- rbind(growyrscrop, growyrsforest, growyrsgrassland, growyrsurbanlow, growyrsurbanmedium, growyrsurbanopen, growyrsurbanhigh)
#write.csv(growyrs, file.path(pathShare, "k=12_growing_season_yrs.csv"), row.names=F)

growyrs <- rbind(growyrscrop, growyrsforest, growyrsforestwet, growyrsgrassland, growyrsurbanlow, growyrsurbanmedium, growyrsurbanopen, growyrsurbanhigh)
write.csv(growyrs, file.path(pathShare, "k=12_growing_season_yrs_with_forest-wet.csv"), row.names=F)
######################
#reformat table for growing season dates
######################
grow_norms <- grow_norms[grow_norms$type!="forest",]
grow_norms$type[grow_norms$type=="forest-wet"] <- "forest"
grow_norms$date <- as.Date(grow_norms$yday, origin="2022-12-31")
grow_norms$type <- factor(grow_norms$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

grow_dates <- grow_norms[c("type","date")]
grow_dates <- grow_dates %>% group_by(type) %>%
  summarise(
    start = min(date),
    end = max(date)
  )

grow_dates$start <- strftime(grow_dates$start, format="%b %d" )
grow_dates$end <- strftime(grow_dates$end, format="%b %d" )

write.csv(grow_dates, file.path(pathShare2, "growing_season_dates_table.csv"), row.names=F)

######################