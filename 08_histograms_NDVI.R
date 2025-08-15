#histograms/misc. NDVI plots

library(ggplot2)
library(tidyr)
library(dplyr)
library(tidyverse)
library(lubridate)
library(cowplot)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/08_histograms_NDVI")

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
usdm <- usdmcum[usdmcum$percentage>50,] #filter data to show more than 50% area coverage 

for (level in unique(usdm$severity)){
  df <- usdm[usdm$severity==level,] #filter data by drought category and order by date ascending
  df <- arrange(df, date)
  df$consecutive <- c(NA, diff(df$date)==7) #marking consecutive weeks as TRUE
  x <- rle(df$consecutive) #finding length of values in a row
  x <- x$lengths[x$values==TRUE] #finding lengths of only TRUE values/the consecutive ones
  x <- x[!is.na(x)] #remove NA
  x <- sequence(x) #order lengths as a sequence of values including all values below it
  x <- data.frame(x) #turn into df
  x$category <- paste0("",level) #save as separate dfs
  assign(paste0("df",level),x)
}

df <- rbind(dfD0, dfD1, dfD2,dfD3) #save again as a combined df
df$category <- as.factor(df$category)

ggplot(data=df, aes(x=x,fill=category)) + #plot for the full date range of cumulative USDM data
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

for (level in unique(grow$severity)){ #repeating loop process for dates within determined growing season of ANY lc type
  df <- grow[grow$severity==level,]
  df <- arrange(df, date)
  df <- distinct(df, date, .keep_all=TRUE) #use this to sort through repeat dates
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

ggplot(data=df, aes(x=x,fill=category)) + #cumulative consecutive weeks in drought for growing season
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

ggplot(data=df, aes(x=x,fill=category)) + #categorical full range data
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
  df <- distinct(df, date, .keep_all=TRUE)
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

ggplot(data=df, aes(x=x,fill=category)) + #growing season categorical
  geom_histogram(bins=8) + ylab("frequency") + xlab("consecutive weeks in drought")+
  ggtitle("Categorical growing season")+
  scale_fill_manual(name="Category", values=c("D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))
# + ylim(0,40) + xlim(0,55)

######################
#time spent in drought boxplots
######################
usdmcum <- read.csv("~/Downloads/dm_export_20000101_20241024.csv") #usdm chicago region cumulative data
usdmcum$date <- as.Date(usdmcum$ValidStart)

growyrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/growing_season_yrs.csv")) #individual years
grow_norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/growing_season_norms.csv")) #normals

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

weeks <- data.frame()
for (LC in unique(grow$type)){
  df <- grow[grow$type==LC & grow$severity=="D3",]
  df <- distinct(df, date, .keep_all=TRUE)
  df$consecutive <- c(NA,diff(df$date)==7)
  x <- rle(df$consecutive)
  df$count <- sequence(x$lengths)
  df <- df[df$consecutive==TRUE,]
  df$count <- df$count + 1
  df <- df[!is.na(df$count),]
  weeks <- rbind(weeks,df)
}

weeks$type <- factor(weeks$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

ggplot(data=weeks)+ ggtitle("Consecutive weeks in D3+")+
  facet_wrap(~type)+ xlab("consecutive weeks in drought") +
  geom_boxplot(aes(x=count,y=deviation, group = count)) + ylim(-0.15,0.15)
