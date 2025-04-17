library(mgcv) #load packages
library(ggplot2)
library(tibble)
library(dplyr)
library(MASS)
library(lubridate)
library(gganimate)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring/pixel_by_pixel_gam_models/year_gams")
pathShare2 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring")

source("~/Documents/GitHub/NDVI_drought_monitoring/0_Calculate_GAMM_Posteriors_Updated_Copy.R")

######################
#loading in and formatting raw data
######################

landsatAll <- read.csv(file.path(google.drive, "data/spatial_NDVI_monitoring/reprojected_NDVI_all_satellites_pixel_by_pixel.csv"))
dat25 <- landsatAll[landsatAll$year==2025,] #subset for curent yr
nmonths <- length(unique(lubridate::month(dat25$date))) # Number of knots per month for 2025

######################
#Year Splines
######################
newDF <- data.frame(yday=seq(1:365)) #create new data frame with column to represent day of year sequence
pixel_yrs <- data.frame()

for (x in unique(landsatAll$x)){
  datx <- landsatAll[landsatAll$x==x,]
  
  for (y in unique(datx$y)){
    datxy <- datx[datx$y==y,]
    
    for (yr in unique(datxy$year)){
      datyr <- datxy[datxy$year==yr,]
      
      if(length(which(!is.na(datyr$NDVIReprojected)))<40 | length(unique(datyr$yday[!is.na(datyr$NDVIReprojected)]))<24) next
      if (yr==2025){
        gamyr <- gam(NDVIReprojected ~ s(yday, k=nmonths), data=datyr)
      }else{
        gamyr <- gam(NDVIReprojected ~ s(yday, k=12), data=datyr)
      }
      
      pixelyr <- post.distns(model.gam=gamyr, newdata=newDF, vars="yday")
      pixelyr$x <- x
      pixelyr$y <- y
      pixelyr$year <- yr
      
      pixel_yrs <- rbind(pixel_yrs, pixelyr)
      saveRDS(gamyr, file.path(pathShare, paste0(x,"_", y,"_", yr, "_gam.RDS")))
    }
  }
}

write.csv(pixel_yrs, file.path(pathShare2, "pixel_by_pixel_years.csv"), row.names=F)


# yr_2012 <- landsatAll[landsatAll$year==2012,]
# yr_xy <- yr_2012[yr_2012$xy=="-88.7249999666667 42.4833333333333",]
