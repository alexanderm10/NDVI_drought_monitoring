# ==============================================================================
# GAM UTILITY FUNCTIONS
# ==============================================================================
# Purpose: Posterior distributions and derivative calculations for GAM models
# Source: Adapted from Juliana's workflow (0_Calculate_GAMM_Posteriors/Derivs)
# Author: M. Ross Alexander
# Date: 2025-10-21
# ==============================================================================

library(MASS)
library(mgcv)

# ==============================================================================
# POSTERIOR DISTRIBUTIONS
# ==============================================================================

#' Calculate posterior distributions for GAM predictions
#'
#' Generates Bayesian posterior simulations to quantify uncertainty in GAM
#' predictions using the variance-covariance matrix of model coefficients.
#'
#' @param model.gam A GAM or GAMM object
#' @param newdata Data frame for predictions
#' @param vars Character vector of spline predictors to simulate
#' @param n Number of posterior simulations (default: 100)
#' @param terms Logical: model only spline parameters (no intercepts)? (default: FALSE)
#' @param lwr Lower bound for confidence interval (default: 0.025 for 95% CI)
#' @param upr Upper bound for confidence interval (default: 0.975 for 95% CI)
#' @param return.sims Logical: return raw simulations? (default: FALSE)
#'
#' @return Data frame with mean, lwr, upr columns (and simulations if return.sims=TRUE)
#'
#' @details
#' Following Gavin Simpson's approach for simultaneous confidence intervals:
#' - http://www.fromthebottomoftheheap.net/2016/12/15/simultaneous-interval-revisited/
#' - Simulates coefficient distributions using mvrnorm() with model's vcov matrix
#' - Projects simulations through prediction matrix for robust uncertainty estimates
#'
#' @examples
#' gam_model <- gam(NDVI ~ s(yday, k=12), data=ndvi_data)
#' newdata <- data.frame(yday=1:365)
#' posteriors <- post.distns(gam_model, newdata, vars="yday", n=1000)
#'
post.distns <- function(model.gam, newdata, vars, n=100, terms=FALSE,
                        lwr=0.025, upr=0.975, return.sims=FALSE) {

  set.seed(1034)

  # Extract GAM from GAMM if necessary
  if(class(model.gam)[[1]]=="gamm") model.gam <- model.gam$gam

  coef.gam <- coef(model.gam)

  # Generate random distribution of betas using covariance matrix
  Rbeta <- mvrnorm(n=n, coef(model.gam), vcov(model.gam))

  # Create prediction matrix
  Xp <- predict(model.gam, newdata=newdata, type="lpmatrix")

  # Column indices for spline terms
  cols.list <- list(Site = which(substr(names(coef.gam),1,4)=="Site" |
                                  substr(names(coef.gam),1,11)=="(Intercept)"))
  for(v in vars){
    cols.list[[v]] <- which(substr(names(coef.gam),1,(nchar(v)+3))==paste0("s(",v,")"))
  }

  if(terms==TRUE){
    # Separate predictions for each spline term
    for(v in vars){
      sim.tmp <- data.frame(Xp[,cols.list[[v]]] %*% t(Rbeta[,cols.list[[v]]]) )

      # Calculate quantiles
      df.tmp <- data.frame(
        Effect = v,
        x      = newdata[,v],
        mean   = apply(sim.tmp, 1, mean),
        lwr    = apply(sim.tmp, 1, quantile, lwr, na.rm=TRUE),
        upr    = apply(sim.tmp, 1, quantile, upr, na.rm=TRUE)
      )

      if(v == vars[1]) df.out <- df.tmp else df.out <- rbind(df.out, df.tmp)

      # Store simulations if requested
      sim.tmp$Effect <- v
      sim.tmp$x      <- newdata[,v]
      sim.tmp        <- sim.tmp[,c((n+1):ncol(sim.tmp), 1:n)]

      if(v == vars[1]) df.sim <- sim.tmp else df.sim <- rbind(df.sim, sim.tmp)
    }

  } else {
    # Full model predictions
    sim1 <- Xp %*% t(Rbeta)

    df.out <- data.frame(
      mean = apply(sim1, 1, mean, na.rm=TRUE),
      lwr  = apply(sim1, 1, quantile, lwr, na.rm=TRUE),
      upr  = apply(sim1, 1, quantile, upr, na.rm=TRUE)
    )

    df.sim <- data.frame(X = 1:nrow(newdata))

    for(v in vars){
      df.out[,v] <- newdata[,v]
      df.sim[,v] <- newdata[,v]
    }
    df.sim <- cbind(df.sim, sim1)
  }

  if(return.sims==TRUE){
    out <- list()
    out[["ci"]]   <- df.out
    out[["sims"]] <- df.sim
  } else {
    out <- df.out
  }

  return(out)
}

# ==============================================================================
# DERIVATIVE CALCULATIONS
# ==============================================================================

#' Calculate derivatives of GAM smooth terms
#'
#' Computes first derivatives of GAM splines with confidence intervals to
#' statistically detect periods of significant change (e.g., vegetation green-up,
#' senescence onset).
#'
#' @param model.gam A GAM or GAMM object
#' @param newdata Data frame for derivative evaluation
#' @param vars Character vector of variables to compute derivatives for
#' @param n Number of posterior simulations for uncertainty (default: 100)
#' @param eps Finite difference step size (default: 1e-7)
#' @param alpha Significance level for confidence intervals (default: 0.05)
#' @param lwr Lower quantile (default: NULL, computed from alpha)
#' @param upr Upper quantile (default: NULL, computed from alpha)
#' @param return.sims Logical: return raw simulations? (default: FALSE)
#'
#' @return Data frame with mean derivative, lwr, upr, sig (significance flag), var
#'
#' @details
#' Following Gavin Simpson's derivative approach:
#' - https://github.com/gavinsimpson/random_code/blob/master/derivFun.R
#' - Uses finite difference approximation: (f(x+eps) - f(x)) / eps
#' - Significance: if lwr*upr > 0, derivative excludes zero (marked with "*")
#' - Useful for detecting phenological transitions (green-up, senescence)
#'
#' @examples
#' gam_model <- gam(NDVI ~ s(yday, k=12), data=ndvi_data)
#' newdata <- data.frame(yday=1:365)
#' derivs <- calc.derivs(gam_model, newdata, vars="yday", n=1000)
#' # Check where significant change occurs
#' signif_change <- derivs[!is.na(derivs$sig), ]
#'
calc.derivs <- function(model.gam, newdata, vars, n=100, eps=1e-7,
                       alpha=0.05, lwr=NULL, upr=NULL, return.sims=FALSE) {

  set.seed(1124)

  # Extract GAM from GAMM if necessary
  if(class(model.gam)[[1]]=="gamm") model.gam <- model.gam$gam

  # Calculate confidence bounds if not specified
  if(is.null(lwr) & is.null(upr)){
    lwr <- alpha/2
    upr <- 1 - alpha/2
  }

  # Get model terms
  m.terms <- attr(terms(model.gam), "term.labels")

  # Find numeric columns
  df.model <- model.frame(model.gam)
  cols.num <- vector()
  for(j in 1:ncol(df.model)){
    if(is.numeric(df.model[,j])) cols.num <- c(cols.num, names(df.model)[j])
  }

  # Generate random distribution of betas
  coef.gam <- coef(model.gam)
  Rbeta <- mvrnorm(n=n, model.gam$coefficients, model.gam$Vp)

  # Prediction matrix at x
  X0 <- predict(model.gam, newdata=newdata, type="lpmatrix")

  # Prediction matrix at x + eps
  newD <- newdata
  newD[,m.terms[m.terms %in% cols.num]] <- newdata[,m.terms[m.terms %in% cols.num]] + eps
  X1 <- predict(model.gam, newdata=newD, type="lpmatrix")

  # Finite difference approximation of first derivative
  Xp <- (X1 - X0) / eps

  # Loop through variables
  for(v in vars) {
    Xi <- Xp * 0  # Zero out matrix
    want <- which(substr(names(coef.gam),1,(nchar(v)+3))==paste0("s(",v,")"))
    Xi[, want] <- Xp[, want]
    df <- Xi %*% coef(model.gam)

    # Generate distribution of simulated derivatives
    sim.tmp <- data.frame(Xp[,want] %*% t(Rbeta[,want]) )
    sim.mean <- apply(sim.tmp, 1, mean)
    sim.lwr <- apply(sim.tmp, 1, quantile, lwr)
    sim.upr <- apply(sim.tmp, 1, quantile, upr)

    # Significance: CI excludes zero
    sig <- as.factor(ifelse(sim.lwr * sim.upr > 0, "*", NA))

    df.tmp <- data.frame(
      newdata,
      mean = sim.mean,
      lwr  = sim.lwr,
      upr  = sim.upr,
      sig  = sig,
      var  = as.factor(v)
    )

    sim.tmp$var <- as.factor(v)

    if(v == vars[1]){
      df.out <- df.tmp
      df.sim <- sim.tmp
    } else {
      df.out <- rbind(df.out, df.tmp)
      df.sim <- rbind(df.sim, sim.tmp)
    }
  }

  if(return.sims==TRUE){
    out <- list()
    out[["ci"]]   <- df.out
    out[["sims"]] <- df.sim
  } else {
    out <- df.out
  }

  return(out)
}

# ==============================================================================
# CONVENIENCE FUNCTIONS
# ==============================================================================

#' Check if posterior/derivative functions are loaded
check_gam_utilities <- function() {
  cat("✓ GAM utility functions loaded:\n")
  cat("  - post.distns(): Bayesian posterior simulations\n")
  cat("  - calc.derivs(): Derivative calculations with significance\n\n")
  cat("Source: Adapted from Juliana's workflow\n")
  cat("References:\n")
  cat("  - Gavin Simpson (2016): Simultaneous confidence intervals\n")
  cat("  - Gavin Simpson (2017): Derivatives of smooths\n\n")
}

# Auto-run check on source
check_gam_utilities()
