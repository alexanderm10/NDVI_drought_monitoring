library(ggplot2)
library(cowplot)
library(dplyr)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/figures")
pathShare3 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/ESA_2025_NDVI_Monitoring_Poster")

# load data ---------------------------------------------------------------

yrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_individual_years_post_GAM_with_forest-wet.csv")) #individual years
yrs <- yrs[yrs$type!="forest",]
yrs$type[yrs$type=="forest-wet"] <- "forest"
yrs$type <- factor(yrs$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_norms_all_LC_types_with_wet-forest.csv")) #normals
norms <- norms[norms$type!="forest",]
norms$type[norms$type=="forest-wet"] <- "forest"
norms$type <- factor(norms$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

yrsderivs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_individual_years_derivs_GAM_with_forest-wet.csv")) #individual years derivatives
yrsderivs <- yrsderivs[yrsderivs$type!="forest",]
yrsderivs$type[yrsderivs$type=="forest-wet"] <- "forest"
yrsderivs$type <- factor(yrsderivs$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

normsderivs <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_norms_derivatives_with_forest-wet.csv")) #normals derivatives
normsderivs <- normsderivs[normsderivs$type!="forest",]
normsderivs$type[normsderivs$type=="forest-wet"] <- "forest"
normsderivs$type <- factor(normsderivs$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

yrs_merge <- yrs %>% inner_join(norms, by= c("type", "yday"), suffix = c("_yrs", "_norm")) 
yrs_merge$mean_anoms <- yrs_merge$mean_yrs - yrs_merge$mean_norm
yrs_merge$upr_anoms <- yrs_merge$upr_yrs - yrs_merge$mean_norm
yrs_merge$lwr_anoms <- yrs_merge$lwr_yrs - yrs_merge$mean_norm

yrsderivs_merge <- yrsderivs %>% inner_join(normsderivs, by= c("type", "yday"), suffix = c("_yrs", "_norm")) 
yrsderivs_merge$mean_anoms <- yrsderivs_merge$mean_yrs - yrsderivs_merge$mean_norm
yrsderivs_merge$upr_anoms <- yrsderivs_merge$upr_yrs - yrsderivs_merge$mean_norm
yrsderivs_merge$lwr_anoms <- yrsderivs_merge$lwr_yrs - yrsderivs_merge$mean_norm
yrsderivs_merge <- yrsderivs_merge[, !names(yrsderivs_merge) %in% c("sig_yrs", "var_yrs", "sig_norm", "var_norm", "mean_yrs", "upr_yrs","lwr_yrs")]

grow_dates <- read.csv(file.path(google.drive, "Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/tables/growing_season_dates_table.csv"))
grow_dates$yday_start <- lubridate::yday(as.Date(grow_dates$start, format="%b %d"))
grow_dates$yday_end <- lubridate::yday(as.Date(grow_dates$end, format="%b %d"))

# plot --------------------------------------------------------------------
day.labels <- data.frame(Date=seq.Date(as.Date("2023-01-01"), as.Date("2023-12-01"), by="month"))
day.labels$yday <- lubridate::yday(day.labels$Date)
day.labels$Text <- paste(lubridate::month(day.labels$Date, label=T), lubridate::day(day.labels$Date))
day.labels
summary(day.labels)

grow_dates <- grow_dates[grow_dates$type=="urban-low",]
yrs_merge <- yrs_merge[yrs_merge$type=="urban-low",]
yrsderivs_merge <- yrsderivs_merge[yrsderivs_merge$type=="urban-low",]

p1 <- ggplot()+
  geom_rect(data=grow_dates, aes(xmin=yday_start, xmax=yday_end,ymin=-Inf,ymax=Inf), fill="lightblue", alpha= 0.3)+
  geom_line(data=yrs_merge, aes(x=yday, y=mean_norm,color="normal"))+
  geom_ribbon(data=yrs_merge, aes(x=yday, ymin=lwr_norm, ymax=upr_norm,fill="normal"), alpha=0.2) +
  geom_line(data=yrs_merge[yrs_merge$year %in% c(2005,2012,2023),], aes(x=yday,y=mean_yrs,color=as.factor(year)))+
  geom_ribbon(data=yrs_merge[yrs_merge$year %in% c(2005,2012,2023),], aes(x=yday, ymin=lwr_yrs, ymax=upr_yrs, fill=as.factor(year)), alpha=0.2) +
  scale_color_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  ylim(0,1)+ 
  scale_x_continuous(name="day of year", expand=c(0,0), breaks=day.labels$yday[seq(2, 12, by=3)], labels=day.labels$Text[seq(2, 12, by=3)])+
  theme_bw(20)+
  ylab("NDVI") +ggtitle("NDVI") 
p1 <- p1 + theme(legend.position = "none", plot.title = element_text(vjust=-1))

p2 <- ggplot()+
  geom_rect(data=grow_dates, aes(xmin=yday_start, xmax=yday_end,ymin=-Inf,ymax=Inf), fill="lightblue", alpha= 0.3)+
  geom_line(data=yrs_merge[yrs_merge$year %in% c(2005,2012,2023),], aes(x=yday,y=mean_anoms,color=as.factor(year)))+
  geom_ribbon(data=yrs_merge[yrs_merge$year %in% c(2005,2012,2023),], aes(x=yday, ymin=lwr_anoms, ymax=upr_anoms, fill=as.factor(year)), alpha=0.2) +
  scale_color_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  geom_hline(yintercept=0, linetype="dotted")+
  ylim(-0.3,0.3)+ 
  scale_x_continuous(name="day of year", expand=c(0,0), breaks=day.labels$yday[seq(2, 12, by=3)], labels=day.labels$Text[seq(2, 12, by=3)])+
  theme_bw(20)+
  ylab("NDVI anomaly") + ggtitle("Anomalies")
p2 <- p2 + theme(legend.position = "none", plot.title = element_text(vjust=-1))

p3 <- ggplot()+
  geom_rect(data=grow_dates, aes(xmin=yday_start, xmax=yday_end,ymin=-Inf,ymax=Inf), fill="lightblue", alpha= 0.3)+
  geom_line(data=yrsderivs_merge[yrsderivs_merge$year %in% c(2005,2012,2023),], aes(x=yday,y=mean_anoms,color=as.factor(year)))+
  geom_ribbon(data=yrsderivs_merge[yrsderivs_merge$year %in% c(2005,2012,2023),], aes(x=yday, ymin=lwr_anoms, ymax=upr_anoms, fill=as.factor(year)), alpha=0.2) +
  scale_color_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  geom_hline(yintercept=0, linetype="dotted")+
  ylim(-0.02,0.02)+ 
  scale_x_continuous(name="day of year", expand=c(0,0), breaks=day.labels$yday[seq(2, 12, by=3)], labels=day.labels$Text[seq(2, 12, by=3)])+
  theme_bw(20)+
  ylab("NDVI derivative anomaly") +ggtitle("Derivative Anomalies")
p3 <- p3 + theme(plot.title = element_text(vjust=-1))


ggpubr::ggarrange(
  p1, p2, p3, # list of plots
  #labels = c("Years", "Anomalies", "Derivative Anomalies"), # labels
  vjust=0.4,
  common.legend = TRUE, # COMMON LEGEND
  legend = "bottom", # legend position
  align = "hv", # Align them both, horizontal and vertical
  nrow = 1 # number of rows
) #+ theme(plot.margin = margin(0.2,0.05,0.05,0.05, "in")) 

ggsave("NDVI_anoms_panels_poster_figure_2.png", path = pathShare3, height=6, width=18, units="in", dpi = 320)
