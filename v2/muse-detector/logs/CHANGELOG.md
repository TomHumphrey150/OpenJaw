# Inference Debug Changelog

Tracks bugs found and fixed, with timestamps. Use this to understand which issues
were present during a particular inference run.

## 2026-01-31 17:58 - Normalization mismatch (FIXED)

**Symptom**: Model always outputs `prob=0.000` even during clenches. Raw logits around -20.

**Root cause**: Inference used `safe_stds = np.maximum(channel_stds, 0.01)` but training
used `np.where(channel_stds < 1e-8, 1.0, channel_stds)`.

Six OPTICS channels have std ~0.0008. Training divides by 0.0008, inference was dividing
by 0.01 - making normalized values 12x smaller for those channels.

**Fix**: Changed `ml/inference.py` `_normalize()` to match `ml/preprocess.py` exactly:
```python
safe_stds = np.where(self.channel_stds < 1e-8, 1.0, self.channel_stds)
```

**Verification**: `debug_model.py` now shows training normalization gives prob=0.93 for
clenches vs old inference method giving prob=0.0001.

---

## 2026-01-31 ~16:00 - Interpolation zeros bug (FIXED)

**Symptom**: Model always outputs `prob=1.000` initially, then normalized values showed
many clipped values.

**Root cause**: Chunk-by-chunk interpolation used `np.interp(left=0.0, right=0.0)` which
produced zeros when timestamps didn't overlap between streams.

**Fix**: Created `TimestampedBuffer` class to store samples with timestamps. Interpolate
using edge values (`left=data[0], right=data[-1]`) instead of zeros.

---

## 2026-01-31 ~15:30 - Near-zero std explosion (FIXED)

**Symptom**: Normalized values exploding to extreme values, causing clipping.

**Root cause**: OPTICS channels have std ~0.0008 in training data. When inference data
differed slightly, normalizing by tiny std caused huge z-scores.

**Fix**: Initially added `safe_stds = np.maximum(channel_stds, 0.01)` and clipping to
[-10, 10]. Later removed in favor of matching training normalization exactly.

---

## How to use this file

When analyzing a run from `logs/runs/`, check the timestamp against this changelog:
- If run is BEFORE a fix timestamp, that bug was present
- If run is AFTER a fix timestamp, that bug should be resolved
