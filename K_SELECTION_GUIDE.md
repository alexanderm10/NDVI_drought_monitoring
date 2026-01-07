# GAM Basis Dimension (k) Selection Guide for MIDWEST Scale

**Date:** 2026-01-07
**Domain:** MIDWEST (1,976 km × 1,208 km, 125,798 pixels)

---

## Complete k vs Resolution Table

| k | Spatial Resolution | Effective Range | Pixels/Basis | Notes |
|---|-------------------|----------------|--------------|-------|
| 30 | 361 km | 722 - 1,082 km | 4,193 | Too coarse |
| 40 | 312 km | 625 - 937 km | 3,145 | Too coarse |
| 50 | 279 km | 559 - 838 km | 2,516 | Moderate |
| 60 | 255 km | 510 - 765 km | 2,097 | Moderate |
| 70 | 236 km | 472 - 709 km | 1,797 | ✅ Good balance |
| **77** | **225 km** | **450 - 676 km** | **1,634** | **✅ Good balance** |
| **87** | **212 km** | **424 - 636 km** | **1,446** | **✅ Good balance** |
| **97** | **201 km** | **401 - 602 km** | **1,297** | **Fine detail** |
| **107** | **191 km** | **382 - 573 km** | **1,176** | **Fine detail** |
| **117** | **183 km** | **365 - 548 km** | **1,075** | **Fine detail** |
| 127 | 175 km | 351 - 526 km | 991 | Very fine |
| 137 | 169 km | 338 - 506 km | 918 | Very fine |
| 147 | 163 km | 326 - 489 km | 856 | Very fine |
| 157 | 158 km | 315 - 473 km | 801 | May overfit |
| 167 | 153 km | 306 - 459 km | 753 | May overfit |
| 177 | 149 km | 297 - 446 km | 711 | May overfit |
| 187 | 144 km | 289 - 433 km | 673 | May overfit |
| 197 | 141 km | 282 - 422 km | 639 | May overfit |

---

## Interpretation Guide

### Spatial Resolution
**Formula:** `domain_width / √k`

**What it means:** The approximate "smoothness scale" of the spatial surface. At 225 km resolution (k=77), the GAM surface varies smoothly over ~225 km distances.

**Real-world analogy:**
- **361 km (k=30):** State-scale patterns (Iowa → Illinois)
- **225 km (k=77):** Multi-county scale (e.g., Des Moines → Cedar Rapids)
- **183 km (k=117):** County-to-regional scale
- **141 km (k=197):** County-scale patterns

---

### Effective Range
**Formula:** `2-3 × spatial_resolution`

**What it means:** The distance at which pixels still meaningfully influence each other's predictions.

**At k=77 (450-676 km range):**
- A pixel in Des Moines, Iowa influences predictions:
  - **Strong:** Within 200 km (to Iowa City)
  - **Moderate:** 200-450 km (to Madison, WI or Kansas City)
  - **Weak:** 450-676 km (to Chicago or Minneapolis)
  - **Negligible:** Beyond 676 km

**At k=30 (722-1,082 km range):**
- Des Moines influences predictions all the way to Detroit (900 km!)

**At k=117 (365-548 km range):**
- More localized - influence drops off around state boundaries

---

### Pixels per Basis Function
**Formula:** `total_pixels / k`

**What it means:** How many data points constrain each basis function.

**Rule of thumb:**
- **<100:** Risk of overfitting
- **100-500:** Ideal range
- **500-1000:** Conservative, robust
- **>1000:** Over-constrained, may miss local detail

**At 10% coverage (12,580 pixels with data):**
| k | Pixels/Basis (full) | Pixels/Basis (10%) | Status |
|---|--------------------|--------------------|--------|
| 77 | 1,634 | 163 | ✅ Well-constrained |
| 107 | 1,176 | 118 | ✅ Good |
| 147 | 856 | 86 | ⚠️ Getting sparse |
| 197 | 639 | 64 | ⚠️ Risky |

---

## Recommended k Values by Use Case

### Conservative (Robust, Regional Patterns)
**k = 70-87**
- Spatial resolution: 212-236 km
- Effective range: 424-709 km
- Captures state-to-regional scale patterns
- Very stable even with sparse data
- **Best for operational system**

---

### Balanced (Good All-Around)
**k = 87-107** ⭐ **RECOMMENDED**
- Spatial resolution: 191-212 km
- Effective range: 382-636 km
- Multi-county to regional scale
- Good compromise between detail and stability
- **Best for most analyses**

---

### Fine Detail (Local Patterns)
**k = 107-127**
- Spatial resolution: 175-191 km
- Effective range: 351-573 km
- County-to-regional scale
- Captures more local variations
- Requires good data coverage
- **Best for high-resolution studies**

---

### Very Fine (Research Only)
**k = 127-157**
- Spatial resolution: 158-175 km
- Effective range: 315-526 km
- County-scale patterns
- Risk of overfitting with sparse data
- Computationally expensive
- **Test carefully before using**

---

## Comparison with Juliana's Chicago Scale

### Juliana's Domain
```
100 km × 100 km, ~625 pixels
k ≈ 30 (default)
Resolution: 100 / √30 = 18 km
Effective range: 36-54 km
```

### Equivalent Resolution at MIDWEST Scale

**To match Juliana's 18 km resolution:**
```
k_needed = (1976 / 18)² ≈ 12,000 basis functions (!!)
```

**This is not feasible.** GAM computations scale as O(k³).

**Practical equivalent:** What k gives us the same **relative** resolution?

Juliana's resolution = 18 km / 100 km domain = **18% of domain width**

For MIDWEST: 18% of 1976 km = 356 km resolution → **k ≈ 31** (what we have!)

**Insight:** If we want **finer relative resolution** than Juliana, we need k > 30.

---

## Computational Considerations

### Runtime Scaling

GAM fitting time scales approximately as **O(n × k²)** where n = number of observations.

**Relative computation time (compared to k=30):**
| k | Relative Time | Notes |
|---|--------------|-------|
| 30 | 1.0× | Baseline |
| 77 | 6.6× | Still reasonable |
| 107 | 12.7× | Noticeable slowdown |
| 147 | 24.0× | Significant |
| 197 | 43.0× | Very slow |

**With 12,580 pixels (10% coverage) per DOY:**
- k=30: ~5-10 seconds per DOY
- k=77: ~30-60 seconds per DOY
- k=107: ~1-2 minutes per DOY
- k=147: ~2-4 minutes per DOY

**Total for 365 DOYs:**
- k=77: ~3-6 hours
- k=107: ~6-12 hours
- k=147: ~12-24 hours

---

## Memory Requirements

Posterior simulation memory scales as **n_pixels × n_sims × 8 bytes**

**Per DOY with 125,798 pixels, 100 simulations:**
- Posteriors: 125,798 × 100 × 8 bytes = **96 MB per DOY**
- Independent of k

**But:** Higher k requires more memory during fitting:
- Working memory ≈ k² × n_pixels × 8 bytes
- k=77: ~6 GB
- k=107: ~11 GB
- k=147: ~22 GB

**Current system:** 96 GB RAM → can handle k up to ~200 safely

---

## Recommendation Matrix

### By Priority

| Priority | k Value | Why |
|----------|---------|-----|
| **Operational/Robust** | **77-87** | Fast, stable, adequate detail |
| **General Research** | **97-107** | Best balance for most studies |
| **High Resolution** | **107-117** | More detail, still reasonable |
| **Experimental** | **127-147** | Test only, may overfit |

### By Data Coverage

With **10% coverage** (12,580 pixels per DOY on average):

| Coverage Scenario | Recommended k | Why |
|------------------|---------------|-----|
| **Low coverage DOYs** (<8k pixels) | **77** | Conservative, needs ~100/basis |
| **Medium coverage** (8-15k pixels) | **87-97** | Good balance |
| **High coverage** (>15k pixels) | **107-117** | Can support finer detail |

---

## Practical Testing Strategy

### Phase 1: Test k=87 (Recommended Starting Point)
1. Modify Script 03 to use k=87
2. Re-run for 2024 only
3. Check:
   - Number of DOYs predicted (should be ~280-300)
   - R² values (should be >0.3 for most DOYs)
   - Computation time (should be <6 hours)
   - Visual inspection of predictions

### Phase 2: If k=87 Works Well
- Run all years with k=87
- Proceed with analyses

### Phase 3: If Want More Detail
- Test k=107 on 2024
- Compare spatial patterns to k=87
- If improvements are marginal, stick with k=87
- If clearly better and time is acceptable, use k=107

### Phase 4: Adaptive Strategy (Optional)
```r
# Adjust k based on data availability
n_pixels_with_data <- nrow(df_subset)

if (n_pixels_with_data < 8000) {
  adaptive_k <- 77    # Conservative for sparse data
} else if (n_pixels_with_data < 15000) {
  adaptive_k <- 97    # Moderate for medium data
} else {
  adaptive_k <- 117   # Fine detail for dense data
}

gam(NDVI ~ norm + s(x, y, k=adaptive_k) - 1, data = df_subset)
```

---

## Final Recommendation

**Start with k=87** for the following reasons:

1. ✅ **Good spatial resolution** (212 km, ~2× better than current)
2. ✅ **Effective range** (424-636 km, more localized than current 722-1082 km)
3. ✅ **Well-constrained** (1,446 pixels/basis, even with 10% coverage = 145/basis)
4. ✅ **Reasonable computation** (~6× slower than k=30, but <6 hours for 365 DOYs)
5. ✅ **Conservative enough** for operational use
6. ✅ **Detailed enough** for research

**If computation time is not a concern and you want more detail, use k=107** (201 km resolution).

**If you need maximum stability for operational system, use k=77** (225 km resolution).
