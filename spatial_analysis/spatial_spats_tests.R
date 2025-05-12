library(mgcv) #load packages
library(ggplot2)
library(tibble)
library(dplyr)
library(MASS)
library(lubridate)
library(gganimate)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare2 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring")

######################
#load data
######################

pixel_norms <- read.csv(file.path(google.drive, "data/spatial_NDVI_monitoring/pixel_by_pixel_norms.csv"))
pixel_yrs <- read.csv(file.path(google.drive, "data/spatial_NDVI_monitoring/pixel_by_pixel_years.csv"))
landsatAll <- read.csv(file.path(google.drive, "data/spatial_NDVI_monitoring/reprojected_NDVI_all_satellites_pixel_by_pixel.csv"))







library(ape)
pixel_norms_180 <- pixel_norms[pixel_norms$yday==180,]
pixel_norms_200 <- pixel_norms[pixel_norms$yday==200,]

pixel_norms_dists <- as.matrix(distm(cbind(pixel_norms_200$x, pixel_norms_200$y)),fun=distHaversine)
norms_dist_inv <- 1/pixel_norms_dists
diag(norms_dist_inv) <- 0

m <- Moran.I(pixel_norms_200$mean, norms_dist_inv, na.rm=TRUE)
plot(m)

library(geoR)
library(geosphere)
library(sp)
library(gstat)

pixel_norms_180 <- na.omit(pixel_norms_180)
pixel_norms_200 <- na.omit(pixel_norms_200)


spatial_data <- SpatialPointsDataFrame(coords=pixel_norms_200[,c("x","y")], data=pixel_norms_200, proj4string=CRS("+proj=longlat +datum=WGS84"))
vario <- variogram(mean ~ 1, data=spatial_data)
plot(vario)

dists <- distm(pixel_norms_200[,3:4], fun=distHaversine)
summary(dists)

coordinates(pixel_norms_200) <- ~x+y
bubble(pixel_norms_200, "mean")

l200 <- landsatAll[landsatAll$yday==200,]
l200 <- na.omit(l200)
coordinates(l200) <- ~x+y
bubble(l200, "MissionResid")

pixel_norms_spatial <- pixel_norms
pixel_norms_spatial <- na.omit(pixel_norms_spatial)
coordinates(pixel_norms_spatial) <- ~x+y
norms_gls <- gls(mean ~ yday, pixel_norms_spatial, method="REML")
plot(norms_gls)

plot(nlme:::Variogram(norms_gls, form = ~x +
                        y, resType = "normalized"))

plot(variogram(residuals(norms_gls, "normalized") ~
                 1, data = norms_gls, cutoff = 6))


coords = cbind(pixel_norms_200$x, pixel_norms_200$y)
w = fields::rdist(coords)
Moran.I(x=pixel_norms_200$mean, w=w)