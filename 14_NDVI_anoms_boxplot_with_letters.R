library(ggplot2)
library(tidyr)
library(multcompView)
library(stringr)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/figures")
pathShare2 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/tables")

######################

usdmcum <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/USDM_county_data_2001-2024.csv")) #usdm chicago region cumulative data
#grow_norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_growing_season_norms.csv")) #normals
#growyrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_growing_season_yrs.csv")) #individual years

grow_norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_growing_season_norms_with_forest-wet.csv")) #normals
growyrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_growing_season_yrs_with_forest-wet.csv")) #individual years

######################
#weights by county
######################
#https://datahub.cmap.illinois.gov/datasets/a5d89f35ccc54018b690683b49be1ac7_0/explore?location=41.838395%2C-88.115001%2C9.16

# will <- 3917450609.094
# kendall <- 1494102678.262
# cook <- 4472919440.23
# dupage <- 1571636669.879
# kane <- 2454958976.102
# lake <- 2231222407.188
# mchenry <- 2897036640.547

coArea <- c(3917450609.094, 1494102678.262, 4472919440.23, 1571636669.879, 2454958976.102, 2231222407.188, 2897036640.547)
names(coArea) <- c("Will County","Kendall County","Cook County","DuPage County","Kane County","Lake County","McHenry County")
coWeights <- coArea/sum(coArea)

usdmcum$County <- factor(usdmcum$County, levels = c("Will County","Kendall County","Cook County","DuPage County","Kane County","Lake County","McHenry County"))
usdm_county <- data.frame()
for (county in unique(usdmcum$County)){
  usdmInd <- usdmcum[usdmcum$County==county,]
  usdmInd$None <- usdmInd$None*coWeights[county]
  usdmInd$D0 <- usdmInd$D0*coWeights[county]
  usdmInd$D1 <- usdmInd$D1*coWeights[county]
  usdmInd$D2 <- usdmInd$D2*coWeights[county]
  usdmInd$D3 <- usdmInd$D3*coWeights[county]
  usdmInd$D4 <- usdmInd$D4*coWeights[county]
  usdm_county <- rbind(usdm_county, usdmInd)
}

usdmcum <- usdm_county %>% group_by(ValidStart, ValidEnd) %>%
  summarise_at(vars(None, D0, D1, D2, D3, D4),
               sum) %>%
  ungroup()

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

grow_merge <- grow_merge[grow_merge$type!="forest",]
grow_merge$type[grow_merge$type=="forest-wet"] <- "forest"
grow_merge$type <- factor(grow_merge$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
#grow_merge$type <- factor(grow_merge$type, levels = c("crop", "forest", "forest-wet","grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

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

# anovForestwet <- aov(deviation~ severity, data=grow_merge[grow_merge$type=="forest-wet",])
# tukeyforestwet <- TukeyHSD(anovForestwet, conf.level=0.95)
# forestwetletters <- multcompLetters4(anovForestwet, tukeyforestwet)
# forestwetletters <- as.data.frame.list(forestwetletters$severity)

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

letter_list <- c(cropletters$Letters,forestletters$Letters, grassletters$Letters, urbopletters$Letters, urblowletters$Letters, urbmedletters$Letters, urbhiletters$Letters)
grow_sum$Tukey1 <- letter_list

######################
#anovas/Tukey by USDM category
######################

grow_merge2 <- grow_merge
grow_merge2$type <- gsub("-", "", grow_merge2$type)

anovnone <- aov(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="None",])
tukeynone <- TukeyHSD(anovnone, conf.level = 0.95)
noneletters <- multcompLetters4(anovnone, tukeynone)
noneletters <- as.data.frame.list(noneletters$type)
noneletters <- noneletters["Letters"]
noneletters$severity <- "None"
noneletters <- rownames_to_column(noneletters, "type")

anovd0 <- aov(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="D0",])
tukeyd0 <- TukeyHSD(anovd0, conf.level = 0.95)
d0letters <- multcompLetters4(anovd0, tukeyd0)
d0letters <- as.data.frame.list(d0letters$type)
d0letters <- d0letters["Letters"]
d0letters$severity <- "D0"
d0letters <- rownames_to_column(d0letters, "type")

anovd1 <- aov(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="D1",])
tukeyd1 <- TukeyHSD(anovd1, conf.level = 0.95)
d1letters <- multcompLetters4(anovd1, tukeyd1)
d1letters <- as.data.frame.list(d1letters$type)
d1letters <- d1letters["Letters"]
d1letters$severity <- "D1"
d1letters <- rownames_to_column(d1letters, "type")

anovd2 <- aov(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="D2",])
tukeyd2 <- TukeyHSD(anovd2, conf.level = 0.95)
d2letters <- multcompLetters4(anovd2, tukeyd2)
d2letters <- as.data.frame.list(d2letters$type)
d2letters <- d2letters["Letters"]
d2letters$severity <- "D2"
d2letters <- rownames_to_column(d2letters, "type")

anovd3 <- aov(deviation~ type -1, data=grow_merge2[grow_merge2$severity=="D3",])
tukeyd3 <- TukeyHSD(anovd3, conf.level = 0.95)
d3letters <- multcompLetters4(anovd3, tukeyd3)
d3letters <- as.data.frame.list(d3letters$type)
d3letters <- d3letters["Letters"]
d3letters$severity <- "D3"
d3letters <- rownames_to_column(d3letters, "type")

sev_letters <- rbind(noneletters, d0letters, d1letters, d2letters, d3letters)
sev_letters$Letters <- toupper(sev_letters$Letters)
sev_letters$type <- str_replace(sev_letters$type, "^urban", "urban-")
# grow_merge_sev <- group_by(grow_merge, severity, type) %>%
#   summarise(meandev=mean(deviation),sd=sd(deviation))

grow_sum <- grow_sum %>% inner_join(sev_letters, by=c("type", "severity"))
grow_sum <- grow_sum %>% rename(Tukey2 = Letters)
grow_sum$type <- factor(grow_sum$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

write.csv(grow_sum, file.path(pathShare2, "boxplot_anomalies_tukey_table.csv"), row.names=F)

######################
#boxplot
######################

ggplot()+ #boxplots by drought category for each LC type
  geom_boxplot(data=grow_merge,aes(x=severity, y=deviation, fill=severity)) + ylab("NDVI Anomaly") + xlab("> 50% Coverage") +
  scale_fill_manual(name="Category", values=c("None"="gray50", "D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))+
  geom_text(data=grow_sum, aes(label=Tukey1, x=severity,y=mean_anom+sd),size = 3, vjust=-2, hjust =-1)+
  geom_text(data=grow_sum, aes(label=Tukey2, x=severity,y=mean_anom-sd),size = 3, vjust=2, hjust =-1)+
  facet_wrap(~type)+
  geom_hline(yintercept=0, linetype="dashed")+
  labs(caption = "lowercase = drought category within land cover class \n uppercase = drought category across classes") +
  ylim(-0.2,0.2) + theme_bw(15) + theme(axis.text.x = element_blank(), axis.ticks.x = element_blank(),plot.caption.position="plot",
                                        plot.caption = element_text(hjust=0,vjust=0.5),plot.margin = margin(5.5,5.5,20,5.5,"pt"))

ggsave("NDVI_anoms_boxplot_with_letters_wet-forest.png", path = pathShare, height=6, width=12, units="in", dpi = 320)
