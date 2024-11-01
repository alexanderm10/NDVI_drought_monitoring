# making scatterplots based on growing season for each LC type

library(ggplot2)
library(tidyr)
library(dplyr)
library(tidyverse)
library(lubridate)
library(cowplot)

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

grow_merge <- grow_merge %>% pivot_longer(cols = c(12:16), names_to = "severity", values_to = "percentage") #combining index columns

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
#box plots 
######################
grow_merge <- grow_merge[grow_merge$percentage==0 | grow_merge$percentage>50,]
grow_merge$severity[grow_merge$percentage==0] <- "0"
grow_merge$percentage <- ""
grow_merge <- na.omit(grow_merge)

ggplot(data=grow_merge)+
  geom_boxplot(aes(x=percentage, y=deviation, fill=severity)) + xlab("0% or over 50%") +
  scale_fill_manual(name="Category", values=c("0"="gray50", "D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))+
  facet_wrap(~type)+
  ylim(-0.2,0.2)

# ######################
# forestd0 <- forest[forest$D0==0 | forest$D0>50,]
# forestd0 <- na.omit(forestd0)
# forestd0$D0[forestd0$D0>50] <- "50+"
# forestd0$D0 <- as.factor(forestd0$D0)
# p4 <- ggplot()+
#   geom_boxplot(data=forestd0, aes(x=D0, y=deviation, fill=D0)) + xlab("Percentage area in D0") +
#   scale_fill_manual(name="D0", values=c("0"="gray50", "50+"="yellow"))+
#   ylim(-0.2,0.2) + ggtitle("Forest")
# 
# forestd1 <- forest[forest$D1==0 | forest$D1>50,]
# forestd1 <- na.omit(forestd1)
# forestd1$D1[forestd1$D1>50] <- "50+"
# forestd1$D1 <- as.factor(forestd1$D1)
# p5 <- ggplot()+
#   geom_boxplot(data=forestd1, aes(x=D1, y=deviation, fill=D1)) + xlab("Percentage area in D1") +
#   scale_fill_manual(name="D1", values=c("0"="gray50", "50+"="burlywood"))+
#   ylim(-0.2,0.2) #+ ggtitle("Forest")
# 
# forestd2 <- forest[forest$D2==0 | forest$D2>50,]
# forestd2 <- na.omit(forestd2)
# forestd2$D2[forestd2$D2>50] <- "50+"
# forestd2$D2 <- as.factor(forestd2$D2)
# p6 <- ggplot()+
#   geom_boxplot(data=forestd2, aes(x=D2, y=deviation, fill=D2)) + xlab("Percentage area in D2") +
#   scale_fill_manual(name="D2", values=c("0"="gray50", "50+"="darkorange")) +
#   ylim(-0.2,0.2) #+ ggtitle("Forest")
# 
# forestd3 <- forest[forest$D3==0 | forest$D3>50,]
# forestd3 <- na.omit(forestd3)
# forestd3$D3[forestd3$D3>50] <- "50+"
# forestd3$D3 <- as.factor(forestd3$D3)
# p7 <- ggplot()+
#   geom_boxplot(data=forestd3, aes(x=D3, y=deviation, fill=D3)) + xlab("Percentage area in D3") +
#   scale_fill_manual(name="D3", values=c("0"="gray50", "50+"="red"))+
#   ylim(-0.2,0.2) #+ ggtitle("Forest")
# 
# ######################
# grassd0 <- grassland[grassland$D0==0 | grassland$D0>50,]
# grassd0 <- na.omit(grassd0)
# grassd0$D0[grassd0$D0>50] <- "50+"
# grassd0$D0 <- as.factor(grassd0$D0)
# p8 <- ggplot()+
#   geom_boxplot(data=grassd0, aes(x=D0, y=deviation, fill=D0)) + xlab("Percentage area in D0") +
#   scale_fill_manual(name="D0", values=c("0"="gray50", "50+"="yellow"))+
#   ylim(-0.2,0.2) + ggtitle("Grassland")
# 
# grassd1 <- grassland[grassland$D1==0 | grassland$D1>50,]
# grassd1 <- na.omit(grassd1)
# grassd1$D1[grassd1$D1>50] <- "50+"
# grassd1$D1 <- as.factor(grassd1$D1)
# p9 <- ggplot()+
#   geom_boxplot(data=grassd1, aes(x=D1, y=deviation, fill=D1)) + xlab("Percentage area in D1") +
#   scale_fill_manual(name="D1", values=c("0"="gray50", "50+"="burlywood"))+
#   ylim(-0.2,0.2) #+ ggtitle("Grassland")
# 
# grassd2 <- grassland[grassland$D2==0 | grassland$D2>50,]
# grassd2 <- na.omit(grassd2)
# grassd2$D2[grassd2$D2>50] <- "50+"
# grassd2$D2 <- as.factor(grassd2$D2)
# p10 <- ggplot()+
#   geom_boxplot(data=grassd2, aes(x=D2, y=deviation, fill=D2)) + xlab("Percentage area in D2") +
#   scale_fill_manual(name="D2", values=c("0"="gray50", "50+"="darkorange")) +
#   ylim(-0.2,0.2) #+ ggtitle("Grass")
# 
# grassd3 <- grassland[grassland$D3==0 | grassland$D3>50,]
# grassd3 <- na.omit(grassd3)
# grassd3$D3[grassd3$D3>50] <- "50+"
# grassd3$D3 <- as.factor(grassd3$D3)
# p11 <- ggplot()+
#   geom_boxplot(data=grassd3, aes(x=D3, y=deviation, fill=D3)) + xlab("Percentage area in D3") +
#   scale_fill_manual(name="D3", values=c("0"="gray50", "50+"="red"))+
#   ylim(-0.2,0.2) #+ ggtitle("grass")
# 
# ######################
# 
# urblowd0 <- urblow[urblow$D0==0 | urblow$D0>50,]
# urblowd0 <- na.omit(urblowd0)
# urblowd0$D0[urblowd0$D0>50] <- "50+"
# urblowd0$D0 <- as.factor(urblowd0$D0)
# p12 <- ggplot()+
#   geom_boxplot(data=urblowd0, aes(x=D0, y=deviation, fill=D0)) + xlab("Percentage area in D0") +
#   scale_fill_manual(name="D0", values=c("0"="gray50", "50+"="yellow"))+
#   ylim(-0.2,0.2) + ggtitle("urban-low")
# 
# urblowd1 <- urblow[urblow$D1==0 | urblow$D1>50,]
# urblowd1 <- na.omit(urblowd1)
# urblowd1$D1[urblowd1$D1>50] <- "50+"
# urblowd1$D1 <- as.factor(urblowd1$D1)
# p13 <- ggplot()+
#   geom_boxplot(data=urblowd1, aes(x=D1, y=deviation, fill=D1)) + xlab("Percentage area in D1") +
#   scale_fill_manual(name="D1", values=c("0"="gray50", "50+"="burlywood"))+
#   ylim(-0.2,0.2) #+ ggtitle("urblow")
# 
# urblowd2 <- urblow[urblow$D2==0 | urblow$D2>50,]
# urblowd2 <- na.omit(urblowd2)
# urblowd2$D2[urblowd2$D2>50] <- "50+"
# urblowd2$D2 <- as.factor(urblowd2$D2)
# p14 <- ggplot()+
#   geom_boxplot(data=urblowd2, aes(x=D2, y=deviation, fill=D2)) + xlab("Percentage area in D2") +
#   scale_fill_manual(name="D2", values=c("0"="gray50", "50+"="darkorange")) +
#   ylim(-0.2,0.2) #+ ggtitle("urb-low")
# 
# urblowd3 <- urblow[urblow$D3==0 | urblow$D3>50,]
# urblowd3 <- na.omit(urblowd3)
# urblowd3$D3[urblowd3$D3>50] <- "50+"
# urblowd3$D3 <- as.factor(urblowd3$D3)
# p15 <- ggplot()+
#   geom_boxplot(data=urblowd3, aes(x=D3, y=deviation, fill=D3)) + xlab("Percentage area in D3") +
#   scale_fill_manual(name="D3", values=c("0"="gray50", "50+"="red"))+
#   ylim(-0.2,0.2) #+ ggtitle("urblow")
# 
# ######################
# urbmedd0 <- urbmed[urbmed$D0==0 | urbmed$D0>50,]
# urbmedd0 <- na.omit(urbmedd0)
# urbmedd0$D0[urbmedd0$D0>50] <- "50+"
# urbmedd0$D0 <- as.factor(urbmedd0$D0)
# p16 <- ggplot()+
#   geom_boxplot(data=urbmedd0, aes(x=D0, y=deviation, fill=D0)) + xlab("Percentage area in D0") +
#   scale_fill_manual(name="D0", values=c("0"="gray50", "50+"="yellow"))+
#   ylim(-0.2,0.2) + ggtitle("urban-medium")
# 
# urbmedd1 <- urbmed[urbmed$D1==0 | urbmed$D1>50,]
# urbmedd1 <- na.omit(urbmedd1)
# urbmedd1$D1[urbmedd1$D1>50] <- "50+"
# urbmedd1$D1 <- as.factor(urbmedd1$D1)
# p17 <- ggplot()+
#   geom_boxplot(data=urbmedd1, aes(x=D1, y=deviation, fill=D1)) + xlab("Percentage area in D1") +
#   scale_fill_manual(name="D1", values=c("0"="gray50", "50+"="burlywood"))+
#   ylim(-0.2,0.2) #+ ggtitle("urbmed")
# 
# urbmedd2 <- urbmed[urbmed$D2==0 | urbmed$D2>50,]
# urbmedd2 <- na.omit(urbmedd2)
# urbmedd2$D2[urbmedd2$D2>50] <- "50+"
# urbmedd2$D2 <- as.factor(urbmedd2$D2)
# p18 <- ggplot()+
#   geom_boxplot(data=urbmedd2, aes(x=D2, y=deviation, fill=D2)) + xlab("Percentage area in D2") +
#   scale_fill_manual(name="D2", values=c("0"="gray50", "50+"="darkorange")) +
#   ylim(-0.2,0.2) #+ ggtitle("urb-med")
# 
# urbmedd3 <- urbmed[urbmed$D3==0 | urbmed$D3>50,]
# urbmedd3 <- na.omit(urbmedd3)
# urbmedd3$D3[urbmedd3$D3>50] <- "50+"
# urbmedd3$D3 <- as.factor(urbmedd3$D3)
# p19 <- ggplot()+
#   geom_boxplot(data=urbmedd3, aes(x=D3, y=deviation, fill=D3)) + xlab("Percentage area in D3") +
#   scale_fill_manual(name="D3", values=c("0"="gray50", "50+"="red"))+
#   ylim(-0.2,0.2) #+ ggtitle("urbmed")
# 
# ######################
# urbhighd0 <- urbhigh[urbhigh$D0==0 | urbhigh$D0>50,]
# urbhighd0 <- na.omit(urbhighd0)
# urbhighd0$D0[urbhighd0$D0>50] <- "50+"
# urbhighd0$D0 <- as.factor(urbhighd0$D0)
# p20 <- ggplot()+
#   geom_boxplot(data=urbhighd0, aes(x=D0, y=deviation, fill=D0)) + xlab("Percentage area in D0") +
#   scale_fill_manual(name="D0", values=c("0"="gray50", "50+"="yellow"))+
#   ylim(-0.2,0.2) + ggtitle("urban-high")
# 
# urbhighd1 <- urbhigh[urbhigh$D1==0 | urbhigh$D1>50,]
# urbhighd1 <- na.omit(urbhighd1)
# urbhighd1$D1[urbhighd1$D1>50] <- "50+"
# urbhighd1$D1 <- as.factor(urbhighd1$D1)
# p21 <- ggplot()+
#   geom_boxplot(data=urbhighd1, aes(x=D1, y=deviation, fill=D1)) + xlab("Percentage area in D1") +
#   scale_fill_manual(name="D1", values=c("0"="gray50", "50+"="burlywood"))+
#   ylim(-0.2,0.2) #+ ggtitle("urbhigh")
# 
# urbhighd2 <- urbhigh[urbhigh$D2==0 | urbhigh$D2>50,]
# urbhighd2 <- na.omit(urbhighd2)
# urbhighd2$D2[urbhighd2$D2>50] <- "50+"
# urbhighd2$D2 <- as.factor(urbhighd2$D2)
# p22 <- ggplot()+
#   geom_boxplot(data=urbhighd2, aes(x=D2, y=deviation, fill=D2)) + xlab("Percentage area in D2") +
#   scale_fill_manual(name="D2", values=c("0"="gray50", "50+"="darkorange")) +
#   ylim(-0.2,0.2) #+ ggtitle("urb-high")
# 
# urbhighd3 <- urbhigh[urbhigh$D3==0 | urbhigh$D3>50,]
# urbhighd3 <- na.omit(urbhighd3)
# urbhighd3$D3[urbhighd3$D3>50] <- "50+"
# urbhighd3$D3 <- as.factor(urbhighd3$D3)
# p23 <- ggplot()+
#   geom_boxplot(data=urbhighd3, aes(x=D3, y=deviation, fill=D3)) + xlab("Percentage area in D3") +
#   scale_fill_manual(name="D3", values=c("0"="gray50", "50+"="red"))+
#   ylim(-0.2,0.2) #+ ggtitle("urbhigh")
# ######################
# urbopd0 <- urbopen[urbopen$D0==0 | urbopen$D0>50,]
# urbopd0 <- na.omit(urbopd0)
# urbopd0$D0[urbopd0$D0>50] <- "50+"
# urbopd0$D0 <- as.factor(urbopd0$D0)
# p24 <- ggplot()+
#   geom_boxplot(data=urbopd0, aes(x=D0, y=deviation, fill=D0)) + xlab("Percentage area in D0") +
#   scale_fill_manual(name="D0", values=c("0"="gray50", "50+"="yellow"))+
#   ylim(-0.2,0.2) + ggtitle("urban-open")
# 
# urbopd1 <- urbopen[urbopen$D1==0 | urbopen$D1>50,]
# urbopd1 <- na.omit(urbopd1)
# urbopd1$D1[urbopd1$D1>50] <- "50+"
# urbopd1$D1 <- as.factor(urbopd1$D1)
# p25 <- ggplot()+
#   geom_boxplot(data=urbopd1, aes(x=D1, y=deviation, fill=D1)) + xlab("Percentage area in D1") +
#   scale_fill_manual(name="D1", values=c("0"="gray50", "50+"="burlywood"))+
#   ylim(-0.2,0.2) #+ ggtitle("urbopen")
# 
# urbopd2 <- urbopen[urbopen$D2==0 | urbopen$D2>50,]
# urbopd2 <- na.omit(urbopd2)
# urbopd2$D2[urbopd2$D2>50] <- "50+"
# urbopd2$D2 <- as.factor(urbopd2$D2)
# p26 <- ggplot()+
#   geom_boxplot(data=urbopd2, aes(x=D2, y=deviation, fill=D2)) + xlab("Percentage area in D2") +
#   scale_fill_manual(name="D2", values=c("0"="gray50", "50+"="darkorange")) +
#   ylim(-0.2,0.2) #+ ggtitle("urb-open")
# 
# urbopd3 <- urbopen[urbopen$D3==0 | urbopen$D3>50,]
# urbopd3 <- na.omit(urbopd3)
# urbopd3$D3[urbopd3$D3>50] <- "50+"
# urbopd3$D3 <- as.factor(urbopd3$D3)
# p27 <- ggplot()+
#   geom_boxplot(data=urbopd3, aes(x=D3, y=deviation, fill=D3)) + xlab("Percentage area in D3") +
#   scale_fill_manual(name="D3", values=c("0"="gray50", "50+"="red"))+
#   ylim(-0.2,0.2) #+ ggtitle("urbopen")
# 
# 
# 
# plot_grid(p0,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,
#           p12,p13,p14,p15,p16,p17,p18,p19,p20,p21,p22,p23,p24,p25,p26,p27,ncol=4, nrow=7)
