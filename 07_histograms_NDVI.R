#histograms/misc NDVI plots

library(ggplot2)
library(tidyr)
library(dplyr)
library(tidyverse)
library(lubridate)
library(cowplot)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/figures/06_scatterplots_usdm_deviation_growing_season")

######################
usdmcum <- read.csv("~/Downloads/dm_export_20000101_20241024.csv") #usdm chicago region cumulative data
usdmcum <- usdmcum %>% pivot_longer(cols = c(4:8), names_to = "severity", values_to = "percentage") #combining index columns
usdmcum$date <- as.Date(usdmcum$ValidStart)


usdm <- usdmcum[usdmcum$percentage>50,]

for (level in unique(usdm$severity)){
  df <- usdm[usdm$severity==level,]
  df <- arrange(df, date)
  df$consecutive <- c(NA, diff(df$date)==7)
  x <- rle(df$consecutive)
  x <- x$lengths[x$values==TRUE]
  x <- x[!is.na(x)]
  x <- sequence(x)
  x <- data.frame(x)
  x$category <- paste0("",level)
  assign(paste0("df",level),x)
}

df <- rbind(dfD0, dfD1, dfD2,dfD3)
df$category <- as.factor(df$category)

ggplot(data=df, aes(x=x,fill=category)) +
  geom_histogram(bins=52) + ylab("frequency") + xlab("consecutive weeks in drought")+
  ggtitle("Chicago Region Conseutive Weeks Spent in Drought 01/2000-10/2024")+
  scale_fill_manual(name="Category", values=c("D0"="yellow", "D1"="burlywood","D2"="darkorange", "D3"="red"))

