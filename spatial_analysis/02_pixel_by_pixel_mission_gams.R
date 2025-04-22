library(mgcv) #load packages
library(ggplot2)
library(tibble)
library(dplyr)
library(MASS)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring/pixel_by_pixel_gam_models/mission_gams")
pathShare2 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring")

###################
#load data & aggregate
###################

landsatAll <- read.csv(file.path(google.drive, "data/spatial_NDVI_monitoring/spatial_raw_data_all_satellites.csv"))
landsatAll <- aggregate(NDVI ~ x + y  + xy + mission + date + year + yday, data=landsatAll, FUN=median, na.rm=T)

###

landsatAll <- landsatAll %>% group_by(x,y, mission) %>% #get mean NDVI by coord & mission
  mutate(mean_NDVI = mean(NDVI, na.rm=TRUE))

landsatAll <- landsatAll[landsatAll$mean_NDVI > 0.1,] #filter
landsatAll$mission <- as.factor(landsatAll$mission)

###################
#gam coord loop by mission
###################
#df <- data.frame()

for (x in unique(landsatAll$x)){
  datx <- landsatAll[landsatAll$x==x,]
  
  for (y in unique(datx$y)){
    datxy <- datx[datx$y==y,]
    if(length(which(!is.na(datxy$NDVI)))<40 | length(unique(datxy$yday[!is.na(datxy$NDVI)]))<24) next
    
    indXY <- which(landsatAll$x==x & landsatAll$y==y)
    
    gam_loop <- gam(NDVI ~ s(yday, k=12,by=mission)+ mission-1,data=datxy)
    datxy_dupe <- datxy
    datxy_dupe$mission <- "landsat 8"
    datxy$MissionPred <- predict(gam_loop, newdata=datxy)
    datxy$MissionResid <- datxy$NDVI - datxy$MissionPred
    datxy$ReprojPred <- predict(gam_loop, newdata = datxy_dupe)
    datxy$NDVIReprojected <- datxy$MissionResid + datxy$ReprojPred
    #df <- rbind(df, datxy)
    landsatAll[indXY, "MissionPred"] <- datxy$MissionPred
    landsatAll[indXY, "MissionResid"] <- datxy$MissionResid
    landsatAll[indXY, "ReprojPred"] <- datxy$ReprojPred
    landsatAll[indXY, "NDVIReprojected"] <- datxy$NDVIReprojected
    
    # l8$pred[indXY] <- datxy$pred
    
    saveRDS(gam_loop, file.path(pathShare, paste0(x,"_", y,"_coord_gam.RDS")))

  }
}

###################
#Save
###################

write.csv(landsatAll, file.path(pathShare2, "reprojected_NDVI_all_satellites_pixel_by_pixel.csv"),row.names = FALSE)

###################

# l5 <- landsatAll[landsatAll$mission=="landsat 5",]
# 
# l5_mean_NDVI <- l5 %>% group_by(x,y) %>%
#   summarise_at(vars("NDVI"), mean, na.rm=TRUE) %>% as.data.frame()
# 
# l5_mean_NDVI <- l5_mean_NDVI[l5_mean_NDVI$NDVI>0.1,]
# l5_mean_NDVI$xy <- paste(l5_mean_NDVI$x, l5_mean_NDVI$y)
# l5 <- filter(l5, xy %in% l5_mean_NDVI$xy)
# 
# ###
# 
# l7 <- landsatAll[landsatAll$mission=="landsat 7",]
# 
# l7_mean_NDVI <- l7 %>% group_by(x,y) %>%
#   summarise_at(vars("NDVI"), mean, na.rm=TRUE) %>% as.data.frame()
# 
# l7_mean_NDVI <- l7_mean_NDVI[l7_mean_NDVI$NDVI>0.1,]
# l7_mean_NDVI$xy <- paste(l7_mean_NDVI$x, l7_mean_NDVI$y)
# l7 <- filter(l7, xy %in% l7_mean_NDVI$xy)
# 
# ###
# 
# l8 <- landsatAll[landsatAll$mission=="landsat 8",]
# 
# l8_mean_NDVI <- l8 %>% group_by(x,y) %>%
#   summarise_at(vars("NDVI"), mean, na.rm=TRUE) %>% as.data.frame()
# 
# l8_mean_NDVI <- l8_mean_NDVI[l8_mean_NDVI$NDVI>0.1,]
# l8_mean_NDVI$xy <- paste(l8_mean_NDVI$x, l8_mean_NDVI$y)
# l8 <- filter(l8, xy %in% l8_mean_NDVI$xy)
# 
# ###
# 
# l9 <- landsatAll[landsatAll$mission=="landsat 9",]
# 
# l9_mean_NDVI <- l9 %>% group_by(x,y) %>%
#   summarise_at(vars("NDVI"), mean, na.rm=TRUE) %>% as.data.frame()
# 
# l9_mean_NDVI <- l9_mean_NDVI[l9_mean_NDVI$NDVI>0.1,]
# l9_mean_NDVI$xy <- paste(l9_mean_NDVI$x, l9_mean_NDVI$y)
# l9 <- filter(l9, xy %in% l9_mean_NDVI$xy)
# 
# landsatAll <- rbind (l5,l7,l8,l9)
# landsatAll$mission <- as.factor(landsatAll$mission)
