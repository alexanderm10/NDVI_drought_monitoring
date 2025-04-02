library(ggplot2)
library(cowplot)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/Manuscript - Urban Drought NDVI Monitoring by Land Cover Class/figures")

######################

yrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_individual_years_post_GAM.csv")) #individual years
yrs$type <- factor(yrs$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_norms_all_LC_types.csv")) #normals
norms$type <- factor(norms$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

yrsderivs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_individual_years_derivs_GAM.csv")) #individual years derivatives
normsderivs <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/k=12_norms_derivatives.csv")) #normals derivatives

######################

ggplot()+
  geom_line(data=norms, aes(x=yday, y=mean,color="normal"))+
  geom_ribbon(data=norms, aes(x=yday, ymin=lwr, ymax=upr,fill="normal"), alpha=0.2) +
  geom_line(data=yrs[yrs$year %in% c(2005,2012,2023),], aes(x=yday,y=mean,color=as.factor(year)))+
  geom_ribbon(data=yrs[yrs$year %in% c(2005,2012,2023),], aes(x=yday, ymin=lwr, ymax=upr, fill=as.factor(year)), alpha=0.2) +
  scale_color_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00", "2012"="#E69F00", "2023"="#CC79A7")) +
  facet_wrap(~type) + ylim(0,1)+ xlim(0,365)+
  ggtitle("Drought Years and Norm NDVI")+ ylab("NDVI")
ggsave("NDVI_norms_and_years.png", path = pathShare, height=6, width=12, units="in", dpi = 320)

#######################

yrs2005 <- yrs[yrs$year==2005,]
yrs2012 <- yrs[yrs$year==2012,]
yrs2023 <- yrs[yrs$year==2023,]

yrsderivs2005 <- yrsderivs[yrsderivs$year==2005,]
yrsderivs2012 <- yrsderivs[yrsderivs$year==2012,]
yrsderivs2023 <- yrsderivs[yrsderivs$year==2023,]

yrs2005$anoms <- yrs2005$mean - norms$mean
yrs2012$anoms <- yrs2012$mean - norms$mean
yrs2023$anoms <- yrs2023$mean - norms$mean

yrsderivs2005$anoms <- yrsderivs2005$mean - normsderivs$mean
yrsderivs2012$anoms <- yrsderivs2012$mean - normsderivs$mean
yrsderivs2023$anoms <- yrsderivs2023$mean - normsderivs$mean

yrs2005$date <- as.Date(yrs2005$yday, origin="2004-12-31")
yrs2012$date <- as.Date(yrs2012$yday, origin="2011-12-31")
yrs2023$date <- as.Date(yrs2023$yday, origin="2022-12-31")

yrsderivs2005$date <- as.Date(yrsderivs2005$yday, origin="2004-12-31")
yrsderivs2012$date <- as.Date(yrsderivs2012$yday, origin="2011-12-31")
yrsderivs2023$date <- as.Date(yrsderivs2023$yday, origin="2022-12-31")

yrs2005$upper <- yrs2005$upr - norms$mean
yrs2005$lower <- yrs2005$lwr - norms$mean

yrs2012$upper <- yrs2012$upr - norms$mean
yrs2012$lower <- yrs2012$lwr - norms$mean

yrs2023$upper <- yrs2023$upr - norms$mean
yrs2023$lower <- yrs2023$lwr - norms$mean

yrsderivs2005$upper <- yrsderivs2005$upr - normsderivs$mean
yrsderivs2005$lower <- yrsderivs2005$lwr - normsderivs$mean

yrsderivs2012$upper <- yrsderivs2012$upr - normsderivs$mean
yrsderivs2012$lower <- yrsderivs2012$lwr - normsderivs$mean

yrsderivs2023$upper <- yrsderivs2023$upr - normsderivs$mean
yrsderivs2023$lower <- yrsderivs2023$lwr - normsderivs$mean

yrsderivs2005$type <- factor(yrsderivs2005$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
yrsderivs2012$type <- factor(yrsderivs2012$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
yrsderivs2023$type <- factor(yrsderivs2023$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

yrs2005$type <- factor(yrs2005$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
yrs2012$type <- factor(yrs2012$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))
yrs2023$type <- factor(yrs2023$type, levels = c("crop", "forest", "grassland", "urban-open", "urban-low", "urban-medium", "urban-high"))

#########
#2005
#########

p1 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2005-04-26"), xmax=as.Date("2005-12-31"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrs2005, aes(x=date, ymin=lower, ymax=upper,fill=type), alpha=0.2) +
  geom_line(data=yrs2005, aes(x=date, y=anoms, color=type),linewidth=0.7)+
  ggtitle("2005 NDVI anomalies") +
  scale_x_date(date_breaks= "1 month",date_labels = ("%b %d")) +
  ylim(-0.2,0.2)+ylab("NDVI anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1))+
  scale_color_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  scale_fill_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))

p2 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2005-04-26"), xmax=as.Date("2005-12-31"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrsderivs2005, aes(x=date, ymin=lower, ymax=upper,fill=type), alpha=0.2) +
  geom_line(data=yrsderivs2005, aes(x=date, y=anoms, color=type),linewidth=0.7)+
  ggtitle("2005 NDVI derivative anomalies") +
  scale_x_date(date_breaks= "1 month",date_labels = ("%b %d")) +
  ylim(-0.02,0.02)+ylab("NDVI deriv anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1))+
  scale_color_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  scale_fill_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))

#########
#2012
#########

p3 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2012-06-12"), xmax=as.Date("2012-12-31"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrs2012, aes(x=date, ymin=lower, ymax=upper,fill=type), alpha=0.2) +
  geom_line(data=yrs2012, aes(x=date, y=anoms, color=type),linewidth=0.7)+
  ggtitle("2012 NDVI anomalies") +
  scale_x_date(date_breaks= "1 month",date_labels = ("%b %d")) +
  ylim(-0.25,0.27)+ylab("NDVI anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1))+
  scale_color_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  scale_fill_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))

p4 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2012-06-12"), xmax=as.Date("2012-12-31"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrsderivs2012, aes(x=date, ymin=lower, ymax=upper,fill=type), alpha=0.2) +
  geom_line(data=yrsderivs2012, aes(x=date, y=anoms, color=type),linewidth=0.7)+
  ggtitle("2012 NDVI derivative anomalies") +
  scale_x_date(date_breaks= "1 month",date_labels = ("%b %d")) +
  ylim(-0.02,0.02)+ylab("NDVI deriv anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1))+
  scale_color_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  scale_fill_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))

#########
#2023
#########

p5 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2023-05-09"), xmax=as.Date("2023-09-26"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrs2023, aes(x=date, ymin=lower, ymax=upper,fill=type), alpha=0.2) +
  geom_line(data=yrs2023, aes(x=date, y=anoms, color=type),linewidth=0.7)+
  ggtitle("2023 NDVI anomalies") +
  scale_x_date(date_breaks= "1 month",date_labels = ("%b %d")) +
  ylim(-0.2,0.2)+ylab("NDVI anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1))+
  scale_color_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  scale_fill_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))

p6 <- ggplot()+
  geom_rect(aes(xmin=as.Date("2023-05-09"), xmax=as.Date("2023-09-26"),ymin=-Inf,ymax=Inf), fill='yellow', alpha= 0.3)+
  geom_ribbon(data=yrsderivs2023, aes(x=date, ymin=lower, ymax=upper,fill=type), alpha=0.2) +
  geom_line(data=yrsderivs2023, aes(x=date, y=anoms, color=type),linewidth=0.7)+
  ggtitle("2023 NDVI derivative anomalies") +
  scale_x_date(date_breaks= "1 month",date_labels = ("%b %d")) +
  ylim(-0.02,0.02)+ylab("NDVI deriv anomalies")+
  geom_hline(yintercept=0, linetype="dotted")+
  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust=1))+
  scale_color_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))+
  scale_fill_manual(name="type", values=c("crop"="darkorange3", "forest"="darkgreen", "grassland"="navajowhite1","urban-high"="darkred", "urban-medium"="red", "urban-low"="indianred","urban-open"="lightpink3"))

plot_grid(p1,p2,p3,p4,p5,p6, align = "hv",ncol=2)
ggsave("NDVI_anoms_and_derivs_panels.png", path = pathShare, height=12, width=12, units="in", dpi = 320)
