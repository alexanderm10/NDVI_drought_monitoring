# load packages -----------------------------------------------------------
library(mgcv)
library(ggplot2)
library(dplyr)
library(lubridate)
library(gganimate)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring/day_of_year_gam_normals")
pathShare2 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring")

source("../0_Calculate_GAMM_Posteriors_Updated_Copy.R")


# load data ---------------------------------------------------------------

landsatAll <- read.csv(file.path(google.drive, "data/spatial_NDVI_monitoring/reprojected_NDVI_all_satellites_pixel_by_pixel.csv"))
summary(landsatAll)

# Shouldn't need to do this with the new one, but just in case...
# landsatAll <- aggregate(cbind(NDVI, MissionPred, MissionResid, ReprojPred, NDVIReprojected) ~ x + y  + xy + mission + date + year + yday, data=landsatAll, FUN=median, na.rm=T)
# summary(landsatAll)

landsatNormdf <- data.frame(xy=rep(unique(landsatAll$xy), each=365),
                            yday=1:365)
landsatNormdf$x <- unlist(lapply(strsplit(landsatNormdf$xy, " "), FUN=function(x){x[1]}))
landsatNormdf$y <- unlist(lapply(strsplit(landsatNormdf$xy, " "), FUN=function(x){x[2]}))
head(landsatNormdf)
tail(landsatNormdf)

landsatNormdf$x <- as.numeric(landsatNormdf$x)
landsatNormdf$y <- as.numeric(landsatNormdf$y)

# landsatNormdf <- unique(landsatAll[c('x','y')])
# landsatNormdf <- landsatNormdf[rep(seq_len(nrow(landsatNormdf)), each=365),]
# landsatNormdf$yday <- rep_len(1:365,nrow(landsatNormdf))


# yday norms loop ---------------------------------------------------------

for (day in 1:365){
  start <- day - 7
  end <- day + 7
  
  if (start <1){
    start_section <- c(start + 365, 1:day)
  } else{
    start_section <- start:day
  }
  if (end > 365){
    end_section <- c(day:365, 1:(end - 365))
  } else{
    end_section <- day:end
  }
  days_section <- unique(c(start_section, end_section))
  dfyday <- landsatAll %>% filter(yday %in% days_section)
  
  norm_gam <- gam(NDVIReprojected ~ s(y,x), data=dfyday)
  
  yday_ind <- which(landsatNormdf$yday==day)
  ydaynorm <- post.distns(model.gam=norm_gam, newdata=landsatNormdf[yday_ind,], vars=c("x","y"))
  
  landsatNormdf[yday_ind,c("mean", "lwr", "upr")] <- ydaynorm[,c("mean", "lwr", "upr")]
  
  saveRDS(norm_gam, file.path(pathShare, paste0("yday=",day,"_norm_spatial_gam")))
}

write.csv(landsatNormdf, file.path(pathShare2, "yday_loop_norms.csv"), row.names=F)

# plots -------------------------------------------------------------------

p <- ggplot(landsatNormdf, aes(x=x,y=y,fill=mean))+
  geom_tile()+coord_equal()+scale_fill_gradientn(limits=c(0,1),colors = hcl.colors(20, "BrBG"))+
  transition_time(yday)+ ggtitle('norms yday = {frame_time}')+labs(fill="mean NDVI")

gganimate::animate(p, length = 15, width = 700, height = 400, nframes=365,fps=2)
anim_save("yday_loop_norms.gif",p)

ggplot(landsatNormdf[landsatNormdf$yday==206,], aes(x=x,y=y, fill=mean))+
  geom_tile()+ coord_equal()+ scale_fill_gradientn(limits=c(0,1),colors = hcl.colors(20, "BrBG"))+
  ylab("y") + xlab("x")+
  ggtitle('Norms, yday = 206')+labs(fill="mean anomaly")


ggplot(landsatNormdf[landsatNormdf$yday==144,], aes(x=x,y=y, fill=mean))+
  geom_tile()+ coord_equal()+ scale_fill_gradientn(limits=c(0,1),colors = hcl.colors(20, "BrBG"))+
  ylab("y") + xlab("x")+
  ggtitle('Norms, yday = 144')+labs(fill="mean anomaly")
