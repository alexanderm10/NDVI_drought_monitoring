# Docker Setup for CONUS HLS Drought Monitor

## Overview

This Docker environment provides a reproducible R environment with all necessary spatial packages and system dependencies for HLS NDVI processing and GAM analysis.

## Prerequisites

- Docker and Docker Compose installed on Linux server
- Access to `/mnt/malexander/datasets/ndvi_monitor` data directory
- Sufficient resources: 16+ cores, 64GB+ RAM recommended

## Building the Container

From the `CONUS_HLS_drought_monitoring/` directory:

```bash
# Build the Docker image
docker-compose build

# Or rebuild without cache if needed
docker-compose build --no-cache
```

## Running the Container

### Method 1: Interactive R Session

```bash
# Start container and attach to R session
docker-compose run --rm drought-monitor-r R
```

### Method 2: VS Code Dev Container

1. Install "Dev Containers" extension in VS Code
2. Open `CONUS_HLS_drought_monitoring/` folder in VS Code
3. Click "Reopen in Container" when prompted
4. VS Code will build and attach to the container

### Method 3: Long-running Background Container

```bash
# Start container in background
docker-compose up -d

# Attach to running container
docker exec -it conus-hls-drought-monitor bash

# Inside container, start R
R

# Stop container when done
docker-compose down
```

## Data Access Inside Container

The data directory is mounted at `/data` inside the container:

```r
# In R session inside container
list.files("/data/processed_ndvi/daily/2024")
```

The path detection in `00_setup_paths.R` automatically recognizes `/data` on Linux and configures paths accordingly.

## Running the GAM Workflow

Inside the container:

```r
# Source paths (auto-detects /data location)
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

# Phase 1: Aggregate to 4km
source("01_aggregate_to_4km.R")
timeseries_4km <- process_ndvi_to_4km(config)

# Phase 2: Fit climatology
source("02_fit_climatology_gams.R")
timeseries_4km <- read.csv(config$input_file, stringsAsFactors = FALSE)
timeseries_4km$date <- as.Date(timeseries_4km$date)
climatology <- fit_all_climatologies(timeseries_4km, config)

# Phase 3: Fit year-specific GAMs
source("03_fit_year_gams.R")
year_splines <- fit_all_year_gams(timeseries_4km, config)

# Phase 4: Calculate anomalies
source("04_calculate_anomalies.R")
anomaly_df <- process_anomalies(config)

# Phase 5: Classify drought (placeholder)
source("05_classify_drought.R")
classified_df <- process_drought_classification(config)
```

## Resource Configuration

Edit `docker-compose.yml` to adjust resource limits:

```yaml
deploy:
  resources:
    limits:
      cpus: '16.0'  # Adjust based on server capacity
      memory: 64G   # Adjust based on available RAM
    reservations:
      cpus: '4.0'   # Minimum cores
      memory: 16G   # Minimum RAM
```

## Parallel Processing Inside Container

The GAM scripts detect available cores automatically:

```r
# Check available cores inside container
parallel::detectCores()  # Will respect Docker CPU limits

# Scripts use detectCores() - 1 by default
# Adjust in config if needed:
config$n_cores <- 8  # Manually override
```

## Troubleshooting

### Permission Issues

If you get permission errors:

```bash
# Check your UID/GID on host system
id

# Set UID/GID when starting container
UID=1000 GID=1000 docker-compose up
```

### Out of Memory

If container runs out of memory during Phase 1:

```r
# Process years sequentially instead of all at once
config$years <- 2013:2014  # Start with subset
timeseries_4km_partial <- process_ndvi_to_4km(config)

config$years <- 2015:2016  # Continue
# ... append results
```

### Data Path Not Found

If `/data` directory is empty:

```bash
# Check mount on host system
ls /mnt/malexander/datasets/ndvi_monitor

# Verify mount in docker-compose.yml matches your system path
# Edit docker-compose.yml line 14:
# - /mnt/malexander/datasets/ndvi_monitor:/data
```

## Installed R Packages

The container includes all necessary packages:

- **Spatial**: `terra`, `sf`, `raster`, `stars`, `exactextractr`
- **GAM**: `mgcv`, `MASS`, `nlme`, `lme4`
- **Parallel**: `parallel`, `foreach`, `doParallel`, `future`
- **Data**: `dplyr`, `tidyr`, `lubridate`, `data.table`
- **Visualization**: `ggplot2`, `viridis`, `RColorBrewer`
- **NASA API**: `httr`, `jsonlite`, `curl`

## Persistent Package Installation

Additional packages install to persistent volume `r-libs`:

```r
# Inside container - packages persist across rebuilds
install.packages("new_package")
```

## Cleaning Up

```bash
# Stop and remove container
docker-compose down

# Remove container and volumes (WARNING: deletes installed packages)
docker-compose down -v

# Remove Docker image
docker rmi conus-hls-drought-monitor_drought-monitor-r
```

## Notes

- Container user matches host UID/GID to avoid permission issues
- `/workspace` mounts project code (read/write from container)
- `/data` mounts read-only data directory
- RStudio Server available at `http://localhost:8787` (password: `rstudio`)
