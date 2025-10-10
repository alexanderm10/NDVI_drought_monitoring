# Use rocker/geospatial as base - includes R with spatial packages and system dependencies
FROM rocker/geospatial:4.4.1

# Install additional system dependencies for HLS NDVI processing
RUN apt-get update && apt-get install -y \
    # NetCDF and HDF5 libraries for ncdf4
    libnetcdf-dev \
    netcdf-bin \
    libhdf5-dev \
    # GDAL/PROJ/GEOS dependencies (enhanced for HLS data)
    libgdal-dev \
    gdal-bin \
    libproj-dev \
    libgeos-dev \
    # Additional spatial libraries
    libudunits2-dev \
    # SQLite for metadata management
    libsqlite3-dev \
    # System libraries for visualization
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    # Network and security libraries
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    # Development tools
    git \
    vim \
    htop \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Configure R to use binary packages when available and set CRAN mirror
ENV R_REPOS="https://packagemanager.rstudio.com/cran/__linux__/jammy/latest"

# Install R packages in batches to avoid timeouts
# Batch 1: Core data manipulation
RUN R -e "install.packages(c('data.table', 'dplyr', 'tidyr', 'lubridate', 'readr', 'stringr'), repos=Sys.getenv('R_REPOS'), dependencies=TRUE)"

# Batch 2: Spatial packages (critical for HLS processing)
RUN R -e "install.packages(c('terra', 'sf', 'raster', 'stars', 'exactextractr'), repos=Sys.getenv('R_REPOS'), dependencies=TRUE)"

# Batch 3: Statistical modeling (GAM core)
RUN R -e "install.packages(c('mgcv', 'MASS', 'nlme', 'lme4'), repos=Sys.getenv('R_REPOS'), dependencies=TRUE)"

# Batch 4: Parallel processing
RUN R -e "install.packages(c('parallel', 'foreach', 'doParallel', 'future', 'future.apply'), repos=Sys.getenv('R_REPOS'), dependencies=TRUE)"

# Batch 5: Visualization
RUN R -e "install.packages(c('ggplot2', 'viridis', 'RColorBrewer', 'scales', 'gridExtra', 'cowplot'), repos=Sys.getenv('R_REPOS'), dependencies=TRUE)"

# Batch 6: NASA data access (httr for API, jsonlite for STAC parsing)
RUN R -e "install.packages(c('httr', 'jsonlite', 'curl'), repos=Sys.getenv('R_REPOS'), dependencies=TRUE)"

# Batch 7: Additional utilities
RUN R -e "install.packages(c('arrow', 'RSQLite', 'DBI'), repos=Sys.getenv('R_REPOS'), dependencies=TRUE)"

# Set proper permissions for the workspace (rstudio user already exists in base image)
RUN chown -R rstudio:rstudio /workspace

# Switch to non-root user
USER rstudio

# Set environment variables for R
ENV R_LIBS_USER=/home/rstudio/R/library

# Expose port for RStudio Server (if needed)
EXPOSE 8787

# Default command (VS Code will override this)
CMD ["R", "--interactive"]
