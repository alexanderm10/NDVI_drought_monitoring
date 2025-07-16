library(ggplot2)
library(cowplot)
library(dplyr)
library(tidyverse)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/figures")

######################

#yrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_individual_years_post_GAM.csv")) #individual years
#yrs$type <- factor(yrs$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

#norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_norms_all_LC_types.csv")) #normals
#norms$type <- factor(norms$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

#yrsderivs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_individual_years_derivs_GAM.csv")) #individual years derivatives
#normsderivs <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_norms_derivatives.csv")) #normals derivatives

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
#yrs_merge <- yrs_merge %>% pivot_longer(cols=c("mean_yrs","mean_anoms"), names_to =("graph type"), values_to = "mean")

yrsderivs_merge <- yrsderivs %>% inner_join(normsderivs, by= c("type", "yday"), suffix = c("_yrs", "_norm")) 
yrsderivs_merge$mean_anoms <- yrsderivs_merge$mean_yrs - yrsderivs_merge$mean_norm
yrsderivs_merge$upr_anoms <- yrsderivs_merge$upr_yrs - yrsderivs_merge$mean_norm
yrsderivs_merge$lwr_anoms <- yrsderivs_merge$lwr_yrs - yrsderivs_merge$mean_norm
yrsderivs_merge <- yrsderivs_merge[, !names(yrsderivs_merge) %in% c("sig_yrs", "var_yrs", "sig_norm", "var_norm", "mean_yrs", "upr_yrs","lwr_yrs")]

grow_dates <- read.csv(file.path(google.drive, "Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/tables/growing_season_dates_table.csv"))
grow_dates$yday_start <- lubridate::yday(as.Date(grow_dates$start, format="%b %d"))
grow_dates$yday_end <- lubridate::yday(as.Date(grow_dates$end, format="%b %d"))

df_full <- yrs_merge %>% inner_join(yrsderivs_merge, by=c("type", "yday", "year"), suffix=c("yrs", "deriv"))
df_full <- df_full %>% pivot_longer(cols=-c("yday","type", "year", "mean_normyrs", "lwr_normyrs", "upr_normyrs", "mean_normderiv", "lwr_normderiv", "upr_normderiv"), names_to = c("pos","graph_type"), names_sep = "_", values_to = "value")
df_full$graph_type[df_full$graph_type=="yrs"] <- "NDVI"
df_full$graph_type[df_full$graph_type=="anomsyrs"] <- "Anoms"
df_full$graph_type[df_full$graph_type=="anomsderiv"] <- "Deriv anoms"

dfNormDupe <- df_full[df_full$year==2013 & df_full$graph_type=="NDVI", c("yday", "type", "year",  "graph_type", "mean_normyrs", "lwr_normyrs", "upr_normyrs")]
dfNormDupe$year <- "normal"
names(dfNormDupe) <- c("yday", "type", "year", "graph_type", "mean", "lwr", "upr")

df_full2 <- rbind(df_full[,names(dfNormDupe)], dfNormDupe)
df_full2$graph_type <- factor(df_full2$graph_type, levels=c("NDVI", "Anoms", "Deriv anoms"))
dfHline <- data.frame(graph_type=c("NDVI", "Anoms", "Deriv anoms"), yint = c(NA, 0, 0))
dfHline$graph_type <- factor(dfHline$graph_type, levels=c("NDVI", "Anoms", "Deriv anoms"))


ggplot(data=df_full2[df_full2$year %in% c(2005, 2012, 2023, "normal"),]) +
  facet_grid(graph_type~type, scales="free_y") +
  geom_ribbon(aes(x=yday, ymin=lwr, ymax=upr, fill=year), alpha=0.5) +
  geom_line(aes(x=yday, y=mean, color=year)) +
  geom_hline(data=dfHline, aes(yintercept=yint), linetype="dashed", color="black")

ggplot(data=df_full2[df_full2$year %in% c(2005, 2012, 2023) & df_full2$graph_type %in% c("Anoms", "Deriv anoms"),]) +
  facet_grid(graph_type~year, scales="free_y") +
  geom_ribbon(aes(x=yday, ymin=lwr, ymax=upr, fill=type), alpha=0.5) +
  geom_line(aes(x=yday, y=mean, color=type)) +
  geom_hline(data=dfHline[dfHline$graph_type!="NDVI",], aes(yintercept=yint), linetype="dashed", color="black")


#df_full <- df_full %>% pivot_longer(cols=c("lwr_yrs_yrs","lwr_anoms_yrs", "lwr_anoms_deriv"), names_to = ("graph_type"), values_to = "lwr")

df_full <- df_full %>% pivot_wider(names_from = pos, values_from = value)

######################
day.labels <- data.frame(Date=seq.Date(as.Date("2023-01-01"), as.Date("2023-12-01"), by="month"))
day.labels$yday <- lubridate::yday(day.labels$Date)
day.labels$Text <- paste(lubridate::month(day.labels$Date, label=T), lubridate::day(day.labels$Date))
day.labels
summary(day.labels)


ggplot(data=df_full)+
  geom_rect(data=grow_dates, aes(xmin=yday_start, xmax=yday_end,ymin=-Inf,ymax=Inf), fill="lightblue", alpha= 0.3)+
  geom_line(data=df_full[df_full$year %in% c(2005,2012,2023),], aes(x=yday,y=mean,color=as.factor(year)))+
  geom_ribbon(data=df_full[df_full$year %in% c(2005,2012,2023),], aes(x=yday, ymin=lwr, ymax=upr, fill=as.factor(year)), alpha=0.2) +
  scale_color_manual(name="year", values=c("2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  facet_grid(graph_type~type, scale='free') +
  scale_x_continuous(name="Day of Year", expand=c(0,0), breaks=day.labels$yday[seq(2, 12, by=3)], labels=day.labels$Text[seq(2, 12, by=3)])+
  ylab("NDVI")+ theme_bw(15)
ggsave("raw_vs_harmonized_NDVI_mission_curves.png", path = pathShare, height=12, width=12, units="in", dpi = 320)





p1 <- ggplot()+
  geom_rect(data=grow_dates, aes(xmin=yday_start, xmax=yday_end,ymin=-Inf,ymax=Inf), fill="lightblue", alpha= 0.3)+
  geom_line(data=yrs_merge, aes(x=yday, y=mean_norm,color="normal"))+
  geom_ribbon(data=yrs_merge, aes(x=yday, ymin=lwr_norm, ymax=upr_norm,fill="normal"), alpha=0.2) +
  geom_line(data=yrs_merge[yrs_merge$year %in% c(2005,2012,2023),], aes(x=yday,y=mean_yrs,color=as.factor(year)))+
  geom_ribbon(data=yrs_merge[yrs_merge$year %in% c(2005,2012,2023),], aes(x=yday, ymin=lwr_yrs, ymax=upr_yrs, fill=as.factor(year)), alpha=0.2) +
  scale_color_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  facet_wrap(~type, ncol=7) + ylim(0,1)+ 
  scale_x_continuous(name="Day of Year", expand=c(0,0), breaks=day.labels$yday[seq(2, 12, by=3)], labels=day.labels$Text[seq(2, 12, by=3)])+
  theme_bw(11)+
  ylab("NDVI") #+ggtitle("Drought Years and Normal NDVI")+ 
p1 <- p1 + theme(legend.position = "none")

p2 <- ggplot()+
  #geom_line(data=yrs_merge, aes(x=yday, y=mean_norm,color="normal"))+
  #geom_ribbon(data=yrs_merge, aes(x=yday, ymin=lwr_norm, ymax=upr_norm,fill="normal"), alpha=0.2) +
  geom_rect(data=grow_dates, aes(xmin=yday_start, xmax=yday_end,ymin=-Inf,ymax=Inf), fill="lightblue", alpha= 0.3)+
  geom_line(data=yrs_merge[yrs_merge$year %in% c(2005,2012,2023),], aes(x=yday,y=mean_anoms,color=as.factor(year)))+
  geom_ribbon(data=yrs_merge[yrs_merge$year %in% c(2005,2012,2023),], aes(x=yday, ymin=lwr_anoms, ymax=upr_anoms, fill=as.factor(year)), alpha=0.2) +
  scale_color_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  geom_hline(yintercept=0, linetype="dotted")+
  facet_wrap(~type, ncol=7) + ylim(-0.3,0.3)+ 
  scale_x_continuous(name="Day of Year", expand=c(0,0), breaks=day.labels$yday[seq(2, 12, by=3)], labels=day.labels$Text[seq(2, 12, by=3)])+
  theme_bw(11)+
  ylab("NDVI Anomaly") #+ggtitle("Drought Years and Normal NDVI")+ 
p2 <- p2 + theme(legend.position = "none")

p3 <- ggplot()+
  #geom_line(data=yrs_merge, aes(x=yday, y=mean_norm,color="normal"))+
  #geom_ribbon(data=yrs_merge, aes(x=yday, ymin=lwr_norm, ymax=upr_norm,fill="normal"), alpha=0.2) +
  geom_rect(data=grow_dates, aes(xmin=yday_start, xmax=yday_end,ymin=-Inf,ymax=Inf), fill="lightblue", alpha= 0.3)+
  geom_line(data=yrsderivs_merge[yrsderivs_merge$year %in% c(2005,2012,2023),], aes(x=yday,y=mean_anoms,color=as.factor(year)))+
  geom_ribbon(data=yrsderivs_merge[yrsderivs_merge$year %in% c(2005,2012,2023),], aes(x=yday, ymin=lwr_anoms, ymax=upr_anoms, fill=as.factor(year)), alpha=0.2) +
  scale_color_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  geom_hline(yintercept=0, linetype="dotted")+
  facet_wrap(~type, ncol=7) + ylim(-0.02,0.02)+ 
  scale_x_continuous(name="Day of Year", expand=c(0,0), breaks=day.labels$yday[seq(2, 12, by=3)], labels=day.labels$Text[seq(2, 12, by=3)])+
  theme_bw(11)+
  ylab("NDVI Derivative Anomaly") #+ggtitle("Drought Years and Normal NDVI")+ 

ggpubr::ggarrange(
  p1, p2, p3, # list of plots
  labels = c("Years", "Anomalies", "Derivative Anomalies"), # labels
  vjust=0.4,
  common.legend = TRUE, # COMMON LEGEND
  legend = "bottom", # legend position
  align = "hv", # Align them both, horizontal and vertical
  nrow = 3 # number of rows
)
ggsave("NDVI_norms_and_years_three_columns.png", path = pathShare, height=15, width=12, units="in", dpi = 320)

#######################
yrs2005 <- yrs_merge[yrs_merge$year==2005,]
yrs2012 <- yrs_merge[yrs_merge$year==2012,]
yrs2023 <- yrs_merge[yrs_merge$year==2023,]

yrs2005$date <- as.Date(yrs2005$yday, origin="2004-12-31")
yrs2012$date <- as.Date(yrs2012$yday, origin="2011-12-31")
yrs2023$date <- as.Date(yrs2023$yday, origin="2022-12-31")

yrsderivs2005 <- yrsderivs_merge[yrsderivs_merge$year==2005,]
yrsderivs2012 <- yrsderivs_merge[yrsderivs_merge$year==2012,]
yrsderivs2023 <- yrsderivs_merge[yrsderivs_merge$year==2023,]

yrsderivs2005$date <- as.Date(yrsderivs2005$yday, origin="2004-12-31")
yrsderivs2012$date <- as.Date(yrsderivs2012$yday, origin="2011-12-31")
yrsderivs2023$date <- as.Date(yrsderivs2023$yday, origin="2022-12-31")

yrsderivs2005$type <- factor(yrsderivs2005$type, levels = c("crop", "forest", "forest-wet", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
yrsderivs2012$type <- factor(yrsderivs2012$type, levels = c("crop", "forest", "forest-wet", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
yrsderivs2023$type <- factor(yrsderivs2023$type, levels = c("crop", "forest", "forest-wet", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

#########
#2005
#########

p1 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2005-04-26"), xmax=as.Date("2005-12-31"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrs2005, aes(x=date, ymin=lwr_anoms, ymax=upr_anoms,fill=type), alpha=0.2) +
  geom_line(data=yrs2005, aes(x=date, y=anoms, color=type),linewidth=0.7)+
  ggtitle("2005 NDVI anomalies") +
  scale_x_date(date_breaks= "1 month", expand=c(0,0),date_labels = ("%b %d")) +
  ylim(-0.2,0.2)+ylab("NDVI anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme_bw(11)+
  scale_color_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen","grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  scale_fill_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))
p1 <- p1 +  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1), legend.position = "none")

p2 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2005-04-26"), xmax=as.Date("2005-12-31"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrsderivs2005, aes(x=date, ymin=lwr_anoms, ymax=upr_anoms,fill=type), alpha=0.2) +
  geom_line(data=yrsderivs2005, aes(x=date, y=anoms, color=type),linewidth=0.7)+
  ggtitle("2005 NDVI derivative anomalies") +
  scale_x_date(date_breaks= "1 month",expand=c(0,0), date_labels = ("%b %d")) +
  ylim(-0.02,0.02)+ylab("NDVI deriv anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme_bw(11)+
  scale_color_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  scale_fill_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))
p2 <- p2 +  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1),legend.position = "none")
#########
#2012
#########

p3 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2012-06-12"), xmax=as.Date("2012-12-31"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrs2012, aes(x=date, ymin=lwr_anoms, ymax=upr_anoms,fill=type), alpha=0.2) +
  geom_line(data=yrs2012, aes(x=date, y=anoms, color=type),linewidth=0.7)+
  ggtitle("2012 NDVI anomalies") +
  scale_x_date(date_breaks= "1 month",expand=c(0,0),date_labels = ("%b %d")) +
  ylim(-0.25,0.27)+ylab("NDVI anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme_bw(11)+
  scale_color_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen","grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  scale_fill_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))
p3 <- p3+ theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1),legend.position = "none")

p4 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2012-06-12"), xmax=as.Date("2012-12-31"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrsderivs2012, aes(x=date, ymin=lwr_anoms, ymax=upr_anoms,fill=type), alpha=0.2) +
  geom_line(data=yrsderivs2012, aes(x=date, y=anoms, color=type),linewidth=0.7)+
  ggtitle("2012 NDVI derivative anomalies") +
  scale_x_date(date_breaks= "1 month",expand=c(0,0),date_labels = ("%b %d")) +
  ylim(-0.02,0.02)+ylab("NDVI deriv anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme_bw(11)+
  scale_color_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  scale_fill_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))
p4 <- p4 +theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1),legend.position = "none")

#########
#2023
#########

p5 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2023-05-23"), xmax=as.Date("2023-09-26"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  #geom_rect(aes(xmin=as.Date("2023-11-21"), xmax=as.Date("2023-12-05"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrs2023, aes(x=date, ymin=lwr_anoms, ymax=upr_anoms,fill=type), alpha=0.2) +
  geom_line(data=yrs2023, aes(x=date, y=anoms, color=type),linewidth=0.7)+
  ggtitle("2023 NDVI anomalies") +
  scale_x_date(date_breaks= "1 month",expand=c(0,0),date_labels = ("%b %d")) +
  ylim(-0.2,0.2)+ylab("NDVI anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme_bw(11)+
  scale_color_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  scale_fill_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))
p5 <- p5 + theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1),legend.position = "none")

p6 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2023-05-23"), xmax=as.Date("2023-09-26"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  #geom_rect(aes(xmin=as.Date("2023-11-21"), xmax=as.Date("2023-12-05"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrsderivs2023, aes(x=date, ymin=lwr_anoms, ymax=upr_anoms,fill=type), alpha=0.2) +
  geom_line(data=yrsderivs2023, aes(x=date, y=anoms, color=type),linewidth=0.7)+
  ggtitle("2023 NDVI derivative anomalies") +
  scale_x_date(date_breaks= "1 month",expand=c(0,0),date_labels = ("%b %d")) +
  ylim(-0.02,0.02)+ylab("NDVI deriv anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme_bw(11)+
  scale_color_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen",  "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  scale_fill_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen",  "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))
p6 <- p6 +theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1), legend.position = "bottom")
  
plot_grid(p1,p2,p3,p4,p5,p6, align = "hv",ncol=2)

ggpubr::ggarrange(
  p1, p2, p3, p4 ,p5, p6,# list of plots
  #labels = c("Years", "Anomalies"), # labels
  common.legend = TRUE, # COMMON LEGEND
  legend = "bottom", # legend position
  align = "hv", # Align them both, horizontal and vertical
  ncol = 2 # number of rows
)


ggsave("NDVI_anoms_and_derivs_panels_forest-wet.png", path = pathShare, height=12, width=12, units="in", dpi = 320)
##

# yrs2005 <- yrs[yrs$year==2005,]
# yrs2012 <- yrs[yrs$year==2012,]
# yrs2023 <- yrs[yrs$year==2023,]
# 
# yrsderivs2005 <- yrsderivs[yrsderivs$year==2005,]
# yrsderivs2012 <- yrsderivs[yrsderivs$year==2012,]
# yrsderivs2023 <- yrsderivs[yrsderivs$year==2023,]
# 
# yrs2005$anoms <- yrs2005$mean - norms$mean
# yrs2012$anoms <- yrs2012$mean - norms$mean
# yrs2023$anoms <- yrs2023$mean - norms$mean
# 
# yrsderivs2005$anoms <- yrsderivs2005$mean - normsderivs$mean
# yrsderivs2012$anoms <- yrsderivs2012$mean - normsderivs$mean
# yrsderivs2023$anoms <- yrsderivs2023$mean - normsderivs$mean
# 
# yrs2005$date <- as.Date(yrs2005$yday, origin="2004-12-31")
# yrs2012$date <- as.Date(yrs2012$yday, origin="2011-12-31")
# yrs2023$date <- as.Date(yrs2023$yday, origin="2022-12-31")
# 
# yrsderivs2005$date <- as.Date(yrsderivs2005$yday, origin="2004-12-31")
# yrsderivs2012$date <- as.Date(yrsderivs2012$yday, origin="2011-12-31")
# yrsderivs2023$date <- as.Date(yrsderivs2023$yday, origin="2022-12-31")
# 
# yrs2005$upper <- yrs2005$upr - norms$mean
# yrs2005$lower <- yrs2005$lwr - norms$mean
# 
# yrs2012$upper <- yrs2012$upr - norms$mean
# yrs2012$lower <- yrs2012$lwr - norms$mean
# 
# yrs2023$upper <- yrs2023$upr - norms$mean
# yrs2023$lower <- yrs2023$lwr - norms$mean
# 
# yrsderivs2005$upper <- yrsderivs2005$upr - normsderivs$mean
# yrsderivs2005$lower <- yrsderivs2005$lwr - normsderivs$mean
# 
# yrsderivs2012$upper <- yrsderivs2012$upr - normsderivs$mean
# yrsderivs2012$lower <- yrsderivs2012$lwr - normsderivs$mean
# 
# yrsderivs2023$upper <- yrsderivs2023$upr - normsderivs$mean
# yrsderivs2023$lower <- yrsderivs2023$lwr - normsderivs$mean
# 
# yrsderivs2005$type <- factor(yrsderivs2005$type, levels = c("crop", "forest", "forest-wet", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
# yrsderivs2012$type <- factor(yrsderivs2012$type, levels = c("crop", "forest", "forest-wet", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
# yrsderivs2023$type <- factor(yrsderivs2023$type, levels = c("crop", "forest", "forest-wet", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
# 
# yrs2005$type <- factor(yrs2005$type, levels = c("crop", "forest", "forest-wet", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
# yrs2012$type <- factor(yrs2012$type, levels = c("crop", "forest", "forest-wet", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
# yrs2023$type <- factor(yrs2023$type, levels = c("crop", "forest", "forest-wet", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))


ggplot()+
  geom_line(data=norms, aes(x=yday, y=mean,color="normal"))+
  geom_ribbon(data=norms, aes(x=yday, ymin=lwr, ymax=upr,fill="normal"), alpha=0.2) +
  #geom_line(data=yrs[yrs$year %in% c(2005,2012,2023),], aes(x=yday,y=mean,color=as.factor(year)))+
  #geom_ribbon(data=yrs[yrs$year %in% c(2005,2012,2023),], aes(x=yday, ymin=lwr, ymax=upr, fill=as.factor(year)), alpha=0.2) +
  scale_color_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  facet_wrap(~type) + ylim(0,1)+
  scale_x_continuous(name="Day of Year", expand=c(0,0), breaks=day.labels$yday[seq(2, 12, by=3)], labels=day.labels$Text[seq(2, 12, by=3)])+
  theme_bw(11)+
  ggtitle("Original Norms")+
  ylab("NDVI") #+ggtitle("Drought Years and Normal NDVI")+
ggsave("NDVI_norms_and_years.png", path = pathShare, height=6, width=12, units="in", dpi = 320)