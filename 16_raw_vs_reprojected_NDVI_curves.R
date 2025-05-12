library(mgcv) #load packages
library(ggplot2)
library(tibble)
library(dplyr)
library(MASS)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/figures")

source("~/Documents/GitHub/NDVI_drought_monitoring/0_Calculate_GAMM_Posteriors_Updated_Copy.R")

# load data ---------------------------------------------------------------

ndvi.raw <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/raw_data_k=12.csv")) #individual years
ndvi.raw$type <- factor(ndvi.raw$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
ndvi.raw$mission <- factor(ndvi.raw$mission, levels=c("landsat 5", "landsat 7", "landsat 8", "landsat 9"))

yrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_individual_years_post_GAM.csv")) #individual years
yrs$type <- factor(yrs$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

# raw vs. reprojected data by satellite -----------------------------------

#raw data
ggplot(data=ndvi.raw, aes(x=yday,y=NDVI))+
  geom_point(data=ndvi.raw, aes(x=yday, y=NDVI, color=mission),size=0.1, alpha=0.5)+
  geom_smooth(method="gam", formula= y ~ s(x, bs="tp", k=12), aes(color=mission, fill=mission))+
  scale_color_manual(name="mission", values=c("landsat 5" = "#D81B60", "landsat 7"="#1E88E5", "landsat 8"="#FFC107", "landsat 9"="#004D40")) +
  scale_fill_manual(name="mission", values=c("landsat 5" = "#D81B60", "landsat 7"="#1E88E5", "landsat 8"="#FFC107", "landsat 9"="#004D40")) +
  facet_wrap(~type) + ylim(0,1)+ xlim(0,365)+
  ggtitle("Raw NDVI")+ ylab("NDVI")+ theme_bw(11)
ggsave("raw_NDVI_mission_curves.png", path = pathShare, height=6, width=12, units="in", dpi = 320)

#reprojected data
ggplot(data=ndvi.raw, aes(x=yday,y=NDVIReprojected))+
  geom_point(data=ndvi.raw, aes(x=yday, y=NDVIReprojected, color=mission),size=0.1, alpha=0.5)+
  geom_smooth(method="gam", formula= y ~ s(x, bs="tp", k=12), aes(color=mission,fill=mission))+
  scale_color_manual(name="mission", values=c("landsat 5" = "#D81B60", "landsat 7"="#1E88E5", "landsat 8"="#FFC107", "landsat 9"="#004D40")) +
  scale_fill_manual(name="mission", values=c("landsat 5" = "#D81B60", "landsat 7"="#1E88E5", "landsat 8"="#FFC107", "landsat 9"="#004D40")) +
  facet_wrap(~type) + ylim(0,1)+ xlim(0,365)+
  ggtitle("Reprojected NDVI")+ ylab(" Reprojected NDVI")+ theme_bw(11)
ggsave("reprojected_NDVI_mission_curves.png", path = pathShare, height=6, width=12, units="in", dpi = 320)

# raw vs. reprojected data by year ----------------------------------------

#raw
# ggplot(data=ndvi.raw, aes(x=yday,y=NDVI))+
#   geom_point(data=ndvi.raw[ndvi.raw$year %in% c(2005, 2012, 2023),], aes(x=yday, y=NDVI, color=as.factor(year)),size=0.1, alpha=0.5)+
#   geom_smooth(method="gam", aes(color="normal", fill="normal")) +
#   geom_smooth(method="gam", data=ndvi.raw[ndvi.raw$year %in% c(2005, 2012, 2023),], aes(color=as.factor(year), fill=as.factor(year))) +
#   scale_color_manual(name="year", values=c("normal" = "black","2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
#   scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
#   facet_wrap(~type) + ylim(0,1)+ xlim(0,365)+
#   ggtitle("Raw NDVI")+ ylab("NDVI")
# ggsave("raw_NDVI_year_curves.png", path = pathShare, height=6, width=12, units="in", dpi = 320)

#reprojected
# ggplot(data=ndvi.raw, aes(x=yday,y=NDVIReprojected))+
#   geom_point(data=ndvi.raw[ndvi.raw$year %in% c(2005, 2012, 2023),], aes(x=yday, y=NDVIReprojected, color=as.factor(year)),size=0.1, alpha=0.5)+
#   geom_smooth(method="gam", aes(color="normal", fill="normal")) +
#   geom_smooth(method="gam", data=ndvi.raw[ndvi.raw$year %in% c(2005, 2012, 2023),], aes(color=as.factor(year), fill=as.factor(year))) +
#   scale_color_manual(name="year", values=c("normal" = "black","2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
#   scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
#   facet_wrap(~type) + ylim(0,1)+ xlim(0,365)+
#   ggtitle("Reprojected NDVI")+ ylab(" Reprojected NDVI")
# ggsave("reprojected_NDVI_year_curves.png", path = pathShare, height=6, width=12, units="in", dpi = 320)
