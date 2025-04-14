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

source("~/Documents/GitHub/NDVI_drought_monitoring/0_Calculate_GAMM_Posteriors_Updated_Copy.R")

######################
#loading in and formatting raw data from 01_raw_data.R
######################

landsatAll <- read.csv(file.path(google.drive, "data/spatial_NDVI_monitoring/reprojected_NDVI_all_satellites_pixel_by_pixel.csv"))

######################
#Norms
######################
newDF <- data.frame(yday=seq(1:365)) #create new data frame with column to represent day of year sequence
pixel_norms <- data.frame()

for (x in unique(landsatAll$x)){
  datx <- landsatAll[landsatAll$x==x,]
  
  for (y in unique(datx$y)){
    datxy <- datx[datx$y==y,]
    if(length(which(!is.na(datxy$NDVIReprojected)))<40 | length(unique(datxy$yday[!is.na(datxy$NDVIReprojected)]))<24) next
    norm_gam <- gam(NDVIReprojected ~ s(yday, k=12), data=datxy)
    pixelnorm <- post.distns(model.gam=norm_gam, newdata=newDF, vars="yday")
    pixelnorm$x <- x
    pixelnorm$y <- y
    
    pixel_norms <- rbind(pixel_norms, pixelnorm)
    saveRDS(norm_gam, file.path(pathShare, paste0(x,"_", y,"_norm_gam.RDS")))
    
  }
}

write.csv(pixel_norms, file.path(pathShare2, "pixel_by_pixel_norms.csv"), row.names=F)


ggplot(pixel_norms[pixel_norms$yday==180,], aes(x=x,y=y, fill=mean))+ #mean resids plot
  geom_tile()+ coord_equal()+ scale_fill_gradientn(colors = hcl.colors(20, "RdYlGn"))+
  ggtitle("norms yday=180")

ggplot(pixel_norms[pixel_norms$yday==1,], aes(x=x,y=y, fill=mean))+ #mean resids plot
  geom_tile()+ coord_equal()+ scale_fill_gradientn(colors = hcl.colors(20, "RdYlGn"))+
  ggtitle("norms yday=1")

p <- ggplot(pixel_norms, aes(x=x,y=y, fill=mean))+ #mean resids plot
  geom_tile()+ coord_equal()+ scale_fill_gradientn(colors = hcl.colors(20, "RdYlGn"))+
  transition_time(yday)+
  ggtitle('{frame_time}')+labs(fill="mean")

gganimate::animate(p, length = 15, width = 700, height = 400, nframes=365,fps=2)
anim_save("test.gif2",p)
