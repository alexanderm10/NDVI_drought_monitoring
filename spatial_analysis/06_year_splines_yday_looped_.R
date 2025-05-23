# load packages -----------------------------------------------------------
library(mgcv)
library(ggplot2)
library(dplyr)
library(lubridate)
library(gganimate)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring/yday_loop_yearly_splines")
pathShare2 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring")

source("../00_Calc_GAMM_posteriors_spatial_norms.R")

# load data ---------------------------------------------------------------

landsatAll <- read.csv(file.path(google.drive, "data/spatial_NDVI_monitoring/reprojected_NDVI_all_satellites_pixel_by_pixel.csv"))
landsatNorms <- read.csv(file.path(google.drive, "data/spatial_NDVI_monitoring/yday_loop_norms.csv"))

# new data frame for predictions ------------------------------------------

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

landsatYears$x <- as.numeric(landsatYears$x)
landsatYears$y <- as.numeric(landsatYears$y)

landsatYears <- merge(landsatYears, landsatNorms, by = c("xy", "x", "y", "yday"))
landsatYears <- landsatYears %>% rename(norm=mean, norm_lwr = lwr, norm_upr = upr)

# yday years loop ---------------------------------------------------------

for (yr in unique(landsatAll$year)){
  
  yr_dates <- seq(as.Date(paste(yr,1,1,sep="-")), as.Date(paste(yr,12,31,sep="-")), by="day")
  
  yr_window <- subset(landsatAll, date >= as.Date(paste(yr-1,12,16, sep="-")) & date <= as.Date(paste(yr,12,31,sep="-")))
  yr_window <- merge(yr_window, landsatNorms, by = c("xy", "x", "y", "yday"))
  yr_window <- yr_window %>% rename(norm=mean)
  
  for (day in 1:365){
    
    ydays <- seq(yr_dates[day]-16, yr_dates[day], by="day")
    df_subset <- yr_window %>% filter(date %in% ydays)
    
    if(length(which(!is.na(df_subset$NDVIReprojected)))<25) next
    
    gam_day <- gam(NDVIReprojected ~ norm + s(x,y), data=df_subset)
    
    yr_day_Ind <- which(landsatYears$year==yr & landsatYears$yday==day)
    yr_day_post <- post.distns(model.gam=gam_day, newdata=landsatYears[yr_day_Ind,], vars=c("x","y"))
    landsatYears[yr_day_Ind,c("mean", "lwr", "upr")] <- yr_day_post[,c("mean", "lwr", "upr")]
    
    #saveRDS(gamyr, file.path(pathShare, paste0("yday=",day,"yr=", yr, "_year_spatial_gam")))

  }
}

write.csv(landsatNormdf, file.path(pathShare2, "yday_loop_norms.csv"), row.names=F)
