# code for making panel plots using USDM data

library(cowplot)
library(ggplot2)
library(tidyr)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/04_panel_plots_usdm_deviation_meanNDVI")

######################

usdm <- read.csv("~/Downloads/dm_export_20000101_20241017.csv") #usdm chicago region data
yrs <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/individual_years_post_GAM.csv")) #individual years
norms <-read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/norms_all_LC_types.csv")) #normals
rawdat <- read.csv(file.path(google.drive, "data/NDVI_drought_monitoring/raw_data.csv")) #raw data

######################
#subset to specific yr/LC type
######################

usdm <- usdm %>% pivot_longer(cols = c(4:8), names_to = "severity", values_to = "percentage") #combining index columns
usdm$date <- as.Date(usdm$ValidStart)
usdm2005 <-usdm[usdm$MapDate %in% c(20041228:20051227),] #2005
usdm2012 <-usdm[usdm$MapDate %in% c(20111227:20121225),] #2012
usdm2023 <-usdm[usdm$MapDate %in% c(20221227:20231226),] #2023

yrs2005 <- yrs[yrs$year==2005,]
yrs2012 <- yrs[yrs$year==2012,]
yrs2023 <- yrs[yrs$year==2023,]
yrs2005$date <- as.Date(yrs2005$yday, origin="2004-12-31")
yrs2012$date <- as.Date(yrs2012$yday, origin="2011-12-31")
yrs2023$date <- as.Date(yrs2023$yday, origin="2022-12-31")

raw2005 <- rawdat[rawdat$year==2005,] #raw data
raw2012 <- rawdat[rawdat$year==2012,]
raw2023 <- rawdat[rawdat$year==2023,]
raw2005$date <- as.Date(raw2005$date)
raw2012$date <- as.Date(raw2012$date)
raw2023$date <- as.Date(raw2023$date)

norms2005 <- norms
norms2005$date <- as.Date(norms2005$yday, origin="2004-12-31")
norms2012 <- norms
norms2012$date <- as.Date(norms2012$yday, origin="2011-12-31")
norms2023 <- norms
norms2023$date <- as.Date(norms2023$yday, origin="2022-12-31")

######################
#calculate deviation and its CI, put in separate df
######################
deviation <- yrs2005[yrs2005$type=="crop",]$mean - norms2005[norms2005$type=="crop",]$mean
lwrdev <- yrs2005[yrs2005$type=="crop",]$lwr - norms2005[norms2005$type=="crop",]$mean
uprdev <- yrs2005[yrs2005$type=="crop",]$upr - norms2005[norms2005$type=="crop",]$mean

dev2005 <- data.frame(yday=seq(1:365))
dev2005$deviation <- deviation
dev2005$date <- as.Date(dev2005$yday, origin="2004-12-31")
dev2005$uprdev <- uprdev
dev2005$lwrdev <- lwrdev

###

deviation <- yrs2012[yrs2012$type=="crop",]$mean - norms2012[norms2012$type=="crop",]$mean
lwrdev <- yrs2012[yrs2012$type=="crop",]$lwr - norms2012[norms2012$type=="crop",]$mean
uprdev <- yrs2012[yrs2012$type=="crop",]$upr - norms2012[norms2012$type=="crop",]$mean

dev2012 <- data.frame(yday=seq(1:365))
dev2012$deviation <- deviation
dev2012$date <- as.Date(dev2012$yday, origin="2011-12-31")
dev2012$uprdev <- uprdev
dev2012$lwrdev <- lwrdev

###

deviation <- yrs2023[yrs2023$type=="crop",]$mean - norms2023[norms2023$type=="crop",]$mean
lwrdev <- yrs2023[yrs2023$type=="crop",]$lwr - norms2023[norms2023$type=="crop",]$mean
uprdev <- yrs2023[yrs2023$type=="crop",]$upr - norms2023[norms2023$type=="crop",]$mean

dev2023 <- data.frame(yday=seq(1:365))
dev2023$deviation <- deviation
dev2023$date <- as.Date(dev2023$yday, origin="2022-12-31")
dev2023$uprdev <- uprdev
dev2023$lwrdev <- lwrdev

######################
#cowplot 2005
######################

p1 <- ggplot()+
  geom_ribbon(data=yrs2005[yrs2005$type=="crop",], aes(x=date, ymin=lwr, ymax=upr), fill="#D55E00", alpha=0.2) +
  geom_ribbon(data=norms2005[norms2005$type=="crop",],aes(x=date, ymin=lwr, ymax=upr), color=NA, alpha=0.2) +
  geom_line(data=yrs2005[yrs2005$type=="crop",], aes(x=date,y=mean,color="2005"))+
  geom_line(data=norms2005[norms2005$type=="crop",], aes(x=date,y=mean,color="normal"))+
  geom_point(data=raw2005[raw2005$type=="crop",], aes(x=date, y=NDVIReprojected,color="gray50"),alpha=0.7)+
  scale_color_manual(name="year", values=c("normal" = "black", "2005"="#D55E00")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00")) +
  ylab(" Mean NDVI")+ theme(legend.position="bottom") +ggtitle("2005 crop")

p2 <- ggplot()+
  geom_area(data=usdm2005, aes(x=date, y=percentage, fill=severity),alpha=0.8)+
  scale_fill_manual(values=c("yellow","burlywood", "darkorange","red","brown4")) + theme(legend.position = "bottom") +
  geom_line(data=dev2005, aes(x=date, y=(deviation+0.2)*250)) +
  geom_ribbon(data=dev2005, aes(x=date, ymin=(lwrdev+0.2)*250, ymax=(uprdev+0.2)*250), fill="black", alpha=0.3) +
  geom_hline(yintercept=50)+
  scale_y_continuous(name="percentage", sec.axis = sec_axis(~./250-0.2,name="deviation")) 

plot_grid(p1,p2,align="hv") #2005

######################
#cowplot 2012
######################

p3 <- ggplot()+
  geom_ribbon(data=yrs2012[yrs2012$type=="crop",], aes(x=date, ymin=lwr, ymax=upr), fill="#E69F00", alpha=0.2) +
  geom_ribbon(data=norms2012[norms2012$type=="crop",],aes(x=date, ymin=lwr, ymax=upr), color=NA, alpha=0.2) +
  geom_line(data=yrs2012[yrs2012$type=="crop",], aes(x=date,y=mean,color="2012"))+
  geom_line(data=norms2012[norms2012$type=="crop",], aes(x=date,y=mean,color="normal"))+
  geom_point(data=raw2012[raw2012$type=="crop",], aes(x=date, y=NDVIReprojected,color="gray50"),alpha=0.7)+
  scale_color_manual(name="year", values=c("normal" = "black", "2012"="#E69F00")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2012"="#E69F00")) +
  ylab(" Mean NDVI")+ theme(legend.position="bottom") +ggtitle("2012 crop")

p4 <- ggplot()+
  geom_area(data=usdm2012, aes(x=date, y=percentage, fill=severity),alpha=0.8)+
  scale_fill_manual(values=c("yellow","burlywood", "darkorange","red","brown4")) + theme(legend.position = "bottom") +
  geom_line(data=dev2012, aes(x=date, y=(deviation+0.2)*250)) +
  geom_ribbon(data=dev2012, aes(x=date, ymin=(lwrdev+0.2)*250, ymax=(uprdev+0.2)*250), fill="black", alpha=0.3) +
  geom_hline(yintercept=50)+
  scale_y_continuous(name="percentage", sec.axis = sec_axis(~./250-0.2,name="deviation")) 

plot_grid(p3,p4,align="hv") #2012

######################
#cowplot 2023
######################

p5 <- ggplot()+
  geom_ribbon(data=yrs2023[yrs2023$type=="crop",], aes(x=date, ymin=lwr, ymax=upr), fill="#CC79A7", alpha=0.2) +
  geom_ribbon(data=norms2023[norms2023$type=="crop",],aes(x=date, ymin=lwr, ymax=upr), color=NA, alpha=0.2) +
  geom_line(data=yrs2023[yrs2023$type=="crop",], aes(x=date,y=mean,color="2023"))+
  geom_line(data=norms2023[norms2023$type=="crop",], aes(x=date,y=mean,color="normal"))+
  geom_point(data=raw2023[raw2023$type=="crop",], aes(x=date, y=NDVIReprojected,color="gray50"),alpha=0.7)+
  scale_color_manual(name="year", values=c("normal" = "black", "2023"="#CC79A7")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2023"="#CC79A7")) +
  ylab("Mean NDVI")+ theme(legend.position="bottom") +ggtitle("2023 crop")

p6 <- ggplot()+
  geom_area(data=usdm2023, aes(x=date, y=percentage, fill=severity),alpha=0.8)+
  scale_fill_manual(values=c("yellow","burlywood", "darkorange","red","brown4")) + theme(legend.position = "bottom") +
  geom_line(data=dev2023, aes(x=date, y=(deviation+0.2)*250)) +
  geom_ribbon(data=dev2023, aes(x=date, ymin=(lwrdev+0.2)*250, ymax=(uprdev+0.2)*250), fill="black", alpha=0.3) +
  geom_hline(yintercept=50)+
  scale_y_continuous(name="percentage", sec.axis = sec_axis(~./250-0.2,name="deviation")) 

plot_grid(p5,p6,align="hv") #2023

######################

#p2 <- ggplot()+
#geom_line(data=dev, aes(x=date, y=deviation), color="#D55E00")+
#geom_ribbon(data=dev, aes(x=date, ymin=lwrdev, ymax=uprdev), fill="#D55E00", alpha=0.2) +
#geom_hline(yintercept=0)+
#ylim(-0.15,0.15)

# for (LC in unique(raw2005$type)){
#   datLC <- raw2005[raw2005$type==LC,]
#   assign(paste0("raw2005",LC),datLC)
# }

# for (LC in unique(raw2012$type)){
#   datLC <- raw2012[raw2012$type==LC,]
#   assign(paste0("raw2012",LC),datLC)
# }

# for (LC in unique(yrs2005$type)){
#   datLC <- yrs2005[yrs2005$type==LC,]
#   datLC$date <- as.Date(datLC$yday, origin="2004-12-31")
#   assign(paste0(LC,"2005"),datLC)
# }

# for (LC in unique(yrs2012$type)){
#   df <- yrs2012[yrs2012$type==LC,]
#   df$date <- as.Date(df$yday, origin="2011-12-31")
#   assign(paste0(LC,"2012"),df)
# }

# for (LC in unique(norms2005$type)){
#   df <- norms2005[norms2005$type==LC,]
#   assign(paste0("norms2005",LC),df)
# }
# 
# for (LC in unique(norms2012$type)){
#   df <- norms2012[norms2012$type==LC,]
#   assign(paste0("norms2012",LC),df)
# }

#urbmed2005 <- yrs[yrs$year==2005 & yrs$type=="urban-medium",] #year-specific data
#urbmed2012 <- yrs[yrs$year==2012 & yrs$type=="urban-medium",] #year-specific data

#urbmed2005$date <- as.Date(urbmed2005$yday, origin="2004-12-31") #adding date column
#urbmed2012$date <- as.Date(urbmed2012$yday, origin="2011-12-31") #adding date column

#normsurbmed <- norms[norms$type=="urban-medium",] #normal
#normsurbmed$date <- as.Date(normsurbmed$yday, origin="2004-12-31")
#normsurbmed$date <- as.Date(normsurbmed$yday, origin="2011-12-31")

#rawurbmed2005 <- rawdat[rawdat$year==2005 & rawdat$type=="urban-medium",] #raw data
#rawurbmed2012 <- rawdat[rawdat$year==2012 & rawdat$type=="urban-medium",] #raw data
#rawurbmed2005$date <- as.Date(rawurbmed2005$date)
#rawurbmed2012$date <- as.Date(rawurbmed2012$date)