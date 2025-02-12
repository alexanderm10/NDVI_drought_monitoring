#NDVI spatial data acquisition

library(rgee); library(raster); library(terra)
ee_check() # For some reason, it's important to run this before initializing right now
rgee::ee_Initialize(user = 'jharr@mortonarb.org', drive=T)
path.google <- ("~/Google Drive/My Drive/")
path.google.share <- "~/Google Drive/Shared drives/Urban Ecological Drought/"
L8save <- "landsat8_spatial_data"
assetHome <- ee_get_assethome()

##################### 
#helper functions
##################### 
addTime <- function(image){ 
  return(image$addBands(image$metadata('system:time_start')$divide(1000 * 60 * 60 * 24 * 365)))
}

setYear <- function(img){
  return(img$set("year", img$date()$get("year")))
}

addYear = function(img) {
  d= ee$Date(ee$Number(img$get('system:time_start')));
  y= ee$Number(d$get('year'));
  return(img$set('year', y));
}

bitwiseExtract <- function(input, fromBit, toBit) {
  maskSize <- ee$Number(1)$add(toBit)$subtract(fromBit)
  mask <- ee$Number(1)$leftShift(maskSize)$subtract(1)
  return(input$rightShift(fromBit)$bitwiseAnd(mask))
}

addNDVI <- function(img){
  return( img$addBands(img$normalizedDifference(c('nir','red'))$rename('NDVI')));
}


applyLandsatBitMask = function(img){
  qaPix <- img$select('QA_PIXEL');
  qaRad <- img$select('QA_RADSAT');
  terrMask <- qaRad$bitwiseAnd(11)$eq(0); ## get rid of any terrain occlusion
  # satMask <- qaRad$bitwiseAnd(3 << 4)$eq(0); ## get rid of any saturated bands we use to calculate NDVI
  satMask <- bitwiseExtract(qaRad, 3, 4)$eq(0) ## get rid of any saturated bands we use to calculate NDVI 
  # clearMask <- qaPix$bitwiseAnd(1<<7)$eq(0)
  clearMask <- bitwiseExtract(qaPix, 1, 5)$eq(0)
  waterMask <- bitwiseExtract(qaPix, 7, 7)$eq(0)
  cloudConf = bitwiseExtract(qaPix, 8, 9)$lte(1) ## we can only go with low confidence; doing finer leads to NOTHING making the cut
  shadowConf <- bitwiseExtract(qaPix, 10, 11)$lte(1) ## we can only go with low confidence; doing finer leads to NOTHING making the cut
  snowConf <- bitwiseExtract(qaPix, 12, 13)$lte(1) ## we can only go with low confidence; doing finer leads to NOTHING making the cut
  
  
  img <- img$updateMask(clearMask$And(waterMask)$And(cloudConf)$And(shadowConf)$And(snowConf)$And(terrMask)$And(satMask));
  
  return(img)
  
}

# Function for combining images with the same date
# 2nd response from here: https:#gis.stackexchange.com/questions/280156/mosaicking-image-collection-by-date-day-in-google-earth-engine 
mosaicByDate <- function(imcol, dayWindow){
  # imcol: An image collection
  # returns: An image collection
  imlist = imcol$toList(imcol$size())
  
  # Note: needed to specify the ee_utils_pyfunc since it's not an image collection
  unique_dates <- imlist$map(ee_utils_pyfunc(function(img){
    return(ee$Image(img)$date()$format("YYYY-MM-dd"))
  }))$distinct()
  
  # Same as above: what we're mappign through is a List, so need to call python
  mosaic_imlist = unique_dates$map(ee_utils_pyfunc(function(d){
    d = ee$Date(d)
    dy= d$get('day');    
    m= d$get('month');
    y= d$get('year');
    
    im = imcol$filterDate(d$advance(-dayWindow, "day"), d$advance(dayWindow, "day"))$reduce(ee$Reducer$median()) # shoudl influence the window for image aggregation
    
    return(im$set("system:time_start", d$millis(), 
                  "system:id", d$format("YYYY-MM-dd"),
                  'date', d, 'day', dy, 'month', m, 'year', y))
  }))
  
  # testOUT <- ee$ImageCollection(mosaic_imlist)
  # ee_print(testOUT)
  return (ee$ImageCollection(mosaic_imlist))
}

##################### 
# Chicago geometry
##################### 

Chicago = ee$FeatureCollection("projects/breidyee/assets/SevenCntyChiReg") 
ee_print(Chicago)

chiBounds <- Chicago$geometry()$bounds()
chiBBox <- ee$Geometry$BBox(-88.70738, 41.20155, -87.52453, 42.49575)

##################### 
# Read in & Format Landsat 8 ----
##################### 
# "LANDSAT/LC08/C02/T1_RT"
# Load MODIS NDVI data; attach month & year
# https://developers.google.com/earth-engine/datasets/catalog/LANDSAT_LC08_C02_T1_L2
landsat8 <- ee$ImageCollection("LANDSAT/LC08/C02/T1_L2")$filterBounds(Chicago)$map(function(image){
  return(image$clip(Chicago))
})$map(function(img){
  d= ee$Date(img$get('system:time_start'));
  dy= d$get('day');    
  m= d$get('month');
  y= d$get('year');
  
  # # Add masks 
  img <- applyLandsatBitMask(img)
  
  # #scale correction; doing here & separating form NDVI so it gets saved on the image
  lAdj = img$select(c('SR_B1', 'SR_B2', 'SR_B3', 'SR_B4', 'SR_B5', 'SR_B6', 'SR_B7'))$multiply(0.0000275)$add(-0.2);
  lst_k = img$select('ST_B10')$multiply(0.00341802)$add(149);
  
  # img3 = img2$addBands(srcImg=lAdj, overwrite=T)$addBands(srcImg=lst_k, overwrite=T)$set('date',d, 'day',dy, 'month',m, 'year',y)
  return(img$addBands(srcImg=lAdj, overwrite=T)$addBands(srcImg=lst_k, overwrite=T)$set('date',d, 'day',dy, 'month',m, 'year',y))
})$select(c('SR_B2', 'SR_B3', 'SR_B4', 'SR_B5', 'SR_B6', 'SR_B7', 'ST_B10'),c('blue', 'green', 'red', 'nir', 'swir1', 'swir2', 'LST_K'))$map(addNDVI)
# Map$addLayer(landsat8$first()$select('NDVI'), ndviVis, "NDVI - First")
# ee_print(landsat8)
# Map$addLayer(landsat8$first()$select('NDVI'))

l8Mosaic = mosaicByDate(landsat8, 7)$select(c('blue_median', 'green_median', 'red_median', 'nir_median', 'swir1_median', 'swir2_median', 'LST_K_median', "NDVI_median"),c('blue', 'green', 'red', 'nir', 'swir1', 'swir2', 'LST_K', "NDVI"))$sort("date")
# ee_print(l8Mosaic, "landsat8-Mosaic")
# Map$addLayer(l8Mosaic$first()$select('NDVI'), ndviVis, "NDVI - First")

##################### 
# Read in GRIDMET data for reprojection
##################### 

GRIDMET <- ee$ImageCollection("IDAHO_EPSCOR/GRIDMET")$filterBounds(Chicago)$map(function(image){
  return(image$clip(Chicago))})
#ee_print(GRIDMET)

projGRID = GRIDMET$first()$projection()

##################### 
# reproject landsat8 to GRIDMET
##################### 

l8reproj = l8Mosaic$map(function(img){
  return(img$reduceResolution(reducer=ee$Reducer$mean())$reproject(projGRID))
})$map(addTime); # add year here!

yrMod <- ee$List(l8reproj$aggregate_array("year"))$distinct()
yrString <- ee$List(paste0("YR", yrMod$getInfo()))

l8_flat <- ee$ImageCollection$toBands(l8reproj)$rename(yrString)
#ee_print(l8_flat)

export_l8 <- ee_image_to_drive(image=l8_flat, description="Save_landsat8_reproject", region=Chicago$geometry(), fileNamePrefix="landsat8_reproject", folder=L8save, timePrefix=F)
export_l8$start()

#savel8 <- ee_image_to_asset(l8_flat, description="Save_landsat8_reproject", assetId=file.path(assetHome, "landsat8_reproject"), maxPixels = 10e9, scale=926.6, region = maskBBox, crs="SR-ORG:6974", crsTransform=c(926.625433056, 0, -20015109.354, 0, -926.625433055, 10007554.677), overwrite=T)
#savel8$start()