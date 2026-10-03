# exubercrit

exubercrit holds simulated critical values for the recursive right-tailed
unit root tests (ADF, SADF, GSADF and BSADF, Phillips–Shi–Yu 2015). A
critical value is the threshold that a test statistic must exceed before we
reject the null hypothesis of a unit root. The tests are implemented by
[exuber](https://github.com/kvasilopoulos/exuber) (R) and
[pyexuber](https://github.com/kvasilopoulos/pyexuber) (Python). The tables,
the scripts that produce them and the proxy that serves them live in this
repository, so that both packages and the website use the same numbers and
none of them bundles its own copy.

```
data/lag<L>/n<N>.bin.xz   one table per (lag, n): lag 0–4, n from n_min(lag) to 4000
scripts/simulate-crit.R   generates every table for a lag from one Monte Carlo run, then syncs the lag
scripts/common.R          binary writer + bucket sync helper, sourced by simulate-crit.R
scripts/exuber-fn.ts      Railway function "exuber-fn": read-only proxy, GET /crit2/<lag>/<n>
```

## Coverage

| lag | n         | tables |
|-----|-----------|--------|
| 0   | 6–4000    | 3995   |
| 1   | 7–4000    | 3994   |
| 2   | 9–4000    | 3992   |
| 3   | 11–4000   | 3990   |
| 4   | 15–4000   | 3986   |

All tables were generated on 2026-09-12 with 2000 replications, seed 123,
the PSY minimum window `psy_minw(n) = floor(0.01 n + 1.8 sqrt(n))` and
exubercore v0.2.0. The smallest sample size n_min(lag) is the smallest n
whose first window keeps a residual degree of freedom and that has at least
two windows. Below it, `radf_mc_cv()` itself fails. The proxy accepts n up
to 5000, so `Rscript scripts/simulate-crit.R 0:4 5000` extends the grid if
that is ever needed.

## How the numbers are produced

A critical value at sample size n is a quantile, taken across replications,
of a test statistic computed on a pure random walk `cumsum(rnorm(n))`.
Simulating each n separately costs O(n³) per table, which adds up to months
for a grid of this size. Two observations bring it down to minutes.

First, every n of a lag can be read from the same paths. The statistics for
sample size n only ever use windows `[start, end]` with `end < n`, and these
are prefix windows of a longer path. One sweep over the (start, end)
triangle of a path of length 4000 therefore contains the statistics for
every shorter n. `exubercore::radf_nested()` (exposed in R as
`exuber:::rls_nested()`) makes this sweep once. For each path it returns
the `badf` row `W(0, e)` for every end `e`, and `gsadf` for every n. The PSY
minimum window changes with n, and the function handles this by keeping a
prefix maximum for each distinct window size.

Second, the sweep uses running sufficient statistics. The ADF t-statistic of
each window uses `SSR = y'y − b'X'y`, computed from the accumulated `X'X`,
`X'y` and `y'y`, and the residual vector is never re-formed. A window then
costs O(1) for lag 0 and O(nc²) for lag > 0, and a whole path costs O(N²).

For each lag, 2000 paths of length 4000 take 3 to 8 minutes on 12 cores,
and reducing them to tables takes about 8 more. The reduction is the same as
in `radf_mc_cv()`. The `adf`, `sadf` and `gsadf` entries are the 90, 95 and
99% quantiles across replications. `bsadf_cv` is the quantile of
`cummax(badf)` at each time position, which is the conservative option in
exuber. `badf_cv` uses the PWY asymptotic constants (−0.44, −0.08, 0.6). We
checked the tables against per-n `rls_gsadf()` on the same seeded paths, and
they agree to about 1e-11.

## Validation (2026-09-14)

We ran three checks after exubercore v0.3.1 replaced the v0.2.0 numerics.
The v0.2.0 formulation of the SSR could lose precision on series with large
levels, although zero-mean random walks do not have such levels.

- **Numerics.** We recomputed 20 of the actual seeded N = 4000 paths with
  `radf_nested()` from v0.3.1. They differ from the v0.2.0 output that the
  tables were built from by at most 3e-11 (lag 0), 2e-8 (lag 2) and 2e-6
  (lag 4). These differences are orders of magnitude below Monte Carlo
  noise, so we did not simulate the tables again.
- **Reduction.** Every stored quantile (`adf`, `sadf` and `gsadf`, and the
  full `bsadf` sequence) equals a per-n recomputation with `rls_gsadf()` on
  the same 2000 paths, to 3e-11 or better. We checked n = 100 and n = 500 at
  lag 0, n = 100 at lag 2 and n = 300 at lag 1.
- **Statistics.** We compared the tables with independent runs of
  `radf_mc_cv(n, nrep = 2000)` using fresh seeds. For lag 0 we used 5 runs
  for each n from 20 to 2000, and for lag 1 we used 5 runs for each n from
  50 to 1000. To measure the sampling standard deviation of a quantile from
  2000 replications, we added 40 runs at n = 100 and 20 at n = 400. That
  standard deviation is about 0.02 to 0.04 at the 90% and 95% levels. The
  90% and 95% tables lie within one standard deviation of the independent
  mean at every n tested. The 99% column rests on one heavy-tailed draw (20
  exceedances out of 2000) that is shared by every n, and it lies on the
  high side by about 0.1 to 0.15 for n ≥ 400. For example, the gsadf 99%
  value at n = 400 is 2.867 against an independent mean of 2.70 ± 0.03, and
  1 of 25 independent draws reached it. We left the tables as they are.
  2000 replications is the standard in the literature (PSY 2015 use the
  same), and `datestamp()` and `summary()` use the 90% and 95% columns by
  default.

The first observation above has a consequence for how the tables relate to
each other. They are nested: every n of a lag shares the same 2000 paths, and
so does every lag. The per-replication seeds are fixed up front, so the
output does not depend on the number of cores. Each table is still exactly
the null distribution at its own n. The only difference from independently
simulated tables is that consecutive values of n are correlated, so the
critical values vary smoothly in n and do not jitter with Monte Carlo
noise.

## File format

Each table is an xz-compressed binary file with a fixed little-endian
layout. It can be read with `readBin()` in R or `np.frombuffer` in Python,
and needs no RDS or pickle support:

```
int32   x4            n, minw, lag, nrows        (nrows = n − minw − lag)
float64 x3            adf_cv   (90/95/99%)
float64 x3            sadf_cv
float64 x3            gsadf_cv
float64 x(nrows*3)    bsadf_cv, row-major (row = time index, col = pcnt)
```

`badf_cv` is not stored, because it is the constant PWY asymptotic tiling
and the client rebuilds it. The readers are `parse_crit_bin()` in
`exuber/R/crit-bucket.R` and `parse_crit_bin()` in
`pyexuber/src/exuber/crit.py`.

## Serving

The bucket `exuber-storage` and the function `exuber-fn` belong to the
Railway project `exuber`. The objects live under `crit/lag<L>/n<N>.bin.xz`
and are served at `https://exuber.up.railway.app/crit2/<lag>/<n>` (alias
`exubercrit.kvasilopoulos.com`). The proxy is a read-only allowlist. It can
address only those keys, and it checks that lag is between 0 and 4 and n
between 6 and 5000, so clients need no credentials. A missing object
returns 404 with `{"error":"not found"}`, and the clients report this as
"not simulated yet".

Each client caches a table on disk after the first use. In R the cache is
`tools::R_user_dir("exuber", "cache")`. In Python it is `XDG_CACHE_HOME`,
`LOCALAPPDATA` or `~/.cache/exuber`, depending on the system.

## Workflow

```sh
eval "$(railway bucket credentials -b exuber-storage)"   # optional: flush each lag to the bucket as it lands
Rscript scripts/simulate-crit.R 0:4 4000        # lags, N, [nrep=2000], [ncores]; skips lags already complete
railway functions push -p scripts/exuber-fn.ts  # only if exuber-fn.ts changed
curl -sI https://exuber.up.railway.app/crit2/1/100 | head -1
```

If the sync of a lag fails (the log shows `UPLOAD FAILED`), push it by hand
with the same credentials in the environment:

```sh
aws s3 sync data/lag1 s3://critical-values-kwz4n3ykp/crit/lag1/ --endpoint-url https://t3.storageapi.dev --region auto
```

`simulate-crit.R` needs the development tree of `exuber` next door (`../exuber`,
resolved relative to the script) for `rls_nested()`. The DLL of that tree
must be built with optimisation, using `pkgbuild::compile_dll(debug = FALSE)`.
`devtools::load_all()` alone builds it with `-O0`, which is roughly 8 times
slower.
