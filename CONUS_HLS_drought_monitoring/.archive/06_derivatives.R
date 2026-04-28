# ==============================================================================
# 06_derivatives.R
#
# Purpose: Calculate derivatives for phenology timing (TABLED FOR LATER)
#
# Status: This script is tabled pending decisions on:
#   1. Whether discrete differences between adjacent DOYs are sufficient
#   2. Whether to fit secondary temporal smooth on DOY-looped predictions
#   3. How to calculate derivative uncertainty
#
# Reference implementations in .archive/:
#   - 03_derivatives_baseline.R (temporal GAM derivatives)
#   - 05_derivatives_individual_years.R (year-specific derivatives)
#
# Potential approaches:
#   A. Discrete differences: deriv[day] = norm[day] - norm[day-1]
#   B. Secondary smooth: Fit s(yday) to DOY predictions, then calc.derivs()
#
# ==============================================================================

# TODO: Revisit after main workflow (02-04-05) is working

cat("Script 06_derivatives.R - TABLED FOR LATER\n")
cat("See CHANGELOG.md for discussion\n")
cat("Reference implementations in .archive/\n")
