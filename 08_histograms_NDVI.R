#histograms/misc NDVI plots

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
usdmcum <- read.csv("~/Downloads/dm_export_20000101_20241024.csv") #usdm chicago region cumulative data
usdmcum <- usdmcum %>% pivot_longer(cols = c(4:8), names_to = "severity", values_to = "percentage") #combining index columns
usdmcum$date <- as.Date(usdmcum$ValidStart)

usdmcat <- read.csv("~/Downloads/dm_export_20000101_20241017.csv") #usdm chicago region categorical data
usdmcat <- usdmcat %>% pivot_longer(cols = c(4:8), names_to = "severity", values_to = "percentage") #combining index columns
usdmcat$date <- as.Date(usdmcat$ValidStart)

grow_norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/growing_season_norms.csv")) #normals
growyrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/growing_season_yrs.csv")) #individual years

######################
#all time cumulative
######################
usdm <- usdmcum[usdmcum$percentage>50,]

for (level in unique(usdm$severity)){
  df <- usdm[usdm$severity==level,]
  df <- arrange(df, date)
  df$consecutive <- c(NA, diff(df$date)==7)
  x <- rle(df$consecutive)
  x <- x$lengths[x$values==TRUE]
  x <- x[!is.na(x)]
  x <- sequence(x)
  x <- data.frame(x)
  x$category <- paste0("",level)
  assign(paste0("df",level),x)
}

df <- rbind(dfD0, dfD1, dfD2,dfD3)
df$category <- as.factor(df$category)

ggplot(data=df, aes(x=x,fill=category)) +
  geom_histogram(bins=52) + ylab("frequency") + xlab("consecutive weeks in drought")+
  ggtitle("Cumulative full data range")+
  scale_fill_manual(name="Category", values=c("D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))

######################
#growing season cumulative
######################
usdmcum <- read.csv("~/Downloads/dm_export_20000101_20241024.csv") #usdm chicago region cumulative data
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

grow_merge <- merge(x=df, y=usdmcum, by="date", all.x=F, all.y=T)

grow_merge <- grow_merge %>% pivot_longer(cols = c(12:16), names_to = "severity", values_to = "percentage") #combining index columns

grow <- grow_merge[grow_merge$percentage>50,]

grow <- (grow[!is.na(grow$yday),])

for (level in unique(grow$severity)){
  df <- grow[grow$severity==level,]
  df <- arrange(df, date)
  df <- distinct(df, date, .keel_all=TRUE)
  df$consecutive <- c(NA, diff(df$date)==7)
  x <- rle(df$consecutive)
  x <- x$lengths[x$values==TRUE]
  x <- x[!is.na(x)]
  x <- sequence(x)
  x <- data.frame(x)
  x$category <- paste0("",level)
  assign(paste0("df",level),x)
}

df <- rbind(dfD0, dfD1, dfD2,dfD3)
df$category <- as.factor(df$category)

ggplot(data=df, aes(x=x,fill=category)) +
  geom_histogram(bins=23) + ylab("frequency") + xlab("consecutive weeks in drought")+
  ggtitle("Cumulative growing season")+
  scale_fill_manual(name="Category", values=c("D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))
 # + ylim(0,40) + xlim(0,55)

######################
#all time categorical
######################

usdm <- usdmcat[usdmcat$percentage>50,]

for (level in unique(usdm$severity)){
  df <- usdm[usdm$severity==level,]
  df <- arrange(df, date)
  df$consecutive <- c(NA, diff(df$date)==7)
  x <- rle(df$consecutive)
  x <- x$lengths[x$values==TRUE]
  x <- x[!is.na(x)]
  x <- sequence(x)
  x <- data.frame(x)
  x$category <- paste0("",level)
  assign(paste0("df",level),x)
}

df <- rbind(dfD0, dfD1, dfD2,dfD3)
df$category <- as.factor(df$category)

ggplot(data=df, aes(x=x,fill=category)) +
  geom_histogram(bins=11) + ylab("frequency") + xlab("consecutive weeks in drought")+
  ggtitle("Categorical full data range")+
  scale_fill_manual(name="Category", values=c("D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))
  #+xlim(0,12)

######################
#growing season categorical
######################
usdmcat <- read.csv("~/Downloads/dm_export_20000101_20241017.csv") #usdm chicago region categorical data
usdmcat$date <- as.Date(usdmcat$ValidStart)

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

grow_merge <- merge(x=df, y=usdmcat, by="date", all.x=F, all.y=T)

grow_merge <- grow_merge %>% pivot_longer(cols = c(12:16), names_to = "severity", values_to = "percentage") #combining index columns

grow <- grow_merge[grow_merge$percentage>50,]

grow <- (grow[!is.na(grow$yday),])

for (level in unique(grow$severity)){
  df <- grow[grow$severity==level,]
  df <- arrange(df, date)
  df <- distinct(df, date, .keel_all=TRUE)
  df$consecutive <- c(NA, diff(df$date)==7)
  x <- rle(df$consecutive)
  x <- x$lengths[x$values==TRUE]
  x <- x[!is.na(x)]
  x <- sequence(x)
  x <- data.frame(x)
  x$category <- paste0("",level)
  assign(paste0("df",level),x)
}

df <- rbind(dfD0, dfD1, dfD2,dfD3)
df$category <- as.factor(df$category)

ggplot(data=df, aes(x=x,fill=category)) +
  geom_histogram(bins=8) + ylab("frequency") + xlab("consecutive weeks in drought")+
  ggtitle("Categorical growing season")+
  scale_fill_manual(name="Category", values=c("D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))
# + ylim(0,40) + xlim(0,55)