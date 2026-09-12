# exubercrit

Simulated critical values for the recursive right-tailed unit root tests
(ADF/SADF/GSADF/BSADF, Phillips–Shi–Yu 2015) implemented by
[exuber](https://github.com/kvasilopoulos/exuber) (R) and
[pyexuber](https://github.com/kvasilopoulos/pyexuber) (Python). Kept here as
a standalone artifact — the tables themselves, the scripts that produce
them, and the proxy that serves them — so both bindings and the website
consume the same numbers instead of each bundling their own.

```
lag<L>/n<N>.bin.xz   one table per (lag, n): lag 0–4, n from n_min(lag) to 4000
common.R             binary writer + bucket sync helper shared by the scripts
simulate-crit.R      generates every table for a lag from one Monte Carlo run; syncs the lag when done
upload-crit.R        catch-up: sync every lag<L>/ to the bucket
exuber-fn.ts         Railway function "exuber-fn": read-only proxy, GET /crit2/<lag>/<n>
runs/                logs of the generation runs
```

## Coverage

| lag | n         | tables |
|-----|-----------|--------|
| 0   | 6–4000    | 3995   |
| 1   | 7–4000    | 3994   |
| 2   | 9–4000    | 3992   |
| 3   | 11–4000   | 3990   |
| 4   | 15–4000   | 3986   |

All generated 2026-09-12 (`runs/2026-09-12.log`): 2000 replications, seed
123, PSY minimum window `psy_minw(n) = floor(0.01 n + 1.8 sqrt(n))`,
exubercore v0.2.0. n_min(lag) is the smallest n whose first window keeps a
residual degree of freedom and that has at least two windows; below it
`radf_mc_cv()` itself fails. The proxy accepts n up to 5000, so
`Rscript simulate-crit.R 0:4 5000` extends the grid if ever needed.

## How the numbers are produced

A critical value at sample size n is a quantile, across replications, of a
test statistic computed on a pure random walk `cumsum(rnorm(n))`. Doing
that separately for every n is O(n³) per table and adds up to months for a
grid this size. Two observations make it minutes:

1. **Every n of a lag comes from the same paths.** The statistics for
   sample size n only ever look at windows `[start, end]` with `end < n`
   — prefix windows of a longer path. So one sweep over the (start, end)
   triangle of a length-4000 path already contains the statistics of every
   shorter n. `exubercore::radf_nested()` (exposed in R as
   `exuber:::rls_nested()`) does that sweep once and returns, per path,
   the `badf` row `W(0, e)` for every end `e` plus `gsadf` for every n —
   handling the fact that the PSY minimum window changes with n by keeping
   a prefix-max per distinct window size.
2. **Running sufficient statistics.** Each window's ADF t-statistic uses
   `SSR = y'y − b'X'y` from accumulated `X'X`, `X'y`, `y'y` instead of
   re-forming the residual vector, so a window is O(1) (lag 0) or O(nc²)
   (lag > 0), and a whole path is O(N²).

Per lag, 2000 paths of length 4000 take 3–8 minutes on 12 cores; the
reduction to tables another ~8. Reduction is exactly `radf_mc_cv()`'s:
`adf`/`sadf`/`gsadf` are 90/95/99% quantiles across replications;
`bsadf_cv` is the per-position quantile of `cummax(badf)` (exuber's
conservative option); `badf_cv` is the PWY asymptotic constants
(−0.44, −0.08, 0.6). Verified against per-n `rls_gsadf()` on the same seeded
paths to ~1e-11.

Consequence of (1): the tables are *nested* — every n of a lag shares the
same 2000 paths, and every lag shares them too (per-replication seeds are
fixed up front, so output is independent of core count). Each table is
still exactly the null distribution at its n; the only difference from
independently simulated tables is that consecutive n are correlated, so
the critical values vary smoothly in n instead of jittering by Monte Carlo
noise.

## File format

xz-compressed, fixed little-endian binary — readable with `readBin()` /
`np.frombuffer`, no RDS or pickle:

```
int32   x4            n, minw, lag, nrows        (nrows = n − minw − lag)
float64 x3            adf_cv   (90/95/99%)
float64 x3            sadf_cv
float64 x3            gsadf_cv
float64 x(nrows*3)    bsadf_cv, row-major (row = time index, col = pcnt)
```

`badf_cv` is not stored — it is the constant PWY asymptotic tiling, rebuilt
client-side. Readers: `exuber/R/crit-bucket.R` (`parse_crit_bin()`),
`pyexuber/src/exuber/crit.py` (`parse_crit_bin()`).

## Serving

Bucket `exuber-storage` and function `exuber-fn` in the Railway project
`exuber`; objects live under `crit/lag<L>/n<N>.bin.xz`, served at
`https://exuber.up.railway.app/crit2/<lag>/<n>` (alias
`exubercrit.kvasilopoulos.com`). The proxy is a read-only allowlist —
it can only ever address those keys, bounds-checked to lag 0–4, n 6–5000 —
so clients need no credentials. Missing objects answer 404
`{"error":"not found"}`, which the clients turn into "not simulated yet".

Clients cache each table on disk after first use
(`tools::R_user_dir("exuber", "cache")` in R; `XDG_CACHE_HOME` /
`LOCALAPPDATA` / `~/.cache/exuber` in Python).

## Workflow

```sh
eval "$(railway bucket credentials -b exuber-storage)"   # optional: flush each lag to the bucket as it lands
Rscript simulate-crit.R 0:4 4000        # lags, N, [nrep=2000], [ncores]; skips lags already complete
Rscript upload-crit.R                   # only if a sync failed above
railway functions push -p exuber-fn.ts  # only if exuber-fn.ts changed
curl -sI https://exuber.up.railway.app/crit2/1/100 | head -1
```

`simulate-crit.R` needs the `exuber` dev tree next door (`../exuber`) for
`rls_nested()`, and that tree's DLL built optimised —
`pkgbuild::compile_dll(debug = FALSE)`; `devtools::load_all()` alone
builds it with `-O0`, roughly 8× slower.
