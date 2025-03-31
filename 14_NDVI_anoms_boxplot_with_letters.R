library(ggplot2)
library(tidyr)
library(multcompView)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/figures")

######################

usdmcum <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/cumulative_dm_export_20010101_20241231.csv")) #usdm chicago region cumulative data
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
#subset data to 50% or above in category
######################

grow_merge <- grow_merge[grow_merge$percentage>50,]
grow_merge <- grow_merge[!is.na(grow_merge$yday),]
grow_merge$severity <- factor(grow_merge$severity, levels=c("None", "D0", "D1", "D2", "D3"))
grow_merge$type <- factor(grow_merge$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

######################
#anovas/Tukey by LC type
######################

anovUrbLow <- aov(deviation~ severity, data=grow_merge[grow_merge$type=="urban-low",])
tukeyurblow <- TukeyHSD(anovUrbLow, conf.level=0.95)
urblowletters <- multcompLetters4(anovUrbLow, tukeyurblow)
urblowletters <- as.data.frame.list(urblowletters$severity)

anovcrop <- aov(deviation~ severity, data=grow_merge[grow_merge$type=="crop",])
tukeycrop <- TukeyHSD(anovcrop, conf.level=0.95)
cropletters <- multcompLetters4(anovcrop, tukeycrop)
cropletters <- as.data.frame.list(cropletters$severity)

anovForest <- aov(deviation~ severity, data=grow_merge[grow_merge$type=="forest",])
tukeyforest <- TukeyHSD(anovForest, conf.level=0.95)
forestletters <- multcompLetters4(anovForest, tukeyforest)
forestletters <- as.data.frame.list(forestletters$severity)
forestletters2 = c("a","b","b","ab","ab")

anovgrass <- aov(deviation~ severity, data=grow_merge[grow_merge$type=="grassland",])
tukeygrass <- TukeyHSD(anovgrass, conf.level=0.95)
grassletters <- multcompLetters4(anovgrass, tukeygrass)
grassletters <- as.data.frame.list(grassletters$severity)

anovurbmed <- aov(deviation~ severity, data=grow_merge[grow_merge$type=="urban-medium",])
tukeyurbmed <- TukeyHSD(anovurbmed, conf.level=0.95)
urbmedletters <- multcompLetters4(anovurbmed, tukeyurbmed)
urbmedletters <- as.data.frame.list(urbmedletters$severity)

anovurbhi <- aov(deviation~ severity, data=grow_merge[grow_merge$type=="urban-high",])
tukeyurbhi <- TukeyHSD(anovurbhi, conf.level=0.95)
urbhiletters <- multcompLetters4(anovurbhi, tukeyurbhi)
urbhiletters <- as.data.frame.list(urbhiletters$severity)

anovurbop <- aov(deviation~ severity, data=grow_merge[grow_merge$type=="urban-open",])
tukeyurbop <- TukeyHSD(anovurbop, conf.level=0.95)
urbopletters <- multcompLetters4(anovurbop, tukeyurbop)
urbopletters <- as.data.frame.list(urbopletters$severity)

grow_sum <- group_by(grow_merge, type, severity) %>% 
  summarise(mean_anom=mean(deviation),sd=sd(deviation))

letter_list <- c(cropletters$Letters,forestletters2, grassletters$Letters, urbopletters$Letters, urblowletters$Letters, urbmedletters$Letters, urbhiletters$Letters)
grow_sum$Tukey <- letter_list

######################
#anovas/Tukey by USDM category
######################

grow_merge2 <- grow_merge
grow_merge2$type <- gsub("-", "", grow_merge2$type)

anovnone <- aov(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="None",])
tukeynone <- TukeyHSD(anovnone, conf.level = 0.95)
noneletters <- multcompLetters4(anovnone, tukeynone)
noneletters <- as.data.frame.list(noneletters$type)

anovd0 <- aov(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="D0",])
tukeyd0 <- TukeyHSD(anovd0, conf.level = 0.95)
d0letters <- multcompLetters4(anovd0, tukeyd0)
d0letters <- as.data.frame.list(d0letters$type)

anovd1 <- aov(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="D1",])
tukeyd1 <- TukeyHSD(anovd1, conf.level = 0.95)
d1letters <- multcompLetters4(anovd1, tukeyd1)
d1letters <- as.data.frame.list(d1letters$type)

anovd2 <- aov(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="D2",])
tukeyd2 <- TukeyHSD(anovd2, conf.level = 0.95)
d2letters <- multcompLetters4(anovd2, tukeyd2)
d2letters <- as.data.frame.list(d2letters$type)

anovd3 <- aov(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="D3",])
tukeyd3 <- TukeyHSD(anovd3, conf.level = 0.95)
d3letters <- multcompLetters4(anovd3, tukeyd3)
d3letters <- as.data.frame.list(d3letters$type)

#grow_merge_sev <- group_by(grow_merge, severity, type) %>%
  #summarise(meandev=mean(deviation),sd=sd(deviation))

sev_letters <- c("A","AB","A","A","AB","A","AB","A","AB","A","A","B","B","C","C","A","B","B","C","C","A","AB","B","C","C","A","AB","AB","BC","C","A","A","A","AB","B")
grow_sum$tukey2 <- sev_letters

ggplot()+ #boxplots by drought category for each LC type
  geom_boxplot(data=grow_merge,aes(x=severity, y=deviation, fill=severity)) + ylab("NDVI Anomaly") + xlab("> 50% Coverage") +
  scale_fill_manual(name="Category", values=c("None"="gray50", "D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))+
  geom_text(data=grow_sum, aes(label=Tukey, x=severity,y=mean_anom+sd),size = 3, vjust=-2, hjust =-1)+
  geom_text(data=grow_sum, aes(label=tukey2, x=severity,y=mean_anom-sd),size = 3, vjust=2, hjust =-1)+
  facet_wrap(~type)+
  geom_hline(yintercept=0, linetype="dashed")+
  labs(caption = "lowercase = drought category within land cover class \n uppercase = drought category across classes") +
  ylim(-0.2,0.2) + theme_bw(10) + theme(axis.text.x = element_blank(), axis.ticks.x = element_blank(),plot.caption.position="plot",
                                        plot.caption = element_text(hjust=0,vjust=0.5),plot.margin = margin(5.5,5.5,20,5.5,"pt"))
ggsave("NDVI_anoms_boxplot_with_letters.png", path = pathShare, height=6, width=12, units="in", dpi = 320)


#grid.arrange(p, bottom = textGrob("lowercase leters = within land cover class ", vjust=-5, hjust=-0.01))

