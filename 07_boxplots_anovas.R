#boxplots, raincloud plots, anovas, etc.

library(ggplot2)
library(tidyr)
library(dplyr)
library(tidyverse)
library(lubridate)
library(cowplot)
library(ggdist)
library(multcompView)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/07_boxplots_anovas")

######################

usdmcat <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/categorical_dm_export_20000101_20241219.csv")) #usdm chicago region categorical data
#usdmcat <- read.csv("~/Downloads/dm_export_20000101_20241017.csv") #usdm chicago region categorical data
#usdmcum <- read.csv("~/Downloads/dm_export_20000101_20241024.csv") #usdm chicago region cumulative data
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


######################
#box plots 
######################
#grow_merge <- grow_merge[grow_merge$percentage==0 | grow_merge$percentage>50,]
grow_merge <- grow_merge[grow_merge$percentage>50,]
#grow_merge$severity[grow_merge$percentage==0] <- "0"
grow_merge$percentage <- ""
# grow_merge <- na.omit(grow_merge)
grow_merge <- grow_merge[!is.na(grow_merge$deviation),]
grow_merge$severity <- factor(grow_merge$severity, levels=c("None", "D0", "D1", "D2", "D3"))

#png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/k=12_boxplots_redo/k=12_drought_category_deviations_box.png", height=6, width=12, units="in", res=320)
ggplot(data=grow_merge)+ #boxplots by drought category for each LC type
  geom_boxplot(aes(x=percentage, y=deviation, fill=severity)) + ylab("NDVI Anomaly") + xlab("> 50% Coverage") +
  scale_fill_manual(name="Category", values=c("None"="gray50", "D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))+
  facet_wrap(~type)+
  geom_hline(yintercept=0, linetype="dashed")+
  ylim(-0.2,0.2) + theme_bw(10)
ggsave("k=12_drought_category_deviations_box.png", path = pathShare, height=6, width=12, units="in", dpi = 320)
#dev.off()

#png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/k=12_boxplots_redo/k=12_deviation_LCtype_redo.png", height=6, width=12, units="in", res=320)
grow_merge$type <- factor(grow_merge$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
ggplot(data=grow_merge) + ylab("NDVI Anomaly") + xlab("> 50% Coverage") + #boxplots by LC type for each drought category
  geom_boxplot(aes(x=percentage, y=deviation, fill=type)) +
  scale_fill_manual(name="Type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  facet_wrap(~severity)+
  geom_hline(yintercept=0, linetype="dashed")+
  ylim(-0.2,0.2) + theme_bw(10)
ggsave("k=12_boxplots_redo/k=12_deviation_LCtype_redo.png", path = pathShare, height=6, width=12, units="in", dpi = 320)
#dev.off()

######################
#tukey matrix function https://rdrr.io/github/PhilippJanitza/rootdetectR/man/tukey_to_matrix.html
######################

tukey_to_matrix <- function(tukeyHSD_output) {
  if (!is.data.frame(tukeyHSD_output)) {
    tukeyHSD_output <- as.data.frame(tukeyHSD_output)
  }
  
  temp <- data.frame(name = rownames(tukeyHSD_output), p.val = tukeyHSD_output$`p adj`)
  
  temp_new <- tidyr::separate(temp, "name", into = c("V1", "V2"), sep = "-")
  labs <- sort(unique(c(temp_new$V1, temp_new$V2)))
  nr_labs <- length(labs)
  # create empty matrix
  mat <- matrix(NA, nrow = nr_labs, ncol = nr_labs)
  colnames(mat) <- labs
  rownames(mat) <- labs
  
  
  for (j in 1:(nr_labs - 1)) {
    for (k in (j + 1):nr_labs) {
      # get p-values and put them into the matrix
      idx <- which(paste(labs[j], "-", labs[k], sep = "") == temp$name)
      if (length(idx) == 0) {
        idx <- which(paste(labs[k], "-", labs[j], sep = "") == temp$name)
      }
      if (length(idx) != 0) {
        mat[j, k] <- temp[idx, 2]
      }
    }
  }
  return(mat)
}

######################
#tukey significance letters https://rdrr.io/github/PhilippJanitza/rootdetectR/man/tukey_to_matrix.html
######################

get_sig_letters <- function(tukmatrix) {
  # get Letters for twofacaov output
  mat_names <- character()
  mat_values <- numeric()
  # loop over matrix and get names + values
  for (j in 1:(length(row.names(tukmatrix)) - 1)) {
    for (k in (j + 1):length(colnames(tukmatrix))) {
      v <- tukmatrix[j, k]
      t <- paste(row.names(tukmatrix)[j],
                 colnames(tukmatrix)[k],
                 sep = "-"
      )
      mat_names <- c(mat_names, t)
      mat_values <- c(mat_values, v)
    }
  }
  
  # combine names + values
  names(mat_values) <- mat_names
  # get df with letters and replace : with label delim!!
  letters <-
    data.frame(multcompView::multcompLetters(mat_values)["Letters"])
  
  return(letters)
}

######################
#anovas by LC type
######################
summary(grow_merge)
grow_merge <- grow_merge[!is.na(grow_merge$yday),]
# summary(grow_merge[!is.na(grow_merge$yday),])

#grow_merge$severity <- as.factor(grow_merge$severity, levels=c("0", "D0", "D1", "D2", "D3"))
anovUrbLow <- lm(deviation~ severity, data=grow_merge[grow_merge$type=="urban-low",])
anova(anovUrbLow)
summary(anovUrbLow)
urblow <- aov(anovUrbLow)

anovcrop <- lm(deviation~ severity, data=grow_merge[grow_merge$type=="crop",])
anova(anovcrop)
summary(anovcrop)
crop <- aov(anovcrop)

anovForest <- lm(deviation~ severity, data=grow_merge[grow_merge$type=="forest",])
anova(anovForest)
summary(anovForest)
forest <- aov(anovForest)

anovgrass <- lm(deviation~ severity, data=grow_merge[grow_merge$type=="grassland",])
anova(anovgrass)
summary(anovgrass)
grass <- aov(anovgrass)

anovurbmed <- lm(deviation~ severity, data=grow_merge[grow_merge$type=="urban-medium",])
anova(anovurbmed)
summary(anovurbmed)
urbmed <- aov(anovurbmed)

anovurbhi <- lm(deviation~ severity, data=grow_merge[grow_merge$type=="urban-high",])
anova(anovurbhi)
summary(anovurbhi)
urbhi <- aov(anovurbhi)

anovurbop <- lm(deviation~ severity, data=grow_merge[grow_merge$type=="urban-open",])
anova(anovurbop)
summary(anovurbop)
urbop <- aov(anovurbop)

grow_merge_type <- group_by(grow_merge, type, severity)
grow_merge_sum <- grow_merge_type %>% summarise(meandev=mean(deviation),sd=sd(deviation))

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

png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/k=12_boxplots_redo/k=12_tukey_category.png",height=6, width=6, units="in", res=320)
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
#Tukey letter annotation
######################
cropletters <- multcompLetters4(crop, tukeycrop)
cropletters <- as.data.frame.list(cropletters$severity)
forestletters <- multcompLetters4(forest, tukeyforest)
forestletters <- as.data.frame.list(forestletters$severity)
grassletters <- multcompLetters4(grass, tukeygrass)
grassletters <- as.data.frame.list(grassletters$severity)
urbopletters <- multcompLetters4(urbop, tukeyurbop)
urbopletters <- as.data.frame.list(urbopletters$severity)
urblowletters <- multcompLetters4(urblow, tukeyurblow)
urblowletters <- as.data.frame.list(urblowletters$severity)
urbmedletters <- multcompLetters4(urbmed, tukeyurbmed)
urbmedletters <- as.data.frame.list(urbmedletters$severity)
urbhiletters <- multcompLetters4(urbhi, tukeyurbhi)
urbhiletters <- as.data.frame.list(urbhiletters$severity)

forestletters2 = c("a","b","b","ab","ab")
letter_annotation <-rbind(cropletters$Letters, forestletters$Letters, grassletters$Letters, urbopletters$Letters, urblowletters$Letters, urbmedletters$Letters, urbhiletters$Letters)
letter_list <- c(cropletters$Letters,forestletters2, grassletters$Letters, urbopletters$Letters, urblowletters$Letters, urbmedletters$Letters, urbhiletters$Letters)
grow_merge_sum$Tukey <- letter_list

ggplot()+
  geom_boxplot(data=grow_merge, aes(x=type, y=deviation, fill=type)) +
  ylab("NDVI Anomaly") + xlab("> 50% Coverage")+
  geom_text(data=grow_merge_sum, aes(label=Tukey, x=type,y=meandev+sd),size = 3, vjust=-3, hjust =-1)+
  scale_fill_manual(name="Type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  facet_wrap(~severity)+
  geom_hline(yintercept=0, linetype="dashed")+
  ylim(-0.2,0.2) + theme_bw(10)+theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())

ggplot()+ #boxplots by drought category for each LC type
  geom_boxplot(data=grow_merge,aes(x=severity, y=deviation, fill=severity)) + ylab("NDVI Anomaly") + xlab("> 50% Coverage") +
  scale_fill_manual(name="Category", values=c("None"="gray50", "D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))+
  geom_text(data=grow_merge_sum, aes(label=Tukey, x=severity,y=meandev+sd),size = 3, vjust=-2, hjust =-1)+
  facet_wrap(~type)+
  geom_hline(yintercept=0, linetype="dashed")+
  ylim(-0.2,0.2) + theme_bw(10) +  theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())

######################
#anovas by drought category
######################
grow_merge2 <- grow_merge
grow_merge2$type <- gsub("-", "", grow_merge2$type)

anovnone <- lm(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="None",])
anova(anovnone)
summary(anovnone)
none <- aov(anovnone)

anovd0 <- lm(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="D0",])
anova(anovd0)
summary(anovd0)
d0 <- aov(anovd0)

anovd1 <- lm(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="D1",])
anova(anovd1)
summary(anovd1)
d1 <- aov(anovd1)

anovd2 <- lm(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="D2",])
anova(anovd2)
summary(anovd2)
d2 <- aov(anovd2)

anovd3 <- lm(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="D3",])
anova(anovd3)
summary(anovd3)
d3 <- aov(anovd3)

grow_merge_sev <- group_by(grow_merge, severity, type)
grow_merge_sum <- grow_merge_sev %>% summarise(meandev=mean(deviation),sd=sd(deviation))


######################
#Tukey tests by drought category
######################
tukeynone <- TukeyHSD(none, conf.level = 0.95)
tukeyd0 <- TukeyHSD(d0, conf.level = 0.95)
tukeyd1 <- TukeyHSD(d1, conf.level = 0.95)
tukeyd2 <- TukeyHSD(d2, conf.level = 0.95)
tukeyd3 <- TukeyHSD(d3, conf.level = 0.95)

noneletters <- multcompLetters4(none, tukeynone)
noneletters <- as.data.frame.list(noneletters$type)
d0letters <- multcompLetters4(d0, tukeyd0)
d0letters <- as.data.frame.list(d0letters$type)
d1letters <- multcompLetters4(d1, tukeyd1)
d1letters <- as.data.frame.list(d1letters$type)
d2letters <- multcompLetters4(d2, tukeyd2)
d2letters <- as.data.frame.list(d2letters$type)
d3letters <- multcompLetters4(d3, tukeyd3)
d3letters <- as.data.frame.list(d3letters$type)

sevletters <- c("a","a","a","a","a","a","a", "ab","ab","b","b","ab","ab","a","a","a","b","b","b","ab","a","a","ab","c","c","c","bc","ab","a","ab","c","c","c","c","b")
grow_merge_sum$Tukey <- sevletters

ggplot()+ #boxplots by drought category for each LC type
  geom_boxplot(data=grow_merge,aes(x=severity, y=deviation, fill=severity)) + ylab("NDVI Anomaly") + xlab("> 50% Coverage") +
  scale_fill_manual(name="Category", values=c("None"="gray50", "D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))+
  geom_text(data=grow_merge_sum, aes(label=Tukey, x=severity,y=meandev+sd),size = 3, vjust=-2, hjust =-1)+
  facet_wrap(~type)+
  geom_hline(yintercept=0, linetype="dashed")+
  ylim(-0.2,0.2) + theme_bw(10) +  theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())


png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/k=12_boxplots_redo/k=12_tukey_LC.png",height=6, width=12, units="in", res=320)
par(mfrow=c(2,3), col.main="black", mar=c(4,12,4,4))
plot(tukeynone, las=1) + title(main='none', col.main="red", line=0.6)
plot(tukeyd0, las=1) + title(main ='D0', col.main="red",line=0.6)
plot(tukeyd1, las=1) + title(main ='D1', col.main="red",line=0.6)
plot(tukeyd2, las=1) + title(main ='D2', col.main="red",line=0.6)
plot(tukeyd3, las=1) + title(main ='D3', col.main="red",line=0.6)
dev.off()
######################
#adding random effect of date
######################

# library(nlme)
# anovnoneLME <- lme(deviation~ type -1, random=list(date=~1),data=grow_merge[grow_merge$severity=="None",])
# anova.lme(anovnoneLME)
# summary(anovnoneLME)
# noneLME <- anova.lme(anovnoneLME)
# TukeyHSD(noneLME, conf.level = 0.95)
# #anovForestLME <- lme(deviation~ severity, random=list(year=~1), data=grow_merge[grow_merge$type=="forest",])
# #anova(anovForestLME)
# #summary(anovForestLME)
# lmeAll <- lme(deviation~ severity, random=list(year=~1, type=~1), data=grow_merge)
# anova(lmeAll)
# summary(lmeAll)

######################
#raincloud plot
######################
#grow_merge$severity <- as.factor(grow_merge$severity)
png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/k=12_boxplots_redo/k=12_raincloud_LCtype.png",height=6, width=12, units="in", res=320)
ggplot(data=grow_merge, aes(x=severity, y=deviation, fill=severity))+
  facet_wrap(~type)+
  stat_halfeye(.width = 0,justification=-0.2) + ylim(-0.2,0.2)+ xlab("category")+ geom_boxplot(width=0.2,outlier.colour = NA)+
  #stat_dots(side="left", justification=1.2,color=NA)+
  scale_fill_manual(name="Category", values=c("None"="gray50", "D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))+
  coord_flip() #+ ggtitle()
dev.off()
######################
#ridgeline plot
######################
library(ggridges)
png("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/k=12_boxplots_redo/k=12_ridgeline_drought_category.png",height=6, width=6, units="in", res=320)
ggplot(data=grow_merge, aes(x=deviation, y=type, fill=type))+
  facet_wrap(~severity)+
  geom_density_ridges()+
  scale_fill_manual(name="Type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  xlim(-0.2,0.2)+
  geom_vline(xintercept=0,linetype="dashed")+
  scale_y_discrete(limits=rev)
dev.off()

######################
#ANOVA (NDVIanom ~ LC x severity)
######################
grow_merge2 <- grow_merge
grow_merge2$type <- gsub("-", "", grow_merge2$type)

anovlc <- aov(deviation ~ type*severity, data=grow_merge2)
summary(anovlc)

grow_sum <- group_by(grow_merge, type, severity) %>% 
  summarise(mean_anom=mean(deviation),sd=sd(deviation))

tukeylc <- TukeyHSD(anovlc, conf.level=0.95)

tukey_letters <- multcompLetters4(anovlc, tukeylc)
tukey_letters <- as.data.frame.list(tukey_letters$`type:severity`)
tukey_letters_ordered <- tukey_letters[c(6,11,14,16,22,5,9,15,20,10,3,18,26,30,33,1,19,27,31,35,2,17,24,29,34,4,12,23,28,32,7,8,13,21,25),]

grow_sum$Tukey <- tukey_letters_ordered$Letters

ggplot()+ #boxplots by drought category for each LC type
  geom_boxplot(data=grow_merge,aes(x=severity, y=deviation, fill=severity)) + ylab("NDVI Anomaly") + xlab("> 50% Coverage") +
  scale_fill_manual(name="Category", values=c("None"="gray50", "D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))+
  geom_text(data=grow_sum, aes(label=Tukey, x=severity,y=mean_anom+sd),position=position_dodge2(0.75),size = 3, vjust=-3)+
  facet_wrap(~type)+
  geom_hline(yintercept=0, linetype="dashed")+
  ylim(-0.2,0.2) + theme_bw(10) +  theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())
ggsave("2-way_anova_boxplot.png", path = "~/Downloads", height=6, width=12, units="in", dpi = 320)

ggplot() + ylab("NDVI Anomaly") + xlab("> 50% Coverage") + #boxplots by LC type for each drought category
  geom_boxplot(data=grow_merge, aes(x=type, y=deviation, fill=type)) +
  geom_text(data=grow_sum, aes(label=Tukey, x=type,y=mean_anom+sd),position=position_dodge2(0.75),size = 3, vjust=-3)+
  scale_fill_manual(name="Type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  facet_wrap(~severity)+
  geom_hline(yintercept=0, linetype="dashed")+
  ylim(-0.2,0.2) + theme_bw(10) + theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())
ggsave("2-way_anova_boxplot_alt.png", path = "~/Downloads", height=6, width=12, units="in", dpi = 320)