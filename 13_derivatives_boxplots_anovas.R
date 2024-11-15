#boxplots, raincloud plots, anovas, etc. for DERIVATIVES

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
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/13_derivatives_boxplots_anovas")

######################

usdmcat <- read.csv("~/Downloads/dm_export_20000101_20241017.csv") #usdm chicago region categorical data
usdmcum <- read.csv("~/Downloads/dm_export_20000101_20241024.csv") #usdm chicago region cumulative data
grow_norms_derivs <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/growing_season_norms_derivatives.csv")) #normals
growyrs_derivs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/growing_season_yrs_derivatives.csv")) #individual years

######################
#loop to add date and deviation column
######################

usdmcum$date <- as.Date(usdmcum$ValidStart)

df <- data.frame()
for (LC in unique(growyrs_derivs$type)){
  datLC <- growyrs_derivs[growyrs_derivs$type==LC,]
  
  for (yr in unique(datLC$year)){
    datyr <- datLC[datLC$year==yr,]
    originyr <- yr - 1
    origindate <- paste(originyr,12,31,sep="-")
    datyr$date <- as.Date(datyr$yday, origin=origindate)
    datyr$deviation <- datyr$mean - (grow_norms_derivs[grow_norms_derivs$type==LC,])$mean 
    df <- rbind(df,datyr)
  }
}


#grow_subset <- df[df$date %in% usdmcum$start,]

grow_merge_derivs <- merge(x=df, y=usdmcum, by="date", all.x=F, all.y=T)

grow_merge_derivs <- grow_merge_derivs %>% pivot_longer(cols = c(13:18), names_to = "severity", values_to = "percentage") #combining index columns

######################
#box plots 
######################
#grow_merge_derivs_derivs <- grow_merge_derivs_derivs[grow_merge_derivs_derivs$percentage==0 | grow_merge_derivs_derivs$percentage>50,]
grow_merge_derivs <- grow_merge_derivs[grow_merge_derivs$percentage>50,]
#grow_merge_derivs_derivs$severity[grow_merge_derivs_derivs$percentage==0] <- "0"
grow_merge_derivs$percentage <- ""
# grow_merge_derivs_derivs <- na.omit(grow_merge_derivs_derivs)
grow_merge_derivs <- grow_merge_derivs[!is.na(grow_merge_derivs$deviation),]
grow_merge_derivs$severity <- factor(grow_merge_derivs$severity, levels=c("None", "D0", "D1", "D2", "D3"))
grow_merge_derivs$type <- factor(grow_merge_derivs$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

ggplot(data=grow_merge_derivs)+ #boxplots by drought category for each LC type
  geom_boxplot(aes(x=percentage, y=deviation, fill=severity)) + xlab(">50% coverage") +
  scale_fill_manual(name="Category", values=c("None"="gray50", "D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))+
  facet_wrap(~type)+
  geom_hline(yintercept=0, linetype="dashed")+
  ylim(-0.01,0.01) + ylab("derivative deviation")

ggplot(data=grow_merge_derivs) + xlab("> 50% coverage") + #boxplots by LC type for each drought category
  geom_boxplot(aes(x=percentage, y=deviation, fill=type)) +
  scale_fill_manual(name="Category", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  facet_wrap(~severity)+
  geom_hline(yintercept=0, linetype="dashed")+
  ylim(-0.01,0.01) + ylab("derivative deviation")

######################
#anovas by LC type
######################
#summary(grow_merge_derivs_derivs)
#grow_merge_derivs_derivs <- grow_merge_derivs_derivs[!is.na(grow_merge_derivs_derivs$yday),]
# summary(grow_merge_derivs_derivs[!is.na(grow_merge_derivs_derivs$yday),])

#grow_merge_derivs_derivs$severity <- as.factor(grow_merge_derivs_derivs$severity, levels=c("0", "D0", "D1", "D2", "D3"))
anovUrbLow <- lm(deviation~ severity, data=grow_merge_derivs[grow_merge_derivs$type=="urban-low",])
anova(anovUrbLow)
summary(anovUrbLow)
urblow <- aov(anovUrbLow)

anovcrop <- lm(deviation~ severity, data=grow_merge_derivs[grow_merge_derivs$type=="crop",])
anova(anovcrop)
summary(anovcrop)
crop <- aov(anovcrop)

anovForest <- lm(deviation~ severity, data=grow_merge_derivs[grow_merge_derivs$type=="forest",])
anova(anovForest)
summary(anovForest)
forest <- aov(anovForest)

anovgrass <- lm(deviation~ severity, data=grow_merge_derivs[grow_merge_derivs$type=="grassland",])
anova(anovgrass)
summary(anovgrass)
grass <- aov(anovgrass)

anovurbmed <- lm(deviation~ severity, data=grow_merge_derivs[grow_merge_derivs$type=="urban-medium",])
anova(anovurbmed)
summary(anovurbmed)
urbmed <- aov(anovurbmed)

anovurbhi <- lm(deviation~ severity, data=grow_merge_derivs[grow_merge_derivs$type=="urban-high",])
anova(anovurbhi)
summary(anovurbhi)
urbhi <- aov(anovurbhi)

anovurbop <- lm(deviation~ severity, data=grow_merge_derivs[grow_merge_derivs$type=="urban-open",])
anova(anovurbop)
summary(anovurbop)
urbop <- aov(anovurbop)

######################
#Tukey tests by type
######################
tukeycrop <- TukeyHSD(crop, conf.level=0.95)
tukeyforest <- TukeyHSD(forest, conf.level=0.95)
tukeygrass <- TukeyHSD(grass, conf.level=0.95)
tukeyurblow <- TukeyHSD(urblow, conf.level=0.95)
tukeyurbmed <- TukeyHSD(urbmed, conf.level=0.95)
tukeyurbhi <- TukeyHSD(urbhi, conf.level=0.95)
tukeyurbop <- TukeyHSD(urbop, conf.level=0.95)

#png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/07_boxplots_anovas/tukey_tests_drought_categories.png")
par(mfrow=c(3,3), col.main="black", mar=c(5,5,4,2))
plot(tukeycrop, las=1) + title(main ='crop', col.main="red",line=0.6)
plot(tukeyforest, las=1) + title(main='forest',col.main="red",line=0.6)
plot(tukeygrass, las=1) + title(main ='grassland',col.main="red",line=0.6)
plot(tukeyurbop, las=1) + title(main='urban-open', col.main="red",line=0.6)
plot(tukeyurblow, las=1) + title(main='urban-low', col.main="red",line=0.6)
plot(tukeyurbmed, las=1) + title(main='urban-medium', col.main="red",line=0.6)
plot(tukeyurbhi, las=1) + title(main='urban-high', col.main="red",line=0.6)
dev.off()

######################
#anovas by drought category
######################
anovnone <- lm(deviation~ type -1, data=grow_merge_derivs[grow_merge_derivs$severity=="None",])
anova(anovnone)
summary(anovnone)
none <- aov(anovnone)

anovd0 <- lm(deviation~ type -1, data=grow_merge_derivs[grow_merge_derivs$severity=="D0",])
anova(anovd0)
summary(anovd0)
d0 <- aov(anovd0)

anovd1 <- lm(deviation~ type -1, data=grow_merge_derivs[grow_merge_derivs$severity=="D1",])
anova(anovd1)
summary(anovd1)
d1 <- aov(anovd1)

anovd2 <- lm(deviation~ type -1, data=grow_merge_derivs[grow_merge_derivs$severity=="D2",])
anova(anovd2)
summary(anovd2)
d2 <- aov(anovd2)

anovd3 <- lm(deviation~ type -1, data=grow_merge_derivs[grow_merge_derivs$severity=="D3",])
anova(anovd3)
summary(anovd3)
d3 <- aov(anovd3)

######################
#Tukey tests by drought category
######################
tukeynone <- TukeyHSD(none, conf.level = 0.95)
tukeyd0 <- TukeyHSD(d0, conf.level = 0.95)
tukeyd1 <- TukeyHSD(d1, conf.level = 0.95)
tukeyd2 <- TukeyHSD(d2, conf.level = 0.95)
tukeyd3 <- TukeyHSD(d3, conf.level = 0.95)

par(mfrow=c(2,3), col.main="black", mar=c(4,11,4,4))
plot(tukeynone, las=1) + title(main='none', col.main="red", line=0.6)
plot(tukeyd0, las=1) + title(main ='D0', col.main="red",line=0.6)
plot(tukeyd1, las=1) + title(main ='D1', col.main="red",line=0.6)
plot(tukeyd2, las=1) + title(main ='D2', col.main="red",line=0.6)
plot(tukeyd3, las=1) + title(main ='D3', col.main="red",line=0.6)
dev.off()
######################
#ridgeline plot
######################
library(ggridges)
ggplot(data=grow_merge_derivs, aes(x=deviation, y=type, fill=type))+
  facet_wrap(~severity)+
  geom_density_ridges()+
  scale_fill_manual(name="Category", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  xlim(-0.01,0.01) + xlab("derivative deviation")+
  geom_vline(xintercept=0,linetype="dashed") +
  scale_y_discrete(limits=rev)

ggplot(data=grow_merge_derivs, aes(x=deviation, y=severity, fill=severity))+
  facet_wrap(~type)+
  geom_density_ridges()+
  scale_fill_manual(name="Category", values=c("None"="gray50", "D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))+  xlim(-0.01,0.01) + xlab("derivative deviation")+
  geom_vline(xintercept=0,linetype="dashed") +
  scale_y_discrete(limits=rev)
