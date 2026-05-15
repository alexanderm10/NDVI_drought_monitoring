##' @param model.gam - a GAM or GAMM object
##' @param newdata - the data to be used for predicting the posterior distributions
##' @param vars - the spline predictors to be simulated
##' @param n - number of simulations to be generated for the posterior distribution; defaults to 1000
##' @param terms - (logical) only model the spline parameters and make separate predictions for each var (do not include intercepts); defaults to T
##' @param lwr - lower bound for confidence interval; default = 0.025 (lower end of 2-tailed 95% CI)
##' @param upr - upper bound for confidence interval; default = 0.975 (upper end of 2-tailed 95% CI)
##' @param return.sims - (logical) store and return the raw posterior simulations? defaults to F
##' @param seed - integer seed passed to set.seed() before drawing posteriors.
##'   Defaults to 1034 (legacy reproducible behavior). Pass a unique seed per
##'   call (e.g. 1034 + DOY) to ensure the 100 simulations are statistically
##'   INDEPENDENT across calls. This matters when downstream code combines
##'   posteriors from multiple calls (e.g. script 06's change derivatives,
##'   which compute baseline[day] - baseline[day-k] across DOYs). Pass NULL
##'   to leave the global RNG state untouched.

post.distns <- function(model.gam, newdata, vars, n=100, terms=F, lwr=0.025, upr=0.975, return.sims=F, seed=1034){
  # Note: this function can be used to generate a 95% CI on the full model.gam OR terms

  # -----------
  # Simulating a posterior distribution of Betas to get variance on non-linear functions
  # This is following Gavin Simpson's post here:
  # http://www.fromthebottomoftheheap.net/2011/06/12/additive-modelling-and-the-hadcrut3v-global-mean-temperature-series/
  # His handy-dandy functions can be found here: https://github.com/gavinsimpson/random_code/
  #      Including the derivative funcition that will probably come in handy later
  # March 2017: Gavin updated his blog posts to correct his confidence interval methodology:
  #    http://www.fromthebottomoftheheap.net/2016/12/15/simultaneous-interval-revisited/
  #    http://www.fromthebottomoftheheap.net/2017/03/21/simultaneous-intervals-for-derivatives-of-smooths/
  #  - NOTE: I don't think this makes a difference for me because I've always been working with full simulations, so I
  #          *think* I've basically been doing the simultaneous interval.  Gavin's way would be less memory intensive,
  #          but I like my way.
  # -----------
  library(MASS)
  if (!is.null(seed)) set.seed(seed)
  
  # If the model.gam is a mixed model.gam (gamm) rather than a normal gam, extract just the gam portion
  if(class(model.gam)[[1]]=="gamm") model.gam <- model.gam$gam
  
  
  coef.gam <- coef(model.gam)
  
  # Generate a random distribution of betas using the covariance matrix
  Rbeta <- mvrnorm(n=n, coef(model.gam), vcov(model.gam))
  
  # Create the prediction matrix
  Xp <- predict(model.gam, newdata=newdata, type="lpmatrix")
  
  # Some handy column indices
  cols.list <- list(Site = which(substr(names(coef.gam),1,4)=="Site" | substr(names(coef.gam),1,11)=="(Intercept)"))
  for(v in vars){
    cols.list[[v]] <- which(substr(names(coef.gam),1,(nchar(v)+3))==paste0("s(",v,")"))
  }
  
  # sim.list <- list()
  if(terms==T){
    for(v in vars){
      sim.tmp <- data.frame(Xp[,cols.list[[v]]] %*% t(Rbeta[,cols.list[[v]]]) )
      
      # Saving the quantiles into a data frame
      df.tmp <- data.frame(Effect = v, 
                           x      = newdata[,v],
                           mean   = apply(sim.tmp, 1, mean), 
                           lwr    = apply(sim.tmp, 1, quantile, lwr, na.rm=T), 
                           upr    = apply(sim.tmp, 1, quantile, upr, na.rm=T))
      
      #if("Site"       %in% names(newdata)) df.tmp$Site       <- newdata$Site
      #if("Extent"     %in% names(newdata)) df.tmp$Extent     <- newdata$Extent
      #if("Resolution" %in% names(newdata)) df.tmp$Resolution <- newdata$Resolution
      #if("PlotID"     %in% names(newdata)) df.tmp$PlotID     <- newdata$PlotID
      #if("TreeID"     %in% names(newdata)) df.tmp$TreeID     <- newdata$TreeID
      #if("PFT"        %in% names(newdata)) df.tmp$PFT        <- newdata$PFT
      
      if(v == vars[1]) df.out <- df.tmp else df.out <- rbind(df.out, df.tmp)
      
      # Creating a data frame storing all the simulations for more robust analyses
      sim.tmp$Effect      <- v
      sim.tmp$x           <- newdata[,v]
      
      #if("Site"       %in% names(newdata)) sim.tmp$Site       <- newdata$Site
      #if("Extent"     %in% names(newdata)) sim.tmp$Extent     <- newdata$Extent
      #if("Resolution" %in% names(newdata)) sim.tmp$Resolution <- newdata$Resolution
      #if("PlotID"     %in% names(newdata)) sim.tmp$PlotID     <- newdata$PlotID
      #if("TreeID"     %in% names(newdata)) sim.tmp$TreeID     <- newdata$TreeID
      #if("PFT"        %in% names(newdata)) sim.tmp$PFT        <- newdata$PFT
      
      sim.tmp             <- sim.tmp[,c((n+1):ncol(sim.tmp), 1:n)]
      
      if(v == vars[1]) df.sim <- sim.tmp else df.sim <- rbind(df.sim, sim.tmp)
      
    }
    
  } else {
    sim1 <- Xp %*% t(Rbeta) # simulates n predictions of the response variable in the model.gam
    
    df.out <- data.frame(mean       = apply(sim1, 1, mean, na.rm=T), 
                         lwr        = apply(sim1, 1, quantile, lwr, na.rm=T), 
                         upr        = apply(sim1, 1, quantile, upr, na.rm=T))
    
    #if("Site"       %in% names(newdata)) df.out$Site       <- newdata$Site
    #if("Extent"     %in% names(newdata)) df.out$Extent     <- newdata$Extent
    #if("Resolution" %in% names(newdata)) df.out$Resolution <- newdata$Resolution
    #if("Year"       %in% names(newdata)) df.out$Year       <- newdata$Year
    #if("PlotID"     %in% names(newdata)) df.out$PlotID     <- newdata$PlotID
    #if("TreeID"     %in% names(newdata)) df.out$TreeID     <- newdata$TreeID
    #if("PFT"        %in% names(newdata)) df.out$PFT        <- newdata$PFT
    
    df.sim <- data.frame(X      = 1:nrow(newdata))
    
    #if("Site"       %in% names(newdata)) df.sim$Site       <- newdata$Site
    #if("Extent"     %in% names(newdata)) df.sim$Extent     <- newdata$Extent
    #if("Resolution" %in% names(newdata)) df.sim$Resolution <- newdata$Resolution
    #if("Year"       %in% names(newdata)) df.sim$Year       <- newdata$Year
    #if("PlotID"     %in% names(newdata)) df.sim$PlotID     <- newdata$PlotID
    #if("TreeID"     %in% names(newdata)) df.sim$TreeID     <- newdata$TreeID
    #if("PFT"        %in% names(newdata)) df.sim$PFT        <- newdata$PFT
    
    for(v in vars){
      df.out[,v] <- newdata[,v]
      df.sim[,v] <- newdata[,v]
    }
    df.sim <- cbind(df.sim, sim1)
    
  }
  
  if(return.sims==T){
    out <- list()
    out[["ci"]]	 <- df.out
    out[["sims"]] <- df.sim
  } else {
    out <- df.out
  }

  return(out)
}

# ==============================================================================
# saveRDS_validated — atomic write + read-back validation for CIFS-corruption defense
#
# The //ascend.egs.anl.gov mount has been observed to silently produce corrupt
# files when saveRDS() crosses a midnight CDT window (likely a backup window
# or scheduled disruption). The write returns success; the file looks valid at
# the OS level (correct xz magic bytes); but readRDS() later fails with
# "lzma decoder corrupt data". This bit:
#   - 03 v2 on 2026-05-09 00:00 → year_predictions_posteriors/2015/doy_205.rds
#   - 03 v3 on 2026-05-13 00:00 → year_predictions_posteriors/2025/doy_086.rds
#                              + year_predictions_posteriors/2025/doy_322.rds
# All three corrupt files were written within a 1-minute window of midnight CDT;
# all three were detected only when downstream 04 tried to read them days later.
#
# Two-layer defense (added 2026-05-14):
#
#   (1) ATOMIC PUBLICATION via write-to-tmp + file.rename.
#       saveRDS writes to <file>.tmp first; on validation success, file.rename
#       atomically swaps it into place. The final filename only ever contains
#       a fully-written, validated payload — there is no window where another
#       process / a resume-scan / a downstream read can see a partial file.
#       Atomicity guaranteed by the SET_INFO rename op in SMB2 (the protocol
#       used by this CIFS mount).
#
#   (2) READ-BACK VALIDATION via readRDS of the .tmp before rename.
#       Catches lzma stream corruption, truncated payloads, and any other
#       deserialization failure. The validation read happens BEFORE the rename,
#       so a failed validation leaves the .tmp behind (cleaned up before retry)
#       and the final filename is unchanged.
#
# Caveat (r-reviewer 2026-05-14): the readback may be served from the local
# page cache rather than re-read from the CIFS server (cache=strict on this
# mount). In the worst case (server got partial bytes but local cache has the
# full intended payload) the validation could be fooled. The atomic-publication
# layer (1) is the primary defense in that scenario: the .tmp on the server is
# truncated, the rename promotes a truncated file, and a future read (e.g. by
# 04 a few days later) detects the issue. Until we instrument with O_DIRECT or
# explicit cache invalidation, layer (1) carries the load there.
#
# Cost: one extra readRDS per posterior write. For 78 MB xz-compressed per-DOY
# posteriors through CIFS, full read-back is ~5-15s (page-cached: ~1-2s).
# Across a full 03 run (4,745 writes) that's anywhere from ~3 hours (cached)
# to ~12-15 hours (cold reads) of validation overhead on top of the ~40 hr
# fit time. Estimated 5-30% overhead range — accept the upper bound.
#
# Defaults: 3 attempts, 5s/30s/90s backoff. The 90s tail catches a typical
# midnight backup window (1-3 minutes); longer outages will exhaust retries
# and stop() loudly so the failure surfaces in the run log.
# ==============================================================================

# ==============================================================================
# readRDS_retry — defend against transient CIFS read errors
#
# Symmetric to saveRDS_validated but addresses the read side. 04 v2 (2026-05-13)
# hit a transient CIFS hiccup at ~midnight CDT that took out 281 of 365 DOYs in
# year 2025: all 3 workers succeeded for their first ~28 DOYs, then failed
# simultaneously with "cannot open the connection" / "error reading from
# connection" from readRDS. This helper retries the read with backoff so a
# typical 10-60s CIFS hiccup doesn't lose work.
#
# Defaults: 3 attempts, 5s/15s/30s backoff. Worst-case extra wait per failed
# read: 50s. Catches all readRDS errors (we don't enumerate "transient"
# subclasses — anything that fails twice + waits ~50s is unlikely to recover
# on a 4th try regardless).
#
# Originally lived inline in 04_calculate_anomalies.R; moved here 2026-05-15
# so 04 and 06 share a single definition. See header of saveRDS_validated for
# the corresponding write-side defense.
# ==============================================================================

readRDS_retry <- function(path, max_attempts = 3L,
                          backoff_secs = c(5, 15, 30)) {
  stopifnot(length(backoff_secs) >= max_attempts - 1L)
  last_err <- NULL
  for (attempt in seq_len(max_attempts)) {
    result <- tryCatch(readRDS(path), error = function(e) e)
    if (!inherits(result, "error")) return(result)
    last_err <- result
    if (attempt < max_attempts) {
      Sys.sleep(backoff_secs[attempt])
    }
  }
  stop(sprintf("readRDS(%s) failed after %d attempts. Last error: %s",
               path, max_attempts, conditionMessage(last_err)))
}

saveRDS_validated <- function(object, file, compress = "xz",
                              max_attempts = 3L,
                              backoff_secs = c(5, 30, 90)) {
  # Defensive: ensure caller passed enough backoff entries for max_attempts-1
  # sleeps (sleep happens between attempts, not after the last). Without this,
  # bumping max_attempts without extending backoff_secs would NA-poison
  # Sys.sleep at runtime.
  stopifnot(length(backoff_secs) >= max_attempts - 1L)

  tmp_file <- paste0(file, ".tmp")
  last_err <- NULL

  for (attempt in seq_len(max_attempts)) {
    # Layer (1): write to .tmp, never directly to the final filename.
    saveRDS(object, tmp_file, compress = compress)

    # Layer (2): read-back validation before promoting via rename.
    # Any error (corrupt lzma, truncated stream, transient CIFS read failure,
    # etc.) → treat as a failed write, clean up, and retry.
    test <- tryCatch(readRDS(tmp_file), error = function(e) e)

    if (!inherits(test, "error")) {
      # Atomic publication. file.rename returns FALSE on failure (CIFS quirks,
      # permission issues, etc.) — surface that as a stop() rather than silently
      # leaving the .tmp orphaned and the final file missing.
      ok <- file.rename(tmp_file, file)
      if (!isTRUE(ok)) {
        suppressWarnings(file.remove(tmp_file))
        stop(sprintf(
          "saveRDS_validated(%s): file.rename from .tmp failed", file
        ))
      }
      return(invisible(NULL))
    }

    last_err <- test
    # Clean up the bad .tmp before retrying (avoid disk leaks across retries).
    suppressWarnings(file.remove(tmp_file))

    if (attempt < max_attempts) {
      Sys.sleep(backoff_secs[attempt])
    }
  }

  stop(sprintf(
    "saveRDS_validated(%s) failed after %d attempts. Last validation error: %s",
    file, max_attempts, conditionMessage(last_err)
  ))
}
