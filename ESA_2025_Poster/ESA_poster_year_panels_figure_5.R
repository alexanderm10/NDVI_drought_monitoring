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
#yrs_merge <- yrs_merge %>% pivot_longer(cols=c("mean_yrs","mean_anoms"), names_to =("graph type"), values_to = "mean")

yrsderivs_merge <- yrsderivs %>% inner_join(normsderivs, by= c("type", "yday"), suffix = c("_yrs", "_norm")) 
yrsderivs_merge$mean_anoms <- yrsderivs_merge$mean_yrs - yrsderivs_merge$mean_norm
yrsderivs_merge$upr_anoms <- yrsderivs_merge$upr_yrs - yrsderivs_merge$mean_norm
yrsderivs_merge$lwr_anoms <- yrsderivs_merge$lwr_yrs - yrsderivs_merge$mean_norm
yrsderivs_merge <- yrsderivs_merge[, !names(yrsderivs_merge) %in% c("sig_yrs", "var_yrs", "sig_norm", "var_norm", "mean_yrs", "upr_yrs","lwr_yrs")]

# plot --------------------------------------------------------------------
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

p1 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2005-04-26"), xmax=as.Date("2005-12-31"),ymin=-Inf,ymax=Inf), fill='orange', alpha= 0.3)+
  geom_ribbon(data=yrs2005, aes(x=date, ymin=lwr_anoms, ymax=upr_anoms,fill=type), alpha=0.2) +
  geom_line(data=yrs2005, aes(x=date, y=mean_anoms, color=type),linewidth=0.7)+
  ggtitle("2005 NDVI Anomalies") +
  scale_x_date(date_breaks= "1 month", expand=c(0,0),date_labels = ("%b %d")) +
  ylim(-0.2,0.2)+ylab("NDVI anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme_bw(20)+
  scale_color_manual(name="type", values=c("crop"="#DCD939", "forest"="#68AB5F","grassland"="#CCB879","urban-high"="#AB0000", "urban-medium"="#EB0000", "urban-low"="#D99282","urban-open"="#DEC5C5"))+
  scale_fill_manual(name="type", values=c("crop"="#DCD939", "forest"="#68AB5F", "grassland"="#CCB879","urban-high"="#AB0000", "urban-medium"="#EB0000", "urban-low"="#D99282","urban-open"="#DEC5C5"))
p1 <- p1 +  theme(axis.text.x = element_text(angle = 20, vjust = 1, hjust=1), legend.position = "none",plot.title = element_text(vjust=-1))

p2 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2005-04-26"), xmax=as.Date("2005-12-31"),ymin=-Inf,ymax=Inf), fill='orange', alpha= 0.3)+
  geom_ribbon(data=yrsderivs2005, aes(x=date, ymin=lwr_anoms, ymax=upr_anoms,fill=type), alpha=0.2) +
  geom_line(data=yrsderivs2005, aes(x=date, y=mean_anoms, color=type),linewidth=0.7)+
  ggtitle("2005 NDVI Derivative Anomalies") +
  scale_x_date(date_breaks= "1 month",expand=c(0,0), date_labels = ("%b %d")) +
  ylim(-0.01,0.01)+ylab("Deriv anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme_bw(20)+
  scale_color_manual(name="type", values=c("crop"="#DCD939", "forest"="#68AB5F","grassland"="#CCB879","urban-high"="#AB0000", "urban-medium"="#EB0000", "urban-low"="#D99282","urban-open"="#DEC5C5"))+
  scale_fill_manual(name="type", values=c("crop"="#DCD939", "forest"="#68AB5F", "grassland"="#CCB879","urban-high"="#AB0000", "urban-medium"="#EB0000", "urban-low"="#D99282","urban-open"="#DEC5C5"))
p2 <- p2 +  theme(axis.text.x = element_text(angle = 20, vjust = 1, hjust=1),legend.position = "none",plot.title = element_text(vjust=-1))

#########
#2012
#########

p3 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2012-06-12"), xmax=as.Date("2012-12-31"),ymin=-Inf,ymax=Inf), fill='orange', alpha= 0.3)+
  geom_ribbon(data=yrs2012, aes(x=date, ymin=lwr_anoms, ymax=upr_anoms,fill=type), alpha=0.2) +
  geom_line(data=yrs2012, aes(x=date, y=mean_anoms, color=type),linewidth=0.7)+
  ggtitle("2012 NDVI Anomalies") +
  scale_x_date(date_breaks= "1 month",expand=c(0,0),date_labels = ("%b %d")) +
  ylim(-0.25,0.27)+ylab("NDVI anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme_bw(20)+
  scale_color_manual(name="type", values=c("crop"="#DCD939", "forest"="#68AB5F","grassland"="#CCB879","urban-high"="#AB0000", "urban-medium"="#EB0000", "urban-low"="#D99282","urban-open"="#DEC5C5"))+
  scale_fill_manual(name="type", values=c("crop"="#DCD939", "forest"="#68AB5F", "grassland"="#CCB879","urban-high"="#AB0000", "urban-medium"="#EB0000", "urban-low"="#D99282","urban-open"="#DEC5C5"))
p3 <- p3+ theme(axis.text.x = element_text(angle = 20, vjust = 1, hjust=1),legend.position = "none",plot.title = element_text(vjust=-1))

p4 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2012-06-12"), xmax=as.Date("2012-12-31"),ymin=-Inf,ymax=Inf), fill='orange', alpha= 0.3)+
  geom_ribbon(data=yrsderivs2012, aes(x=date, ymin=lwr_anoms, ymax=upr_anoms,fill=type), alpha=0.2) +
  geom_line(data=yrsderivs2012, aes(x=date, y=mean_anoms, color=type),linewidth=0.7)+
  ggtitle("2012 NDVI Derivative Anomalies") +
  scale_x_date(date_breaks= "1 month",expand=c(0,0),date_labels = ("%b %d")) +
  ylim(-0.01,0.01)+ylab("Deriv anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme_bw(20)+
  scale_color_manual(name="type", values=c("crop"="#DCD939", "forest"="#68AB5F","grassland"="#CCB879","urban-high"="#AB0000", "urban-medium"="#EB0000", "urban-low"="#D99282","urban-open"="#DEC5C5"))+
  scale_fill_manual(name="type", values=c("crop"="#DCD939", "forest"="#68AB5F", "grassland"="#CCB879","urban-high"="#AB0000", "urban-medium"="#EB0000", "urban-low"="#D99282","urban-open"="#DEC5C5"))
p4 <- p4 +theme(axis.text.x = element_text(angle = 20, vjust = 1, hjust=1),legend.position = "none",plot.title = element_text(vjust=-1))

#########
#2023
#########

p5 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2023-05-23"), xmax=as.Date("2023-09-26"),ymin=-Inf,ymax=Inf), fill='orange', alpha= 0.3)+
  #geom_rect(aes(xmin=as.Date("2023-11-21"), xmax=as.Date("2023-12-05"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrs2023, aes(x=date, ymin=lwr_anoms, ymax=upr_anoms,fill=type), alpha=0.2) +
  geom_line(data=yrs2023, aes(x=date, y=mean_anoms, color=type),linewidth=0.7)+
  ggtitle("2023 NDVI Anomalies") +
  scale_x_date(date_breaks= "1 month",expand=c(0,0),date_labels = ("%b %d")) +
  ylim(-0.2,0.2)+ylab("NDVI anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme_bw(20)+
  scale_color_manual(name="type", values=c("crop"="#DCD939", "forest"="#68AB5F","grassland"="#CCB879","urban-high"="#AB0000", "urban-medium"="#EB0000", "urban-low"="#D99282","urban-open"="#DEC5C5"))+
  scale_fill_manual(name="type", values=c("crop"="#DCD939", "forest"="#68AB5F", "grassland"="#CCB879","urban-high"="#AB0000", "urban-medium"="#EB0000", "urban-low"="#D99282","urban-open"="#DEC5C5"))
p5 <- p5 + theme(axis.text.x = element_text(angle = 20, vjust = 1, hjust=1),legend.position = "none",plot.title = element_text(vjust=-1))

p6 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2023-05-23"), xmax=as.Date("2023-09-26"),ymin=-Inf,ymax=Inf), fill='orange', alpha= 0.3)+
  #geom_rect(aes(xmin=as.Date("2023-11-21"), xmax=as.Date("2023-12-05"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrsderivs2023, aes(x=date, ymin=lwr_anoms, ymax=upr_anoms,fill=type), alpha=0.2) +
  geom_line(data=yrsderivs2023, aes(x=date, y=mean_anoms, color=type),linewidth=0.7)+
  ggtitle("2023 NDVI Derivative Anomalies") +
  scale_x_date(date_breaks= "1 month",expand=c(0,0),date_labels = ("%b %d")) +
  ylim(-0.01,0.01)+ylab("Deriv anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme_bw(20)+
  scale_color_manual(name="type", values=c("crop"="#DCD939", "forest"="#68AB5F","grassland"="#CCB879","urban-high"="#AB0000", "urban-medium"="#EB0000", "urban-low"="#D99282","urban-open"="#DEC5C5"))+
  scale_fill_manual(name="type", values=c("crop"="#DCD939", "forest"="#68AB5F", "grassland"="#CCB879","urban-high"="#AB0000", "urban-medium"="#EB0000", "urban-low"="#D99282","urban-open"="#DEC5C5"))
p6 <- p6 +theme(axis.text.x = element_text(angle = 20, vjust = 1, hjust=1), legend.position = "bottom",plot.title = element_text(vjust=-1))

plot_grid(p1,p2,p3,p4,p5,p6, align = "hv",ncol=2)

ggpubr::ggarrange(
  p1, p2, p3, p4 ,p5, p6,# list of plots
  #labels = c("Years", "Anomalies"), # labels
  common.legend = TRUE, # COMMON LEGEND
  legend = "bottom", # legend position
  align = "hv", # Align them both, horizontal and vertical
  ncol = 2,
  nrow= 3# number of rows
)

ggsave("ESA_poster_NDVI_anoms_and_derivs_panels_figure_5.png", path = pathShare3, height=12, width=21, units="in", dpi = 320)
