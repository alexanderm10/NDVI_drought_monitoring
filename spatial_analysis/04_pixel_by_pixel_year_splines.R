library(mgcv) #load packages
library(ggplot2)
library(tibble)
library(dplyr)
library(MASS)
library(lubridate)
library(gganimate)
library(scales)

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

landsatYears <- data.frame(yday=1:365,
                           year=rep(unique(landsatAll$year), each=365),
                           xy=rep(unique(landsatAll$xy), each=365*length(unique(landsatAll$year))))
landsatYears$x <- unlist(lapply(strsplit(landsatYears$xy, " "), FUN=function(x){x[1]}))
landsatYears$y <- unlist(lapply(strsplit(landsatYears$xy, " "), FUN=function(x){x[2]}))
head(landsatYears)
tail(landsatYears)

landsatYears <- landsatYears[order(landsatYears$xy, landsatYears$year, landsatYears$yday),]
head(landsatYears)
tail(landsatYears)

######################
#Year Splines
######################
#newDF <- data.frame(yday=seq(1:365)) #create new data frame with column to represent day of year sequence
#pixel_yrs <- data.frame()

for (x in unique(landsatAll$x)){
  datx <- landsatAll[landsatAll$x==x,]
  
  for (y in unique(datx$y)){
    datxy <- datx[datx$y==y,]
    
    for (yr in unique(datxy$year)){
      datyr <- datxy[datxy$year==yr,]
      
      xyYrInd <- which(landsatYears$x == x & landsatYears$y==y & landsatYears$year==yr)
      
      if(length(which(!is.na(datyr$NDVIReprojected)))<15 | length(unique(datyr$yday[!is.na(datyr$NDVIReprojected)]))<15) next
      if (yr==2025){
        gamyr <- gam(NDVIReprojected ~ s(yday, k=nmonths), data=datyr)
      }else{
        gamyr <- gam(NDVIReprojected ~ s(yday, k=12), data=datyr)
      }
      
      pixelyr <- post.distns(model.gam=gamyr, newdata=landsatYears[xyYrInd,], vars="yday")
      # pixelyr$x <- x
      # pixelyr$y <- y
      # pixelyr$year <- yr
      # 
      # pixel_yrs <- rbind(pixel_yrs, pixelyr)
      landsatYears[xyYrInd,c("mean", "lwr", "upr")] <- pixelyr[,c("mean", "lwr", "upr")]
      
      saveRDS(gamyr, file.path(pathShare, paste0(x,"_", y,"_", yr, "_gam.RDS")))
    }
  }
}

landsatYears$x <- as.numeric(landsatYears$x)
landsatYears$y <- as.numeric(landsatYears$y)

write.csv(landsatYears, file.path(pathShare2, "pixel_by_pixel_years.csv"), row.names=F)

######################
#Plots
######################

landsatYears2012 <- landsatYears[landsatYears$year==2012,]
landsatYears180 <- landsatYears[landsatYears$yday==180,]

p <- ggplot(landsatYears180, aes(x=x,y=y, fill=mean))+
  geom_tile()+ coord_equal()+ scale_fill_gradientn(limits=c(0,1),colors = hcl.colors(20, "BrBG"))+
  transition_time(year)+
  ggtitle('Year splines yday =180, {frame_time}')+labs(fill="mean")

gganimate::animate(p, length = 15, width = 700, height = 400, nframes=25,fps=2)
anim_save("years_yday_180.gif",p)

ggplot(landsatYears2012[landsatYears2012$yday==180,], aes(x=x,y=y, fill=mean))+ 
  geom_tile()+ coord_equal()+ scale_fill_gradientn(limits=c(0,1),colors = hcl.colors(20, "BrBG"))+
  ggtitle("norms yday=180")