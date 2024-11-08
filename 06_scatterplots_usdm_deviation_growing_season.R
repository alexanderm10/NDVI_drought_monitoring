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

usdmcat <- read.csv("~/Downloads/dm_export_20000101_20241017.csv") #usdm chicago region categorical data
usdmcum <- read.csv("~/Downloads/dm_export_20000101_20241024.csv") #usdm chicago region cumulative data
grow_norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/growing_season_norms.csv")) #normals
growyrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/growing_season_yrs.csv")) #individual years

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

#grow_merge <- grow_merge %>% pivot_longer(cols = c(11:16), names_to = "severity", values_to = "percentage") #combining index columns

######################
#crop
######################
crop <- grow_merge[grow_merge$type=="crop",]

p0 <- ggplot()+
  geom_point(data=crop, aes(x=D0, y=deviation, color="gray50")) +
  geom_point(data=crop[crop$year %in% c(2005,2012,2023),], aes(x=D0, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("Crop D0+") + xlab("D0 and above percentage") + xlim(0,100)


p1 <- ggplot()+
  geom_point(data=crop, aes(x=D1, y=deviation, color="gray50")) +
  geom_point(data=crop[crop$year %in% c(2005,2012,2023),], aes(x=D1, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("Crop D1+") + xlab("D1 and above percentage") + xlim(0,100)

p2 <- ggplot()+
  geom_point(data=crop, aes(x=D2, y=deviation, color="gray50")) +
  geom_point(data=crop[crop$year %in% c(2005,2012,2023),], aes(x=D2, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("Crop D2+") + xlab("D2 and above percentage") + xlim(0,100)

p3 <- ggplot()+
  geom_point(data=crop, aes(x=D3, y=deviation, color="gray50")) +
  geom_point(data=crop[crop$year %in% c(2005,2012,2023),], aes(x=D3, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("Crop D3+") + xlab("D3 and above percentage") + xlim(0,100)

p4 <- ggplot()+
  geom_point(data=crop, aes(x=D4, y=deviation, color="gray50")) +
  geom_point(data=crop[crop$year %in% c(2005,2012,2023),], aes(x=D4, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("Crop D4+") + xlab("D4 and above percentage") + xlim(0,100)

plot_grid(p0,p1,p2,p3,p4)

######################
#forest
######################
forest <- grow_merge[grow_merge$type=="forest",]

p0 <- ggplot()+
  geom_point(data=forest, aes(x=D0, y=deviation, color="gray50")) +
  geom_point(data=forest[forest$year %in% c(2005,2012,2023),], aes(x=D0, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("Forest D0+") + xlab("D0 and above percentage") + xlim(0,100)


p1 <- ggplot()+
  geom_point(data=forest, aes(x=D1, y=deviation, color="gray50")) +
  geom_point(data=forest[forest$year %in% c(2005,2012,2023),], aes(x=D1, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("Forest D1+") + xlab("D1 and above percentage") + xlim(0,100)

p2 <- ggplot()+
  geom_point(data=forest, aes(x=D2, y=deviation, color="gray50")) +
  geom_point(data=forest[forest$year %in% c(2005,2012,2023),], aes(x=D2, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("Forest D2+") + xlab("D2 and above percentage") + xlim(0,100)

p3 <- ggplot()+
  geom_point(data=forest, aes(x=D3, y=deviation, color="gray50")) +
  geom_point(data=forest[forest$year %in% c(2005,2012,2023),], aes(x=D3, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("Forest D3+") + xlab("D3 and above percentage") + xlim(0,100)

p4 <- ggplot()+
  geom_point(data=forest, aes(x=D4, y=deviation, color="gray50")) +
  geom_point(data=forest[forest$year %in% c(2005,2012,2023),], aes(x=D4, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("Forest D4+") + xlab("D4 and above percentage") + xlim(0,100)

plot_grid(p0,p1,p2,p3,p4)

######################
#grassland
######################
grassland <- grow_merge[grow_merge$type=="grassland",]

p0 <- ggplot()+
  geom_point(data=grassland, aes(x=D0, y=deviation, color="gray50")) +
  geom_point(data=grassland[grassland$year %in% c(2005,2012,2023),], aes(x=D0, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("grassland D0+") + xlab("D0 and above percentage") + xlim(0,100)


p1 <- ggplot()+
  geom_point(data=grassland, aes(x=D1, y=deviation, color="gray50")) +
  geom_point(data=grassland[grassland$year %in% c(2005,2012,2023),], aes(x=D1, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("grassland D1+") + xlab("D1 and above percentage") + xlim(0,100)

p2 <- ggplot()+
  geom_point(data=grassland, aes(x=D2, y=deviation, color="gray50")) +
  geom_point(data=grassland[grassland$year %in% c(2005,2012,2023),], aes(x=D2, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("grassland D2+") + xlab("D2 and above percentage") + xlim(0,100)

p3 <- ggplot()+
  geom_point(data=grassland, aes(x=D3, y=deviation, color="gray50")) +
  geom_point(data=grassland[grassland$year %in% c(2005,2012,2023),], aes(x=D3, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("grassland D3+") + xlab("D3 and above percentage") + xlim(0,100)

p4 <- ggplot()+
  geom_point(data=grassland, aes(x=D4, y=deviation, color="gray50")) +
  geom_point(data=grassland[grassland$year %in% c(2005,2012,2023),], aes(x=D4, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("grassland D4+") + xlab("D4 and above percentage") + xlim(0,100)

plot_grid(p0,p1,p2,p3,p4)

######################
#urban-low
######################
urblow <- grow_merge[grow_merge$type=="urban-low",]

p0 <- ggplot()+
  geom_point(data=urblow, aes(x=D0, y=deviation, color="gray50")) +
  geom_point(data=urblow[urblow$year %in% c(2005,2012,2023),], aes(x=D0, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-low D0+") + xlab("D0 and above percentage") + xlim(0,100)


p1 <- ggplot()+
  geom_point(data=urblow, aes(x=D1, y=deviation, color="gray50")) +
  geom_point(data=urblow[urblow$year %in% c(2005,2012,2023),], aes(x=D1, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-low D1+") + xlab("D1 and above percentage") + xlim(0,100)

p2 <- ggplot()+
  geom_point(data=urblow, aes(x=D2, y=deviation, color="gray50")) +
  geom_point(data=urblow[urblow$year %in% c(2005,2012,2023),], aes(x=D2, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-low D2+") + xlab("D2 and above percentage") + xlim(0,100)

p3 <- ggplot()+
  geom_point(data=urblow, aes(x=D3, y=deviation, color="gray50")) +
  geom_point(data=urblow[urblow$year %in% c(2005,2012,2023),], aes(x=D3, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-low D3+") + xlab("D3 and above percentage") + xlim(0,100)

p4 <- ggplot()+
  geom_point(data=urblow, aes(x=D4, y=deviation, color="gray50")) +
  geom_point(data=urblow[urblow$year %in% c(2005,2012,2023),], aes(x=D4, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-low D4+") + xlab("D4 and above percentage") + xlim(0,100)

plot_grid(p0,p1,p2,p3,p4)

######################
#urban-medium
######################
urbmed <- grow_merge[grow_merge$type=="urban-medium",]

p0 <- ggplot()+
  geom_point(data=urbmed, aes(x=D0, y=deviation, color="gray50")) +
  geom_point(data=urbmed[urbmed$year %in% c(2005,2012,2023),], aes(x=D0, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-medium D0+") + xlab("D0 and above percentage") + xlim(0,100)


p1 <- ggplot()+
  geom_point(data=urbmed, aes(x=D1, y=deviation, color="gray50")) +
  geom_point(data=urbmed[urbmed$year %in% c(2005,2012,2023),], aes(x=D1, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-medium D1+") + xlab("D1 and above percentage") + xlim(0,100)

p2 <- ggplot()+
  geom_point(data=urbmed, aes(x=D2, y=deviation, color="gray50")) +
  geom_point(data=urbmed[urbmed$year %in% c(2005,2012,2023),], aes(x=D2, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-medium D2+") + xlab("D2 and above percentage") + xlim(0,100)

p3 <- ggplot()+
  geom_point(data=urbmed, aes(x=D3, y=deviation, color="gray50")) +
  geom_point(data=urbmed[urbmed$year %in% c(2005,2012,2023),], aes(x=D3, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-medium D3+") + xlab("D3 and above percentage") + xlim(0,100)

p4 <- ggplot()+
  geom_point(data=urbmed, aes(x=D4, y=deviation, color="gray50")) +
  geom_point(data=urbmed[urbmed$year %in% c(2005,2012,2023),], aes(x=D4, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-medium D4+") + xlab("D4 and above percentage") + xlim(0,100)

plot_grid(p0,p1,p2,p3,p4)

######################
#urban-high
######################
urbhigh <- grow_merge[grow_merge$type=="urban-high",]

p0 <- ggplot()+
  geom_point(data=urbhigh, aes(x=D0, y=deviation, color="gray50")) +
  geom_point(data=urbhigh[urbhigh$year %in% c(2005,2012,2023),], aes(x=D0, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-high D0+") + xlab("D0 and above percentage") + xlim(0,100)


p1 <- ggplot()+
  geom_point(data=urbhigh, aes(x=D1, y=deviation, color="gray50")) +
  geom_point(data=urbhigh[urbhigh$year %in% c(2005,2012,2023),], aes(x=D1, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-high D1+") + xlab("D1 and above percentage") + xlim(0,100)

p2 <- ggplot()+
  geom_point(data=urbhigh, aes(x=D2, y=deviation, color="gray50")) +
  geom_point(data=urbhigh[urbhigh$year %in% c(2005,2012,2023),], aes(x=D2, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-high D2+") + xlab("D2 and above percentage") + xlim(0,100)

p3 <- ggplot()+
  geom_point(data=urbhigh, aes(x=D3, y=deviation, color="gray50")) +
  geom_point(data=urbhigh[urbhigh$year %in% c(2005,2012,2023),], aes(x=D3, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-high D3+") + xlab("D3 and above percentage") + xlim(0,100)

p4 <- ggplot()+
  geom_point(data=urbhigh, aes(x=D4, y=deviation, color="gray50")) +
  geom_point(data=urbhigh[urbhigh$year %in% c(2005,2012,2023),], aes(x=D4, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-high D4+") + xlab("D4 and above percentage") + xlim(0,100)

plot_grid(p0,p1,p2,p3,p4)

######################
#urban-open
######################
urbopen <- grow_merge[grow_merge$type=="urban-open",]

p0 <- ggplot()+
  geom_point(data=urbopen, aes(x=D0, y=deviation, color="gray50")) +
  geom_point(data=urbopen[urbopen$year %in% c(2005,2012,2023),], aes(x=D0, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-open D0+") + xlab("D0 and above percentage") + xlim(0,100)


p1 <- ggplot()+
  geom_point(data=urbopen, aes(x=D1, y=deviation, color="gray50")) +
  geom_point(data=urbopen[urbopen$year %in% c(2005,2012,2023),], aes(x=D1, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-open D1+") + xlab("D1 and above percentage") + xlim(0,100)

p2 <- ggplot()+
  geom_point(data=urbopen, aes(x=D2, y=deviation, color="gray50")) +
  geom_point(data=urbopen[urbopen$year %in% c(2005,2012,2023),], aes(x=D2, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-open D2+") + xlab("D2 and above percentage") + xlim(0,100)

p3 <- ggplot()+
  geom_point(data=urbopen, aes(x=D3, y=deviation, color="gray50")) +
  geom_point(data=urbopen[urbopen$year %in% c(2005,2012,2023),], aes(x=D3, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-open D3+") + xlab("D3 and above percentage") + xlim(0,100)

p4 <- ggplot()+
  geom_point(data=urbopen, aes(x=D4, y=deviation, color="gray50")) +
  geom_point(data=urbopen[urbopen$year %in% c(2005,2012,2023),], aes(x=D4, y=deviation,color=as.factor(year), fill=as.factor(year)))+
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7"))+
  ylim(-0.2,0.2) +ggtitle("urban-open D4+") + xlab("D4 and above percentage") + xlim(0,100)

plot_grid(p0,p1,p2,p3,p4)

######################