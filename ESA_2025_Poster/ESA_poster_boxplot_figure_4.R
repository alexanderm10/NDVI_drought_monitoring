library(ggplot2)
library(tidyr)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/figures")
pathShare2 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/tables")
pathShare3 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/ESA_2025_NDVI_Monitoring_Poster")

# load data ---------------------------------------------------------------

grow_merge <-read.csv(file.path(google.drive, "Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/ESA_2025_NDVI_Monitoring_Poster/growing_season_USDM_data_boxplot.csv"))
grow_merge$type <- factor(grow_merge$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
grow_merge$severity <- factor(grow_merge$severity, levels=c("None", "D0", "D1", "D2", "D3"))

grow_sum <-read.csv(file.path(google.drive, "Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/tables/boxplot_anomalies_tukey_table.csv"))
grow_sum$type <- factor(grow_sum$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

# plot --------------------------------------------------------------------

ggplot()+ #boxplots by drought category for each LC type
  geom_boxplot(data=grow_merge[grow_merge$type!="grassland",],aes(x=severity, y=deviation, fill=severity)) + ylab("NDVI Anomaly") + xlab(NULL) +
  scale_fill_manual(name="USDM Drought Severity", values=c("None"="gray50", "D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))+
  geom_text(data=grow_sum[grow_sum$type!="grassland",], aes(label=Tukey1, x=severity,y=mean_anom+sd),size = 3, vjust=-2, hjust =-1)+
  geom_text(data=grow_sum[grow_sum$type!="grassland",], aes(label=Tukey2, x=severity,y=mean_anom-sd),size = 3, vjust=2, hjust =-1)+
  facet_wrap(~type)+
  geom_hline(yintercept=0, linetype="dashed")+
  labs(caption = "lowercase = effect of drought severity on NDVI anomalies within a given land cover class \nuppercase = effect of land cover type on NDVI anomalies within a given drought category") +
  ylim(-0.2,0.2) + theme_bw(20) + theme(axis.text.x = element_blank(), axis.ticks.x = element_blank(),plot.caption.position="plot",
                                        plot.caption = element_text(hjust=0,vjust=0.5),plot.margin = margin(5.5,5.5,20,5.5,"pt"))

ggsave("NDVI_anoms_boxplot_poster.png", path = pathShare3, height=6, width=12, units="in", dpi = 320)

