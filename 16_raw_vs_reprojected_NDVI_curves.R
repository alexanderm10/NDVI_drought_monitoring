library(mgcv) #load packages
library(ggplot2)
library(tibble)
library(dplyr)
library(MASS)
library(cowplot)

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

day.labels <- data.frame(Date=seq.Date(as.Date("2023-01-01"), as.Date("2023-12-01"), by="month"))
day.labels$yday <- lubridate::yday(day.labels$Date)
day.labels$Text <- paste(lubridate::month(day.labels$Date, label=T), lubridate::day(day.labels$Date))
day.labels
summary(day.labels)

#raw data
p<- ggplot(data=ndvi.raw, aes(x=yday,y=NDVI))+
  geom_point(data=ndvi.raw, aes(x=yday, y=NDVI, color=mission),size=0.1, alpha=0.5)+
  geom_smooth(method="gam", formula= y ~ s(x, bs="tp", k=12), aes(color=mission, fill=mission))+
  scale_color_manual(name="mission", values=c("landsat 5" = "#D81B60", "landsat 7"="#1E88E5", "landsat 8"="#FFC107", "landsat 9"="#004D40")) +
  scale_fill_manual(name="mission", values=c("landsat 5" = "#D81B60", "landsat 7"="#1E88E5", "landsat 8"="#FFC107", "landsat 9"="#004D40")) +
  facet_wrap(~type, ncol=1) + ylim(0,1)+ 
  scale_x_continuous(name="Day of Year", expand=c(0,0), breaks=day.labels$yday[seq(2, 12, by=3)], labels=day.labels$Text[seq(2, 12, by=3)])+
  ggtitle("Raw NDVI")+ ylab("NDVI")+ theme_bw(11)
p <- p + theme(legend.position = "none")
#ggsave("raw_NDVI_mission_curves.png", path = pathShare, height=6, width=12, units="in", dpi = 320)

#harmonized data
p_harmonized <- ggplot(data=ndvi.raw, aes(x=yday,y=NDVIReprojected))+
  geom_point(data=ndvi.raw, aes(x=yday, y=NDVIReprojected, color=mission),size=0.1, alpha=0.5)+
  geom_smooth(method="gam", formula= y ~ s(x, bs="tp", k=12), aes(color=mission,fill=mission))+
  scale_color_manual(name="mission", values=c("landsat 5" = "#D81B60", "landsat 7"="#1E88E5", "landsat 8"="#FFC107", "landsat 9"="#004D40")) +
  scale_fill_manual(name="mission", values=c("landsat 5" = "#D81B60", "landsat 7"="#1E88E5", "landsat 8"="#FFC107", "landsat 9"="#004D40")) +
  facet_wrap(~type, ncol=1) + ylim(0,1)+
  scale_x_continuous(name="Day of Year", expand=c(0,0), breaks=day.labels$yday[seq(2, 12, by=3)], labels=day.labels$Text[seq(2, 12, by=3)])+
  ggtitle("Harmonized NDVI")+ ylab("Harmonized NDVI")+ theme_bw(11)
p_harmonized <- p_harmonized + theme(legend.position = "none")

ggpubr::ggarrange(
  p, p_harmonized, # list of plots
  labels = "AUTO", # labels
  common.legend = TRUE, # COMMON LEGEND
  legend = "bottom", # legend position
  align = "hv", # Align them both, horizontal and vertical
  ncol = 2 # number of rows
)

ggsave("raw_vs_harmonized_NDVI_mission_curves.png", path = pathShare, height=12, width=12, units="in", dpi = 320)

# mean and sd -------------------------------------------------------------
ndvi.raw$month <- lubridate::month(ndvi.raw$date)

raw_stats <- group_by(ndvi.raw, mission, month) %>%
   summarise(mean_NDVI=mean(NDVI, na.rm=T),sd=sd(NDVI, na.rm=T))

reproj_stats <- group_by(ndvi.raw, mission, month) %>%
  summarise(mean_NDVI_reproj=mean(NDVIReprojected, na.rm=T),sd=sd(NDVIReprojected, na.rm=T))

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
