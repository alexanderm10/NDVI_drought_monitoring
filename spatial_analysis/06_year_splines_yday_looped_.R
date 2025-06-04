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

source("00_Calc_GAMM_posteriors_spatial_norms.R")

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

modelStats <- data.frame(date=seq.Date(as.Date(paste0(min(landsatYears$year), "-01-01")), as.Date(paste0(max(landsatYears$year), "-12-31")), by="day"))
modelStats$year <- lubridate::year(modelStats$date)
modelStats$yday <- lubridate::yday(modelStats$date)
modelStats[,c("R2", "Intercept", "NormCoef", "SplineP", "RMSE", "error")] <- NA

# yday years loop ---------------------------------------------------------
nPixels <- length(unique(landsatNorms$xy))
for (yr in unique(landsatAll$year)){
  print(yr)
  yr_dates <- seq(as.Date(paste(yr,1,1,sep="-")), as.Date(paste(yr,12,31,sep="-")), by="day")
  
  yr_window <- subset(landsatAll, date >= as.Date(paste(yr-1,12,16, sep="-")) & date <= as.Date(paste(yr,12,31,sep="-")))
  yr_window <- merge(yr_window, landsatNorms, by = c("xy", "x", "y", "yday"))
  yr_window <- yr_window %>% rename(norm=mean)
  
  pb <- txtProgressBar(min=1, max=365, style=3)
  for (DAY in 1:365){
    setTxtProgressBar(pb, DAY)
    statsInd <- which(modelStats$year==yr & modelStats$yday==DAY)
    
    ydays <- seq(yr_dates[DAY]-16, yr_dates[DAY], by="day")
    df_subset <- yr_window %>% filter(date %in% ydays)
    
    # ggplot(data=df_subset[,]) +
    #   coord_equal() +
    #   facet_wrap(~yday) +
    #   geom_tile(aes(x=x, y=y, fill=norm))
    # 
    # ggplot(data=df_subset[,]) +
    #   coord_equal() +
    #   facet_wrap(~yday) +
    #   geom_tile(aes(x=x, y=y, fill=NDVIReprojected))
    # 
    # ggplot(data=df_subset[,]) +
    #   coord_equal() +
    #   facet_wrap(~yday + mission) +
    #   geom_tile(aes(x=x, y=y, fill=NDVIReprojected-norm))
    
      if(length(unique(df_subset$xy[!is.na(df_subset$NDVIReprojected)]))<nPixels*0.33) next
    #if(length(which(!is.na(df_subset$NDVIReprojected)))<25) next
    
    gam_day <- gam(NDVIReprojected ~ norm + s(x,y) -1, data=df_subset)
    gamSummary <- summary(gam_day)
    
    modelStats$R2[statsInd] <- gamSummary$r.sq
    # plot(df_subset$NDVIReprojected[!is.na(df_subset$NDVIReprojected)] ~ predict(gam_day))
    modelStats[statsInd,c("Intercept", "NormCoef")] <- gamSummary$p.table[,"Estimate"]
    modelStats$SplineP[statsInd] <- gamSummary$s.table[,"p-value"]
    modelStats$error[statsInd] <- mean(residuals(gam_day))
    # hist(residuals(gam_day))
    modelStats$RMSE[statsInd] <- sqrt(mean(residuals(gam_day)^2))
    
    yr_day_Ind <- which(landsatYears$year==yr & landsatYears$yday==DAY)
    yr_day_post <- post.distns(model.gam=gam_day, newdata=landsatYears[yr_day_Ind,], vars=c("x","y"))
    landsatYears[yr_day_Ind,c("mean", "lwr", "upr")] <- yr_day_post[,c("mean", "lwr", "upr")]
    
    #saveRDS(gam_day, file.path(pathShare, paste0("yday=",DAY,"yr=", yr, "_year_spatial_gam")))

  }# End day loop
} # End year loop
summary(modelStats)

write.csv(modelStats, file.path(pathShare2, "yday_spatial_loop_model_stats.csv"), row.names=F)
write.csv(landsatYears, file.path(pathShare2, "yday_spatial_loop_years.csv"), row.names=F)

# plots -------------------------------------------------------------------

landsatYears$anoms <- landsatYears$mean - landsatYears$norms

anoms_median <- landsatYears %>% group_by(x,y,yday) %>%
  summarise_at(vars("anoms"), median, na.rm=TRUE) %>% as.data.frame()

p <- ggplot(anoms_median, aes(x=x,y=y,fill=anoms))+
  geom_tile()+coord_equal()+scale_fill_gradientn(limits=c(-0.1,0.1),colors = hcl.colors(20, "BrBG"))+
  transition_time(yday)+ ggtitle('median anoms yday = {frame_time}')+labs(fill="median anoms")

gganimate::animate(p, length = 15, width = 700, height = 400, nframes=365,fps=1)
anim_save("median_anoms_yday_loop.gif",p)

ggplot(modelStats, aes(x=yday, y=error))+
  geom_point(aes(color=factor(year)))

landsatYears2012 <- landsatYears[landsatYears$year==2012,]

p <- ggplot(landsatYears2012, aes(x=x,y=y,fill=mean))+
  geom_tile()+coord_equal()+scale_fill_gradientn(limits=c(0,1),colors = hcl.colors(20, "BrBG"))+
  transition_time(yday)+ ggtitle('2012 NDVI yday = {frame_time}')+labs(fill="pred NDVI")

gganimate::animate(p, length = 15, width = 700, height = 400, nframes=365,fps=1)
anim_save("2012_NDVI_yday_loop.gif",p)

p <- ggplot(landsatYears[landsatYears$year==2005,], aes(x=x,y=y,fill=anoms))+
  geom_tile()+coord_equal()+scale_fill_gradientn(colors = hcl.colors(20, "BrBG"))+
  transition_time(yday)+ ggtitle('2005 anoms NDVI yday = {frame_time}')+labs(fill="NDVI anoms")

gganimate::animate(p, length = 15, width = 700, height = 400, nframes=365,fps=1)
anim_save("2005_NDVI_anoms_yday_loop.gif",p)


