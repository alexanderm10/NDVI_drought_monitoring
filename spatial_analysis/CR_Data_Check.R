library(raster)
library(ggplot2)
library(tidyverse)
library(mgcv)
library(lubridate)
library(stringr)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring/")

# Reading in Juliana's existing dataf
test <- read.csv(file.path(pathShare, "spatial_raw_data_all_satellites.csv"))

# Aggregating so we only have 1 value per pixel per day... because of the tiling Landsat does, it could "double dip"
test2 <- aggregate(NDVI ~ x + y  + xy + mission + date + year + yday, data=test, FUN=median, na.rm=T)
summary(test2)
dim(test)
dim(test2)

length(test$NDVI[!is.na(test$NDVI)])


test3 <- aggregate(NDVI ~ x+ y + xy + mission, data=test2, FUN=length)
summary(test3)

ggplot(data=test3) +
  facet_wrap(~mission) +
  geom_tile(aes(x=x, y=y, fill=NDVI))+ 
  coord_equal() +
  theme_classic()


ggplot(data=test3[test3$mission=="landsat 8",]) +
  facet_wrap(~mission) +
  geom_tile(aes(x=x, y=y, fill=NDVI))+ 
  coord_equal() +
  theme_classic()


aggTot <- aggregate(NDVI ~ x+ y + xy, data=test2, FUN=length)

ggplot(data=aggTot) +
  # facet_wrap(~mission) +
  geom_tile(aes(x=x, y=y, fill=NDVI))+ 
  coord_equal() +
  theme_classic()
