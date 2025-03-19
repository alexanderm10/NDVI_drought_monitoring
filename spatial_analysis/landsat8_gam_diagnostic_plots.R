library(raster)
library(ggplot2)
library(tidyverse)
library(cowplot)
library(plotly)
library(stringr)
library(mgcv)
library(lubridate)
library(htmlwidgets)

###################
#load & format L8 data
###################

l8 <- brick("~/Google Drive/Shared drives/Urban Ecological Drought/data/NDVI_drought_monitoring/landsat8_reproject_no_mosaic.tif")
l8 <- as.data.frame(l8, xy=TRUE) #include xy coordinates

l8$values <- rowSums(!is.na(l8[3:ncol(l8)])) #total non-missing values and get rid of coordinates with nothing
l8 <- l8[!(l8$values==0),]

l8 <- l8 %>% pivot_longer(cols=c(3:(ncol(l8)-1)), names_to = "date", values_to = "NDVI") #make dataframe into long format

l8$date <- str_sub(l8$date, -8,-1) #format is weird but last 8 characters of band name represent date!!
l8$date <- as.Date(l8$date, "%Y%m%d")
l8$yday <- lubridate::yday(l8$date)
l8$year <- lubridate::year(l8$date)

l8$xy <- paste(l8$x, l8$y) #column for coord pairs

l8 <- l8[l8$xy!='-87.8083333 42.3583333333333',] #masking out coord with bad data
l8 <- l8[l8$xy!='-87.7666666333333 42.1916666666667',]
l8 <- l8[l8$xy!='-87.5999999666667 41.9',]
l8 <- l8[l8$xy!='-87.5999999666667 41.8583333333333',]
l8 <- l8[l8$xy!='-87.5583333 41.775',]
l8 <- l8[l8$xy!='-87.5166666333333 41.7333333333333',]

###################
#calculate mean NDVI for each pixel
###################

l8_mean_NDVI <- l8 %>% group_by(x,y) %>%
  summarise_at(vars("NDVI"), mean, na.rm=TRUE) %>% as.data.frame()

ggplot(l8_mean_NDVI, aes(x=x,y=y, fill=NDVI))+
  geom_tile()+ coord_equal()+ scale_fill_gradientn(colors = hcl.colors(20, "RdYlGn")) +
  ggtitle("Landsat 8 Mean NDVI")+labs(fill="mean NDVI")

###################
#Run test GAM
###################

l8gamtest <- gam(NDVI ~ s(x,y,yday),data=l8) #DEFAULT K (110 ish)
summary(l8gamtest)
AIC(l8gamtest)
par(mfrow = c(2, 2))
gam.check(l8gamtest)
tidy_gam(l8gamtest)

l8gamtest <- gam(NDVI ~ s(x,y,yday,k=200),data=l8) #k=200
summary(l8gamtest)
AIC(l8gamtest)
par(mfrow = c(2, 2))
gam.check(l8gamtest)
tidy_gam(l8gamtest)

l8gamtest <- gam(NDVI ~ s(x,y,yday,k=300),data=l8) #k=300
summary(l8gamtest)
AIC(l8gamtest)
par(mfrow = c(2, 2))
gam.check(l8gamtest)
tidy_gam(l8gamtest)

###################
#gam coord loop?
###################
df <- data.frame()

for (x in unique(l8$x)){
  datx <- l8[l8$x==x,]
  
  for (y in unique(datx$y)){
    datxy <- datx[datx$y==y,]
    
    gam_loop <- gam(NDVI ~ s(yday),data=datxy)
    datxy$pred <- predict(gam_loop, newdata=datxy)
    df <- rbind(df, datxy)
  }
}

###################
#calculate reaiduals & RMSE
###################
#resid(l8gamtest)

l8$pred <- predict(l8gamtest, newdata=l8)
l8$resid <- l8$NDVI - l8$pred
ggplot(data=l8, aes(x=yday, y=resid))+
  geom_point(alpha=0.5) + ggtitle("Residuals vs. Day of Year")

l8_resid_mean <- l8 %>% group_by(x,y) %>%
  summarise_at(vars("resid"), mean, na.rm=TRUE) %>% as.data.frame()


l8$resid_sq <- (l8$resid)^2
l8_resid_sq_mean <- l8 %>% group_by(x,y) %>%
  summarise_at(vars("resid_sq"), mean, na.rm=TRUE) %>% as.data.frame()

l8_resid_sq_mean$RMSE <- sqrt(l8_resid_sq_mean$resid_sq)

###################
#plot residuals and RMSE
###################

l8_resid_mean <- l8_resid_mean %>% #formatting for plotly widget
  mutate(text = paste0("x: ", round(x,2), "\n", "y: ", round(y,2), "\n", "Residual: ",round(resid,3), "\n"))

#p1 <-
ggplot(l8_resid_mean, aes(x=x,y=y, fill=resid, text=text))+ #mean resids plot
  geom_tile()+ coord_equal()+ scale_fill_gradient(low="white", high="blue")+
  ggtitle("Landsat 8 NDVI Mean Residuals")+labs(fill="residuals")

pp <- ggplotly(p1, tooltip = "text")
saveWidget(pp, file="~/Downloads/l8_residuals.html")

l8_resid_mean$normalized_resid <- l8_resid_mean$resid/l8_mean_NDVI$NDVI

ggplot(l8_resid_mean, aes(x=x,y=y, fill=normalized_resid, text=text))+ #mean resids plot
  geom_tile()+ coord_equal()+ scale_fill_gradient(low="white", high="blue")+
  ggtitle("Landsat 8 NDVI Mean Residuals/Mean NDVI")+labs(fill="mean resid/mean NDVI")

###################

l8_resid_sq_mean <- l8_resid_sq_mean %>%
  mutate(text = paste0("x: ", round(x,2), "\n", "y: ", round(y,2), "\n", "RMSE: ",round(RMSE,3), "\n"))

#p2 <- 
ggplot(l8_resid_sq_mean, aes(x=x,y=y, fill=RMSE,text=text))+ #RMSE plot
  geom_tile()+ coord_equal()+ scale_fill_gradient(low="white", high="blue")+
  ggtitle("Landsat 8 NDVI RMSE")+labs(fill="RMSE")

pp <- ggplotly(p2, tooltip = "text")
saveWidget(pp, file="~/Downloads/l8_RMSE.html")
