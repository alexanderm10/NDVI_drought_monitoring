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
pathShare2 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/tables")
pathShare3 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/ESA_2025_NDVI_Monitoring_Poster")

source("~/Documents/GitHub/NDVI_drought_monitoring/0_Calculate_GAMM_Posteriors_Updated_Copy.R")

# load data ---------------------------------------------------------------

ndvi.raw <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/raw_data_k=12_with_wet-forest.csv")) #individual years
ndvi.raw <- ndvi.raw[ndvi.raw$type!="forest",]
ndvi.raw$type[ndvi.raw$type=="forest-wet"] <- "forest"
ndvi.raw$type <- factor(ndvi.raw$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
ndvi.raw$mission <- factor(ndvi.raw$mission, levels=c("landsat 5", "landsat 7", "landsat 8", "landsat 9"))

# raw vs. reprojected data by satellite -----------------------------------

day.labels <- data.frame(Date=seq.Date(as.Date("2023-01-01"), as.Date("2023-12-01"), by="month"))
day.labels$yday <- lubridate::yday(day.labels$Date)
day.labels$Text <- paste(lubridate::month(day.labels$Date, label=T), lubridate::day(day.labels$Date))
day.labels
summary(day.labels)

ndvi.raw <- ndvi.raw %>% rename("Raw" = "NDVI", "Harmonized" = "NDVIReprojected")
ndvi.raw <- ndvi.raw %>% pivot_longer(cols = c("Raw", "Harmonized"), names_to = "version", values_to = "NDVI")
ndvi.raw$version <- factor(ndvi.raw$version, levels=c("Raw", "Harmonized"))

ggplot(data=ndvi.raw[ndvi.raw$type=="urban-low",], aes(x=yday,y=NDVI))+
  geom_point(data=ndvi.raw[ndvi.raw$type=="urban-low",], aes(x=yday, y=NDVI, color=mission),size=0.1, alpha=0.5)+
  geom_smooth(data=ndvi.raw[ndvi.raw$type=="urban-low",],method="gam", formula= y ~ s(x, bs="tp", k=12), aes(color=mission, fill=mission))+
  scale_color_manual(name="mission", values=c("landsat 5" = "#D81B60", "landsat 7"="#1E88E5", "landsat 8"="#FFC107", "landsat 9"="#004D40")) +
  scale_fill_manual(name="mission", values=c("landsat 5" = "#D81B60", "landsat 7"="#1E88E5", "landsat 8"="#FFC107", "landsat 9"="#004D40")) +
  facet_grid(type~version) + ylim(0,1)+ 
  scale_x_continuous(name="Day of Year", expand=c(0,0), breaks=day.labels$yday[seq(2, 12, by=3)], labels=day.labels$Text[seq(2, 12, by=3)])+
  ylab("NDVI")+ theme_bw(15)
ggsave("figure_1_raw_vs_harmonized_NDVI_mission_curves.png", path = pathShare3, height=4, width=18, units="in", dpi = 320)
