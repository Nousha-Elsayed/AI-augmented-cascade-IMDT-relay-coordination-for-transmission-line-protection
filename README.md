# AI-Augmented IDMT Relay Coordination — MATLAB/Simulink

Coordinated overcurrent protection for an 11 kV radial feeder with an embedded Random Forest fault classifier.

---

## What It Does

- Simulates two IDMT relays (R1 upstream, R2 downstream) on a two-section 11 kV feeder
- Tests all four fault types: **3LG, SLG, LL, DLG** at Bus 2 and Bus 3
- Embeds an ML classifier as a MATLAB Function block for real-time fault-type identification
- Verifies coordination time interval (CTI ≥ 0.3 s) across all fault scenarios

---

## Relay Settings

| | R2 (Downstream) | R1 (Upstream) |
|---|---|---|
| Pickup | 210 A | 400 A |
| TDS | 0.25 | 0.25 |
| Curve | IEC Very Inverse | IEC Very Inverse |
| 50P Instantaneous | 2440 A | 3750 A |

---

## Simulation Results

| Fault | Bus | I_fault (A) | t_R2 (s) | t_R1 (s) |
|---|---|---|---|---|
| 3LG | 2 | 2440 | 0.319 | 0.619 |
| 3LG | 3 | 1600 | 0.567 | 0.972 |
| SLG | 2 | 1890 | 0.453 | 0.771 |
| LL  | 2 | 2110 | 0.380 | 0.709 |
| DLG | 2 | 2040 | 0.394 | 0.721 |

CTI ≥ 0.30 s across all cases. Zero false trips under normal load.

---

## ML Classifier

- **Model:** Random Forest (200 trees, scikit-learn)
- **Input:** 24 features from a 128-sample current window (RMS, symmetrical components, wavelet energy, harmonics)
- **Classes:** Normal, 3LG, SLG, LL, DLG
- **Weighted F1-score:** 97.4% — overall accuracy > 99%
- **Latency:** < 2 ms — advisory only, never overrides relay logic

---

## Stack

![MATLAB](https://img.shields.io/badge/MATLAB-Simulink-orange?logo=mathworks)
![Python](https://img.shields.io/badge/Python-scikit--learn-blue?logo=python)

**Solver:** ode23tb — 0.5 s window — fault injected at t = 0.1 s

---

## Run

```bash
# Simulink
# Open idmt_relay_model.slx → configure fault block → Run

# Python classifier
pip install scikit-learn numpy pandas matplotlib
python fault_classifier.py
```

