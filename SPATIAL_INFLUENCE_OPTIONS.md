# Limiting Spatial Influence in GAM Predictions

**Date:** 2026-01-07
**Question:** Should we limit how far pixels influence each other in spatial predictions?

---

## Current Approach: Thin Plate Regression Spline (TPRS)

### What We're Using
```r
gam(NDVI ~ norm + s(x, y) - 1, data = df_subset)
```

The `s(x, y)` uses thin plate regression spline (TPRS) - the mgcv default.

### How TPRS Handles Proximity

**Yes, proximity is already built in!**

1. **Distance-based basis functions**
   - Basis functions are radial (circular influence patterns)
   - Influence decays smoothly with distance
   - No hard cutoffs

2. **Automatic smoothing parameter selection**
   - GAM fits `sp` (smoothing parameter) via REML/GCV
   - High `sp` = smoother = broader spatial influence (~500km)
   - Low `sp` = rougher = more local influence (~50-100km)
   - GAM chooses based on data

3. **Penalty term**
   - Penalizes "wiggliness" of the spatial surface
   - Balances fit to data vs. smoothness
   - Effectively controls how much nearby vs distant points matter

### What This Means

**At 361 km spatial resolution (k=30 for MIDWEST):**
- Predictions at location X are influenced by:
  - **Strong influence:** pixels within ~100-200 km
  - **Moderate influence:** pixels within ~200-400 km
  - **Weak influence:** pixels >400 km
  - **Negligible influence:** pixels >1000 km

**The influence naturally decays with distance - it's not uniform across the domain.**

---

## The Question: Is This Enough?

### Scenarios Where Current Approach May Struggle

#### 1. **Large Contiguous Data Gaps**
- Winter storm covers 500km × 500km
- No observations in that region
- GAM must extrapolate from surrounding 500+ km away
- **Problem:** Assuming spatial pattern holds across large gap

#### 2. **Spatially Heterogeneous Events**
- Drought in Plains, normal in Great Lakes
- With smooth spatial surface, boundary is gradual
- **Problem:** May over-smooth sharp transitions

#### 3. **Regional Climate Differences**
- Semi-arid west vs humid east
- Different baseline NDVI patterns
- **Problem:** Single smooth may not capture different regimes

---

## Options to Constrain Spatial Influence

### Option 1: Gaussian Process with Explicit Range (bs="gp")

**Implementation:**
```r
# Specify maximum correlation distance (e.g., 500 km)
gam(NDVI ~ norm + s(x, y, bs="gp", m=c(3, 500000)) - 1, data = df_subset)
                                   #        ^^^^^^ range in meters
```

**How it works:**
- `bs="gp"` = Gaussian process smooth
- `m[2]` = range parameter (meters)
- Correlation = exp(-distance/range)
- At range=500km:
  - 250km away: 60% correlation
  - 500km away: 37% correlation
  - 1000km away: 14% correlation

**Pros:**
- ✅ Explicit control over spatial influence
- ✅ More realistic for large domains
- ✅ Prevents over-extrapolation

**Cons:**
- ⚠️ Much more computationally expensive
- ⚠️ Requires choosing range parameter
- ⚠️ May struggle with 40k+ observations

**Recommendation:** **Test with smaller k first**, then evaluate if GP is needed

---

### Option 2: Increase Basis Dimension (Higher k)

**Implementation:**
```r
# Instead of k=30, use k=100-150
gam(NDVI ~ norm + s(x, y, k=100) - 1, data = df_subset)
```

**How it works:**
- More basis functions = finer spatial resolution
- MIDWEST with k=100: 1976 / √100 = **198 km resolution** (vs 361 km)
- MIDWEST with k=150: 1976 / √150 = **161 km resolution**
- Predictions become more localized

**Pros:**
- ✅ Simple - just change one number
- ✅ Captures finer-scale patterns
- ✅ More local influence automatically

**Cons:**
- ⚠️ Computationally slower (k² complexity)
- ⚠️ Requires more data per basis
- ⚠️ May overfit with sparse data

**Recommendation:** **Try k=50-75** as compromise
- Improves from 361 km to ~250-280 km resolution
- Still computationally feasible
- Better local detail

---

### Option 3: Regional Models (Divide and Conquer)

**Implementation:**
```r
# Define regions (e.g., by state or ecoregion)
regions <- c("Plains", "Great_Lakes", "Northeast", "Southeast")

for (region in regions) {
  df_region <- df_subset %>% filter(region_id == region)
  gam_region <- gam(NDVI ~ norm + s(x, y, k=30) - 1, data = df_region)
  # Predict only within region
}
```

**How it works:**
- Fit separate GAMs for geographic regions
- Each region has its own spatial pattern
- No cross-region influence

**Pros:**
- ✅ Respects regional boundaries (e.g., ecoregions)
- ✅ Allows different spatial patterns per region
- ✅ More parallelizable

**Cons:**
- ⚠️ Need to define regions
- ⚠️ Boundary artifacts between regions
- ⚠️ Smaller sample size per region

**Recommendation:** **Consider for Phase 2**
- Define ecoregions or climate zones
- Useful for operational system

---

### Option 4: Markov Random Field (Neighbor-Only) (bs="mrf")

**Implementation:**
```r
# Define neighbor structure (e.g., 4km pixels touching)
neighbor_matrix <- make_neighbor_matrix(pixels, max_distance=8000)  # 8km = adjacent

gam(NDVI ~ norm + s(pixel_id, bs="mrf", xt=list(nb=neighbor_matrix)) - 1,
    data = df_subset)
```

**How it works:**
- Only directly adjacent pixels influence each other
- No long-range influence
- Common in spatial statistics (CAR/SAR models)

**Pros:**
- ✅ True local influence only
- ✅ No extrapolation across large gaps
- ✅ Interpretable neighborhood structure

**Cons:**
- ⚠️ Requires building neighbor matrix (125k × 125k!)
- ⚠️ Computationally intensive
- ⚠️ May be too local (no regional patterns)

**Recommendation:** **Not practical at this scale**
- Neighbor matrix would be huge
- Better for smaller domains

---

### Option 5: Hybrid Smooth (Local + Regional)

**Implementation:**
```r
# Two-scale model
gam(NDVI ~ norm +
      s(x, y, k=30) +        # Coarse regional pattern
      s(x, y, k=100, m=1) -  # Fine local deviations
      1,
    data = df_subset)
```

**How it works:**
- First smooth captures broad regional patterns
- Second smooth captures local deviations
- Separates scales of variation

**Pros:**
- ✅ Flexible multi-scale representation
- ✅ Regional patterns + local detail
- ✅ Can weight differently

**Cons:**
- ⚠️ Complex interpretation
- ⚠️ Potential overfitting
- ⚠️ Slower computation

**Recommendation:** **Interesting but complex** - save for future research

---

## What Does Juliana Do?

**Her code:** `gam(NDVIReprojected ~ norm + s(x,y) -1, data=df_subset)`

**Same as ours!** Just default TPRS with no constraints.

**Why it works for her:**
- Chicago domain: 100km × 100km
- With k~30: ~18 km spatial resolution
- Extrapolation distances: typically 10-30 km
- At that scale, smooth spatial influence is reasonable

**At MIDWEST scale:**
- 2000km × 1200km domain
- With k~30: ~361 km spatial resolution
- Extrapolation distances: 100-500 km
- May want more local influence

---

## Practical Recommendations

### Immediate Actions (Today)

**1. Lower coverage threshold (already discussed):**
```r
min_pixel_coverage = 0.10
```

**2. Increase basis dimension moderately:**
```r
s(x, y, k=75)  # Instead of default k~30
```
- Improves resolution from 361 km to ~227 km
- Still computationally feasible
- More local predictions

**Combined change in Script 03:**
```r
config <- list(
  min_pixel_coverage = 0.10,  # Was 0.33
  gam_k = 75                   # NEW: spatial basis dimension
)

# In fit function:
gam(NDVI ~ norm + s(x, y, k=config$gam_k) - 1, data = df_subset)
```

---

### Medium-Term Improvements

**1. Adaptive k by data density:**
```r
# More data = can support more basis functions
n_pixels_with_data <- nrow(df_subset)
adaptive_k <- min(150, max(30, floor(n_pixels_with_data / 100)))

gam(NDVI ~ norm + s(x, y, k=adaptive_k) - 1, data = df_subset)
```

**2. Monitor effective degrees of freedom (EDF):**
```r
gam_summary <- summary(gam_model)
edf <- sum(gam_summary$edf)

# If EDF close to k, increase k
# If EDF << k, spatial pattern is simple, k is fine
```

---

### Long-Term Research

**1. Test Gaussian Process for selected dates:**
- Pick a few low-coverage DOYs
- Compare TPRS vs GP predictions
- Evaluate if explicit range improves quality

**2. Ecoregion-stratified models:**
- Define 3-5 major regions
- Fit separate models
- Compare regional vs domain-wide approaches

**3. Validation study:**
- Hold out 20% of pixels
- Test how well predictions match held-out data
- Compare different spatial smooth options

---

## Summary: Yes, Proximity Matters and You Can Control It

### Built-In Proximity in TPRS
- ✅ Distance-based influence (automatic)
- ✅ Smooth decay with distance
- ✅ Smoothing parameter controls how much

### At MIDWEST Scale, Current Approach May Be Too Broad
- ⚠️ 361 km effective resolution
- ⚠️ Extrapolates across entire states
- ⚠️ May over-smooth regional differences

### Recommended Improvements

**Priority 1 - Easy Win:**
```r
# Increase k from ~30 to 75
s(x, y, k=75)
```
→ Improves resolution to ~227 km

**Priority 2 - If still issues:**
```r
# Further increase k (if computation allows)
s(x, y, k=100-150)
```
→ Resolution ~161-198 km

**Priority 3 - Research:**
```r
# Test Gaussian Process with explicit range
s(x, y, bs="gp", m=c(3, 300000))  # 300km range
```
→ Hard limit on spatial influence

---

## Technical Details

### Thin Plate Spline Effective Range

For TPRS, "effective range" ≈ `2-3 × (domain_size / √k)`

**MIDWEST (k=30):**
- Basis resolution: 361 km
- Effective range: 2-3 × 361 = **720-1080 km**
- → Pixels 500+ km away still influence predictions

**MIDWEST (k=75):**
- Basis resolution: 227 km
- Effective range: 2-3 × 227 = **454-681 km**
- → More localized

**MIDWEST (k=150):**
- Basis resolution: 161 km
- Effective range: 2-3 × 161 = **322-483 km**
- → Even more localized

---

## Conclusion

**Your intuition is correct** - at MIDWEST scale, you probably want to constrain spatial influence more than the default TPRS does.

**Easiest solution:**
1. Lower coverage threshold to 10% (more DOYs)
2. Increase k to 75 (more local influence)
3. Test and validate

**These two changes together should:**
- Fill most time series gaps ✅
- Make predictions more localized ✅
- Still be computationally feasible ✅
- Maintain prediction quality ✅
