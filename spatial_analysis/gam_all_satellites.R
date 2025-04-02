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
#load data
###################

landsatAll <- read.csv(file.path(google.drive, "data/spatial_NDVI_monitoring/spatial_raw_data_all_satellites.csv"))

###

l5 <- landsatAll[landsatAll$mission=="landsat 5",]

l5_mean_NDVI <- l5 %>% group_by(x,y) %>%
  summarise_at(vars("NDVI"), mean, na.rm=TRUE) %>% as.data.frame()

l5_mean_NDVI <- l5_mean_NDVI[l5_mean_NDVI$NDVI>0.1,]
l5_mean_NDVI$xy <- paste(l5_mean_NDVI$x, l5_mean_NDVI$y)
l5 <- filter(l5, xy %in% l5_mean_NDVI$xy)

###

l7 <- landsatAll[landsatAll$mission=="landsat 7",]

l7_mean_NDVI <- l7 %>% group_by(x,y) %>%
  summarise_at(vars("NDVI"), mean, na.rm=TRUE) %>% as.data.frame()

l7_mean_NDVI <- l7_mean_NDVI[l7_mean_NDVI$NDVI>0.1,]
l7_mean_NDVI$xy <- paste(l7_mean_NDVI$x, l7_mean_NDVI$y)
l7 <- filter(l7, xy %in% l7_mean_NDVI$xy)

###

l8 <- landsatAll[landsatAll$mission=="landsat 8",]

l8_mean_NDVI <- l8 %>% group_by(x,y) %>%
  summarise_at(vars("NDVI"), mean, na.rm=TRUE) %>% as.data.frame()

l8_mean_NDVI <- l8_mean_NDVI[l8_mean_NDVI$NDVI>0.1,]
l8_mean_NDVI$xy <- paste(l8_mean_NDVI$x, l8_mean_NDVI$y)
l8 <- filter(l8, xy %in% l8_mean_NDVI$xy)

###

l9 <- landsatAll[landsatAll$mission=="landsat 9",]

l9_mean_NDVI <- l9 %>% group_by(x,y) %>%
  summarise_at(vars("NDVI"), mean, na.rm=TRUE) %>% as.data.frame()

l9_mean_NDVI <- l9_mean_NDVI[l9_mean_NDVI$NDVI>0.1,]
l9_mean_NDVI$xy <- paste(l9_mean_NDVI$x, l9_mean_NDVI$y)
l9 <- filter(l9, xy %in% l9_mean_NDVI$xy)

landsatAll <- rbind (l5,l7,l8,l9)
landsatAll$mission <- as.factor(landsatAll$mission)

###################
#Run test GAM for all
###################

all_gam <- gam(NDVI ~ s(y,x,yday,by=mission) + mission-1,data=landsatAll) #DEFAULT K
gam.check(all_gam)
tidy_gam(all_gam)
plot.gam(all_gam)

saveRDS(all_gam, file.path(pathShare, "3D_gam_all_satellites.RDS"))

###################
#Precict function
###################

landsatAll$MissionPred <- predict(all_gam, newdata=landsatAll)
landsatAll$resid <- landsatAll$NDVI - landsatAll$MissionPred

ggplot(data=landsatAll, aes(x=yday, y=resid))+
  geom_point(alpha=0.5) + ggtitle("Residuals vs. Day of Year all satellites")

all_resid_mean <- landsatAll %>% group_by(x,y) %>% #mean residuals at each coord
  summarise_at(vars("resid"), mean, na.rm=TRUE) %>% as.data.frame()

all_resid_mean <- all_resid_mean %>% #formatting for plotly widget
  mutate(text = paste0("x: ", round(x,2), "\n", "y: ", round(y,2), "\n", "Residual: ",round(resid,3), "\n"))

#p1 <- mean resids
ggplot(all_resid_mean, aes(x=x,y=y, fill=resid, text=text))+ #mean resids plot
  geom_tile()+ coord_equal()+ scale_fill_gradient(low="white", high="blue")+
  ggtitle("All Satellites NDVI Mean Residuals")+labs(fill="residuals")

###

landsatAll$resid_sq <- (landsatAll$resid)^2
all_resid_sq_mean <- landsatAll %>% group_by(x,y) %>%
  summarise_at(vars("resid_sq"), mean, na.rm=TRUE) %>% as.data.frame()

all_resid_sq_mean$RMSE <- sqrt(all_resid_sq_mean$resid_sq)

all_resid_sq_mean <- all_resid_sq_mean %>%
  mutate(text = paste0("x: ", round(x,2), "\n", "y: ", round(y,2), "\n", "RMSE: ",round(RMSE,3), "\n"))

#p2 <- RMSE
ggplot(all_resid_sq_mean, aes(x=x,y=y, fill=RMSE,text=text))+ #RMSE plot
  geom_tile()+ coord_equal()+ scale_fill_gradient(low="white", high="blue")+
  ggtitle("All Satellites NDVI RMSE")+labs(fill="RMSE")

###
all_mean_NDVI <- landsatAll %>% group_by(x,y) %>%
  summarise_at(vars("NDVI"), mean, na.rm=TRUE) %>% as.data.frame()

all_resid_mean$normalized_resid <- all_resid_mean$resid/all_mean_NDVI$NDVI

ggplot(all_resid_mean, aes(x=x,y=y, fill=normalized_resid))+ #mean resids plot
  geom_tile()+ coord_equal()+ scale_fill_gradient(low="white", high="blue")+
  ggtitle("All Satellites NDVI Mean Residuals/Mean NDVI")+labs(fill="mean resid/mean NDVI")

###################
#Reproject
###################

df_dupe <- landsatAll
df_dupe$mission <- "landsat 8"

landsatAll$ReprojPred <- predict(all_gam, newdata=df_dupe)
landsatAll$NDVIReprojected <- landsatAll$resid + landsatAll$ReprojPred

reproj_mean_NDVI <- landsatAll %>% group_by(x,y) %>%
  summarise_at(vars("NDVIReprojected"), mean, na.rm=TRUE) %>% as.data.frame()

ggplot(reproj_mean_NDVI, aes(x=x,y=y, fill=NDVIReprojected))+ #mean resids plot
  geom_tile()+ coord_equal()+ scale_fill_gradientn(colors = hcl.colors(20, "RdYlGn"))+
  ggtitle("All Satellites Mean Reprojected NDVI")+labs(fill="mean NDVI reproj")

###################
#Save Raw Data
###################

write.csv(landsatAll, file.path(pathShare, "reprojected_NDVI_all_satellites.csv"),row.names = FALSE)
