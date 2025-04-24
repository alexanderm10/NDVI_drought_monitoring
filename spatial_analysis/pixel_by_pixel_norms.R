library(mgcv) #load packages
library(ggplot2)
library(tibble)
library(dplyr)
library(MASS)
library(gganimate)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring/pixel_by_pixel_gam_models/norm_gams")
pathShare2 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring")

source("../0_Calculate_GAMM_Posteriors_Updated_Copy.R")

######################
#loading in and formatting raw data from 01_raw_data.R
######################

landsatAll <- read.csv(file.path(google.drive, "data/spatial_NDVI_monitoring/reprojected_NDVI_all_satellites_pixel_by_pixel.csv"))
summary(landsatAll)

# Shouldn't need to do this with the new one, but just in case...
# landsatAll <- aggregate(cbind(NDVI, MissionPred, MissionResid, ReprojPred, NDVIReprojected) ~ x + y  + xy + mission + date + year + yday, data=landsatAll, FUN=median, na.rm=T)
# summary(landsatAll)

# landsatNormdf <- data.frame(xy=rep(unique(landsatAll$xy), each=365),
#                             yday=1:365)
# landsatNormdf$x <- unlist(lapply(strsplit(landsatNormdf$xy, " "), FUN=function(x){x[1]}))
# landsatNormdf$y <- unlist(lapply(strsplit(landsatNormdf$xy, " "), FUN=function(x){x[2]}))
# head(landsatNormdf)
# tail(landsatNormdf)


landsatNormdf <- unique(landsatAll[c('x','y')])
landsatNormdf <- landsatNormdf[rep(seq_len(nrow(landsatNormdf)), each=365),]
landsatNormdf$yday <- rep_len(1:365,nrow(landsatNormdf))
######################
#Norms
######################
# newDF <- data.frame(yday=seq(1:365)) #create new data frame with column to represent day of year sequence
#pixel_norms <- data.frame()

for (x in unique(landsatAll$x)){
  datx <- landsatAll[landsatAll$x==x,]
  
  for (y in unique(datx$y)){
    datxy <- datx[datx$y==y,]
    
    xyInd <- which(landsatNormdf$x == x & landsatNormdf$y==y)
    dfNow <- landsatNormdf[xyInd,]
    if(length(which(!is.na(datxy$NDVIReprojected)))<40 | length(unique(datxy$yday[!is.na(datxy$NDVIReprojected)]))<24) next
    norm_gam <- gam(NDVIReprojected ~ s(yday, k=12), data=datxy)
    pixelnorm <- post.distns(model.gam=norm_gam, newdata=landsatNormdf[xyInd,], vars="yday")
    
    landsatNormdf[xyInd,c("mean", "lwr", "upr")] <- pixelnorm[,c("mean", "lwr", "upr")]
    # pixelnorm$x <- x
    # pixelnorm$y <- y
    
    # pixel_norms <- rbind(pixel_norms, pixelnorm)
    saveRDS(norm_gam, file.path(pathShare, paste0(x,"_", y,"_norm_gam.RDS")))
    
  }
}

write.csv(landsatNormdf, file.path(pathShare2, "pixel_by_pixel_norms.csv"), row.names=F)

######################
#Plots
######################

ggplot(landsatNormdf[landsatNormdf$yday==180,], aes(x=x,y=y, fill=mean))+ 
  geom_tile()+ coord_equal()+ scale_fill_gradientn(limits=c(0,1),colors = hcl.colors(20, "BrBG"))+
  ggtitle("norms yday=180")

ggplot(landsatNormdf[landsatNormdf$yday==1,], aes(x=x,y=y, fill=mean))+ 
  geom_tile()+ coord_equal()+ scale_fill_gradientn(limits=c(0,1),colors = hcl.colors(20, "BrBG"))+
  ggtitle("norms yday=1")

p <- ggplot(landsatNormdf, aes(x=x,y=y, fill=mean))+ #mean resids plot
  geom_tile()+ coord_equal()+ scale_fill_gradientn(limits=c(0,1),colors = hcl.colors(20, "BrBG"))+
  transition_time(yday)+
  ggtitle('norms yday = {frame_time}')+labs(fill="mean")

gganimate::animate(p, length = 15, width = 700, height = 400, nframes=365,fps=2)
anim_save("test.gif",p)
