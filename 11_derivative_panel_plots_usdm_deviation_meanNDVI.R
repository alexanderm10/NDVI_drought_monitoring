# code for making derivative panel plots using USDM data

library(cowplot)
library(ggplot2)
library(tidyr)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/11_derivative_panel_plots_usdm_deviation_meanNDVI")

######################

usdmcat <- read.csv("~/Downloads/dm_export_20000101_20241017.csv") #usdm chicago region data
yrsderivs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/individual_years_derivs_GAM.csv")) #individual years derivatives
normsderivs <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/norms_derivatives.csv")) #normals derivatives
rawdat <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/raw_data.csv")) #raw data

yrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/individual_years_post_GAM.csv")) #individual years
norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/norms_all_LC_types.csv")) #normals

######################
#subset to specific yr/LC type
######################

usdm <- usdmcat %>% pivot_longer(cols = c(4:8), names_to = "severity", values_to = "percentage") #combining index columns
usdm$date <- as.Date(usdm$ValidStart)
usdm2005 <-usdm[usdm$MapDate %in% c(20041228:20051227),] #2005
usdm2012 <-usdm[usdm$MapDate %in% c(20111227:20121225),] #2012
usdm2023 <-usdm[usdm$MapDate %in% c(20221227:20231226),] #2023

yrsderivs2005 <- yrsderivs[yrsderivs$year==2005,]
yrsderivs2012 <- yrsderivs[yrsderivs$year==2012,]
yrsderivs2023 <- yrsderivs[yrsderivs$year==2023,]
yrsderivs2005$date <- as.Date(yrsderivs2005$yday, origin="2004-12-31")
yrsderivs2012$date <- as.Date(yrsderivs2012$yday, origin="2011-12-31")
yrsderivs2023$date <- as.Date(yrsderivs2023$yday, origin="2022-12-31")

raw2005 <- rawdat[rawdat$year==2005,] #raw data
raw2012 <- rawdat[rawdat$year==2012,]
raw2023 <- rawdat[rawdat$year==2023,]
raw2005$date <- as.Date(raw2005$date)
raw2012$date <- as.Date(raw2012$date)
raw2023$date <- as.Date(raw2023$date)

normsderivs2005 <- normsderivs
normsderivs2005$date <- as.Date(normsderivs2005$yday, origin="2004-12-31")
normsderivs2012 <- normsderivs
normsderivs2012$date <- as.Date(normsderivs2012$yday, origin="2011-12-31")
normsderivs2023 <- normsderivs
normsderivs2023$date <- as.Date(normsderivs2023$yday, origin="2022-12-31")
######################

yrs2005 <- yrs[yrs$year==2005,]
yrs2012 <- yrs[yrs$year==2012,]
yrs2023 <- yrs[yrs$year==2023,]
yrs2005$date <- as.Date(yrs2005$yday, origin="2004-12-31")
yrs2012$date <- as.Date(yrs2012$yday, origin="2011-12-31")
yrs2023$date <- as.Date(yrs2023$yday, origin="2022-12-31")

norms2005 <- norms
norms2005$date <- as.Date(norms2005$yday, origin="2004-12-31")
norms2012 <- norms
norms2012$date <- as.Date(norms2012$yday, origin="2011-12-31")
norms2023 <- norms
norms2023$date <- as.Date(norms2023$yday, origin="2022-12-31")

######################
#calculate deviation and its CI, put in separate df
######################

deviationderivs <- yrsderivs2005[yrsderivs2005$type=="urban-open",]$mean - normsderivs2005[normsderivs2005$type=="urban-open",]$mean
lwrdev <- yrsderivs2005[yrsderivs2005$type=="urban-open",]$lwr - normsderivs2005[normsderivs2005$type=="urban-open",]$mean
uprdev <- yrsderivs2005[yrsderivs2005$type=="urban-open",]$upr - normsderivs2005[normsderivs2005$type=="urban-open",]$mean

devderiv2005 <- data.frame(yday=seq(1:365))
devderiv2005$deviation <- deviationderivs
devderiv2005$date <- as.Date(devderiv2005$yday, origin="2004-12-31")
devderiv2005$uprdev <- uprdev
devderiv2005$lwrdev <- lwrdev

###

deviationderivs <- yrsderivs2012[yrsderivs2012$type=="urban-open",]$mean - normsderivs2012[normsderivs2012$type=="urban-open",]$mean
lwrdev <- yrsderivs2012[yrsderivs2012$type=="urban-open",]$lwr - normsderivs2012[normsderivs2012$type=="urban-open",]$mean
uprdev <- yrsderivs2012[yrsderivs2012$type=="urban-open",]$upr - normsderivs2012[normsderivs2012$type=="urban-open",]$mean

devderiv2012 <- data.frame(yday=seq(1:365))
devderiv2012$deviation <- deviationderivs
devderiv2012$date <- as.Date(devderiv2012$yday, origin="2011-12-31")
devderiv2012$uprdev <- uprdev
devderiv2012$lwrdev <- lwrdev

###

deviationderivs <- yrsderivs2023[yrsderivs2023$type=="urban-open",]$mean - normsderivs2023[normsderivs2023$type=="urban-open",]$mean
lwrdev <- yrsderivs2023[yrsderivs2023$type=="urban-open",]$lwr - normsderivs2023[normsderivs2023$type=="urban-open",]$mean
uprdev <- yrsderivs2023[yrsderivs2023$type=="urban-open",]$upr - normsderivs2023[normsderivs2023$type=="urban-open",]$mean

devderiv2023 <- data.frame(yday=seq(1:365))
devderiv2023$deviation <- deviationderivs
devderiv2023$date <- as.Date(devderiv2023$yday, origin="2022-12-31")
devderiv2023$uprdev <- uprdev
devderiv2023$lwrdev <- lwrdev

######################
#deviation no derivatives
######################
deviation <- yrs2005[yrs2005$type=="urban-open",]$mean - norms2005[norms2005$type=="urban-open",]$mean
lwrdev <- yrs2005[yrs2005$type=="urban-open",]$lwr - norms2005[norms2005$type=="urban-open",]$mean
uprdev <- yrs2005[yrs2005$type=="urban-open",]$upr - norms2005[norms2005$type=="urban-open",]$mean

dev2005 <- data.frame(yday=seq(1:365))
dev2005$deviation <- deviation
dev2005$date <- as.Date(dev2005$yday, origin="2004-12-31")
dev2005$uprdev <- uprdev
dev2005$lwrdev <- lwrdev

###

deviation <- yrs2012[yrs2012$type=="urban-open",]$mean - norms2012[norms2012$type=="urban-open",]$mean
lwrdev <- yrs2012[yrs2012$type=="urban-open",]$lwr - norms2012[norms2012$type=="urban-open",]$mean
uprdev <- yrs2012[yrs2012$type=="urban-open",]$upr - norms2012[norms2012$type=="urban-open",]$mean

dev2012 <- data.frame(yday=seq(1:365))
dev2012$deviation <- deviation
dev2012$date <- as.Date(dev2012$yday, origin="2011-12-31")
dev2012$uprdev <- uprdev
dev2012$lwrdev <- lwrdev

###

deviation <- yrs2023[yrs2023$type=="urban-open",]$mean - norms2023[norms2023$type=="urban-open",]$mean
lwrdev <- yrs2023[yrs2023$type=="urban-open",]$lwr - norms2023[norms2023$type=="urban-open",]$mean
uprdev <- yrs2023[yrs2023$type=="urban-open",]$upr - norms2023[norms2023$type=="urban-open",]$mean

dev2023 <- data.frame(yday=seq(1:365))
dev2023$deviation <- deviation
dev2023$date <- as.Date(dev2023$yday, origin="2022-12-31")
dev2023$uprdev <- uprdev
dev2023$lwrdev <- lwrdev

######################
#cowplot 2005
######################

p1 <- ggplot()+
  geom_ribbon(data=yrs2005[yrs2005$type=="urban-open",], aes(x=date, ymin=lwr, ymax=upr), fill="#D55E00", alpha=0.2) +
  geom_ribbon(data=norms2005[norms2005$type=="urban-open",],aes(x=date, ymin=lwr, ymax=upr), color=NA, alpha=0.2) +
  geom_line(data=yrs2005[yrs2005$type=="urban-open",], aes(x=date,y=mean,color="2005"))+
  geom_line(data=norms2005[norms2005$type=="urban-open",], aes(x=date,y=mean,color="normal"))+
  geom_point(data=raw2005[raw2005$type=="urban-open",], aes(x=date, y=NDVIReprojected,color="gray50"),alpha=0.7)+
  scale_color_manual(name="year", values=c("normal" = "black", "2005"="#D55E00")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00")) +
  ylab(" Mean NDVI") +ggtitle("2005 urban-open") + theme(legend.position="none")

p2 <- ggplot()+
  geom_area(data=usdm2005, aes(x=date, y=percentage, fill=severity),alpha=0.8)+
  scale_fill_manual(values=c("yellow","burlywood", "darkorange","red","brown4")) + theme(legend.position = "none") +
  geom_line(data=dev2005, aes(x=date, y=(deviation+0.2)*250)) +
  geom_ribbon(data=dev2005, aes(x=date, ymin=(lwrdev+0.2)*250, ymax=(uprdev+0.2)*250), fill="black", alpha=0.3) +
  geom_hline(yintercept=50)+
  scale_y_continuous(name="percentage", sec.axis = sec_axis(~./250-0.2,name="deviation")) 

p3 <- ggplot()+
  geom_ribbon(data=yrsderivs2005[yrsderivs2005$type=="urban-open",], aes(x=date, ymin=lwr, ymax=upr), fill="#D55E00", alpha=0.2) +
  geom_ribbon(data=normsderivs2005[normsderivs2005$type=="urban-open",],aes(x=date, ymin=lwr, ymax=upr), color=NA, alpha=0.2) +
  geom_line(data=yrsderivs2005[yrsderivs2005$type=="urban-open",], aes(x=date,y=mean,color="2005"))+
  geom_line(data=normsderivs2005[normsderivs2005$type=="urban-open",], aes(x=date,y=mean,color="normal"))+
  #geom_point(data=raw2005[raw2005$type=="crop",], aes(x=date, y=NDVIReprojected,color="gray50"),alpha=0.7)+
  scale_color_manual(name="year", values=c("normal" = "black", "2005"="#D55E00")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00")) + ylim(-0.02,0.02)+
  geom_hline(yintercept=0)+
  ylab("1st derivative mean NDVI")+ theme(legend.position="bottom") +ggtitle("2005 urban-open derivatives")

p4 <- ggplot()+
  geom_area(data=usdm2005, aes(x=date, y=percentage, fill=severity),alpha=0.8)+
  scale_fill_manual(values=c("yellow","burlywood", "darkorange","red","brown4")) + theme(legend.position = "bottom") +
  geom_line(data=devderiv2005, aes(x=date, y=(deviation+0.01)*5000)) +
  geom_ribbon(data=devderiv2005, aes(x=date, ymin=(lwrdev+0.01)*5000, ymax=(uprdev+0.01)*5000), fill="black", alpha=0.3) +
  geom_hline(yintercept=50)+
  scale_y_continuous(name="percentage", sec.axis = sec_axis(~./5000-0.01,name="deriv deviation"))

plot_grid(p1,p2,p3,p4,align="hv") #2005

######################
#cowplot 2012
######################

p5 <- ggplot()+
  geom_ribbon(data=yrs2012[yrs2012$type=="urban-open",], aes(x=date, ymin=lwr, ymax=upr), fill="#E69F00", alpha=0.2) +
  geom_ribbon(data=norms2012[norms2012$type=="urban-open",],aes(x=date, ymin=lwr, ymax=upr), color=NA, alpha=0.2) +
  geom_line(data=yrs2012[yrs2012$type=="urban-open",], aes(x=date,y=mean,color="2012"))+
  geom_line(data=norms2012[norms2012$type=="urban-open",], aes(x=date,y=mean,color="normal"))+
  geom_point(data=raw2012[raw2012$type=="urban-open",], aes(x=date, y=NDVIReprojected,color="gray50"),alpha=0.7)+
  scale_color_manual(name="year", values=c("normal" = "black", "2012"="#E69F00")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2012"="#E69F00")) +
  ylab(" Mean NDVI")+ theme(legend.position="none") +ggtitle("2012 urban-open")

p6 <- ggplot()+
  geom_area(data=usdm2012, aes(x=date, y=percentage, fill=severity),alpha=0.8)+
  scale_fill_manual(values=c("yellow","burlywood", "darkorange","red","brown4")) + theme(legend.position = "none") +
  geom_line(data=dev2012, aes(x=date, y=(deviation+0.2)*250)) +
  geom_ribbon(data=dev2012, aes(x=date, ymin=(lwrdev+0.2)*250, ymax=(uprdev+0.2)*250), fill="black", alpha=0.3) +
  geom_hline(yintercept=50)+
  scale_y_continuous(name="percentage", sec.axis = sec_axis(~./250-0.2,name="deviation")) 

p7 <- ggplot()+
  geom_ribbon(data=yrsderivs2012[yrsderivs2012$type=="urban-openn",], aes(x=date, ymin=lwr, ymax=upr), fill="#E69F00", alpha=0.2) +
  geom_ribbon(data=normsderivs2012[normsderivs2012$type=="urban-open",],aes(x=date, ymin=lwr, ymax=upr), color=NA, alpha=0.2) +
  geom_line(data=yrsderivs2012[yrsderivs2012$type=="urban-open",], aes(x=date,y=mean,color="2012"))+
  geom_line(data=normsderivs2012[normsderivs2012$type=="urban-open",], aes(x=date,y=mean,color="normal"))+
  #geom_point(data=raw2005[raw2005$type=="crop",], aes(x=date, y=NDVIReprojected,color="gray50"),alpha=0.7)+
  scale_color_manual(name="year", values=c("normal" = "black", "2012"="#E69F00")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2012"="#E69F00")) + ylim(-0.02,0.02)+
  geom_hline(yintercept=0)+
  ylab("1st derivative mean NDVI")+ theme(legend.position="bottom") +ggtitle("2012 urban-open derivatives")

p8 <- ggplot()+
  geom_area(data=usdm2012, aes(x=date, y=percentage, fill=severity),alpha=0.8)+
  scale_fill_manual(values=c("yellow","burlywood", "darkorange","red","brown4")) + theme(legend.position = "bottom") +
  geom_line(data=devderiv2012, aes(x=date, y=(deviation+0.01)*5000)) +
  geom_ribbon(data=devderiv2012, aes(x=date, ymin=(lwrdev+0.01)*5000, ymax=(uprdev+0.01)*5000), fill="black", alpha=0.3) +
  geom_hline(yintercept=50)+
  scale_y_continuous(name="percentage", sec.axis = sec_axis(~./5000-0.01,name="deriv deviation"))

plot_grid(p5,p6,p7,p8,align="hv") #2012

######################
#cowplot 2023
######################

p9 <- ggplot()+
  geom_ribbon(data=yrs2023[yrs2023$type=="urban-open",], aes(x=date, ymin=lwr, ymax=upr), fill="#CC79A7", alpha=0.2) +
  geom_ribbon(data=norms2023[norms2023$type=="urban-open",],aes(x=date, ymin=lwr, ymax=upr), color=NA, alpha=0.2) +
  geom_line(data=yrs2023[yrs2023$type=="urban-open",], aes(x=date,y=mean,color="2023"))+
  geom_line(data=norms2023[norms2023$type=="urban-open",], aes(x=date,y=mean,color="normal"))+
  geom_point(data=raw2023[raw2023$type=="urban-open",], aes(x=date, y=NDVIReprojected,color="gray50"),alpha=0.7)+
  scale_color_manual(name="year", values=c("normal" = "black", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2023"="#CC79A7")) +
  ylab("Mean NDVI")+ theme(legend.position="none") +ggtitle("2023 urban-open")

p10 <- ggplot()+
  geom_area(data=usdm2023, aes(x=date, y=percentage, fill=severity),alpha=0.8)+
  scale_fill_manual(values=c("yellow","burlywood", "darkorange","red","brown4")) + theme(legend.position = "none") +
  geom_line(data=dev2023, aes(x=date, y=(deviation+0.2)*250)) +
  geom_ribbon(data=dev2023, aes(x=date, ymin=(lwrdev+0.2)*250, ymax=(uprdev+0.2)*250), fill="black", alpha=0.3) +
  geom_hline(yintercept=50)+
  scale_y_continuous(name="percentage", sec.axis = sec_axis(~./250-0.2,name="deviation")) 

p11 <- ggplot()+
  geom_ribbon(data=yrsderivs2023[yrsderivs2023$type=="urban-open",], aes(x=date, ymin=lwr, ymax=upr), fill="#CC79A7", alpha=0.2) +
  geom_ribbon(data=normsderivs2023[normsderivs2023$type=="urban-open",],aes(x=date, ymin=lwr, ymax=upr), color=NA, alpha=0.2) +
  geom_line(data=yrsderivs2023[yrsderivs2023$type=="urban-open",], aes(x=date,y=mean,color="2023"))+
  geom_line(data=normsderivs2023[normsderivs2023$type=="urban-open",], aes(x=date,y=mean,color="normal"))+
  #geom_point(data=raw2005[raw2005$type=="forest",], aes(x=date, y=NDVIReprojected,color="gray50"),alpha=0.7)+
  scale_color_manual(name="year", values=c("normal" = "black", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2023"="#CC79A7")) + ylim(-0.02,0.02)+
  geom_hline(yintercept=0)+
  ylab("1st derivative mean NDVI")+ theme(legend.position="bottom") +ggtitle("2023 urban-open derivatives")

p12 <- ggplot()+
  geom_area(data=usdm2023, aes(x=date, y=percentage, fill=severity),alpha=0.8)+
  scale_fill_manual(values=c("yellow","burlywood", "darkorange","red","brown4")) + theme(legend.position = "bottom") +
  geom_line(data=devderiv2023, aes(x=date, y=(deviation+0.01)*5000)) +
  geom_ribbon(data=devderiv2023, aes(x=date, ymin=(lwrdev+0.01)*5000, ymax=(uprdev+0.01)*5000), fill="black", alpha=0.3) +
  geom_hline(yintercept=50)+
  scale_y_continuous(name="percentage", sec.axis = sec_axis(~./5000-0.01,name="deriv deviation"))

plot_grid(p9,p10,p11,p12,align="hv") #2023

######################