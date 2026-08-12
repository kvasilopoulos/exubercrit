# exubercrit

Simulated critical values for the recursive right-tailed unit root tests
(ADF/SADF/GSADF/BSADF, Phillips-Shi-Yu 2015) implemented by
[exuber](https://github.com/kvasilopoulos/exuber) (R) and
[pyexuber](https://github.com/kvasilopoulos/pyexuber) (Python), kept here as
a standalone artifact so both bindings — and the website — consume the same
tables instead of each bundling their own.

## Layout

```
lag<L>/n<N>.bin.xz   Monte Carlo critical values, nrep = 2000, seed = 123
crit-bucket/         generation + export + upload scripts
```

`lag0/` starts at n = 601 (n = 6:600, lag 0 ships bundled inside `exuber`);
other lags start at n = 6.

Each `.bin.xz` is xz-compressed, fixed little-endian binary — readable with
`readBin()` / `np.frombuffer`, no RDS or pickle:

```
int32   x4            n, minw, lag, nrows
float64 x3            adf_cv   (90/95/99%)
float64 x3            sadf_cv
float64 x3            gsadf_cv
float64 x(nrows*3)    bsadf_cv, row-major (row = time index, col = pcnt)
```

`badf_cv` is not stored — it is the constant PWY asymptotic tiling, rebuilt
client-side.

## Scripts

| File | Does |
|---|---|
| `crit-bucket/simulate-crit.R` | generates `lag*/n*.bin.xz`; resumable, one subprocess per (lag, n) |
| `crit-bucket/upload-crit.R` | `aws s3 sync` of the above to the Railway bucket |
| `crit-bucket/1-export-r-and-json.R` | exports the legacy `exuberdata` tables to `radf_crit2.rds` + a JSON bridge |
| `crit-bucket/2-export-python.py` | consumes that bridge, writes `radf_crit*.pkl.xz` |
| `crit-bucket/exuber-fn.ts` | read-only Railway function serving the bucket objects |

Each script's header comment has its own run instructions.
