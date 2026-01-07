# Spatial Scale Analysis: Why 33% Threshold is Different for MIDWEST vs Chicago

**Date:** 2026-01-07
**Critical Finding:** The 33% pixel coverage threshold has **completely different implications** at MIDWEST scale vs Juliana's Chicago scale

---

## The Scale Problem

### Juliana's Chicago Domain
```
Area: ~10,000 km² (100km × 100km)
Pixels: ~625 (at 4km resolution)
33% threshold: ~206 pixels
Linear dimension: ~100 km
```

### Our MIDWEST Domain
```
Area: ~2,012,768 km² (1,976km × 1,208km)
Pixels: 125,798
33% threshold: 41,513 pixels
Linear dimension: ~1,976 km
```

### Scale Comparison
- **Area:** 201× larger
- **Pixels:** 201× more
- **Linear extent:** 14× wider
- **Threshold pixels:** 201× more pixels required

---

## How GAM `s(x, y)` Sees This Data

### The Spatial Smooth

**Model specification:** `gam(NDVI ~ norm + s(x, y) - 1)`

The `s(x, y)` term creates a **2D spatial surface** using thin plate regression splines.

### Basis Dimension (k)

GAM uses `k` basis functions to represent the spatial pattern:
- **Default:** `k = 30` for 2D smooths (effectively ~5.5×5.5 grid of basis functions)
- **Maximum:** Usually capped at 30-40 for computational reasons
- **Spatial resolution:** Domain size / √k

### Effective Spatial Resolution

**Chicago (Juliana):**
- Domain: 100 km × 100 km
- k ≈ 30 basis functions
- **Resolution:** 100 / √30 ≈ **18 km per basis function**
- Each basis captures ~18km × 18km area

**MIDWEST (Us):**
- Domain: 1,976 km × 1,208 km
- k ≈ 30 basis functions (same!)
- **Resolution:** 1,976 / √30 ≈ **361 km per basis function**
- Each basis captures ~361km × 361km area

---

## The Critical Implication

### What 33% Coverage Means Spatially

**Chicago Scale:**
- 206 pixels with data spread over 100km × 100km
- With k=30 basis functions covering 18km each
- **~11 data pixels per basis function** (206/18.25)
- Spatial smooth is **well-constrained** by local data
- Interpolation distances: ~10-20 km

**MIDWEST Scale:**
- 41,513 pixels with data spread over 1,976km × 1,208km
- With k=30 basis functions covering 361km each
- **~1,383 data pixels per basis function** (41,513/30)
- But data may be **spatially clustered** (e.g., cloud gaps leave large empty regions)
- Interpolation distances: **potentially 100s of kilometers**

---

## The Problem Illustrated

### Scenario: DOY 10 (Jan 10, 2024)

**Actual data:**
- 36,099 pixels with data (28.7% coverage)
- **Fails 33% threshold** → no prediction

**Spatial distribution:**
- X range: -746 to 1,194 km (full width covered)
- Y range: 1,586 to 2,798 km (full height covered)
- Data is spread across entire domain
- But likely has **large contiguous gaps** (winter clouds/snow)

### What GAM "Sees"

With 36,099 pixels spread over ~2 million km²:
- Average density: ~0.018 pixels/km²
- **One pixel per ~56 km²** on average
- But actually clustered: some regions dense, others empty

With k=30 basis functions:
- Each basis must represent ~361 km × 361 km
- Some basis functions have **lots of data** (clear regions)
- Some basis functions have **zero data** (cloudy regions)

**Result:** GAM must **extrapolate** across 100s of km for cloudy regions using only the spatial pattern learned from clear regions.

---

## Why This Matters

### Juliana's Chicago: Local Interpolation

```
Data spacing: ~10-20 km between pixels
Basis resolution: ~18 km
Interpolation: Fill small gaps using nearby observations
```

**Analogy:** Filling in missing pixels in a photograph using surrounding pixels

**Quality:** Good - interpolation distances are small relative to spatial patterns

---

### Our MIDWEST: Regional Extrapolation

```
Data spacing: ~56 km average (but clustered)
Basis resolution: ~361 km
Interpolation: Predict entire sub-regions (e.g., 200km × 200km)
                using pattern from distant regions
```

**Analogy:** Predicting weather in Wyoming based only on observations from Minnesota and Texas

**Quality:** Questionable - assumes spatial patterns are uniform across 100s of km

---

## The "33% Coverage" Paradox

### At Chicago Scale (625 pixels total)
- 33% = 206 pixels
- Dense enough for local interpolation
- Spatial smooth is well-behaved

### At MIDWEST Scale (125,798 pixels total)
- 33% = 41,513 pixels
- Sounds like a lot, but spread over ~2 million km²
- **Same percentage, completely different spatial density**
- Spatial smooth must extrapolate across large empty regions

---

## What This Means for Your Data

### Question: Is 33% Enough at MIDWEST Scale?

**It depends on spatial distribution:**

1. **If data is uniformly distributed:**
   - 36,099 pixels = ~18 pixels/km² × 2 million km²
   - Reasonable coverage for broad-scale patterns
   - ✅ Probably OK for regional averages

2. **If data is clustered (reality):**
   - Cloud systems create 100-300 km contiguous gaps
   - GAM must extrapolate across entire states
   - ⚠️ Predictions in gap regions are highly uncertain

### Example: Winter Storm

Imagine a winter storm covers 500km × 500km (Nebraska):
- Storm area: 250,000 km² (12% of domain)
- Covered pixels: ~15,000
- Remaining data: 36,099 - 15,000 = ~21,000 pixels (17%)
- **Fails threshold** → no prediction

But the 21,000 pixels in **clear regions** (surrounding states) could still provide useful information about the **regional pattern**.

---

## Comparison of Approaches

### Juliana's Strategy (Chicago)
```r
min_pixel_coverage = 0.33  # Local density sufficient
s(x, y)                     # Smooth at ~18 km scale
```
✅ Works well - interpolates locally

### Our Current Strategy (MIDWEST)
```r
min_pixel_coverage = 0.33  # Regional density may be insufficient
s(x, y)                     # Smooth at ~361 km scale
```
⚠️ May fail unnecessarily - rejects useful regional data

---

## Solutions

### Option 1: Scale-Aware Threshold

**Instead of percentage, use spatial density:**

```r
# Require minimum spatial density, not percentage
min_density_per_km2 <- 0.01  # 1 pixel per 100 km²
min_pixels_required <- domain_area_km2 * min_density_per_km2

# For MIDWEST: 2,012,768 km² × 0.01 = ~20,128 pixels
# This is ~16% coverage, not 33%
```

**Rationale:** At large scales, you need less percentage coverage to still have adequate spatial sampling.

---

### Option 2: Adaptive Basis Dimension

**Increase k to match domain scale:**

```r
# Chicago scale: k=30 for 100km domain → ~18km resolution
# MIDWEST scale: k should be ~300 for 2000km domain → ~18km resolution

# But: computational constraints limit k
# Compromise: k=100-150 for MIDWEST

gam(NDVI ~ norm + s(x, y, k=100) - 1, data = df_subset)
```

**Rationale:** More basis functions = finer spatial resolution = better local fits

**Caveat:** Computationally expensive with 40k+ pixels

---

### Option 3: Hierarchical Spatial Model

**Multi-scale approach:**

```r
# Coarse scale (MIDWEST-wide pattern)
gam(NDVI ~ norm + s(x, y, k=30) - 1)  # Regional trends

# Fine scale (state-level residuals)
gam(residuals ~ s(x, y, k=100), data=by_state)  # Local deviations
```

**Rationale:** Separate regional patterns from local anomalies

---

### Option 4: Lower Threshold for Large Domains

**Simple pragmatic fix:**

```r
# Scale threshold with domain size
if (domain_area_km2 > 100000) {
  min_pixel_coverage = 0.10  # Large domain: 10%
} else {
  min_pixel_coverage = 0.33  # Small domain: 33%
}
```

**For MIDWEST:** 10% = 12,580 pixels
- Still ~0.006 pixels/km² density
- Should capture regional patterns adequately

---

## Recommendation

### **Lower the threshold to 10-15%** for MIDWEST scale

**Justification:**

1. **Spatial density matters more than percentage**
   - 12,580 pixels over 2M km² = reasonable regional sampling
   - With k=30, each basis still has ~400 data points

2. **GAM works at regional scale anyway**
   - With 361 km basis resolution, you're already doing regional interpolation
   - Local detail is limited regardless of data density

3. **Better to have uncertain predictions than no predictions**
   - Uncertainty bounds will be wider (honest)
   - Still useful for regional trends
   - Can flag high-uncertainty periods

4. **Juliana's threshold was for her scale**
   - 33% made sense for 100km × 100km domain
   - Doesn't translate directly to 2000km × 1200km domain

---

## Technical Details

### GAM Basis Function Math

For 2D thin plate regression spline with k basis functions:
- **Effective resolution:** `domain_size / √k`
- **Data per basis (needed):** At least 5-10 observations
- **Chicago:** 100km / √30 ≈ 18km resolution, 206 pixels / 30 ≈ 7 obs/basis ✅
- **MIDWEST:** 1976km / √30 ≈ 361km resolution, 41513 pixels / 30 ≈ 1384 obs/basis ✅
- **MIDWEST at 10%:** 1976km / √30 ≈ 361km, 12580 / 30 ≈ 419 obs/basis ✅ (still plenty)

### Minimum Viable Coverage

Rule of thumb: Need 5-10 data points per basis function
- k=30 → need ~150-300 pixels minimum
- MIDWEST: 12,580 pixels (10%) → 419 per basis ✅ well above minimum

---

## Conclusion

**The 33% threshold is a Chicago-scale heuristic** that's too conservative for MIDWEST scale.

At MIDWEST scale:
- **10-15% coverage** (~12-19k pixels) is **sufficient** for regional patterns
- GAM spatial resolution (~361 km) already averages over large areas
- More data is better, but 10% still provides robust regional estimates

**Recommended change:**
```r
min_pixel_coverage = 0.10  # MIDWEST scale
```

This should fill most gaps while maintaining reasonable prediction quality.
