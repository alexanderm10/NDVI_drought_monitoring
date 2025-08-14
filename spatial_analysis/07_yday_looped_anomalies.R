# load packages -----------------------------------------------------------

library(dplyr)
library(lubridate)

Sys.setenv(GOOGLE_DRIVE = "~/Google Drive/Shared drives/Urban Ecological Drought")
google.drive <- Sys.getenv("GOOGLE_DRIVE")
path.google <- ("~/Google Drive/My Drive/")
pathShare2 <- file.path(path.google, "../Shared drives/Urban Ecological Drought/data/spatial_NDVI_monitoring")

# load data ---------------------------------------------------------------

spatial_yrs <- read.csv(file.path(google.drive, "data/spatial_NDVI_monitoring/16_day_window_yday_spatial_loop_years.csv"))

spatial_yrs$anoms_mean <- spatial_yrs$mean - spatial_yrs$norm
spatial_yrs$anoms_lwr <- spatial_yrs$lwr - spatial_yrs$norm
spatial_yrs$anoms_upr <- spatial_yrs$upr - spatial_yrs$norm

write.csv(spatial_yrs, file.path(pathShare2, "16_day_window_spatial_data_with_anomalies.csv"), row.names=F)
