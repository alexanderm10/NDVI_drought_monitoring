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

###################
#load & format L8 data
###################
l8 <- brick("~/Google Drive/Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring/landsat8_reproject_no_mosaic.tif")
l8 <- as.data.frame(l8, xy=TRUE) #include xy coordinates

l8$values <- rowSums(!is.na(l8[3:ncol(l8)])) #total non-missing values and get rid of coordinates with nothing
l8 <- l8[!(l8$values==0),]

l8 <- l8 %>% pivot_longer(cols=c(3:(ncol(l8)-1)), names_to = "date", values_to = "NDVI") #make dataframe into long format

l8$date <- str_sub(l8$date, -8,-1) #format is weird but last 8 characters of band name represent date!!
l8$date <- as.Date(l8$date, "%Y%m%d")
l8$yday <- lubridate::yday(l8$date)
l8$year <- lubridate::year(l8$date)

l8$xy <- paste(l8$x, l8$y) #column for coord pairs

###################
#load & format L9 data
###################

l9 <- brick("~/Google Drive/Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring/landsat9_reproject_no_mosaic.tif")
l9 <- as.data.frame(l9, xy=TRUE) #include xy coordinates

l9$values <- rowSums(!is.na(l9[3:ncol(l9)])) #total non-missing values and get rid of coordinates with nothing
l9 <- l9[!(l9$values==0),]

l9 <- l9 %>% pivot_longer(cols=c(3:(ncol(l9)-1)), names_to = "date", values_to = "NDVI") #make dataframe into long format

l9$date <- str_sub(l9$date, -8,-1) #format is weird but last 8 characters of band name represent date!!
l9$date <- as.Date(l9$date, "%Y%m%d")
l9$yday <- lubridate::yday(l9$date)
l9$year <- lubridate::year(l9$date)

l9$xy <- paste(l9$x, l9$y) #column for coord pairs

###################
#load & format L7 data
###################

l7 <- brick("~/Google Drive/Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring/landsat7_reproject_no_mosaic.tif")
l7 <- as.data.frame(l7, xy=TRUE) #include xy coordinates

l7$values <- rowSums(!is.na(l7[3:ncol(l7)])) #total non-missing values and get rid of coordinates with nothing
l7 <- l7[!(l7$values==0),]

l7 <- l7 %>% pivot_longer(cols=c(3:(ncol(l7)-1)), names_to = "date", values_to = "NDVI") #make dataframe into long format

l7$date <- str_sub(l7$date, -8,-1) #format is weird but last 8 characters of band name represent date!!
l7$date <- as.Date(l7$date, "%Y%m%d")
l7$yday <- lubridate::yday(l7$date)
l7$year <- lubridate::year(l7$date)

l7$xy <- paste(l7$x, l7$y) #column for coord pairs

###################
#load & format L5 data
###################

l5 <- brick("~/Google Drive/Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring/landsat5_reproject_no_mosaic.tif")
l5 <- as.data.frame(l5, xy=TRUE) #include xy coordinates

l5$values <- rowSums(!is.na(l5[3:ncol(l5)])) #total non-missing values and get rid of coordinates with nothing
l5 <- l5[!(l5$values==0),]

l5 <- l5 %>% pivot_longer(cols=c(3:(ncol(l5)-1)), names_to = "date", values_to = "NDVI") #make dataframe into long format

l5$date <- str_sub(l5$date, -8,-1) #format is weird but last 8 characters of band name represent date!!
l5$date <- as.Date(l5$date, "%Y%m%d")
l5$yday <- lubridate::yday(l5$date)
l5$year <- lubridate::year(l5$date)

l5$xy <- paste(l5$x, l5$y) #column for coord pairs

###################
#combine and save
###################

l8$mission <- "landsat 8"
l9$mission <- "landsat 9"
l7$mission <- "landsat 7"
l5$mission <- "landsat 5"

landsatAll <- rbind(l8, l9, l7, l5)

write.csv(landsatAll, file.path(pathShare, "spatial_raw_data_all_satellites.csv"), row.names=F)

