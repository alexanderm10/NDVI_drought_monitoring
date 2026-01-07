# Time Series Gaps Analysis and Solutions

**Date:** 2026-01-07
**Issue:** Systematic gaps in regional time series plots (early Jan, late Dec, scattered through year)

---

## Root Cause Identified

### The 33% Coverage Threshold

**Location:** `03_doy_looped_year_predictions.R` line 45
```r
min_pixel_coverage = 0.33  # Require 33% of pixels to have data
```

**Implementation:** Script 03 line 269-272
```r
n_pixels_with_data <- length(unique(df_subset$pixel_id))
if (n_pixels_with_data < n_pixels * config$min_pixel_coverage) {
  return(list(yday = day, result = NULL, ...))  # SKIP THIS DOY
}
```

**Effect:**
- Threshold: 41,513 pixels (33% of 125,798)
- If a DOY's 16-day window has <41,513 pixels with observations → **no prediction generated**
- Result: Missing DOYs in output

---

## Evidence

### 2024 Example

```
Total DOYs: 365
DOYs with predictions: 198 (54%)
DOYs without predictions: 167 (46%)

Missing DOY ranges:
- Jan 1 - Feb 4 (DOYs 1-35): 35 days
- Dec 22 - Dec 31 (DOYs 356-365): 10 days
- Scattered gaps throughout year: 122 additional days
```

### Why These DOYs Fail

**Winter Months (Jan, Dec):**
- Snow cover → Fmask removes observations
- Cloud cover → fewer clear scenes
- Short days → less satellite coverage
- **Result:** <1-5% pixel coverage → fails 33% threshold

**Scattered Gaps:**
- Cloudy periods during growing season
- Satellite downtime or data gaps
- Processing issues
- **Result:** 5-30% coverage → fails 33% threshold

---

## Comparison with Juliana's Approach

### Her Implementation (spatial_analysis/06_year_splines_yday_looped_.R)

**Line 79:**
```r
if(length(unique(df_subset$xy[!is.na(df_subset$NDVIReprojected)])) < nPixels*0.33) next
```

**Same threshold!** Juliana also uses 33% and skips low-coverage DOYs.

### Why This Works for Her

1. **Smaller spatial domain** (Chicago area)
   - Fewer total pixels (~hundreds vs ~125k)
   - More uniform weather patterns
   - Higher relative coverage

2. **Different visualization approach**
   - May not show gaps as prominently
   - Could use different aggregation methods
   - Possibly smooths/interpolates in visualization

3. **Study period differences**
   - Different years may have better coverage
   - Regional climate differences

---

## Solutions

### Option 1: Lower the Threshold (Quick Fix)

**Change:** Reduce `min_pixel_coverage` from 0.33 to lower value

```r
# Current
min_pixel_coverage = 0.33  # 41,513 pixels

# Options
min_pixel_coverage = 0.10  # 12,580 pixels (10%)
min_pixel_coverage = 0.05  # 6,290 pixels (5%)
min_pixel_coverage = 0.01  # 1,258 pixels (1%)
```

**Pros:**
- Simple - one line change
- Generates predictions for more DOYs
- Fills visualization gaps

**Cons:**
- Low-coverage predictions less reliable
- Spatial interpolation over larger gaps
- Potentially biased estimates (spatially non-representative sample)
- Larger uncertainty bounds

**Recommendation:** Try 10% threshold
- Still requires ~12k pixels with data
- Conservative enough for quality
- Should fill most gaps

---

### Option 2: Temporal Interpolation (Better for Viz)

**Approach:** Keep threshold but interpolate missing DOYs for visualization only

**Implementation in Script 05:**
```r
# After loading anomaly data, interpolate missing DOYs
timeseries_df <- timeseries_df %>%
  complete(date = seq.Date(min(date), max(date), by="day")) %>%
  arrange(date) %>%
  mutate(
    # Linear interpolation for mean anomaly
    mean_anom = zoo::na.approx(mean_anom, na.rm=FALSE),
    # Interpolate or widen bounds for uncertainty
    lwr_anom = zoo::na.approx(lwr_anom, na.rm=FALSE),
    upr_anom = zoo::na.approx(upr_anom, na.rm=FALSE),
    # Flag interpolated points
    interpolated = is.na(mean_anom)
  )
```

**Pros:**
- Preserves prediction quality (high threshold)
- Smooth visualizations
- Clear flagging of interpolated vs observed
- Doesn't affect derivatives or statistics

**Cons:**
- Interpolated values are artificial
- Can't use for quantitative analysis
- Requires documentation/caveats

---

### Option 3: Expand Temporal Window (More Data)

**Approach:** Increase window from 16 days to 24+ days

**Change in Script 03:**
```r
# Current
window_size = 16

# Expanded
window_size = 24  # or 30
```

**Pros:**
- More observations per window → higher coverage
- Still uses real data (not artificial)
- Better predictions for sparse periods

**Cons:**
- Blurs temporal resolution (less "current")
- Longer windows smooth out rapid changes
- Inconsistent with Juliana's 16-day approach

**Note:** Juliana tested 16 vs 24 day windows (see her code comments)

---

### Option 4: Hybrid Spatial-Temporal Smoothing

**Approach:** For low-coverage DOYs, borrow from neighboring DOYs

**Implementation:**
```r
# In Script 03, for DOYs below threshold:
# Instead of skipping, use ±3 day window of DOYs
# Fit GAM with s(yday, k=5) + s(x,y) interaction
# Adds temporal smoothing dimension
```

**Pros:**
- Fills gaps with semi-realistic estimates
- Maintains spatial patterns
- Smooth temporal transitions

**Cons:**
- More complex implementation
- Harder to interpret uncertainty
- May over-smooth rapid events

---

### Option 5: Separate Baselines for Season

**Approach:** Use different thresholds by season

```r
# Winter (DOY 1-60, 335-365): Lower threshold
if (yday <= 60 | yday >= 335) {
  min_pixel_coverage = 0.10
} else {
  # Growing season: Stricter threshold
  min_pixel_coverage = 0.33
}
```

**Pros:**
- Adaptive to data availability
- Maintains quality in high-data seasons
- Accepts lower quality in unavoidable gaps

**Cons:**
- Inconsistent methodology across year
- Harder to document/justify
- Uncertainty varies by season

---

## Recommendations

### Immediate Action (Today)

**Test Lower Threshold:**

1. Edit `03_doy_looped_year_predictions.R`:
   ```r
   min_pixel_coverage = 0.10  # Was 0.33
   ```

2. Re-run Script 03 for one test year (2024):
   ```bash
   docker exec conus-hls-drought-monitor Rscript 03_doy_looped_year_predictions.R
   ```

3. Check improvement:
   - Count DOYs with predictions (should be >198)
   - Compare time series plot (fewer gaps?)
   - Check R² values for new DOYs (quality check)

---

### Medium-Term Solution

**Implement Visualization Interpolation (Option 2):**

- Keep 33% threshold for predictions (quality)
- Add interpolation step in Script 05 for smooth plots
- Document clearly in figure captions
- Use only for visualization, not analysis

**Benefits:**
- Best of both worlds
- High-quality predictions where data exists
- Smooth visualizations for presentation
- Transparent about limitations

---

### Long-Term Consideration

**Evaluate if Gaps Matter:**

1. **For drought detection:** Gaps in winter (Jan-Feb, Dec) are less critical - vegetation dormant anyway

2. **For operational monitoring:** Growing season (Apr-Oct) is priority - check if gaps exist there

3. **For validation:** Compare to USDM temporal coverage - do they have same gaps?

4. **Scientific question:** Is it better to have:
   - Fewer high-quality predictions (current 33% threshold)
   - More predictions with variable quality (lower threshold)

---

## What Juliana Did

Based on code inspection, Juliana:

1. **Used same 33% threshold** ✅
2. **Accepted gaps** in low-coverage periods
3. **May have had better coverage** due to smaller domain/different region
4. **Visualizations may handle gaps differently** (need to see her plots)

**Key insight:** The threshold isn't wrong - it's a **quality control** measure. The question is whether you want to prioritize:
- **Prediction quality** (keep 33%) → accept gaps
- **Visualization completeness** (lower threshold or interpolate) → accept lower quality

---

## Next Steps

1. **Quick test:** Lower threshold to 10% and re-run 2024
2. **Evaluate:** Check R² and uncertainty for new DOYs
3. **Decide:** Based on quality, choose threshold or interpolation approach
4. **Document:** Update scripts with rationale for chosen threshold

---

## Technical Details

### Current Coverage Statistics (2024)

| Metric | Value |
|--------|-------|
| Total pixels | 125,798 |
| 33% threshold | 41,513 pixels |
| DOYs with predictions | 198 (54%) |
| DOYs without predictions | 167 (46%) |
| Earliest prediction | DOY 36 (Feb 5) |
| Latest prediction | DOY 355 (Dec 21) |

### Expected Improvement with 10% Threshold

| Threshold | Required Pixels | Expected DOY Coverage |
|-----------|----------------|---------------------|
| 33% | 41,513 | ~198 DOYs (54%) |
| 10% | 12,580 | ~280 DOYs (77%) |
| 5% | 6,290 | ~320 DOYs (88%) |
| 1% | 1,258 | ~350 DOYs (96%) |

*Note: These are estimates based on data distribution*

---

## Conclusion

The gaps in your time series are **intentional quality control**, not a bug. The 33% threshold ensures predictions are based on sufficient spatial coverage. You have three main options:

1. **Lower threshold** → more DOYs, potentially lower quality
2. **Interpolate for viz** → keep quality, smooth plots
3. **Accept gaps** → emphasize quality over completeness

**My recommendation:** Start with **Option 1 (test 10% threshold)** to see if quality remains acceptable. If yes, use it. If no, implement **Option 2 (interpolation for visualization only)**.
