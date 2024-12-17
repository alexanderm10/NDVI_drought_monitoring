# formatting raw NDVI data separately by LC type and saving into dataframe before fitting monitoring GAMs

library(mgcv) #load packages
library(ggplot2)
library(tibble)
library(dplyr)
library(MASS)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/")

######################
#loading in and formatting latest NDVI data
######################

ndvi.latest <- read.csv(file.path(google.drive, "data/UrbanEcoDrought_NDVI_LocalExtract/NDVIall_latest.csv"))
ndvi.latest$date <- as.Date(ndvi.latest$date)
ndvi.latest$type <- as.factor(ndvi.latest$type)
ndvi.latest$mission <- as.factor(ndvi.latest$mission)
summary(ndvi.latest)

######################
#crop
######################

ndvicrop=ndvi.latest[ndvi.latest$type=="crop",]

gamcrop <- gam(NDVI ~ s(yday, k=12, by=mission) + mission-1, data=ndvicrop) #k=1.5 months in a year
summary(gamcrop)
AIC(gamcrop)

ndvicrop$NDVIMissionPred <- predict(gamcrop, newdata=ndvicrop)
ndvicrop$MissionResid <- ndvicrop$NDVI - ndvicrop$NDVIMissionPred

# Going to "reproject" the predicted mean/normal
ndvicropDupe <- ndvicrop
ndvicropDupe$mission <- "landsat 8"

ndvicrop$ReprojPred <- predict(gamcrop, newdata=ndvicropDupe)
ndvicrop$NDVIReprojected <- ndvicrop$MissionResid + ndvicrop$ReprojPred

summary(ndvicrop)

######################
#forest
######################

ndviforest=ndvi.latest[ndvi.latest$type=="forest",]

gamforest <- gam(NDVI ~ s(yday, k=12, by=mission) + mission-1, data=ndviforest) #k=1.5 months in a year
summary(gamforest)
AIC(gamforest)

ndviforest$NDVIMissionPred <- predict(gamforest, newdata=ndviforest)
ndviforest$MissionResid <- ndviforest$NDVI - ndviforest$NDVIMissionPred

# Going to "reproject" the predicted mean/normal
ndviforestDupe <- ndviforest
ndviforestDupe$mission <- "landsat 8"

ndviforest$ReprojPred <- predict(gamforest, newdata=ndviforestDupe)
ndviforest$NDVIReprojected <- ndviforest$MissionResid + ndviforest$ReprojPred
summary(ndviforest)

######################
#grassland
######################

ndvigrass <- ndvi.latest[ndvi.latest$type=="grassland",]

gamgrass <- gam(NDVI ~ s(yday, k=12, by=mission) + mission-1, data=ndvigrass)
summary(gamgrass)
AIC(gamgrass)

ndvigrass$NDVIMissionPred <- predict(gamgrass, newdata=ndvigrass)
ndvigrass$MissionResid <- ndvigrass$NDVI - ndvigrass$NDVIMissionPred

# Going to "reproject" the predicted mean/normal
ndvigrassDupe <- ndvigrass
ndvigrassDupe$mission <- "landsat 8"

ndvigrass$ReprojPred <- predict(gamgrass, newdata=ndvigrassDupe)
ndvigrass$NDVIReprojected <- ndvigrass$MissionResid + ndvigrass$ReprojPred
summary(ndvigrass)

######################
#urban-high
######################

ndviUrbHigh <- ndvi.latest[ndvi.latest$type=="urban-high",]

gamUrbHigh <- gam(NDVI ~ s(yday, k=12, by=mission) + mission-1, data=ndviUrbHigh)
summary(gamUrbHigh)
AIC(gamUrbHigh)

ndviUrbHigh$NDVIMissionPred <- predict(gamUrbHigh, newdata=ndviUrbHigh)
ndviUrbHigh$MissionResid <- ndviUrbHigh$NDVI - ndviUrbHigh$NDVIMissionPred

# Going to "reproject" the predicted mean/normal
ndviUrbHighDupe <- ndviUrbHigh
ndviUrbHighDupe$mission <- "landsat 8"

ndviUrbHigh$ReprojPred <- predict(gamUrbHigh, newdata=ndviUrbHighDupe)
ndviUrbHigh$NDVIReprojected <- ndviUrbHigh$MissionResid + ndviUrbHigh$ReprojPred
summary(ndviUrbHigh)

######################
#urban-medium
######################

ndviUrbMed <- ndvi.latest[ndvi.latest$type=="urban-medium",]

gamUrbMed <- gam(NDVI ~ s(yday, k=12, by=mission) + mission-1, data=ndviUrbMed)
summary(gamUrbMed)
AIC(gamUrbMed)

ndviUrbMed$NDVIMissionPred <- predict(gamUrbMed, newdata=ndviUrbMed)
ndviUrbMed$MissionResid <- ndviUrbMed$NDVI - ndviUrbMed$NDVIMissionPred

# Going to "reproject" the predicted mean/normal
ndviUrbMedDupe <- ndviUrbMed
ndviUrbMedDupe$mission <- "landsat 8"

ndviUrbMed$ReprojPred <- predict(gamUrbMed, newdata=ndviUrbMedDupe)
ndviUrbMed$NDVIReprojected <- ndviUrbMed$MissionResid + ndviUrbMed$ReprojPred
summary(ndviUrbMed)

######################
#urban-low
######################

ndviUrbLow <- ndvi.latest[ndvi.latest$type=="urban-low",]

gamUrbLow <- gam(NDVI ~ s(yday, k=12, by=mission) + mission-1, data=ndviUrbLow)
summary(gamUrbLow)
AIC(gamUrbLow)

ndviUrbLow$NDVIMissionPred <- predict(gamUrbLow, newdata=ndviUrbLow)
ndviUrbLow$MissionResid <- ndviUrbLow$NDVI - ndviUrbLow$NDVIMissionPred

# Going to "reproject" the predicted mean/normal
ndviUrbLowDupe <- ndviUrbLow
ndviUrbLowDupe$mission <- "landsat 8"

ndviUrbLow$ReprojPred <- predict(gamUrbLow, newdata=ndviUrbLowDupe)
ndviUrbLow$NDVIReprojected <- ndviUrbLow$MissionResid + ndviUrbLow$ReprojPred
summary(ndviUrbLow)

######################
#urban-open
######################

ndviUrbOpen <- ndvi.latest[ndvi.latest$type=="urban-open",]

gamUrbOpen <- gam(NDVI ~ s(yday, k=12, by=mission) + mission-1, data=ndviUrbOpen)
summary(gamUrbOpen)
AIC(gamUrbOpen)

ndviUrbOpen$NDVIMissionPred <- predict(gamUrbOpen, newdata=ndviUrbOpen)
ndviUrbOpen$MissionResid <- ndviUrbOpen$NDVI - ndviUrbOpen$NDVIMissionPred

# Going to "reproject" the predicted mean/normal
ndviUrbOpenDupe <- ndviUrbOpen
ndviUrbOpenDupe$mission <- "landsat 8"

ndviUrbOpen$ReprojPred <- predict(gamUrbOpen, newdata=ndviUrbOpenDupe)
ndviUrbOpen$NDVIReprojected <- ndviUrbOpen$MissionResid + ndviUrbOpen$ReprojPred
summary(ndviUrbOpen)

######################
#combine into one large dataframe & save
######################

raw_data <- rbind(ndvicrop, ndviforest, ndvigrass, ndviUrbHigh, ndviUrbMed, ndviUrbLow, ndviUrbOpen)
write.csv(raw_data, file.path(pathShare, "raw_data_k=12.csv"), row.names=F)

######################