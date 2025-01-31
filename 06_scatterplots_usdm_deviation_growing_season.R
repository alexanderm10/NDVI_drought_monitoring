# making scatterplots based on growing season for each LC type

library(ggplot2)
library(tidyr)
library(dplyr)
library(tidyverse)
library(lubridate)
library(cowplot)
library(ggdist)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/06_scatterplots_usdm_deviation_growing_season")

######################

usdmcat <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/categorical_dm_export_20000101_20241219.csv")) #usdm chicago region categorical data
usdmcum <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/cumulative_dm_export_20000101_20241217.csv")) #usdm chicago region cumulative data
grow_norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_growing_season_norms.csv")) #normals
growyrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_growing_season_yrs.csv")) #individual years

######################
#loop to add date and deviation column
######################
usdmcum$date <- as.Date(usdmcum$ValidStart)

df <- data.frame()
for (LC in unique(growyrs$type)){
  datLC <- growyrs[growyrs$type==LC,]
  
  for (yr in unique(datLC$year)){
    datyr <- datLC[datLC$year==yr,]
    originyr <- yr - 1
    origindate <- paste(originyr,12,31,sep="-")
    datyr$date <- as.Date(datyr$yday, origin=origindate)
    datyr$deviation <- datyr$mean - (grow_norms[grow_norms$type==LC,])$mean 
    df <- rbind(df,datyr)
  }
}


#grow_subset <- df[df$date %in% usdmcum$start,]

grow_merge <- merge(x=df, y=usdmcum, by="date", all.x=F, all.y=T)

grow_merge <- grow_merge %>% pivot_longer(cols = c(11:16), names_to = "severity", values_to = "percentage") #combining index columns

grow_merge <- grow_merge[!is.na(grow_merge$deviation),]

grow_merge$severity <- factor(grow_merge$severity, levels=c("None", "D0", "D1", "D2", "D3", "D4"))

######################
#crop
######################
crop <- grow_merge[grow_merge$type=="crop",]

png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/06_scatterplots_usdm_deviation_growing_season/crop_scatter_panel.png", height=6, width=12, units="in", res=320)
ggplot()+
  facet_wrap(~severity)+
  geom_point(data=crop, aes(x=percentage, y=deviation, color="gray50")) +
  geom_point(data=crop[crop$year %in% c(2005,2012,2023),], aes(x=percentage, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) + xlim(0,100) + ggtitle("Crop")
dev.off()
  
######################
#forest
######################
forest <- grow_merge[grow_merge$type=="forest",]

png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/06_scatterplots_usdm_deviation_growing_season/forest_scatter_panel.png", height=6, width=12, units="in", res=320)
ggplot()+
  facet_wrap(~severity)+
  geom_point(data=forest, aes(x=percentage, y=deviation, color="gray50")) +
  geom_point(data=forest[forest$year %in% c(2005,2012,2023),], aes(x=percentage, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) + xlim(0,100) + ggtitle("Forest")
dev.off()

######################
#grassland
######################
grassland <- grow_merge[grow_merge$type=="grassland",]

png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/06_scatterplots_usdm_deviation_growing_season/grassland_scatter_panel.png", height=6, width=12, units="in", res=320)
ggplot()+
  facet_wrap(~severity)+
  geom_point(data=grassland, aes(x=percentage, y=deviation, color="gray50")) +
  geom_point(data=grassland[grassland$year %in% c(2005,2012,2023),], aes(x=percentage, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) + xlim(0,100) + ggtitle("Grassland")
dev.off()

######################
#urban-low
######################
urblow <- grow_merge[grow_merge$type=="urban-low",]

png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/06_scatterplots_usdm_deviation_growing_season/urban-low_scatter_panel.png", height=6, width=12, units="in", res=320)
ggplot()+
  facet_wrap(~severity)+
  geom_point(data=urblow, aes(x=percentage, y=deviation, color="gray50")) +
  geom_point(data=urblow[urblow$year %in% c(2005,2012,2023),], aes(x=percentage, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) + xlim(0,100) + ggtitle("Urban-low")
dev.off()

######################
#urban-medium
######################
urbmed <- grow_merge[grow_merge$type=="urban-medium",]

png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/06_scatterplots_usdm_deviation_growing_season/urban-medium_scatter_panel.png", height=6, width=12, units="in", res=320)
ggplot()+
  facet_wrap(~severity)+
  geom_point(data=urbmed, aes(x=percentage, y=deviation, color="gray50")) +
  geom_point(data=urbmed[urbmed$year %in% c(2005,2012,2023),], aes(x=percentage, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) + xlim(0,100) + ggtitle("Urban-medium")
dev.off()

######################
#urban-high
######################
urbhigh <- grow_merge[grow_merge$type=="urban-high",]

png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/06_scatterplots_usdm_deviation_growing_season/urban-high_scatter_panel.png", height=6, width=12, units="in", res=320)
ggplot()+
  facet_wrap(~severity)+
  geom_point(data=urbhigh, aes(x=percentage, y=deviation, color="gray50")) +
  geom_point(data=urbhigh[urbhigh$year %in% c(2005,2012,2023),], aes(x=percentage, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) + xlim(0,100) + ggtitle("Urban-high")
dev.off()

######################
#urban-open
######################
urbopen <- grow_merge[grow_merge$type=="urban-open",]

png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/06_scatterplots_usdm_deviation_growing_season/urban-open_scatter_panel.png", height=6, width=12, units="in", res=320)
ggplot()+
  facet_wrap(~severity)+
  geom_point(data=urbopen, aes(x=percentage, y=deviation, color="gray50")) +
  geom_point(data=urbopen[urbopen$year %in% c(2005,2012,2023),], aes(x=percentage, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) + xlim(0,100) + ggtitle("Urban-open")
dev.off()

######################