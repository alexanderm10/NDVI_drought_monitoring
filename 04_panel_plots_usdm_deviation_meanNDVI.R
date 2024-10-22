# code for making panel plots using USDM data

library(cowplot)
library(ggplot2)
library(tidyr)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/")

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

urbmed2005 <- yrs[yrs$year==2005 & yrs$type=="urban-medium",] #year-specific data
urbmed2005$date <- as.Date(urbmed2005$yday, origin="2004-12-31") #adding date column


normsurbmed <- norms[norms$type=="urban-medium",] #normal
normsurbmed$date <- as.Date(normsurbmed$yday, origin="2004-12-31")

rawurbmed2005 <- rawdat[rawdat$year==2005 & rawdat$type=="urban-medium",] #raw data
rawurbmed2005$date <- as.Date(rawurbmed2005$date)

######################
#calculate deviation and its CI, put in separate df
######################

deviation <- urbmed2005$mean - normsurbmed$mean
lwrdev <- urbmed2005$lwr - normsurbmed$mean
uprdev <- urbmed2005$upr - normsurbmed$mean

dev <- data.frame(yday=seq(1:365))
dev$deviation <- deviation
dev$date <- as.Date(dev$yday, origin="2004-12-31")
dev$uprdev <- uprdev
dev$lwrdev <- lwrdev

######################
#cowplot
######################

p1 <- ggplot()+
  geom_ribbon(data=urbmed2005, aes(x=date, ymin=lwr, ymax=upr), fill="#D55E00", alpha=0.2) +
  geom_ribbon(data=normsurbmed,aes(x=date, ymin=lwr, ymax=upr), color=NA, alpha=0.2) +
  geom_line(data=urbmed2005, aes(x=date,y=mean,color="2005"))+
  geom_line(data=normsurbmed, aes(x=date,y=mean,color="normal"))+
  geom_point(data=rawurbmed2005, aes(x=date, y=NDVIReprojected,color="gray50"),alpha=0.7)+
  scale_color_manual(name="year", values=c("normal" = "black", "2005"="#D55E00")) +
  scale_fill_manual(name="year", values=c("normal" = "black", "2005"="#D55E00")) +
  ylab(" Mean NDVI")+ theme(legend.position="bottom") +ggtitle("2005 Urban-Medium")


#p2 <- ggplot()+
  #geom_line(data=dev, aes(x=date, y=deviation), color="#D55E00")+
  #geom_ribbon(data=dev, aes(x=date, ymin=lwrdev, ymax=uprdev), fill="#D55E00", alpha=0.2) +
  #geom_hline(yintercept=0)+
  #ylim(-0.15,0.15)


p3 <- ggplot()+
  geom_area(data=usdm2005, aes(x=date, y=percentage, fill=severity),alpha=0.8)+
  scale_fill_manual(values=c("yellow","burlywood", "darkorange","red","brown4")) + theme(legend.position = "bottom") +
  geom_line(data=dev, aes(x=date, y=(deviation+0.2)*250)) +
  geom_ribbon(data=dev, aes(x=date, ymin=(lwrdev+0.2)*250, ymax=(uprdev+0.2)*250), fill="black", alpha=0.3) +
  geom_hline(yintercept=50)+
  scale_y_continuous(name="percentage", sec.axis = sec_axis(~./250-0.2,name="deviation")) 

plot_grid(p1,p3,align="hv")
